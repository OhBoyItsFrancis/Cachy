# shellcheck shell=bash
# QEMU/KVM + libvirt + virt-manager, and GPU passthrough of the RTX 3080 and
# the PCIe USB card to a Windows 11 VM, switchable between:
#   single: ilayna-style single-GPU passthrough (desktop stops while VM runs)
#   hybrid: desktop on the 7700X iGPU, 3080 free for the VM at any time

pkg_install qemu-full libvirt virt-manager virt-install virt-viewer \
    edk2-ovmf swtpm dnsmasq openbsd-netcat dmidecode psmisc python

# ---- libvirt -----------------------------------------------------------------------
# Socket permissions for the libvirt group (as in the ilayna guide) + a log
conf=/etc/libvirt/libvirtd.conf
for line in 'unix_sock_group = "libvirt"' 'unix_sock_rw_perms = "0770"'; do
    grep -qxF "$line" "$conf" || echo "$line" >>"$conf"
done
usermod -aG libvirt,kvm "$USERNAME"
svc_enable libvirtd.service
# virt-manager: connect to the system instance by default
install -d /etc/libvirt
grep -q '^uri_default' /etc/libvirt/libvirt.conf 2>/dev/null \
    || echo 'uri_default = "qemu:///system"' >>/etc/libvirt/libvirt.conf

# ---- VM image storage: its own btrfs subvolume, copy-on-write disabled -------------------
# Keeps multi-GB qcow2 images out of root snapshots and avoids CoW fragmentation.
img=/var/lib/libvirt/images
if [[ "$(findmnt -no FSTYPE /)" == btrfs ]] && ! btrfs subvolume show "$img" &>/dev/null; then
    if [[ -d "$img" ]] && [[ -z "$(ls -A "$img")" ]]; then rmdir "$img"; fi
    if [[ ! -e "$img" ]]; then
        install -d "$(dirname "$img")"
        btrfs subvolume create "$img" >>"$CACHY_LOG" 2>&1
        ok "created btrfs subvolume $img"
    fi
fi
install -d -m0711 "$img"
chattr +C "$img" 2>/dev/null || true

# ---- passthrough config -------------------------------------------------------------------
[[ -n "$GPU_PCI" ]] || warn "no NVIDIA GPU detected; set GPU_PCI in config.env and re-run 70-virtualization"
if is_true "$PASSTHROUGH_USB_CONTROLLER" && [[ -z "$USB_CONTROLLER_PCI" ]]; then
    warn "could not pick the PCIe USB card automatically; run cachy-vfio-check and set USB_CONTROLLER_PCI in /etc/cachy-vfio.conf"
fi
GPU_SERVICES="ollama.service lactd.service nvidia-persistenced.service"
existing_mode=""
[[ -f /etc/cachy-vfio.conf ]] && existing_mode="$(sed -n 's/^MODE=//p' /etc/cachy-vfio.conf)"
write_file /etc/cachy-vfio.conf <<EOF
# cachy-setup VFIO configuration (read by libvirt hooks, cachy-vm, cachy-vfio-mode)
# Change MODE with: sudo cachy-vfio-mode single|hybrid
MODE=${existing_mode:-$VFIO_MODE}
VM_NAME="$VM_NAME"
# Domains the hooks act on (space separated)
VM_NAMES="$VM_NAME"
GPU_PCI=$GPU_PCI
IGPU_PCI=$IGPU_PCI
USB_CONTROLLER_PCI=$USB_CONTROLLER_PCI
PASSTHROUGH_USB_CONTROLLER=$PASSTHROUGH_USB_CONTROLLER
GPU_ROM_FILE="$GPU_ROM_FILE"
# Host keeps these CPUs while the VM runs; vCPUs get the remaining cores
HOST_CPUS="$HOST_CPUS"
VM_VCPU_CORES=$VM_VCPU_CORES
VM_MEMORY_GB=$VM_MEMORY_GB
VM_DISK_GB=$VM_DISK_GB
# Services that hold /dev/nvidia*; stopped while the VM owns the GPU
GPU_SERVICES="$GPU_SERVICES"
EOF

# ---- hooks + tools ----------------------------------------------------------------------------
install_file libvirt/hooks/qemu /etc/libvirt/hooks/qemu 0755
install_file vfio/vfio-prepare.sh /usr/local/lib/cachy-vfio/vfio-prepare.sh 0755
install_file vfio/vfio-release.sh /usr/local/lib/cachy-vfio/vfio-release.sh 0755
install_file vfio/libvirt-nosleep@.service /etc/systemd/system/libvirt-nosleep@.service 0644
for t in cachy-vm cachy-vfio-mode cachy-vfio-check; do
    install -Dm0755 "$CACHY_ROOT/bin/$t" "/usr/local/bin/$t"
done
install -d /var/log/libvirt

# Xorg layout for the chosen mode (applies at next LightDM start)
mode="${existing_mode:-$VFIO_MODE}"
if [[ -n "$GPU_PCI" ]] && ! /usr/local/bin/cachy-vfio-mode "$mode" --no-restart >>"$CACHY_LOG" 2>&1; then
    warn "cachy-vfio-mode $mode failed (hybrid needs the iGPU enabled in BIOS); using single"
    /usr/local/bin/cachy-vfio-mode single --no-restart >>"$CACHY_LOG" 2>&1 || warn "cachy-vfio-mode single failed"
fi

# Desktop launcher: start the VM (in single mode this ends the Cinnamon session)
write_file /usr/share/applications/cachy-windows-vm.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Windows 11 VM (GPU passthrough)
Comment=Start the $VM_NAME VM with the RTX 3080
Exec=sh -c 'virsh -c qemu:///system start $VM_NAME || notify-send "VM" "Could not start $VM_NAME: run cachy-vm status"'
Icon=computer
Categories=System;Emulator;
EOF
ok "virtualization done"
