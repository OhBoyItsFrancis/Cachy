# Install guide: setting the variables and running the unattended install

This walks through a complete install on the MSI PRO B650-S WIFI / Ryzen 7 7700X / RTX 3080
desktop, from a blank drive to a booted, configured system. It takes about 30–60 minutes,
mostly downloads.

> Keep this page open on your phone: the PC is busy for most of the process.

**Overview**

1. [Prepare](#1-prepare) the BIOS and a USB stick
2. [Boot the live ISO and get online](#2-boot-the-live-iso-and-get-online)
3. [Get this repo](#3-get-this-repo)
4. [Find your values](#4-find-your-values) (disk, time zone, …)
5. [Fill in `config.env`](#5-fill-in-configenv), every variable explained
6. [Dry run](#6-dry-run)
7. [Run the install](#7-run-the-install)
8. [First boot](#8-first-boot)
9. [If something goes wrong](#9-if-something-goes-wrong)

---

## 1. Prepare

**Back up** anything on the drive you will install to. The installer erases the **whole drive**,
not a partition.

**BIOS** (press <kbd>Del</kbd> at power-on). Update the BIOS first, then check:

| Setting | Value |
|---|---|
| BIOS UEFI/CSM Mode | **UEFI** (the installer stops if the PC isn't booted in UEFI mode) |
| Secure Boot | **Disabled** |
| SVM Mode | **Enabled** (needed for VMs) |
| IOMMU | **Enabled** (needed for GPU passthrough) |
| Integrated Graphics | **Force** if you want hybrid passthrough mode; otherwise leave it |
| EXPO | your DDR5 profile |

The README has the [full table with menu locations](../README.md#before-you-start-bios-settings-msi-click-bios).

**USB stick.** Download the CachyOS **Desktop** ISO from <https://cachyos.org/download/> and write it
with [Ventoy](https://www.ventoy.net), [balenaEtcher](https://etcher.balena.io) or Rufus (DD mode).

**Optional: prepare `config.env` in advance.** You can fill in `config.env` (step 5) on another
computer, save it on a second USB stick, and copy it over in step 3. It holds no passwords.

---

## 2. Boot the live ISO and get online

1. Plug the USB stick in, power on, press <kbd>F11</kbd> for the MSI boot menu, and pick the
   **UEFI:** entry for the stick.
2. Choose the default boot option and wait for the live desktop.
3. Connect to the internet:
   - **Ethernet:** it connects automatically.
   - **Wi-Fi:** use the network icon in the panel, or in a terminal:
     ```bash
     nmtui
     ```
4. Close the CachyOS Hello / Calamares window if it opens. You won't use the GUI installer.
5. Open a terminal (Konsole or the terminal in the app menu).

Check you're online:

```bash
ping -c 3 cachyos.org
```

---

## 3. Get this repo

Install `git` and `jq` on the live system (`jq` lets the installer check its generated settings):

```bash
sudo pacman -Sy --needed --noconfirm git jq
```

Clone the repo:

```bash
git clone https://github.com/OhBoyItsFrancis/Cachy
```

```bash
cd Cachy
```

Create your config from the template:

```bash
cp config.example.env config.env
```

If you prepared `config.env` on a USB stick, copy it in instead. Find the stick under
`/run/media/`, then for example:

```bash
cp /run/media/$USER/MYSTICK/config.env .
```

---

## 4. Find your values

### The target disk (most important)

```bash
lsblk -d -o NAME,SIZE,MODEL,TRAN
```

Example output:

```
NAME     SIZE MODEL                   TRAN
sda     28.9G SanDisk Ultra           usb     <- the live USB stick: NOT this
nvme0n1  1.8T Samsung SSD 990 PRO 2TB nvme    <- install here
nvme1n1  931G WD_BLACK SN770 1TB      nvme
```

- Identify the drive by **size and model**, not by its name alone. With two NVMe drives,
  `nvme0n1` and `nvme1n1` can swap between boots.
- `TRAN usb` is the live stick. Never pick it.
- The drive must be at least 64 GiB.
- Use the whole-disk name with `/dev/` in front: `/dev/nvme0n1`, not `/dev/nvme0n1p1`.

To double-check what's on a drive before you erase it:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL /dev/nvme0n1
```

### Time zone

```bash
timedatectl list-timezones | grep -i -E 'new_york|chicago|denver|los_angeles|london|berlin'
```

Use the exact spelling shown, for example `America/Chicago`.

### Keyboard layout and locale

Most US setups keep the defaults (`us`, `en_US.UTF-8`). To see other options:

```bash
localectl list-x11-keymap-layouts | head -40
```

```bash
grep -E '^#?[a-z]{2}_[A-Z]{2}\.UTF-8' /etc/locale.gen | head -40
```

### PCI addresses for passthrough (optional)

Leave `GPU_PCI` and `USB_CONTROLLER_PCI` empty and they are detected automatically. To see them
now:

```bash
lspci -D -nn | grep -E 'VGA|USB controller'
```

- **RTX 3080:** the `NVIDIA … GA102` line, usually `0000:01:00.0`.
- **PCIe USB card:** the one **not** made by AMD. Typical makers are ASMedia, Renesas/NEC, Fresco
  and VIA. AMD-made controllers belong to the motherboard and the CPU. Auto-detection only works
  when exactly one non-AMD USB controller exists. Otherwise set it by hand, here or later in
  `/etc/cachy-vfio.conf`.

---

## 5. Fill in `config.env`

Open the file:

```bash
nano config.env
```

In nano: <kbd>Ctrl</kbd>+<kbd>O</kbd> then <kbd>Enter</kbd> saves, and <kbd>Ctrl</kbd>+<kbd>X</kbd>
quits.

**Rules for the file:** it is a bash file, so write `NAME="value"` with **no spaces around `=`**
and quote values. Lines starting with `#` are comments. Any variable you delete falls back to its
value in `config.example.env`.

### Must change

| Variable | Example | Notes |
|---|---|---|
| `TARGET_DISK` | `"/dev/nvme0n1"` | The drive from step 4. **It is erased completely.** |
| `USERNAME` | `"francis"` | Your login name: lowercase letters, digits, `-` and `_`, starting with a letter. The template value is a placeholder. |
| `HOSTNAME` | `"cachy-desktop"` | The computer's network name: letters, digits and `-`. |
| `TIMEZONE` | `"America/Chicago"` | From step 4. It is checked against `/usr/share/zoneinfo`. |

### System (defaults are fine)

| Variable | Default | Options / notes |
|---|---|---|
| `ESP_SIZE` | `"2G"` | EFI partition size. 2G holds several kernels plus Limine snapshot entries. |
| `LOCALE` | `"en_US.UTF-8"` | Any `xx_YY.UTF-8` from `/etc/locale.gen`. |
| `KEYMAP` | `"us"` | X11 layout name (`us`, `gb`, `de`, …). |
| `KERNELS` | `"linux-cachyos linux-cachyos-lts"` | Space separated. Keeping the LTS kernel gives you a fallback in the boot menu. Other options: `linux-cachyos-bore`, `linux-cachyos-eevdf`, `linux-cachyos-rc`. |
| `BOOTLOADER` | `"limine"` | `limine` (CachyOS default, can boot btrfs snapshots), `systemd-boot` or `grub`. |

### User

| Variable | Default | Options / notes |
|---|---|---|
| `USER_SHELL` | `"/usr/bin/fish"` | `/usr/bin/fish`, `/bin/zsh` or `/bin/bash` (the installer accepts only these exact paths). |
| `AUTOLOGIN` | `"false"` | `true` skips the login screen. |

### Gaming

| Variable | Default | Notes |
|---|---|---|
| `INSTALL_GE_PROTON` | `"true"` | Downloads the newest GE-Proton for Steam. Update it later with `cachy-ge-proton`. |
| `MITIGATIONS_OFF` | `"false"` | `true` adds `mitigations=off`: a few % in some CPU-bound games, at a real security cost. |
| `PERFORMANCE_PROFILE` | `"true"` | Sets the CPU power profile to *performance* on first boot. |

### GPU passthrough

| Variable | Default | Notes |
|---|---|---|
| `VFIO_MODE` | `"single"` | `single`: monitor on the 3080, and the desktop stops while the VM runs. `hybrid`: monitor on the motherboard, and the desktop keeps running (needs the iGPU on in BIOS). Switch later with `sudo cachy-vfio-mode`. |
| `VM_NAME` | `"win11"` | libvirt name of the Windows VM. |
| `VM_MEMORY_GB` | `"16"` | RAM for Windows; the host keeps the other 16 GB. |
| `VM_VCPU_CORES` | `"7"` | Physical cores for the VM (2 threads each, so 7 = 14 vCPUs). |
| `HOST_CPUS` | `"0,8"` | CPUs Linux keeps while the VM runs. On the 7700X, CPU *N* and *N+8* are the same core, so `0,8` = core 0. |
| `VM_DISK_GB` | `"256"` | Size of the Windows disk image. It grows as it's used and starts small. |
| `GPU_PCI` | `""` | Empty = auto-detect (step 4). |
| `USB_CONTROLLER_PCI` | `""` | Empty = auto-detect the single non-AMD USB controller. |
| `PASSTHROUGH_USB_CONTROLLER` | `"true"` | Give the USB card to the VM along with the GPU. |
| `GPU_ROM_FILE` | `""` | Path to a vBIOS file, only if the VM screen stays black (see README). |

### Claude Code / AI

| Variable | Default | Notes |
|---|---|---|
| `INSTALL_CLAUDE_DESKTOP` | `"true"` | The Claude Desktop app. The `claude` CLI is always installed. |
| `INSTALL_OLLAMA` | `"true"` | Ollama with CUDA on the 3080, for `claude-local`. |
| `OLLAMA_MODEL` | `"qwen3-coder:30b"` | Pulled on first boot (about 19 GB download). Set `""` to skip, or pick a smaller tool-calling model such as `qwen2.5-coder:14b` that fits in 10 GB VRAM. |

### Modules

| Variable | Default | Notes |
|---|---|---|
| `SKIP_MODULES` | `""` | Space-separated names to skip, e.g. `"60-ai 70-virtualization"`. List them with `./post-install.sh --list`. |

### A minimal `config.env`

Because missing variables fall back to the template, this is all you strictly need:

```bash
TARGET_DISK="/dev/nvme0n1"
USERNAME="francis"
HOSTNAME="cachy-desktop"
TIMEZONE="America/Chicago"
```

### Passwords

Passwords are **not** stored in `config.env`. By default the installer asks for the user and
root passwords twice each when it starts. To answer them in advance (for example to go fully
hands-off with `--yes`), open a root shell in the `Cachy` folder (`sudo -s` keeps the current
directory) and type them into variables without echoing:

```bash
sudo -s
```

```bash
read -rsp 'User password: ' USER_PASSWORD; echo; export USER_PASSWORD
```

```bash
read -rsp 'Root password: ' ROOT_PASSWORD; echo; export ROOT_PASSWORD
```

They exist only in that shell's memory and are gone when the live session ends.

---

## 6. Dry run

The dry run checks the config and shows the exact settings handed to CachyOS's installer
(passwords masked). It changes **nothing**:

```bash
sudo ./install.sh --dry-run
```

It checks that:

- the PC is booted in UEFI mode
- `TARGET_DISK` is a whole disk, isn't mounted, and is at least 64 GiB
- `USERNAME`, `HOSTNAME`, `TIMEZONE` and `BOOTLOADER` are valid
- the CachyOS mirror is reachable
- the generated settings are valid JSON (when `jq` is installed)

Read the `"device"` line and the partition names once more. If anything is wrong, fix
`config.env` and run the dry run again.

---

## 7. Run the install

```bash
sudo ./install.sh
```

What happens:

1. **Preflight**: the same checks as the dry run.
2. **Passwords**: asked unless you exported them (step 5).
3. **Confirmation**: it shows the disk and asks you to **type the disk name** (e.g. `nvme0n1`).
   Anything else aborts without changes.
4. **Stage 1, about 10–20 min**: CachyOS's installer (`cachyos-installer`, unattended mode)
   partitions the disk, installs the base system, Cinnamon, the kernels, Limine and the NVIDIA
   driver, and creates your user. Progress shows as `[ 42.0%] …` lines.
5. **Stage 2, about 15–30 min**: it mounts the new system and runs `post-install.sh` inside it,
   module by module (`### 10-base`, `### 20-hardware`, …). Lines starting with `!!` are warnings:
   the install continues and they are listed again at the end.
6. **Summary**: lists any packages that failed and the warnings, then asks **Reboot now?**

Fully hands-off variant: export the passwords first (step 5), then:

```bash
./install.sh --yes
```

`--yes` skips the disk-name confirmation and the reboot question, so **make sure `TARGET_DISK`
is right**. Run it from the root shell where you exported the passwords.

### Options

| Option | Effect |
|---|---|
| `--dry-run` | Validate and print settings; change nothing |
| `--yes` | No disk confirmation, no reboot prompt |
| `--help` | Usage |

### Logs

| While installing (live system) | After install (new system) |
|---|---|
| `/tmp/cachy-install.log` (this script) | `/var/log/cachy-install-stage1.log` |
| `/tmp/cachyos-install.log` (CachyOS installer) | `/var/log/cachyos-installer.log` |
| — | `/var/log/cachy-setup.log` (post-install modules) |

To follow along in a second terminal:

```bash
tail -f /tmp/cachy-install.log /tmp/cachyos-install.log
```

---

## 8. First boot

1. Remove the USB stick and reboot. Limine shows the boot menu; the default entry is
   `linux-cachyos`.
2. **Single mode:** the monitor stays on the 3080. **Hybrid mode:** plug the monitor into the
   motherboard.
3. Log in to Cinnamon. A one-time background service finishes the setup: firewall rules, VM
   network, power profile, Tailscale permissions, GE-Proton retry and the Ollama model download.
   Watch it with:
   ```bash
   journalctl -u cachy-firstboot -f
   ```
   It is done when it prints `all done`. If a step failed (e.g. no network yet), it retries on the
   next boot.
4. Follow `~/Desktop/NEXT-STEPS.txt`: Tailscale login, Claude `/login`, installing the IDEs from
   JetBrains Toolbox, and the Windows VM.

Quick health checks:

```bash
nvidia-smi
```

```bash
powerprofilesctl get
```

```bash
cat /proc/cmdline
```

`cat /proc/cmdline` should include `amd_iommu=on iommu=pt`.

```bash
sudo cachy-vfio-check
```

```bash
grep -i -E 'warn|fail' /var/log/cachy-setup.log
```

---

## 9. If something goes wrong

| Problem | What to do |
|---|---|
| `Not booted in UEFI mode` | Set BIOS to UEFI (CSM off) and pick the **UEFI:** entry in the <kbd>F11</kbd> menu. |
| `No internet` | Connect with `nmtui`, then re-run. |
| `… is not a block device` / `not a whole disk` | Re-check `TARGET_DISK` with `lsblk -d`: whole disk, with `/dev/`. |
| `has mounted partitions` | The live desktop auto-mounted it, or a failed earlier attempt left it mounted. Unmount with `sudo umount -R /mnt` and `sudo umount /dev/nvme0n1p*`, then retry. |
| `cachyos-installer failed` | Read `/tmp/cachyos-install.log`. The disk may be half-written, which is fine: re-running erases it again. If it keeps failing, use the **GUI fallback** below. |
| Stage 2 warnings / failed packages | Boot the new system and re-run just that part: `sudo /opt/cachy-setup/post-install.sh 40-gaming` (modules are safe to re-run). |
| Black screen after login (single mode) | Monitor on the 3080? Press <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>F3</kbd>, log in, run `sudo cachy-vfio-mode single`, then reboot. |
| Black screen (hybrid mode) | Monitor on the motherboard? Is the iGPU enabled in BIOS? Or switch back: `sudo cachy-vfio-mode single`. |
| Update broke boot later | Pick an older snapshot under **Snapshots** in the Limine menu. |

### GUI fallback

If the unattended stage 1 doesn't work on your ISO version:

1. Run the normal CachyOS installer (Calamares) from the live desktop. Choose
   **Cinnamon**, **btrfs**, **Limine**, and your user name.
2. Boot the new system, then:
   ```bash
   sudo pacman -S --needed git
   ```
   ```bash
   git clone https://github.com/OhBoyItsFrancis/Cachy && cd Cachy && cp config.example.env config.env
   ```
   Edit `config.env` (`USERNAME` must match the user you created; the disk variables are
   ignored here), then:
   ```bash
   sudo ./post-install.sh
   ```
3. Reboot.

### Changing settings after install

Edit `/opt/cachy-setup/config.env` and re-run the module it affects, e.g. after changing
`OLLAMA_MODEL`:

```bash
sudo /opt/cachy-setup/post-install.sh 60-ai 80-firstboot
```

```bash
sudo reboot
```

Passthrough settings live in `/etc/cachy-vfio.conf` after install. Edit them there directly,
or use `sudo cachy-vfio-mode single|hybrid` for the mode.
