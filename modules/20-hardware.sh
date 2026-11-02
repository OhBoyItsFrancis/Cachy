# shellcheck shell=bash
# Hardware: MSI PRO B650-S WIFI + Ryzen 7 7700X + RTX 3080 (GA102) + PCIe USB card.

# ---- NVIDIA ---------------------------------------------------------------------
# chwd (run by the CachyOS installer) normally picks the open kernel modules
# (linux-cachyos-nvidia-open), the right choice for Ampere. Re-run it if the
# driver is missing, e.g. after a Calamares install without "proprietary drivers".
if [[ -n "$GPU_PCI" ]] && ! pkg_installed nvidia-utils; then
    info "NVIDIA driver missing, running chwd"
    chwd -a -f >>"$CACHY_LOG" 2>&1 || warn "chwd failed; install nvidia manually: sudo chwd -a"
fi
pkg_install nvidia-settings libva-nvidia-driver vulkan-tools

# Driver options:
# - PreserveVideoMemoryAllocations + TemporaryFilePath: suspend/resume without
#   corrupting the desktop (needs the nvidia-suspend/resume services below)
# - UsePageAttributeTable: PAT instead of MTRR for write-combining, a small but
#   free win (also used by Nobara / CachyOS gaming guides)
# - modeset/fbdev are the defaults on current drivers; set explicitly so the
#   single-GPU hooks can count on nvidia-drm owning the console framebuffer
write_file /etc/modprobe.d/cachy-nvidia.conf <<'EOF'
# Managed by cachy-setup (modules/20-hardware.sh)
options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp NVreg_UsePageAttributeTable=1
options nvidia_drm modeset=1 fbdev=1
EOF
svc_enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
# nvidia-persistenced keeps /dev/nvidia* open, which blocks handing the GPU to
# the VM. The desktop keeps the driver loaded anyway, so it buys nothing here.
svc_disable nvidia-persistenced.service

# ---- CPU: Ryzen 7 7700X -------------------------------------------------------------
# amd-pstate (active/EPP) is the CachyOS default on Zen 4; power-profiles-daemon
# drives EPP. "performance" is set on first boot (PERFORMANCE_PROFILE).
pkg_install power-profiles-daemon cpupower
svc_enable power-profiles-daemon.service
# AMD microcode is loaded by the CachyOS initramfs (amd-ucode)
pkg_install amd-ucode

# ---- iGPU (Radeon in the 7700X) -----------------------------------------------------
# Needed for hybrid VFIO mode (desktop on the motherboard outputs). chwd adds
# mesa for it too; harmless when the iGPU is disabled in BIOS.
if [[ -n "$IGPU_PCI" ]]; then
    pkg_install mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
fi

# ---- Kernel command line ---------------------------------------------------------------
# amd_iommu=on is the default but explicit is clearer; iommu=pt keeps host DMA
# fast (only passthrough devices get translated).
params="amd_iommu=on iommu=pt"
is_true "$MITIGATIONS_OFF" && params+=" mitigations=off"
add_kernel_params "$params"

# ---- Sensors ------------------------------------------------------------------------------
# lm_sensors for CPU (k10temp) / NVMe temps. The MSI board's Nuvoton NCT6687D
# Super-I/O (fans, VRM temp) needs the out-of-tree nct6687d-dkms from the AUR.
pkg_install lm_sensors
ok "hardware done"
