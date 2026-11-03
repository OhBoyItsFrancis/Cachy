#!/usr/bin/env bash
# =============================================================================
# Cachy unattended installer. Run from the CachyOS live ISO, as root:
#
#   git clone https://github.com/OhBoyItsFrancis/Cachy && cd Cachy
#   cp config.example.env config.env && nano config.env
#   sudo ./install.sh
#
# Stage 1: CachyOS's own installer (cachyos-installer, headless mode) erases
#          TARGET_DISK and installs base + Cinnamon + kernel + bootloader +
#          chwd drivers, exactly like an official install.
# Stage 2: this repo is copied into the new system and post-install.sh runs in
#          arch-chroot to apply everything else (apps, gaming, VFIO, AI tools).
# =============================================================================
set -Eeuo pipefail

CACHY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CACHY_ROOT
export CACHY_LOG=/tmp/cachy-install.log
# shellcheck source=lib/common.sh
source "$CACHY_ROOT/lib/common.sh"

ASSUME_YES=0
DRY_RUN=0
usage() {
    cat <<EOF
Usage: sudo $0 [--yes] [--dry-run]
  --yes      don't ask for the disk-erase confirmation (passwords still asked
             unless USER_PASSWORD/ROOT_PASSWORD are exported)
  --dry-run  validate config, print the generated installer settings, change nothing
