# shellcheck shell=bash
# Cinnamon desktop polish. The CachyOS installer already installed cinnamon,
# lightdm and the base desktop set (pipewire, fonts, NetworkManager, ...).

pkg_install cinnamon cinnamon-translations lightdm lightdm-slick-greeter \
    nemo nemo-fileroller nemo-share file-roller \
    xed xreader xviewer gnome-terminal gnome-calculator gnome-system-monitor \
    gnome-disk-utility gnome-screenshot gnome-keyring seahorse \
    blueman network-manager-applet system-config-printer \
    pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber pavucontrol \
    papirus-icon-theme noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-jetbrains-mono-nerd \
    xdg-user-dirs xclip

# ---- LightDM ------------------------------------------------------------------
install -d /etc/lightdm/lightdm.conf.d
{
    echo "# Managed by cachy-setup"
    echo "[Seat:*]"
    echo "greeter-session=lightdm-slick-greeter"
    echo "user-session=cinnamon"
    if is_true "$AUTOLOGIN"; then
        echo "autologin-user=$USERNAME"
        echo "autologin-session=cinnamon"
    fi
} | write_file /etc/lightdm/lightdm.conf.d/50-cachy.conf
if is_true "$AUTOLOGIN"; then
    getent group autologin >/dev/null || groupadd -r autologin
    usermod -aG autologin "$USERNAME"
fi
write_file /etc/lightdm/slick-greeter.conf <<'EOF'
[Greeter]
icon-theme-name=Papirus-Dark
theme-name=Adwaita-dark
draw-user-backgrounds=true
EOF
# Make sure no other display manager is enabled, then enable LightDM
for dm in sddm gdm ly; do svc_disable "$dm.service"; done
svc_enable lightdm.service

# ---- Cinnamon defaults (system-wide, user can still change them) -----------------
# - flat mouse acceleration: 1:1 input for games
# - dark theme + Papirus icons
# - keep the compositor from redirecting fullscreen games (Muffin default, made explicit)
write_file /usr/share/glib-2.0/schemas/zz_cachy-setup.gschema.override <<'EOF'
[org.cinnamon.desktop.peripherals.mouse]
accel-profile='flat'

[org.cinnamon.desktop.interface]
icon-theme='Papirus-Dark'
gtk-theme='Adwaita-dark'

[org.x.apps.portal]
color-scheme='prefer-dark'

[org.cinnamon.muffin]
unredirect-fullscreen-windows=true

[org.cinnamon.desktop.default-applications.terminal]
exec='gnome-terminal'
EOF
glib-compile-schemas /usr/share/glib-2.0/schemas >>"$CACHY_LOG" 2>&1 \
    || { warn "schema override rejected, removing it"; rm -f /usr/share/glib-2.0/schemas/zz_cachy-setup.gschema.override; glib-compile-schemas /usr/share/glib-2.0/schemas; }

as_user xdg-user-dirs-update >>"$CACHY_LOG" 2>&1 || true

# PipeWire for the user session (enabled globally for all users)
user_svc_enable pipewire.socket pipewire-pulse.socket wireplumber.service
ok "desktop done"
