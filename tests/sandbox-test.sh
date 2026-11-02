#!/usr/bin/env bash
# Smoke test: run post-install.sh end to end on any Linux box, as root, without
# touching the real system. A private mount namespace puts throw-away overlays
# on /etc /usr /var /opt /home, and stub commands (tests/stubs) stand in for
# pacman, systemctl, lspci (with this machine's PCI layout), paru, etc.
#
#   sudo tests/sandbox-test.sh            # run + assertions
#   sudo tests/sandbox-test.sh --shell    # drop into the sandbox afterwards
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
[[ $EUID -eq 0 ]] || { echo "needs root (for mount namespaces)"; exit 1; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export REPO WORK SHELL_AFTER="${1:-}"

unshare -m --propagation private bash -euo pipefail <<'SANDBOX'
for d in etc usr var opt home root; do
    mkdir -p "$WORK/u/$d" "$WORK/w/$d"
    mount -t overlay overlay -o "lowerdir=/$d,upperdir=$WORK/u/$d,workdir=$WORK/w/$d" "/$d"
done
mount -t tmpfs tmpfs /tmp

export PATH="$REPO/tests/stubs:$PATH" STUB_DIR="$WORK/stub" CACHY_LOG=/var/log/cachy-setup.log
mkdir -p "$STUB_DIR"
# Pretend these don't exist in the repos, to exercise the retry/fallback path
echo "scx-scheds" >"$STUB_DIR/missing"

# Minimal Arch-like files the modules edit
mkdir -p /etc/default /etc/libvirt /usr/lib/systemd/user
cat >/etc/pacman.conf <<'EOF'
[options]
#Color
#ParallelDownloads = 5
#VerbosePkgLists
[cachyos-znver4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
cat >/etc/default/limine <<'EOF'
ESP_PATH="/boot"
KERNEL_CMDLINE[default]="root=UUID=1234 rw rootflags=subvol=/@ quiet splash nowatchdog"
BOOT_ORDER="*, *lts, *fallback, Snapshots"
EOF
echo '#unix_sock_group = "libvirt"' >/etc/libvirt/libvirtd.conf
touch /usr/lib/systemd/user/figma-agent.socket
id francis &>/dev/null || useradd -m -s /bin/bash francis
mkdir -p /home/francis/.claude && echo "my own notes" >/home/francis/.claude/CLAUDE.md
for g in libvirt kvm gamemode render; do getent group "$g" >/dev/null || groupadd "$g"; done

cp "$REPO/config.example.env" "$WORK/config.env"
rm -rf /opt/cachy-src && cp -a "$REPO" /opt/cachy-src && cp "$WORK/config.env" /opt/cachy-src/config.env

set +e
/opt/cachy-src/post-install.sh --chroot
rc=$?
set -e
echo "post-install rc=$rc"

fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
check "post-install exit 0"           "[[ $rc -eq 0 ]]"
check "kernel params added once"      "[[ \$(grep -o 'iommu=pt' /etc/default/limine | wc -l) -eq 1 ]] && grep -q 'amd_iommu=on' /etc/default/limine"
check "existing params kept"          "grep -q 'rootflags=subvol=/@ quiet splash nowatchdog' /etc/default/limine"
check "boot entries regenerated"      "grep -q '^limine-mkinitcpio' $STUB_DIR/calls"
check "pacman tuned"                  "grep -q '^ParallelDownloads = 10' /etc/pacman.conf && grep -q '^Color' /etc/pacman.conf"
check "missing pkg reported"          "grep -q scx-scheds /tmp/cachy-setup-state/failed"
check "nvidia modprobe options"       "grep -q NVreg_PreserveVideoMemoryAllocations=1 /etc/modprobe.d/cachy-nvidia.conf"
check "gaming sysctl"                 "grep -q 'vm.max_map_count = 2147483642' /etc/sysctl.d/80-cachy-gaming.conf"
check "lightdm slick greeter"         "grep -q lightdm-slick-greeter /etc/lightdm/lightdm.conf.d/50-cachy.conf"
check "vfio conf GPU"                 "grep -q '^GPU_PCI=0000:01:00.0' /etc/cachy-vfio.conf"
check "vfio conf USB card (ASMedia)"  "grep -q '^USB_CONTROLLER_PCI=0000:0b:00.0' /etc/cachy-vfio.conf"
check "vfio conf iGPU"                "grep -q '^IGPU_PCI=0000:0e:00.0' /etc/cachy-vfio.conf"
check "xorg single mode on 3080"      "grep -q 'BusID      \"PCI:1:0:0\"' /etc/X11/xorg.conf.d/10-cachy-gpu.conf"
check "libvirt hook installed"        "[[ -x /etc/libvirt/hooks/qemu ]]"
check "libvirt socket group"          "grep -qx 'unix_sock_group = \"libvirt\"' /etc/libvirt/libvirtd.conf"
check "user in libvirt group"         "id -nG francis | grep -qw libvirt"
check "AUR via paru"                  "grep -q 'paru -S .*jetbrains-toolbox' $STUB_DIR/calls"
check "AUR sudoers removed"           "[[ ! -e /etc/sudoers.d/99-cachy-setup-aur ]]"
check "firstboot enabled"             "grep -q 'systemctl enable cachy-firstboot.service' $STUB_DIR/calls"
check "figma launcher"                "[[ -x /usr/local/bin/figma ]] && grep -q /usr/local/bin/figma /usr/share/applications/figma-helium.desktop"
check "ollama override"               "grep -q OLLAMA_CONTEXT_LENGTH /etc/systemd/system/ollama.service.d/cachy.conf"
check "next steps file"               "[[ -f /home/francis/Desktop/NEXT-STEPS.txt ]] && [[ \$(stat -c %U /home/francis/Desktop/NEXT-STEPS.txt) == francis ]]"

echo "--- second run (idempotency) ---"
/opt/cachy-src/post-install.sh --chroot >/dev/null 2>&1 || true
check "kernel params still once"      "[[ \$(grep -o 'iommu=pt' /etc/default/limine | wc -l) -eq 1 ]]"
check "claude pointer once, notes kept" "[[ \$(grep -c 'cachy-setup:begin' /home/francis/.claude/CLAUDE.md) -eq 1 ]] && grep -q 'my own notes' /home/francis/.claude/CLAUDE.md && grep -q /opt/cachy-setup/docs/SYSTEM.md /home/francis/.claude/CLAUDE.md"
check "SYSTEM.md deployed"            "[[ -f /opt/cachy-setup/docs/SYSTEM.md ]]"
check "libvirtd.conf no duplicates"   "[[ \$(grep -cx 'unix_sock_group = \"libvirt\"' /etc/libvirt/libvirtd.conf) -eq 1 ]]"

echo "--- hybrid mode switch ---"
cachy-vfio-mode hybrid --no-restart >/dev/null
check "xorg hybrid on iGPU"           "grep -q 'BusID      \"PCI:14:0:0\"' /etc/X11/xorg.conf.d/10-cachy-gpu.conf && grep -q '^MODE=hybrid' /etc/cachy-vfio.conf"
cachy-vfio-mode single --no-restart >/dev/null

if [[ "$SHELL_AFTER" == --shell ]]; then bash -i; fi
((fail == 0)) && echo "ALL PASSED" || { echo "SOME CHECKS FAILED (log: tail of $CACHY_LOG below)"; tail -n 40 "$CACHY_LOG"; exit 1; }
SANDBOX
