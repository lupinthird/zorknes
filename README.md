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

**Family BASIC Keyboard (typing):**
1. **Settings → Input → Console Type → Famicom** (expansion port devices are Famicom accessories)
2. **Expansion device → Family Basic Keyboard**
3. Open **Setup** on the keyboard to see/edit which PC keys map to FBK keys (including F1)

**Gamepad (Player 1) — word picker at the `>` prompt:**
- **Left / Right** — category: Verb / Adj / Noun / Prep / Nav (bottom row `V:`/`A:`/`N:`/`P:`/`G:`)
- **Up / Down** — choose word in that category
- **A** — append word + space to the command
- **B** — backspace
- **Start** — submit command (same as Enter); also skips the title screen
- **Select** or keyboard **F1** — cycle color themes

Complex lines work on the pad the same way as the keyboard once words are appended, e.g. `KILL` + `TROLL` + `WITH` + `SWORD`.

## Automated tests (Mesen Lua)

Scripts live in `scripts/`. They inject commands into `z_line_buf` and pulse Enter (same path as the Family BASIC keyboard), so FBK hardware is not required for automation.

```text
C:\Mesen\Mesen.exe C:\Mesen\ROMs\neszork.nes E:\GemmaProjects\NESZork1\scripts\zork_smoke_keyboard.lua
C:\Mesen\Mesen.exe C:\Mesen\ROMs\neszork.nes E:\GemmaProjects\NESZork1\scripts\zork_troll_keyboard.lua
```

- `zork_smoke_keyboard.lua` — mailbox → house → lamp/sword → trap → cellar
- `zork_troll_keyboard.lua` — same, then repeats `KILL TROLL WITH SWORD` until the troll is gone. Reseeds `z_rng` from wall clock before the fight so successive runs are not identical (lockstep scripts otherwise always share one PRNG sequence).
- `zork_cmd_inject.lua` — shared injector (parses `build/neszork.lbl`)

Rebuild the ROM before running so label addresses match.

## Status (v0.1-alpha)

Phase 1 plan milestones are complete: SXROM bring-up, Family BASIC keyboard, Z-machine core, and playable early Zork I (LOOK / move / take / read).

Later polish (not Phase 1 blockers): status-line / scroll flicker; rare ops like `read_char` / `scan_table`; flexible packing for differently sized story files; save/restore.
