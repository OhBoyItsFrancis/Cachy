#!/usr/bin/env bash
# =============================================================================
# Cachy post-install: turns a CachyOS (Cinnamon) install into the full setup.
#
# Called automatically by install.sh inside arch-chroot, or run by hand on an
# installed system (e.g. after using the Calamares GUI installer):
#
#   sudo ./post-install.sh                 # all modules
#   sudo ./post-install.sh 40-gaming       # only selected modules
#   sudo ./post-install.sh --list
#
# Every module is idempotent; re-running is safe.
# =============================================================================
set -Eeuo pipefail

CACHY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CACHY_ROOT
: "${CACHY_LOG:=/var/log/cachy-setup.log}"
export CACHY_LOG
# shellcheck source=lib/common.sh
source "$CACHY_ROOT/lib/common.sh"

CHROOT_MODE=0
ONLY=()
while (($#)); do
    case "$1" in
        --chroot) CHROOT_MODE=1 ;;
        --list) for m in "$CACHY_ROOT"/modules/*.sh; do basename "$m" .sh; done; exit 0 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) ONLY+=("${1%.sh}") ;;
    esac
    shift
done
export CHROOT_MODE

require_root
load_config "$CACHY_ROOT"
# Target user: CACHY_USER (set by install.sh) > config USERNAME if that user
# exists here > the user who ran sudo. (Not $USERNAME from the environment:
# sudo sets that to root.)
if [[ -n "${CACHY_USER:-}" ]]; then
    USERNAME="$CACHY_USER"
elif ! id "$USERNAME" &>/dev/null && [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
    USERNAME="$SUDO_USER"
fi
export USERNAME
id "$USERNAME" &>/dev/null || die "user '$USERNAME' does not exist on this system"

install -d "$(dirname "$CACHY_LOG")"
trap 'aur_cleanup' EXIT

info "Cachy post-install for user '$USERNAME' ($(in_chroot && echo chroot || echo live system))"
_log "config: $(grep -vE '^\s*(#|$)' "$CACHY_ROOT/config.env" 2>/dev/null | tr '\n' ' ')"

# Record the detected PCI layout so tools/hooks share one source of truth
GPU_PCI="${GPU_PCI:-$(detect_gpu_pci)}"
USB_CONTROLLER_PCI="${USB_CONTROLLER_PCI:-$(detect_usb_controller_pci)}"
IGPU_PCI="$(detect_igpu_pci)"
export GPU_PCI USB_CONTROLLER_PCI IGPU_PCI
info "detected: NVIDIA=${GPU_PCI:-none} iGPU=${IGPU_PCI:-none} USB card=${USB_CONTROLLER_PCI:-none/ambiguous}"

rm -rf "$CACHY_STATE"; mkdir -p "$CACHY_STATE"
failed_modules=()
for mod in "$CACHY_ROOT"/modules/[0-9]*.sh; do
    name="$(basename "$mod" .sh)"
    if ((${#ONLY[@]})) && [[ ! " ${ONLY[*]} " == *" $name "* ]]; then continue; fi
    if [[ " $SKIP_MODULES " == *" $name "* ]]; then info "skipping $name (SKIP_MODULES)"; continue; fi
    section "$name"
    # Each module runs in a subshell with errexit: a failure stops that module
    # only, gets reported, and the remaining modules still run.
    # (errexit is ignored inside `if ( ... )`, hence the explicit set +e dance)
    set +e
    # shellcheck source=/dev/null
    ( set -Eeuo pipefail; trap 'warn "$name: failed at line $LINENO: $BASH_COMMAND"' ERR; source "$mod" )
    rc=$?
    set -e
    ((rc == 0)) || failed_modules+=("$name")
done

[[ -f "$CACHY_STATE/bootloader" ]] && regen_boot
if ((${#failed_modules[@]})); then
    warn "modules with errors: ${failed_modules[*]} (re-run: sudo $0 ${failed_modules[*]})"
fi
summary_report
if in_chroot; then
    info "chroot stage finished; first-boot service will do the rest"
else
    info "done. Reboot to apply kernel parameters and driver options."
fi
((${#failed_modules[@]} == 0))
