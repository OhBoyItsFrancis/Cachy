# shellcheck shell=bash
# Gaming: CachyOS gaming stack + tweaks gathered from archgaming (xi-Rick),
# Nobara / GloriousEggroll, Bazzite and SteamOS defaults. CachyOS already ships
# much of what those projects add by hand (BORE scheduler, ntsync, zram,
# THP/IO-scheduler/sysctl tuning in cachyos-settings), so this only fills gaps.

# cachyos-gaming-meta: wine-cachyos, proton-cachyos (SLR), umu, winetricks,
#   protontricks, 32-bit libs. cachyos-gaming-applications: Steam, Lutris,
#   Heroic, MangoHud, Gamescope, GOverlay.
pkg_install cachyos-gaming-meta cachyos-gaming-applications
pkg_install steam gamemode lib32-gamemode mangohud lib32-mangohud gamescope \
    protonup-qt lact vulkan-icd-loader lib32-vulkan-icd-loader lib32-nvidia-utils \
    ananicy-cpp cachyos-ananicy-rules scx-scheds scx-manager

usermod -aG gamemode "$USERNAME" 2>/dev/null || true

# ---- sysctl ---------------------------------------------------------------------------
# vm.max_map_count: SteamOS/Bazzite value; some games (and Star Citizen, DayZ,
#   Hogwarts Legacy...) crash when they run out of memory mappings.
# split_lock_mitigate=0: don't penalise games that do split locks (Nobara,
#   Bazzite, SteamOS). Ignored on CPUs without split-lock detection.
write_file /etc/sysctl.d/80-cachy-gaming.conf <<'EOF'
# Managed by cachy-setup (modules/40-gaming.sh)
vm.max_map_count = 2147483642
kernel.split_lock_mitigate = 0
# Lower latency networking for online games
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
EOF

# ---- GameMode --------------------------------------------------------------------------
# Start games with:  gamemoderun %command%   (Steam launch options)
write_file /etc/gamemode.ini <<'EOF'
; Managed by cachy-setup (modules/40-gaming.sh)
[general]
renice=10
softrealtime=auto
ioprio=0
inhibit_screensaver=1
desiredgov=performance
; No [gpu] section on purpose: gamemode addresses GPUs by /sys/class/drm/cardN
; index, which isn't stable with the iGPU + 3080 both present. Use LACT for
; 3080 clocks/power limit/fan curve instead.

[custom]
start=notify-send -a GameMode "GameMode on"
end=notify-send -a GameMode "GameMode off"
EOF

# ---- Session environment for games -------------------------------------------------------
# Sourced by LightDM's Xsession (bash), so it applies to the Cinnamon session
# whatever the login shell is.
write_file /etc/profile.d/cachy-gaming.sh <<'EOF'
# Managed by cachy-setup (modules/40-gaming.sh)
# Bigger NVIDIA shader cache (default 1 GB) and never auto-delete it:
# fewer shader-compile stutters after driver updates / in large games.
export __GL_SHADER_DISK_CACHE_SIZE=12000000000
export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
EOF

# ---- Services -------------------------------------------------------------------------------
svc_enable ananicy-cpp.service lactd.service

# ---- Proton ----------------------------------------------------------------------------------
# proton-cachyos comes from cachyos-gaming-meta. GE-Proton is installed into
# the user's compatibilitytools.d (and can be updated with cachy-ge-proton or
# ProtonUp-Qt).
install -Dm0755 "$CACHY_ROOT/bin/cachy-ge-proton" /usr/local/bin/cachy-ge-proton
if is_true "$INSTALL_GE_PROTON"; then
    as_user /usr/local/bin/cachy-ge-proton >>"$CACHY_LOG" 2>&1 \
        || warn "GE-Proton download failed; first boot will retry"
fi

# Steam launch option cheat-sheet for the user
install -Dm0644 "$CACHY_ROOT/docs/steam-launch-options.md" "/home/$USERNAME/Documents/steam-launch-options.md"
chown -R "$USERNAME:" "/home/$USERNAME/Documents"
ok "gaming done"
