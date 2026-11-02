# Steam launch options cheat-sheet (RTX 3080, Cinnamon/X11)

Set per game: right-click → Properties → General → Launch options.

| Goal | Launch option |
|---|---|
| Everyday default | `gamemoderun %command%` |
| FPS / frametime overlay | `mangohud gamemoderun %command%` (toggle in game: Right Shift + F12) |
| DLSS / Reflex in Proton games | `PROTON_ENABLE_NVAPI=1 %command%` (on by default in recent Proton; add if DLSS is greyed out) |
| Run in gamescope (fixed res / FSR upscale / VRR-like pacing) | `gamescope -W 2560 -H 1440 -r 165 -f -- %command%` |
| Performance power profile only while the game runs | `game-performance %command%` (CachyOS helper, uses power-profiles-daemon) |

## Picking Proton

Steam → game Properties → Compatibility → "Force the use of a specific Steam Play compatibility tool":

- **proton-cachyos** — CachyOS build of Proton with GE/upstream fixes, compiled for your CPU. Try first.
- **GE-Proton (latest)** — GloriousEggroll's build; best for games needing extra media codecs/fixes.
  Update with `cachy-ge-proton` or ProtonUp-Qt.
- **Proton Experimental** — Valve's newest; sometimes fixes a game first.

CachyOS loads the `ntsync` kernel module at boot; current proton-cachyos and GE-Proton builds use it
for Windows sync primitives, which helps CPU-bound games.

Check [ProtonDB](https://www.protondb.com) for per-game launch options.

## Anti-cheat

Kernel-level anti-cheat games (Valorant, many Battlefield/CoD titles, Fortnite) refuse Linux and
often VMs too. Those belong on bare-metal Windows; the passthrough VM is good for everything else
that needs Windows.
