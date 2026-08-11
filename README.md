# NES Zork I (Z-machine interpreter)

ca65/cl65 Z-machine interpreter for NES targeting **MMC1 SXROM** (128 KB PRG, 32 KB battery WRAM, 8 KB CHR-RAM). Playable Zork I on a 32-column screen with mixed-case text, pixel-smooth story scrolling, battery **SAVE** / **RESTORE**, and a title screen that locks input to either the Family BASIC keyboard or a gamepad word picker.

Title version: **v1.0**. Source: [github.com/lupinthird/zorknes](https://github.com/lupinthird/zorknes).

## Build

Requires [cc65](https://cc65.github.io/) (`ca65` / `cl65`) and Python 3.

**Windows (PowerShell):**

```powershell
.\build.ps1
```

Copies `build/neszork.nes` to `C:\Mesen\ROMs\neszork.nes` as well. Default cc65 path: `C:\cc65\bin`.

**Linux / macOS (GNU Make):**

```sh
make
make CC65=/path/to/cc65/bin PYTHON=python3
make clean
```

`ca65` / `cl65` are taken from `PATH` unless you set `CC65`. Optional `make mesen` copies the ROM into `C:/Mesen/ROMs` and launches Mesen (override with `MESEN=` / `ROMDIR=`).

Output: `build/neszork.nes` (NES 2.0, mapper 1, battery PRG-RAM). Labels/map: `build/neszork.lbl`, `build/neszork.map`.

## Story file

`story/zork1.z5` is split at build time by `scripts/split_story.py` into 16 KiB banks at `build/story_banks/storyN.bin`, then `.incbin`'d via `src/story.s` / `src/story_font.s`.

The story header width is patched to **32** columns so Solid Gold’s startup check accepts the NES screen.

## Playing (Mesen)

Use **Mesen 2**. Enable battery saves so **SAVE** / **RESTORE** persist.

**Title screen — pick one input method (locked until QUIT returns here):**
- **Enter** (Family BASIC Keyboard) → keyboard typing only
- **Start** (gamepad) → word-picker only
- **Select** or keyboard **F1** — cycle color themes (green, gray, C64, amber). The choice carries into gameplay.
- **F8** or hold **A+B** for ~5 seconds — erase the battery save slot
- Hold **Left+A** (without B) for ~5 seconds — dedication page; **Start** or **Enter** to leave it

**Family BASIC Keyboard (after Enter on title):**
1. **Settings → Input → Console Type → Famicom** (expansion port devices are Famicom accessories)
2. **Expansion device → Family Basic Keyboard**
3. Open **Setup** on the keyboard to see/edit which PC keys map to FBK keys (including F1)

Type normally at the `>` prompt. **Enter** submits. **F1** still cycles themes in-game.

**Gamepad (after Start on title) — word picker on the bottom HUD row:**
- **Left / Right** — category: Verb / Adj / Noun / Prep / Yes-No / Nav (`V:` / `A:` / `N:` / `P:` / `Y:` / `G:`)
- **Up / Down** — choose word in that category
- **A** — append word + space to the command
- **B** — backspace
- **Start** — submit command (same as Enter)
- **Select** — cycle color themes

The picker stays pinned to the visible bottom row while the story scrolls. Pad and keyboard input wait until a scroll finishes before the next command is accepted.

`Y:` has **YES / NO / Y / N / HINT**. The first `HINT` only shows a warning — submit `HINT` again to open Invisiclues. On that screen the word picker stays hidden and the pad is rebound: **Up**=P, **Down**=N, **A/Start**=Return, **B**=Q. Keyboard N/P/Enter/Q also work. Complex lines still build the same way, e.g. `KILL` + `TROLL` + `WITH` + `SWORD`.

**In-game commands (either mode):** **SAVE** / **RESTORE** use a single battery slot in WRAM. **QUIT** returns to the title screen (input mode is chosen again). **RESTART** reloads the story without the title.

## Automated tests (Mesen Lua)

Scripts live in `scripts/`. They inject commands into `z_line_buf` and pulse Enter (same path as the Family BASIC keyboard), so FBK hardware is not required for automation. Rebuild the ROM first so `build/neszork.lbl` addresses match.

Pass the Lua file as an absolute path (Mesen’s working directory is not the repo):

```text
C:\Mesen\Mesen.exe C:\Mesen\ROMs\neszork.nes <repo>\scripts\zork_smoke_keyboard.lua
```

Headless: add `--testrunner` before the ROM path.

| Script | What it covers |
| --- | --- |
| `zork_smoke_keyboard.lua` | mailbox → house → lamp/sword → trap → cellar |
| `zork_troll_keyboard.lua` | same, then repeats `KILL TROLL WITH SWORD` until the troll is gone. Reseeds `z_rng` from the clock so successive runs are not identical |
| `zork_win350_keyboard.lua` | long 350-point walkthrough (combat/dig loops; auto-dismisses `read_char` / `[MORE]`) |
| `zork_smooth_scroll_smoke.lua` | leaflet/LOOK flood; asserts `scroll_busy` then a clean settle |
| `zork_pad_parse_smoke.lua` | Start on title, then injected phrases to check the parser (`KILL TROLL WITH SWORD`, etc.) |
| `zork_cmd_inject.lua` | shared injector (parses `build/neszork.lbl`; waits for `scroll_busy == 0`) |

## Licensing

**Zork I story data** (`story/zork1.z5`) is derived from Infocom’s Zork I. Microsoft, Activision, and Team Xbox released that source under the MIT License in 2025. The required copyright notice and permission text are in [`story/LICENSE`](story/LICENSE) (`Copyright (c) 2025 Microsoft`). That grant covers the story/source code only — it does **not** include trademark rights to “Zork”, “Infocom”, or related brands, nor commercial packaging or marketing materials.

Any copy or substantial portion of this project that includes the story file must keep `story/LICENSE` alongside it.

**This NES port** (interpreter, title, and tooling under `src/`, `nam/`, `chr/`, `scripts/`) is a non-commercial fan commemoration. It is **not for sale or commercial use**.

## Status (v1.0)

Playable Zork I: 32-column mixed-case output with word-boundary wrapping, Solid Gold status line, smooth NT2 story scroll (MMC1 horizontal mirroring), title logo/font CHR split, gamepad word picker, Family BASIC keyboard, battery save/restore, theme preview, and QUIT back to title.

Still interpreter-side gaps, not required for a normal playthrough: `scan_table` is unimplemented; packing is sized for this `zork1.z5` rather than arbitrary story files.
