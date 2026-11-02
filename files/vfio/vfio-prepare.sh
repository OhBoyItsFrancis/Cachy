#!/usr/bin/env bash
# Free the RTX 3080 (and optionally the PCIe USB card) for a VM.
# Called by /etc/libvirt/hooks/qemu on "prepare". libvirt itself then binds the
# devices to vfio-pci (hostdev managed='yes'), so we only have to make sure
# nothing on the host is still using them.
#
# single mode: the 3080 drives the desktop -> stop LightDM/Cinnamon, release
#              the console, unload the NVIDIA driver.
# hybrid mode: the desktop runs on the iGPU -> only stop GPU users (Ollama,
#              LACT, ...) and unload the NVIDIA driver. The desktop keeps running.
#
# Unlike the original single-GPU scripts, this never unloads drm,
# drm_kms_helper or amdgpu: the 7700X iGPU shares them.
set -u
DOMAIN="$1"
source /etc/cachy-vfio.conf
STATE=/run/cachy-vfio
mkdir -p "$STATE"
log() { echo "$(date '+%F %T') [prepare $DOMAIN/$MODE] $*"; }

rollback() {
    log "FAILED: $*  -- rolling back"
    /usr/local/lib/cachy-vfio/vfio-release.sh "$DOMAIN"
    exit 1
}

log "start"
systemctl start "libvirt-nosleep@${DOMAIN}.service"

# 1. Services that keep /dev/nvidia* open
: >"$STATE/stopped-services"
for svc in ${GPU_SERVICES:-}; do
    if systemctl is-active --quiet "$svc"; then
        log "stopping $svc"
        systemctl stop "$svc" && echo "$svc" >>"$STATE/stopped-services"
    fi
done

# 2. Single mode: take the desktop down
if [[ "$MODE" == single ]]; then
    : >"$STATE/display-manager"
    if systemctl is-active --quiet display-manager.service; then
        systemctl show -p Id --value display-manager.service >"$STATE/display-manager"
        log "stopping display manager $(cat "$STATE/display-manager")"
        systemctl stop display-manager.service
    fi
    for _ in $(seq 1 20); do
        pgrep -x Xorg >/dev/null || pgrep -x cinnamon >/dev/null || break
        sleep 0.5
    done

    # Release virtual consoles bound to the framebuffer
    : >"$STATE/vtconsoles"
    for vt in /sys/class/vtconsole/vtcon*; do
        if grep -q "frame buffer" "$vt/name" 2>/dev/null && [[ "$(cat "$vt/bind")" == 1 ]]; then
            echo 0 >"$vt/bind" && basename "$vt" >>"$STATE/vtconsoles"
        fi
    done
    # Boot framebuffers, if a firmware one is still around (simpledrm/efifb)
    for fb in /sys/bus/platform/drivers/efi-framebuffer/efi-framebuffer.0 \
              /sys/bus/platform/drivers/simple-framebuffer/simple-framebuffer.0; do
        [[ -e "$fb" ]] && echo "$(basename "$fb")" >"$(dirname "$fb")/unbind"
    done
    sleep 1
fi

# 3. Anything else still holding the NVIDIA device nodes?
read -r -a holders < <(fuser /dev/nvidia* 2>/dev/null | tr -s ' ' '\n' | sort -u | tr '\n' ' ')
if ((${#holders[@]})); then
    pids="$(IFS=,; echo "${holders[*]}")"
    if [[ "$MODE" == single ]]; then
        log "killing leftover GPU users: $(ps -o pid=,comm= -p "$pids" | tr -s ' \n' ' ')"
        fuser -k /dev/nvidia* >/dev/null 2>&1
        sleep 2
    else
        # Hybrid: don't kill the user's apps, refuse to start instead
        rollback "processes still use the 3080 (close them and retry): $(ps -o pid=,comm= -p "$pids" | tr -s ' \n' ' ')"
    fi
fi

# 4. Unload the NVIDIA driver stack (retry: Xorg can take a moment to let go)
for _ in 1 2 3 4 5; do
    modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia 2>/dev/null && break
    sleep 1
done
if lsmod | grep -q '^nvidia '; then
    rollback "could not unload nvidia: $(lsmod | grep ^nvidia | tr -s ' ' | tr '\n' ';')"
fi
log "nvidia unloaded"
modprobe vfio-pci

# 5. Give the host only HOST_CPUS while the VM runs (vCPUs are pinned to the rest)
if [[ -n "${HOST_CPUS:-}" ]]; then
    systemctl set-property --runtime -- user.slice AllowedCPUs="$HOST_CPUS"
    systemctl set-property --runtime -- system.slice AllowedCPUs="$HOST_CPUS"
    systemctl set-property --runtime -- init.scope AllowedCPUs="$HOST_CPUS"
    log "host limited to CPUs $HOST_CPUS"
fi
log "done"
