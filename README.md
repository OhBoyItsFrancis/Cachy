# Cachy: an automated CachyOS install for one specific desktop

An unattended installer that builds a gaming + development + VFIO workstation on
[CachyOS](https://github.com/CachyOS), tuned for this machine:

| Part | Model | What the setup does with it |
|---|---|---|
| Motherboard | MSI PRO B650-S WIFI | UEFI + btrfs + Limine; Wi-Fi/2.5 GbE work out of the box (linux-firmware) |
| CPU | Ryzen 7 7700X (Zen 4, 8C/16T) | CachyOS `znver4`/x86-64-v4 repos, amd-pstate EPP + *performance* profile, VM vCPU pinning |
| iGPU | Radeon graphics in the 7700X | optional *hybrid* passthrough mode (desktop on the iGPU) |
| RAM | 32 GB DDR5 | zram (CachyOS default), 16 GB to the VM |
| GPU | Gigabyte RTX 3080 Gaming OC 10G | NVIDIA open kernel modules (via `chwd`), passthrough to Windows 11 |
| USB | PCIe USB controller card | passed through to the VM with the GPU (keyboard/mouse/headset go with it) |

Desktop: **Cinnamon** (LightDM + slick-greeter). Shell: **fish** (CachyOS config).

## How it works

```
CachyOS live ISO
└─ install.sh
   ├─ stage 1: cachyos-installer --config settings.json   (CachyOS's own CLI installer,
   │           headless mode: wipes TARGET_DISK, btrfs + Limine, linux-cachyos(+lts),
   │           Cinnamon, chwd drivers, user + fish)
   └─ stage 2: arch-chroot → post-install.sh               (this repo, module by module)
        10-base           pacman tuning, paru, snapper + bootable Limine snapshots, fwupd
        20-hardware       NVIDIA options, IOMMU kernel params, amd-pstate/ppd, sensors
        30-desktop        Cinnamon apps, LightDM slick-greeter, flat mouse accel, dark theme
        40-gaming         CachyOS gaming stack, GE-Proton, sysctl/GameMode/env tweaks
        50-apps           Bitwarden, Helium, Figma, JetBrains Toolbox, Prism, Spotify, Tailscale, Vesktop, VLC
        60-ai             Claude Code, Claude Desktop, Ollama (CUDA) + claude-local
        70-virtualization QEMU/libvirt/virt-manager, VFIO hooks, cachy-vm tooling
        80-firstboot      one-shot service for things that need a running system
        90-finish         copy of this repo in /opt/cachy-setup, ~/Desktop/NEXT-STEPS.txt
```

Using CachyOS's own installer for stage 1 means the base system is exactly what an
official install produces (same partition layout, subvolumes, mirrors, kernel and
driver detection), and this repo only layers changes on top. Every module is
idempotent and can be re-run on its own.

## Before you start: BIOS settings (MSI Click BIOS)

Update the BIOS first (MSI site → PRO B650-S WIFI → BIOS), then:

| Setting | Where (typical MSI layout) | Value |
|---|---|---|
| Boot mode | Settings → Advanced → Windows OS Configuration → BIOS UEFI/CSM Mode | **UEFI** (CSM off) |
| Secure Boot | Settings → Advanced → Windows OS Configuration → Secure Boot | **Disabled** (Limine isn't signed; you can enable it later with `sbctl`) |
| SVM (AMD-V) | OC → Advanced CPU Configuration → SVM Mode | **Enabled** |
| IOMMU | Settings → Advanced → AMD CBS → NBIO Common Options → IOMMU | **Enabled** |
| Above 4G Decoding / Re-Size BAR | Settings → Advanced → PCI Subsystem Settings | Enabled (if the VM shows *Code 43* or a black screen, try ReBAR **off**) |
| Integrated graphics | Settings → Advanced → Integrated Graphics Configuration | **Force**/Enabled if you want *hybrid* mode, otherwise either is fine |
| Primary display | same page → Initiate Graphic Adapter | **PEG** for single mode, **IGD** for hybrid mode |
| Memory | OC → A-XMP/EXPO | EXPO profile for your DDR5 |

## Install (fully automated path)

Step-by-step walkthrough with every variable explained: **[docs/install-guide.md](docs/install-guide.md)**.

1. Download the CachyOS **Desktop** ISO from <https://cachyos.org/download/> and write it to a USB stick.
2. Boot it (F11 on MSI boards for the boot menu), connect to the network (Wi-Fi: `nmtui`).
3. Open a terminal:
   ```bash
   git clone https://github.com/OhBoyItsFrancis/Cachy && cd Cachy
   ```
   ```bash
   cp config.example.env config.env && nano config.env
   ```
   At minimum set `TARGET_DISK` (check with `lsblk -d -o NAME,SIZE,MODEL`), `USERNAME`,
   `HOSTNAME` and `TIMEZONE`.
4. Optional, changes nothing:
   ```bash
   sudo ./install.sh --dry-run
   ```
5. Install:
   ```bash
   sudo ./install.sh
   ```
   You're asked for the user and root passwords (never stored in the repo) and to type the
   disk name to confirm the wipe. Everything else is unattended. Logs: `/tmp/cachy-install.log`,
   `/tmp/cachyos-install.log`, and in the new system `/var/log/cachy-setup.log`.
6. Reboot, log in. The first-boot service finishes in the background
   (`journalctl -u cachy-firstboot -f`), then follow `~/Desktop/NEXT-STEPS.txt`.

### Alternative: GUI install, then post-install

If the headless installer fails (or you want to dual-boot), install with the normal Calamares
GUI from the same ISO (choose **Cinnamon**, btrfs, Limine), boot into it, then:

```bash
git clone https://github.com/OhBoyItsFrancis/Cachy && cd Cachy && cp config.example.env config.env
```
```bash
sudo ./post-install.sh
```

Run single modules with `sudo ./post-install.sh 40-gaming 50-apps`; list them with `--list`;
skip some permanently with `SKIP_MODULES` in `config.env`.

## What gets installed

| App | Package | Source |
|---|---|---|
| Bitwarden | `bitwarden` | Arch extra |
| Figma | `figma` launcher (figma.com in its own Helium app window) + `figma-agent-linux` (local fonts) | this repo + AUR |
| Helium | `helium-browser-bin` (set as default browser) | CachyOS repo |
| IntelliJ IDEA, WebStorm | `jetbrains-toolbox` (autostarts on login; install both IDEs from it) | AUR |
| Prism Launcher | `prismlauncher` + Java 21/17/8 | Arch extra |
| Spotify | `spotify-launcher` (downloads and verifies Spotify's official build) | Arch extra |
| Steam | `steam` (+ Lutris, Heroic, MangoHud, Gamescope via `cachyos-gaming-applications`) | multilib / CachyOS |
| Tailscale | `tailscale`, daemon enabled, you are set as operator | Arch extra |
| Vesktop | `vesktop-bin` | CachyOS repo |
| VLC | `vlc` + all plugins | Arch extra |
| Claude Code / Desktop | `claude-code`, `claude-desktop` | CachyOS repo |
| Local LLMs | `ollama-cuda` + `claude-local` | Arch extra + this repo |
| VMs | `qemu-full`, `libvirt`, `virt-manager`, `edk2-ovmf`, `swtpm` | Arch extra |

Only two packages are built from the AUR (`jetbrains-toolbox`, `figma-agent-linux`). Figma has no
official Linux app and the community `figma-linux` client hasn't been updated since 2024, hence the
web app approach.

## Gaming optimisations

CachyOS already covers most of what gaming scripts add by hand: the BORE-scheduler
`linux-cachyos` kernel built for Zen 4, `ntsync`, zram, I/O schedulers, THP and VM sysctls
(`cachyos-settings`), and `proton-cachyos`. This setup adds:

| Tweak | Why | From |
|---|---|---|
| `cachyos-gaming-meta` + `cachyos-gaming-applications` | Steam, wine-cachyos, proton-cachyos, umu, protontricks, Lutris, Heroic, MangoHud, Gamescope, GOverlay | CachyOS |
| GE-Proton (latest) in `compatibilitytools.d`, `cachy-ge-proton` updater, ProtonUp-Qt | games that need GE's fixes/codecs | GloriousEggroll, archgaming |
| GameMode (`gamemoderun %command%`), user in `gamemode` group | performance governor, renice, I/O priority while playing | archgaming |
| `vm.max_map_count = 2147483642` | prevents crashes in mapping-heavy games | SteamOS / Bazzite / Nobara |
| `kernel.split_lock_mitigate = 0` | no stalls for games doing split locks | Nobara / Bazzite / SteamOS |
| `power-profiles-daemon` → *performance* | amd-pstate EPP favours clocks | archgaming |
| NVIDIA `NVreg_UsePageAttributeTable=1`, `PreserveVideoMemoryAllocations=1` + suspend services | PAT write-combining; clean suspend/resume | Nobara / CachyOS wiki |
| `__GL_SHADER_DISK_CACHE_SIZE=12GB`, `…SKIP_CLEANUP=1` | fewer shader-compile stutters | NVIDIA docs, common Proton advice |
| Flat mouse acceleration in Cinnamon | 1:1 aim | |
| ananicy-cpp + CachyOS rules, scx-scheds + scx-manager | process priorities; optional sched_ext schedulers (try `scx_lavd` in scx-manager) | CachyOS |
| LACT | 3080 power limit / fan curve / clocks GUI | |

Not done on purpose: `mitigations=off` (opt-in with `MITIGATIONS_OFF=true`; small gain on Zen 4,
real security cost) and a global `PROTON_ENABLE_NVAPI` (recent Proton enables NVAPI itself).
Launch-option tips are copied to `~/Documents/steam-launch-options.md` ([docs/steam-launch-options.md](docs/steam-launch-options.md)).

## GPU passthrough (Windows 11 VM)

Two modes, switchable any time with `sudo cachy-vfio-mode single|hybrid`:

| | **single** (default) | **hybrid** |
|---|---|---|
| Monitor cable | RTX 3080 | motherboard HDMI/DP (iGPU) |
| Linux desktop runs on | 3080 | 7700X iGPU |
| Starting the VM | stops LightDM/Cinnamon, unloads NVIDIA, hands over the 3080; desktop returns when Windows shuts down | Cinnamon keeps running; only GPU users (Ollama, LACT) are paused |
| Linux gaming | full 3080 | games run on the iGPU (switch to single for that) |
| Needs | nothing extra | iGPU enabled in BIOS |

Both modes pass the 3080 (VGA + HDMI audio functions) and, with `PASSTHROUGH_USB_CONTROLLER=true`,
the PCIe USB card. Plug the keyboard/mouse/headset you want in Windows into that card;
anything on the motherboard ports stays with Linux.

### Steps

1. Check the IOMMU groups:
   ```bash
   sudo cachy-vfio-check
   ```
   The GPU and the USB card must each sit in their own group (bridges are fine). If the USB
   card wasn't auto-detected, put its address in `USB_CONTROLLER_PCI` in `/etc/cachy-vfio.conf`.
   If it shares a group, try another slot, or as a last resort add
   `pcie_acs_override=downstream,multifunction` (the CachyOS kernel has the ACS patch).
2. Download the Windows 11 ISO from <https://www.microsoft.com/software-download/windows11>.
3. Create the VM (Q35, Secure Boot OVMF, TPM 2.0, virtio disk/net, 14 vCPUs pinned to cores 1-7,
   16 GB; virtio-win drivers are downloaded automatically):
   ```bash
   sudo cachy-vm create --iso ~/Downloads/Win11_*.iso
   ```
4. Install Windows in **virt-manager** (SPICE window). In setup, *Load driver* →
   `viostor\w11\amd64` for the disk and `NetKVM\w11\amd64` for the network, then run
   `virtio-win-guest-tools.exe` and install the NVIDIA driver. Shut Windows down.
5. Switch the VM to passthrough:
   ```bash
   sudo cachy-vm passthrough on
   ```
6. Start it from the menu (**Windows 11 VM**) or `cachy-vm start`. In single mode the screen goes
   black for a few seconds and Windows comes up on the 3080's outputs. Shut Windows down to get
   Cinnamon back. `sudo cachy-vm passthrough off` returns to SPICE for maintenance.

Logs: `/var/log/libvirt/cachy-vfio.log`. While the VM runs, the host is limited to CPUs 0 and 8
and the system can't sleep.

### Differences from the ilayna guide

The hooks follow [ilayna/Single-GPU-passthrough-amd-nvidia](https://github.com/ilayna/Single-GPU-passthrough-amd-nvidia)
(stop the display manager, unbind VT consoles and framebuffer, unload NVIDIA, let libvirt bind
`vfio-pci`, reverse on release, `libvirt-nosleep@`), with these changes for this machine:

- The original script also unloads `amdgpu`, `drm` and `drm_kms_helper` whenever *any* AMD VGA
  device exists, which would break the 7700X iGPU. These hooks only touch the NVIDIA stack.
- They act only when the domain XML actually contains the 3080, so the same VM still boots with
  SPICE for installation.
- They stop services that hold `/dev/nvidia*` (Ollama, LACT, persistenced) and restart them after.
- On failure they roll back and bring the desktop back instead of leaving a black screen.
- CPU isolation (`AllowedCPUs`) while the VM runs; Xorg config per mode so the session never
  grabs the GPU it shouldn't.

### vBIOS ROM (only if needed)

The 3080 usually works without one. If the VM's screen stays black in **single** mode, dump the
card's vBIOS from Windows with GPU-Z (or download the matching Gigabyte RTX 3080 Gaming OC 10G
ROM from TechPowerUp), copy it to `/var/lib/libvirt/vbios/3080.rom`, set
`GPU_ROM_FILE=/var/lib/libvirt/vbios/3080.rom` in `/etc/cachy-vfio.conf`, and run
`sudo cachy-vm passthrough on` again.

## Claude Code: cloud and local

- **Cloud:** `claude` (CLI, `/login` once) and **Claude Desktop** are installed from the CachyOS
  repo and update with the system. Cloud sessions and Remote Control work from the CLI once you're
  logged in.
- **Local:** Ollama runs on the 3080 (CUDA, flash attention, q8 KV cache, 64k context).
  `claude-local` starts Claude Code against Ollama's Anthropic-compatible API, without touching your
  normal `claude` login:
  ```bash
  claude-local                          # uses OLLAMA_MODEL from config (qwen3-coder:30b)
  ```
  ```bash
  claude-local --model qwen2.5-coder:14b
  ```
  The model is pulled on first boot. With 10 GB VRAM, a 30B MoE model runs partly from RAM
  (usable, slower); 14B-class dense models fit fully on the GPU. Use models with tool calling.
  Ollama is paused while the passthrough VM owns the GPU.
- Also installed for agent work: `git`, `github-cli`, `ripgrep`, `fd`, `jq`, `nodejs`/`npm`
  (for `npx` MCP servers), `uv` (for `uvx` MCP servers), `bubblewrap`.

## Maintenance

- Update everything: `paru` (repo + AUR). Snapper takes pre/post snapshots of every pacman
  transaction; boot an older snapshot from the Limine menu if an update breaks something, and
  manage them with Btrfs Assistant.
- Update GE-Proton: `cachy-ge-proton`.
- Re-apply the setup after editing `config.env`: `sudo /opt/cachy-setup/post-install.sh`.
- VM images live in their own btrfs subvolume (`/var/lib/libvirt/images`, copy-on-write off),
  so they are not part of root snapshots.

## Testing

- `sudo tests/sandbox-test.sh` runs the whole `post-install.sh` on any Linux box inside a
  throw-away mount namespace, with stubbed `pacman`/`systemctl`/`lspci` (this machine's PCI
  layout), and checks the results, including a second run for idempotency and a mode switch.
- `python3 -m unittest tests/test_cachy_vm.py` covers the VM tool (pinning for the 7700X,
  Windows 11 XML, passthrough on/off).
- `shellcheck -x install.sh post-install.sh lib/*.sh modules/*.sh bin/cachy-ge-proton bin/cachy-vfio-* bin/claude-local files/vfio/*.sh files/firstboot/*.sh files/libvirt/hooks/qemu`

These tests check the logic. They can't replace a run on the real hardware, so expect to read
the logs on the first real install.

## References

- CachyOS: [CachyOS org](https://github.com/CachyOS), [New-Cli-Installer headless config](https://github.com/CachyOS/New-Cli-Installer/blob/master/docs/config.md),
  [CachyOS-Settings](https://github.com/CachyOS/CachyOS-Settings), [chwd](https://github.com/CachyOS/chwd), [wiki](https://wiki.cachyos.org)
- Passthrough: [ilayna/Single-GPU-passthrough-amd-nvidia](https://github.com/ilayna/Single-GPU-passthrough-amd-nvidia),
  [risingprismtv single-gpu-passthrough](https://gitlab.com/risingprismtv/single-gpu-passthrough), [Arch wiki: PCI passthrough via OVMF](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
- Gaming: [xi-Rick/archgaming](https://github.com/xi-Rick/archgaming), [GloriousEggroll/proton-ge-custom](https://github.com/GloriousEggroll/proton-ge-custom), [Nobara](https://nobaraproject.org)
- Local models: [Ollama Anthropic compatibility](https://docs.ollama.com/api/anthropic-compatibility)
