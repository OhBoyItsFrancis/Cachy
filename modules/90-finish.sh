# shellcheck shell=bash
# Keep a copy of this repo on the system and leave the user a short guide.

if [[ "$(realpath "$CACHY_ROOT")" != /opt/cachy-setup ]]; then
    install -d /opt/cachy-setup
    rsync -a --delete --exclude .git "$CACHY_ROOT/" /opt/cachy-setup/
fi
[[ -f /opt/cachy-setup/config.env ]] && chmod 0600 /opt/cachy-setup/config.env

# Git working copy for future tweaks (install.sh puts one in ~/Cachy)
if [[ -d "/home/$USERNAME/Cachy" ]]; then
    chown -R "$USERNAME:" "/home/$USERNAME/Cachy"
fi

# Claude Code: a short pointer in the user's global memory, so every session on
# this machine knows where the system documentation is. Replaced on re-runs.
claude_md="/home/$USERNAME/.claude/CLAUDE.md"
install -d "$(dirname "$claude_md")"
touch "$claude_md"
sed -i '/<!-- cachy-setup:begin -->/,/<!-- cachy-setup:end -->/d' "$claude_md"
cat >>"$claude_md" <<'EOF'
<!-- cachy-setup:begin -->
## This machine (cachy-setup)
This PC was installed and configured by cachy-setup: CachyOS + Cinnamon (X11), RTX 3080 with
switchable single/hybrid GPU passthrough to a Windows 11 VM, gaming tweaks, Claude Code + Ollama.
Before changing system configuration (packages, /etc, kernel parameters, drivers, services,
libvirt/VFIO, Xorg), read /opt/cachy-setup/docs/SYSTEM.md and follow its section 0.
Make lasting changes in the git working copy ~/Cachy (running `claude` there loads the full doc),
then deploy and re-run the affected module.
<!-- cachy-setup:end -->
EOF
chown -R "$USERNAME:" "/home/$USERNAME/.claude"

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
