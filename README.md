# NES Zork I (Z-machine interpreter)

ca65/cl65 Z-machine interpreter for NES targeting **MMC1 SXROM** (128 KB PRG, 32 KB WRAM, CHR-RAM). Playable Zork I with Family BASIC keyboard.

## Build

```powershell
.\build.ps1
```

Output: `build/neszork.nes` (also copied to `C:\Mesen\ROMs\neszork.nes`).

Requires [cc65](https://cc65.github.io/) at `C:\cc65\bin` and Python 3 (to split `story/zork1.z5` into 16 KiB PRG banks).

## Story file

`story/zork1.z5` is split at build time into `build/story_banks/storyN.bin`, then `.incbin`'d into MMC1 PRG banks via `src/story.s` / `src/story_font.s`.

## Mesen

**Family BASIC Keyboard (required for typing):**
1. **Settings → Input → Console Type → Famicom** (expansion port devices are Famicom accessories)
2. **Expansion device → Family Basic Keyboard**
3. Open **Setup** on the keyboard to see/edit which PC keys map to FBK keys (including F1)
4. Player 1 stays a standard gamepad — **Select** cycles color themes (handled in NMI)

## Status (v0.1-alpha)

- [x] SXROM bring-up, font CHR, themes
- [x] Family BASIC keyboard + typewriter SFX
- [x] Z-machine core sufficient to play early Zork I (move, take, read, look)
- [ ] Display polish (status line / scroll flicker)
- [ ] Remaining Z-ops (`scan_table`, `read_char`, …)
