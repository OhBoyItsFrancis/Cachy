# shellcheck shell=bash
# Keep a copy of this repo on the system and leave the user a short guide.

if [[ "$(realpath "$CACHY_ROOT")" != /opt/cachy-setup ]]; then
    install -d /opt/cachy-setup
    rsync -a --delete --exclude .git "$CACHY_ROOT/" /opt/cachy-setup/
fi
[[ -f /opt/cachy-setup/config.env ]] && chmod 0600 /opt/cachy-setup/config.env

desk="/home/$USERNAME/Desktop"
install -d "$desk"
write_file "$desk/NEXT-STEPS.txt" <<EOF
Welcome to your CachyOS setup.  Full docs: /opt/cachy-setup/README.md

1. Tailscale:        tailscale up                (log in in the browser)
2. Claude Code:      claude                      (then /login)
   Local model:      claude-local                (Ollama on the 3080)
   Claude Desktop:   in the menu under "Claude"
3. JetBrains:        Toolbox opens at login -> install IntelliJ IDEA + WebStorm
4. Spotify:          first start of "Spotify" downloads the official client
5. Steam:            Settings > Compatibility > enable Steam Play.
                     Launch-option tips: ~/Documents/steam-launch-options.md
6. Windows 11 VM:    download the Win11 ISO from microsoft.com, then
                       sudo cachy-vfio-check                 (IOMMU groups OK?)
                       sudo cachy-vm create --iso ~/Downloads/Win11*.iso
                       (install Windows in virt-manager, NVIDIA driver inside)
                       sudo cachy-vm passthrough on
                       cachy-vm start     (or the "Windows 11 VM" menu entry)
   Mode now: $(sed -n 's/^MODE=//p' /etc/cachy-vfio.conf 2>/dev/null || echo n/a)  (switch: sudo cachy-vfio-mode single|hybrid)
7. Re-run setup:     sudo /opt/cachy-setup/post-install.sh [module]
EOF
chown -R "$USERNAME:" "$desk"
ok "finished"
