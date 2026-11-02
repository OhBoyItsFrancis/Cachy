#!/usr/bin/env bash
# One-time tasks that need a running system (not possible in arch-chroot).
# Run by cachy-firstboot.service; re-run by hand with:
#   sudo rm /var/lib/cachy-setup/firstboot.done && sudo systemctl start cachy-firstboot
set -u
source /etc/cachy-firstboot.conf          # USERNAME, flags, model
DONE=/var/lib/cachy-setup/firstboot.done
log() { echo "[cachy-firstboot] $*"; }
fail=0

# Wait for the network (Ollama pull, GE-Proton download)
for _ in $(seq 1 60); do
    curl -fsS --max-time 5 -o /dev/null https://github.com && break
    sleep 5
done

# 1. Firewall: CachyOS enables ufw (deny incoming). Allow libvirt's NAT
#    network and Tailscale.
if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
    ufw allow in on virbr0 comment 'libvirt DHCP/DNS'
    ufw route allow in on virbr0 comment 'libvirt NAT'
    ufw route allow out on virbr0 comment 'libvirt NAT'
    ufw allow in on tailscale0 comment 'Tailscale'
    ufw allow 41641/udp comment 'Tailscale direct connections'
    log "ufw rules added"
fi

# 2. libvirt default NAT network
if command -v virsh >/dev/null; then
    virsh -c qemu:///system net-info default >/dev/null 2>&1 \
        || virsh -c qemu:///system net-define /usr/share/libvirt/networks/default.xml
    virsh -c qemu:///system net-autostart default
    virsh -c qemu:///system net-start default 2>/dev/null || true
    log "libvirt default network ready"
fi

# 3. CPU power profile
if [[ "${PERFORMANCE_PROFILE:-false}" == true ]] && command -v powerprofilesctl >/dev/null; then
    powerprofilesctl set performance && log "power profile: performance" || fail=1
fi

# 4. Tailscale: let the desktop user manage it without sudo
if command -v tailscale >/dev/null; then
    for _ in 1 2 3 4 5; do
        tailscale set --operator="$USERNAME" 2>/dev/null && { log "tailscale operator: $USERNAME"; break; }
        sleep 3
    done
fi

# 5. GE-Proton (retry if the chroot download failed)
if [[ "${INSTALL_GE_PROTON:-false}" == true ]] && \
   ! compgen -G "/home/$USERNAME/.local/share/Steam/compatibilitytools.d/GE-Proton*" >/dev/null; then
    runuser -u "$USERNAME" -- env HOME="/home/$USERNAME" /usr/local/bin/cachy-ge-proton || fail=1
fi

# 6. Local model for claude-local
if [[ -n "${OLLAMA_MODEL:-}" ]] && systemctl is-active --quiet ollama; then
    log "pulling $OLLAMA_MODEL (can take a while)"
    ollama pull "$OLLAMA_MODEL" || fail=1
fi

if ((fail == 0)); then
    mkdir -p "$(dirname "$DONE")" && touch "$DONE"
    log "all done"
else
    log "some steps failed; will retry on next boot"
fi
exit 0
