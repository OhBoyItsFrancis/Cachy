# shellcheck shell=bash
# Applications: Bitwarden, Figma, Helium, IntelliJ IDEA + WebStorm (Toolbox),
# Prism Launcher, Spotify, Steam (40-gaming), Tailscale, Vesktop, VLC.
#
# Repo packages first (CachyOS repos carry helium-browser-bin and vesktop-bin
# prebuilt); only two things come from the AUR.

pkg_install \
    bitwarden \
    helium-browser-bin \
    prismlauncher jre21-openjdk jre17-openjdk jre8-openjdk \
    spotify-launcher \
    tailscale \
    vesktop-bin \
    vlc vlc-plugins-all

# AUR:
#  - jetbrains-toolbox: installs/updates IntelliJ IDEA and WebStorm, handles
#    the JetBrains account/licence. IDEs are installed from Toolbox after login.
#  - figma-agent-linux: lets figma.com use locally installed fonts
aur_install jetbrains-toolbox figma-agent-linux

# ---- Tailscale ----------------------------------------------------------------------
svc_enable tailscaled.service
# `tailscale up` needs an interactive login; first boot sets the operator so
# the user can run `tailscale up` / use the tray without sudo.

# ---- Figma as an app window in Helium --------------------------------------------------
write_file /usr/local/bin/figma 0755 <<'EOF'
#!/bin/sh
# Figma in its own Helium app window with a separate profile
exec helium-browser --app=https://www.figma.com/files --class=FigmaApp \
    --user-data-dir="$HOME/.local/share/figma-helium" "$@"
EOF
write_file /usr/share/applications/figma-helium.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Figma
Comment=Figma in its own Helium app window
Exec=/usr/local/bin/figma
Icon=applications-graphics
Categories=Graphics;Development;
StartupWMClass=FigmaApp
EOF
# figma-agent (local fonts for figma.com) is socket-activated per user
if [[ -f /usr/lib/systemd/user/figma-agent.socket ]]; then
    user_svc_enable figma-agent.socket
fi

# ---- Helium as default browser ------------------------------------------------------------
mimeapps="/home/$USERNAME/.config/mimeapps.list"
if [[ ! -f "$mimeapps" ]]; then
    write_file "$mimeapps" <<'EOF'
[Default Applications]
text/html=helium.desktop
x-scheme-handler/http=helium.desktop
x-scheme-handler/https=helium.desktop
x-scheme-handler/about=helium.desktop
x-scheme-handler/unknown=helium.desktop
EOF
    chown -R "$USERNAME:" "/home/$USERNAME/.config"
fi

# ---- JetBrains Toolbox autostart (first login opens it so you can install IDEs) ---------
if pkg_installed jetbrains-toolbox; then
    install -d "/home/$USERNAME/.config/autostart"
    write_file "/home/$USERNAME/.config/autostart/jetbrains-toolbox.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=JetBrains Toolbox
Exec=jetbrains-toolbox --minimize
Icon=jetbrains-toolbox
X-GNOME-Autostart-enabled=true
EOF
    chown -R "$USERNAME:" "/home/$USERNAME/.config/autostart"
fi

# JetBrains IDEs index lots of files; raise the inotify watch limit
write_file /etc/sysctl.d/80-cachy-ide.conf <<'EOF'
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1024
EOF
ok "apps done"
