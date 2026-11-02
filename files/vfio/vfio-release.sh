#!/usr/bin/env bash
# Give the RTX 3080 back to the host after the VM stops.
# Called by /etc/libvirt/hooks/qemu on "release" (libvirt has already re-attached
# the managed hostdevs to the host by then), and by vfio-prepare.sh on rollback.
set -u
DOMAIN="$1"
source /etc/cachy-vfio.conf
STATE=/run/cachy-vfio
log() { echo "$(date '+%F %T') [release $DOMAIN/$MODE] $*"; }
log "start"

# 1. All CPUs back to the host
if [[ -n "${HOST_CPUS:-}" ]]; then
    all="0-$(($(nproc --all) - 1))"
    for unit in user.slice system.slice init.scope; do
        systemctl set-property --runtime -- "$unit" AllowedCPUs="$all"
    done
fi

# 2. NVIDIA driver back
modprobe nvidia
modprobe nvidia_modeset
modprobe nvidia_uvm
modprobe nvidia_drm
log "nvidia loaded"

# 3. Single mode: console + desktop back
if [[ "$MODE" == single ]]; then
    if [[ -f "$STATE/vtconsoles" ]]; then
        while read -r vt; do
            [[ -n "$vt" && -e "/sys/class/vtconsole/$vt/bind" ]] && echo 1 >"/sys/class/vtconsole/$vt/bind"
        done <"$STATE/vtconsoles"
    fi
    if [[ -s "$STATE/display-manager" ]]; then
        log "starting $(cat "$STATE/display-manager")"
        systemctl start "$(cat "$STATE/display-manager")"
    else
        systemctl start display-manager.service
    fi
fi

# 4. Services stopped in prepare
if [[ -f "$STATE/stopped-services" ]]; then
    while read -r svc; do
        [[ -n "$svc" ]] && systemctl start "$svc" && log "started $svc"
    done <"$STATE/stopped-services"
fi

systemctl stop "libvirt-nosleep@${DOMAIN}.service"
rm -rf "$STATE"
log "done"
