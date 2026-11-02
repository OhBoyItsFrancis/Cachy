# cachy-setup

Bash installer and post-install configuration for one CachyOS desktop (MSI PRO B650-S WIFI,
Ryzen 7 7700X, RTX 3080, Cinnamon, single/hybrid GPU passthrough, Claude Code + Ollama).

The full description of what is installed, where each file lives, which module owns it, and the
rules for changing it safely is imported below. Follow §0 of it before making changes.

@docs/SYSTEM.md

## Working in this repo

- The deployed copy runs from `/opt/cachy-setup`; this git clone (`~/Cachy`) is where changes are
  made. Deploy and apply a module:
  ```bash
  sudo rsync -a --exclude .git ~/Cachy/ /opt/cachy-setup/ && sudo /opt/cachy-setup/post-install.sh <module>
  ```
- Before committing, run:
  ```bash
  shellcheck -x install.sh post-install.sh lib/*.sh modules/*.sh bin/cachy-ge-proton bin/cachy-vfio-* bin/claude-local files/vfio/*.sh files/firstboot/*.sh files/libvirt/hooks/qemu
  ```
  ```bash
  python3 -m unittest tests/test_cachy_vm.py
  ```
  ```bash
  sudo tests/sandbox-test.sh
  ```
- When you change what gets installed or configured, update `docs/SYSTEM.md` in the same commit
  (packages §4, files §5, services §6, and so on), and add a check to `tests/sandbox-test.sh`.
- `config.env` is git-ignored and machine-specific. New variables go in `config.example.env` with
  a default and a comment, and in the table in `docs/install-guide.md`.
