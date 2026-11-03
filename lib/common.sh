# shellcheck shell=bash
# Shared helpers for install.sh, post-install.sh and modules/*.sh

: "${CACHY_LOG:=/var/log/cachy-setup.log}"
# State shared between modules (each module runs in its own subshell)
: "${CACHY_STATE:=/tmp/cachy-setup-state}"
export CACHY_STATE
mkdir -p "$CACHY_STATE"

if [[ -t 1 ]]; then
    C_RED=$'\e[31m' C_GRN=$'\e[32m' C_YLW=$'\e[33m' C_BLU=$'\e[34m' C_BLD=$'\e[1m' C_RST=$'\e[0m'
else
    C_RED='' C_GRN='' C_YLW='' C_BLU='' C_BLD='' C_RST=''
fi

_log()   { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$CACHY_LOG" 2>/dev/null || true; }
info()   { printf '%s==>%s %s\n' "$C_BLU$C_BLD" "$C_RST" "$*"; _log "INFO  $*"; }
ok()     { printf '%s ok%s %s\n' "$C_GRN" "$C_RST" "$*"; _log "OK    $*"; }
warn()   { printf '%s!! %s%s\n' "$C_YLW" "$*" "$C_RST" >&2; _log "WARN  $*"; echo "$*" >>"$CACHY_STATE/warnings"; }
die()    { printf '%sxx %s%s\n' "$C_RED" "$*" "$C_RST" >&2; _log "FATAL $*"; exit 1; }
section(){ printf '\n%s### %s%s\n' "$C_BLD" "$*" "$C_RST"; _log "----- $*"; }

is_true() { [[ "${1,,}" =~ ^(1|y|yes|true|on)$ ]]; }

require_root() { [[ $EUID -eq 0 ]] || die "Run this as root (sudo $0)"; }

# True when running inside arch-chroot (no running systemd to talk to)
in_chroot() { systemd-detect-virt --chroot &>/dev/null; }

# Defaults come from config.example.env, then config.env overrides them, so an
# older config.env missing newer keys still works.
load_config() {
    local root="$1"
    # shellcheck source=/dev/null
    [[ -f "$root/config.example.env" ]] && source "$root/config.example.env"
    if [[ -f "$root/config.env" ]]; then
        # shellcheck source=/dev/null
        source "$root/config.env"
    else
        warn "config.env not found, using config.example.env defaults"
    fi
}

# ---- packages ------------------------------------------------------------------

# pkg_install pkg... : install with pacman. On failure:
#   1. retry one by one, so one bad package doesn't sink the whole group
#   2. for the ones still failing: re-rank mirrors (once per run), force-refresh
#      the databases and retry with a full upgrade (-Syyu, never a partial
#      upgrade). That covers mirrors that haven't finished syncing, the usual
#      cause of "failed retrieving file" / "not found" on CachyOS.
#   3. anything still failing is reported together with pacman's own error lines.
_pacman_s() {   # _pacman_s FLAGS pkg... ; full output -> log, last output kept
    local flags="$1"; shift
    pacman "-S$flags" --needed --noconfirm "$@" >"$CACHY_STATE/last-pacman" 2>&1
    local rc=$?
    cat "$CACHY_STATE/last-pacman" >>"$CACHY_LOG"
    return $rc
}
_pacman_reason() {
    local r
    r=$(grep -E '^(error:|:: .*(conflict|corrupt)|.* exists in filesystem|warning: .*(conflict|unknown trust|corrupt))' \
        "$CACHY_STATE/last-pacman" | grep -v 'failed to commit transaction' | head -n 4 | tr '\n' ' ')
    echo "${r:-pacman exited with an error (see log)}" | cut -c1-400
}
_refresh_mirrors_once() {
    [[ -e "$CACHY_STATE/mirrors-refreshed" ]] && return 0
    touch "$CACHY_STATE/mirrors-refreshed"
    if command -v cachyos-rate-mirrors &>/dev/null; then
        info "re-ranking CachyOS mirrors (cachyos-rate-mirrors)"
        timeout 300 cachyos-rate-mirrors >>"$CACHY_LOG" 2>&1 || warn "cachyos-rate-mirrors failed, keeping current mirrors"
    fi
}
pkg_install() {
    local pkgs=("$@") p retry=()
    ((${#pkgs[@]})) || return 0
    info "pacman: ${pkgs[*]}"
    _pacman_s "" "${pkgs[@]}" && return 0
    info "group install failed ($(_pacman_reason)); retrying packages one by one"
    for p in "${pkgs[@]}"; do
        _pacman_s "" "$p" || retry+=("$p")
    done
    ((${#retry[@]})) || return 0
    _refresh_mirrors_once
    info "refreshing package databases and retrying: ${retry[*]}"
    for p in "${retry[@]}"; do
        if ! _pacman_s "yyu" "$p"; then
            warn "could not install $p: $(_pacman_reason)"
            echo "$p" >>"$CACHY_STATE/failed"
        fi
    done
}

pkg_installed() { pacman -Qq "$1" &>/dev/null; }

# Run a command as the target user with a login-ish environment
as_user() {
    sudo -u "$USERNAME" -H env HOME="/home/$USERNAME" USER="$USERNAME" LOGNAME="$USERNAME" "$@"
}

# Temporary passwordless sudo for AUR builds; removed by aur_cleanup / EXIT trap
AUR_SUDOERS=/etc/sudoers.d/99-cachy-setup-aur
aur_prepare() {
    printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$USERNAME" >"$AUR_SUDOERS"
    chmod 0440 "$AUR_SUDOERS"
}
aur_cleanup() { rm -f "$AUR_SUDOERS"; }

aur_install() {
    local pkgs=("$@") p
    ((${#pkgs[@]})) || return 0
    command -v paru &>/dev/null || pkg_install paru
    aur_prepare
    for p in "${pkgs[@]}"; do
        pkg_installed "$p" && continue
        info "AUR: $p"
        if ! as_user paru -S --needed --noconfirm --skipreview --noprogressbar "$p" >>"$CACHY_LOG" 2>&1; then
            warn "AUR build failed: $p (see $CACHY_LOG)"
            echo "aur:$p" >>"$CACHY_STATE/failed"
        fi
    done
    aur_cleanup
}

# ---- services --------------------------------------------------------------------

svc_enable() {
    local unit
    for unit in "$@"; do
        if in_chroot; then
            systemctl enable "$unit" >>"$CACHY_LOG" 2>&1 || warn "could not enable $unit"
        else
            systemctl enable --now "$unit" >>"$CACHY_LOG" 2>&1 || warn "could not enable $unit"
        fi
    done
}

svc_disable() {
    local unit
    for unit in "$@"; do
        systemctl disable "$unit" >>"$CACHY_LOG" 2>&1 || true
        in_chroot || systemctl stop "$unit" >>"$CACHY_LOG" 2>&1 || true
    done
}

user_svc_enable() {
    local unit
    for unit in "$@"; do
        systemctl --global enable "$unit" >>"$CACHY_LOG" 2>&1 || warn "could not enable user unit $unit"
    done
}

# ---- files -----------------------------------------------------------------------

# install_file SRC DEST [MODE]: copy from repo files/ dir, creating parents
install_file() {
    local src="$CACHY_ROOT/files/$1" dest="$2" mode="${3:-0644}"
    [[ -f "$src" ]] || die "missing repo file: files/$1"
    install -Dm"$mode" "$src" "$dest"
}

# write_file DEST [MODE] < content
write_file() {
    local dest="$1" mode="${2:-0644}"
    install -d "$(dirname "$dest")"
    cat >"$dest"
    chmod "$mode" "$dest"
}

# ---- kernel command line --------------------------------------------------------

# merge_params "existing" "new": drop tokens from existing whose key matches a
# token in new, then append new. Keeps re-runs idempotent.
merge_params() {
    local existing="$1" new="$2" tok n keep out=()
    for tok in $existing; do
        keep=1
        for n in $new; do [[ "${tok%%=*}" == "${n%%=*}" ]] && keep=0; done
        ((keep)) && out+=("$tok")
    done
    for n in $new; do out+=("$n"); done
    echo "${out[*]}"
}

# _edit_cmdline_var FILE KEY PARAMS: merge PARAMS into the first KEY="..." line
_edit_cmdline_var() {
    local file="$1" key="$2" params="$3" line cur merged
    local qkey=${key//[/\\[}; qkey=${qkey//]/\\]}
    line=$(grep -m1 -E "^${qkey}=" "$file") || return 1
    cur=${line#*=}; cur=${cur#[\"\']}; cur=${cur%[\"\']}
    merged=$(merge_params "$cur" "$params")
    # escape for sed replacement
    merged=${merged//\\/\\\\}; merged=${merged//&/\\&}; merged=${merged//|/\\|}
    sed -i -E "0,/^${qkey}=/s|^${qkey}=.*|${key}=\"${merged}\"|" "$file"
}

# add_kernel_params "a=b c": add params for whichever bootloader is installed.
#   Limine (CachyOS default): KERNEL_CMDLINE[default] in /etc/default/limine
#   systemd-boot (CachyOS):   LINUX_OPTIONS in /etc/sdboot-manage.conf
#   GRUB:                     GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub
add_kernel_params() {
    local params="$1"
    if [[ -f /etc/default/limine ]] && grep -q '^KERNEL_CMDLINE\[default\]=' /etc/default/limine; then
        _edit_cmdline_var /etc/default/limine 'KERNEL_CMDLINE[default]' "$params"
        echo limine >"$CACHY_STATE/bootloader"
    elif [[ -f /etc/sdboot-manage.conf ]] && grep -q '^LINUX_OPTIONS=' /etc/sdboot-manage.conf; then
        _edit_cmdline_var /etc/sdboot-manage.conf LINUX_OPTIONS "$params"
        echo sdboot >"$CACHY_STATE/bootloader"
    elif [[ -f /etc/default/grub ]]; then
        _edit_cmdline_var /etc/default/grub GRUB_CMDLINE_LINUX_DEFAULT "$params"
        echo grub >"$CACHY_STATE/bootloader"
    else
        warn "unknown bootloader: add these kernel params manually: $params"
        return 0
    fi
    ok "kernel params: $params"
}

regen_boot() {
    info "regenerating initramfs and boot entries"
    local bl=""
    [[ -f "$CACHY_STATE/bootloader" ]] && bl=$(<"$CACHY_STATE/bootloader")
    case "$bl" in
        limine) if command -v limine-mkinitcpio &>/dev/null; then limine-mkinitcpio >>"$CACHY_LOG" 2>&1
                else mkinitcpio -P >>"$CACHY_LOG" 2>&1; limine-update >>"$CACHY_LOG" 2>&1; fi ;;
        sdboot) mkinitcpio -P >>"$CACHY_LOG" 2>&1; sdboot-manage gen >>"$CACHY_LOG" 2>&1 ;;
        grub)   mkinitcpio -P >>"$CACHY_LOG" 2>&1; grub-mkconfig -o /boot/grub/grub.cfg >>"$CACHY_LOG" 2>&1 ;;
        *)      mkinitcpio -P >>"$CACHY_LOG" 2>&1 ;;
    esac || warn "boot regeneration reported an error (see $CACHY_LOG)"
}

# ---- hardware detection ------------------------------------------------------------

# First NVIDIA VGA/3D controller, full domain address (0000:01:00.0)
detect_gpu_pci() {
    lspci -D -n -d 10de: 2>/dev/null | awk '$2 ~ /^030[02]:/ {print $1; exit}'
}

# Add-in USB controller: a USB host controller (class 0c03) not made by AMD,
# so the chipset/CPU controllers (vendor 1022) are never picked.
detect_usb_controller_pci() {
    local list
    list=$(lspci -D -n 2>/dev/null | awk '$2 ~ /^0c03:/ && $3 !~ /^1022:/ {print $1}')
    if [[ $(wc -l <<<"$list") -eq 1 && -n "$list" ]]; then
        echo "$list"
    fi
}

# Xorg wants BusID "PCI:bus:dev:func" in decimal
pci_to_xorg_busid() {
    local addr="${1#*:}" bus dev fn
    bus=${addr%%:*}; addr=${addr#*:}; dev=${addr%%.*}; fn=${addr#*.}
    printf 'PCI:%d:%d:%d' "$((16#$bus))" "$((16#$dev))" "$((16#$fn))"
}

detect_igpu_pci() {
    lspci -D -n -d 1002: 2>/dev/null | awk '$2 ~ /^030[02]:/ {print $1; exit}'
}

summary_report() {
    section "Summary"
    if [[ -s "$CACHY_STATE/failed" ]]; then
        printf '%sPackages that failed:%s %s\n' "$C_YLW" "$C_RST" "$(sort -u "$CACHY_STATE/failed" | tr '\n' ' ')"
    else
        ok "all packages installed"
    fi
    if [[ -s "$CACHY_STATE/warnings" ]]; then
        printf '%sWarnings:%s\n' "$C_YLW" "$C_RST"
        sed 's/^/  - /' "$CACHY_STATE/warnings"
    fi
    if in_chroot; then
        echo "Full log: $CACHY_LOG on the installed system (install.sh also copies it to /tmp/cachy-setup.log on the live USB)"
    else
        echo "Full log: $CACHY_LOG"
    fi
}