EOF
}
while (($#)); do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
    shift
done

require_root
load_config "$CACHY_ROOT"
MNT=/mnt
SETTINGS=/tmp/cachy-installer-settings.json
cleanup() { rm -f "$SETTINGS"; }
trap cleanup EXIT

# ---- preflight -------------------------------------------------------------------
section "Preflight"
[[ -d /sys/firmware/efi/efivars ]] || die "Not booted in UEFI mode. Enable UEFI (disable CSM) in the MSI BIOS."
[[ -b "$TARGET_DISK" ]] || die "TARGET_DISK=$TARGET_DISK is not a block device. lsblk -d shows:
$(lsblk -d -o NAME,SIZE,MODEL)"
[[ "$(lsblk -dno TYPE "$TARGET_DISK")" =~ ^(disk|loop)$ ]] || die "$TARGET_DISK is not a whole disk"
if findmnt -rno SOURCE | grep -q "^${TARGET_DISK}"; then
    die "$TARGET_DISK has mounted partitions; unmount them first"
fi
[[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "USERNAME '$USERNAME' is not a valid Linux user name"
[[ "$HOSTNAME" =~ ^[a-zA-Z0-9-]{1,63}$ ]] || die "HOSTNAME '$HOSTNAME' is invalid"
[[ -f "/usr/share/zoneinfo/$TIMEZONE" ]] || die "TIMEZONE '$TIMEZONE' not found in /usr/share/zoneinfo"
case "$BOOTLOADER" in limine|systemd-boot|grub) ;; *) die "BOOTLOADER must be limine, systemd-boot or grub" ;; esac
disk_gb=$(( $(lsblk -bdno SIZE "$TARGET_DISK") / 1024**3 ))
((disk_gb >= 64)) || die "$TARGET_DISK is only ${disk_gb} GiB; this setup needs at least 64 GiB (games + VM image want far more)"
ok "UEFI, target disk (${disk_gb} GiB) and config look valid"

if ! curl -fsS --max-time 10 -o /dev/null https://mirror.cachyos.org; then
    die "No internet. Connect first (nmtui for Wi-Fi), then re-run."
fi
ok "network reachable"

# Partition names: nvme0n1 -> nvme0n1p1, sda -> sda1
if [[ "$TARGET_DISK" =~ [0-9]$ ]]; then PART_PREFIX="${TARGET_DISK}p"; else PART_PREFIX="$TARGET_DISK"; fi
ESP_PART="${PART_PREFIX}1"
ROOT_PART="${PART_PREFIX}2"

# ---- passwords -----------------------------------------------------------------------
ask_password() {
    local label="$1" var="$2" a b
    if [[ -n "${!var:-}" ]]; then return; fi
    while true; do
        read -rsp "Password for $label: " a; echo
        read -rsp "Repeat password for $label: " b; echo
        [[ -n "$a" && "$a" == "$b" ]] && break
        echo "Passwords empty or not matching, try again."
    done
    printf -v "$var" '%s' "$a"
}
if ((DRY_RUN)); then
    USER_PASSWORD="${USER_PASSWORD:-dry-run}"; ROOT_PASSWORD="${ROOT_PASSWORD:-dry-run}"
else
    ask_password "user $USERNAME" USER_PASSWORD
    ask_password "root" ROOT_PASSWORD
fi

# ---- confirmation -----------------------------------------------------------------------
section "Target"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL "$TARGET_DISK"
echo
echo "${C_RED}${C_BLD}EVERYTHING ON $TARGET_DISK WILL BE ERASED.${C_RST}"
echo "Layout: ${ESP_PART} ${ESP_SIZE} EFI (vfat) + ${ROOT_PART} rest btrfs (@, @home, @root, @srv, @cache, @tmp, @log)"
if ((!ASSUME_YES && !DRY_RUN)); then
    read -rp "Type the disk name ($(basename "$TARGET_DISK")) to continue: " answer
    [[ "$answer" == "$(basename "$TARGET_DISK")" ]] || die "Aborted"
fi

# ---- generate headless settings for cachyos-installer --------------------------------------
json_str() {
    local s="$1"
    s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\t'/\\t}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}
    printf '"%s"' "$s"
}
# cachyos-installer expects the locale without the .UTF-8 suffix
locale_short="${LOCALE%.UTF-8}"; locale_short="${locale_short%.utf8}"

umask 077
cat >"$SETTINGS" <<EOF
{
    "menus": 1,
    "headless_mode": true,
    "device": $(json_str "$TARGET_DISK"),
    "fs_name": "btrfs",
    "partitions": [
        {"name": $(json_str "$ESP_PART"), "mountpoint": "/boot", "size": $(json_str "$ESP_SIZE"), "fs_name": "vfat", "type": "boot"},
        {"name": $(json_str "$ROOT_PART"), "mountpoint": "/", "size": "100%", "type": "root"}
    ],
    "hostname": $(json_str "$HOSTNAME"),
    "locale": $(json_str "$locale_short"),
    "xkbmap": $(json_str "$KEYMAP"),
    "timezone": $(json_str "$TIMEZONE"),
    "user_name": $(json_str "$USERNAME"),
    "user_pass": $(json_str "$USER_PASSWORD"),
    "user_shell": $(json_str "$USER_SHELL"),
    "root_pass": $(json_str "$ROOT_PASSWORD"),
    "kernel": $(json_str "$KERNELS"),
    "desktop": "cinnamon",
    "bootloader": $(json_str "$BOOTLOADER")
}
EOF
umask 022

if ((DRY_RUN)); then
    section "Dry run: generated settings (passwords masked)"
    sed -E 's/("(user|root)_pass": ).*/\1"********",/' "$SETTINGS"
    if command -v jq &>/dev/null; then jq empty "$SETTINGS" && ok "settings are valid JSON"; fi
    exit 0
fi

if command -v jq &>/dev/null; then jq empty "$SETTINGS" || die "generated settings are not valid JSON"; fi

# ---- stage 1: official CachyOS installer ------------------------------------------------
section "Stage 1: cachyos-installer (headless)"
info "updating the installer on the live system"
pacman -Sy --needed --noconfirm cachyos-cli-installer-new >>"$CACHY_LOG" 2>&1 \
    || warn "could not update cachyos-cli-installer-new, using the ISO's version"
command -v cachyos-installer &>/dev/null || die "cachyos-installer not found. Use the GUI installer, then run post-install.sh (see README)."

info "installing CachyOS to $TARGET_DISK (takes a while; log: /tmp/cachyos-install.log)"
if ! cachyos-installer --config "$SETTINGS"; then
    die "cachyos-installer failed. See /tmp/cachyos-install.log and $CACHY_LOG.
Fallback: install with the GUI installer (Cinnamon, btrfs, Limine), boot it, then run: sudo ./post-install.sh"
fi
rm -f "$SETTINGS"
ok "base system installed"

# ---- stage 2: mount the new system and configure it in chroot ----------------------------
section "Stage 2: configure the new system"
mountpoint -q "$MNT" && umount -R "$MNT"
mount -o subvol=@ "$ROOT_PART" "$MNT" || die "could not mount $ROOT_PART (subvol=@)"
# Mount the rest (@home, @cache, @log, /boot, ...) exactly as the new fstab says
mount --all --fstab "$MNT/etc/fstab" --target-prefix "$MNT" || die "could not mount target fstab entries"
findmnt -R "$MNT" | tee -a "$CACHY_LOG"
mountpoint -q "$MNT/var/log" || warn "$MNT/var/log is not a separate mount (no @log subvolume?); logs will land in @"

install -d "$MNT/opt/cachy-setup"
rsync -a --delete --exclude .git "$CACHY_ROOT/" "$MNT/opt/cachy-setup/"
# Full git clone in the user's home as the working copy for later tweaks
# (ownership is fixed inside the chroot by modules/90-finish.sh)
if [[ -d "$CACHY_ROOT/.git" && ! -e "$MNT/home/$USERNAME/Cachy" ]]; then
    rsync -a "$CACHY_ROOT/" "$MNT/home/$USERNAME/Cachy/"
fi
# The live ISO's mirror ranking is better than nothing for the chroot
[[ -f /etc/pacman.d/cachyos-mirrorlist ]] && cp /etc/pacman.d/cachyos-mirrorlist "$MNT/etc/pacman.d/" || true

set +e
arch-chroot "$MNT" env CACHY_USER="$USERNAME" CACHY_LOG=/var/log/cachy-setup.log \
    /opt/cachy-setup/post-install.sh --chroot
rc=$?
set -e
cp "$CACHY_LOG" "$MNT/var/log/cachy-install-stage1.log" 2>/dev/null || true
cp /tmp/cachyos-install.log "$MNT/var/log/cachyos-installer.log" 2>/dev/null || true
# Keep a copy of the stage-2 log on the live system: the target is unmounted below
cp "$MNT/var/log/cachy-setup.log" /tmp/cachy-setup.log 2>/dev/null || true

# Is there a desktop to boot into?
desktop_ok=1
if ! arch-chroot "$MNT" pacman -Q cinnamon lightdm >>"$CACHY_LOG" 2>&1; then
    desktop_ok=0
fi

sync
umount -R "$MNT"
if ((rc != 0)); then
    warn "post-install finished with errors (rc=$rc). Boot the system and re-run: sudo /opt/cachy-setup/post-install.sh"
fi

section "Logs"
cat <<EOF
On this live USB (gone after reboot):
  /tmp/cachy-install.log     this script
  /tmp/cachyos-install.log   CachyOS installer (stage 1)
  /tmp/cachy-setup.log       post-install modules (stage 2)
On the installed system:
  /var/log/cachy-setup.log, /var/log/cachy-install-stage1.log, /var/log/cachyos-installer.log
Why a package failed:  grep -n -A6 'could not install' /tmp/cachy-setup.log
EOF

if ((!desktop_ok)); then
    cat <<EOF

${C_RED}${C_BLD}!! Cinnamon/LightDM are NOT installed: the new system has no desktop yet.${C_RST}
Fix it before rebooting (the target is still configured, just unmounted):
  sudo mount -o subvol=@ $ROOT_PART /mnt
  sudo mount --all --fstab /mnt/etc/fstab --target-prefix /mnt
  sudo arch-chroot /mnt pacman -Syu cinnamon cinnamon-session lightdm network-manager-applet
  sudo arch-chroot /mnt env CACHY_USER=$USERNAME /opt/cachy-setup/post-install.sh 30-desktop
  sudo umount -R /mnt
pacman runs interactively there, so you see and can answer whatever stopped it.
EOF
    exit 1
fi

section "Done"
cat <<EOF
Installation complete. Next:
  1. Remove the USB stick and reboot.
  2. Log in to Cinnamon. A one-time first-boot service finishes the rest
     (firewall rules, power profile, GE-Proton, Ollama model pull).
     Check it with:  systemctl status cachy-firstboot
  3. Read /opt/cachy-setup/README.md for passthrough + Claude Code next steps.
EOF
if ((!ASSUME_YES)); then
    read -rp "Reboot now? [y/N] " r
    if is_true "$r"; then systemctl reboot; fi
fi
