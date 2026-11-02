# shellcheck shell=bash
# Base system: pacman tuning, AUR helper, snapshots, everyday CLI tools.

# pacman: parallel downloads, colour, and the CachyOS repos are already set
# up (and ordered for znver4 / x86-64-v4) by the CachyOS installer.
sed -i -E 's/^#?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sed -i -E 's/^#Color$/Color/; s/^#VerbosePkgLists$/VerbosePkgLists/' /etc/pacman.conf
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>/etc/pacman.conf
fi
info "repos: $(grep -oE '^\[[a-z0-9-]+\]' /etc/pacman.conf | tr '\n' ' ' || true)"

info "syncing and updating the system"
pacman -Syu --noconfirm >>"$CACHY_LOG" 2>&1 || warn "system update failed, continuing"

pkg_install base-devel git paru pacman-contrib rebuild-detector \
    curl wget rsync jq unzip p7zip htop btop fastfetch nvtop \
    man-db man-pages bash-completion pciutils usbutils lshw dmidecode \
    smartmontools nvme-cli fwupd \
    flatpak xdg-desktop-portal xdg-desktop-portal-gtk

# btrfs snapshots: snapper + automatic pre/post pacman snapshots, bootable
# from the Limine menu when Limine is the bootloader.
if [[ "$(findmnt -no FSTYPE /)" == btrfs ]]; then
    pkg_install snapper snap-pac btrfs-assistant cachyos-snapper-support
    if [[ -f /etc/default/limine ]]; then
        pkg_install limine-snapper-sync
        svc_enable limine-snapper-sync.service
    fi
    svc_enable snapper-cleanup.timer
    # Keep the snapshot count sane on the root config if cachyos-snapper-support made one
    if [[ -f /etc/snapper/configs/root ]]; then
        sed -i -E 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="10"/; s/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="5"/' /etc/snapper/configs/root
    fi
fi

# Firmware updates for the MSI board / NVMe via LVFS
svc_enable fwupd-refresh.timer

# Weekly SSD TRIM (CachyOS enables it, make sure)
svc_enable fstrim.timer

# Flathub, for anything that's not packaged (nothing in this setup needs it,
# but it saves a step later)
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >>"$CACHY_LOG" 2>&1 \
    || warn "could not add Flathub"

# User groups used by later modules
for g in wheel video audio input render; do
    getent group "$g" >/dev/null && usermod -aG "$g" "$USERNAME"
done
ok "base done"
