# How this project was built

This ROM is a collaboration. Cursor’s coding agent wrote nearly all of the assembly, linker config, build scripts, and Mesen Lua helpers. Christopher Griffin directed the project: what to build, how the NES should behave, what “correct” looked like on screen, and when a design was wrong.

It was not “a novice prompting an AI until a game appeared.” It was an experienced software engineer using an agent as a high-speed assembler — with enough NES/PPU/mapper literacy to reject bad approaches, specify the right ones, and catch bugs the agent could not see.

## Christopher Griffin

**Concept, product, and oversight.** Zork I on NES as a non-commercial commemoration; MMC1 SXROM as the target; Family BASIC keyboard plus a gamepad word picker; title flow that locks one input method per session; battery save; themes; licensing and “not for sale” constraints; the dedication behind the hidden title page.

**Architecture and implementation calls**, including ones that only make sense if you already know the PPU. Smooth story scrolling is the clearest example: Christopher specified the approach (horizontal mirroring, append into nametable 2 at `$2800`, fine-Y scroll, no mid-frame forced blank, prompt/HUD wait until the camera settles). The agent implemented it, then he playtested and sent the nits — premature snaps, end-of-scroll flashes, status-row corruption, the word picker scrolling up with the story — until the behavior matched the design.

**Art and look.** Color schemes (green, gray, C64, amber, including the true-black amber backdrop). Title logo conversion and nametable layout (`chr/`, `nam/`), including sacrificing tile `$FF` as a blank gutter so the timed logo/font CHR split could stay stable.

**Testing.** Extensive emulator playtesting, walkthrough knowledge (smoke path, troll fight, 350-point run), and recommendations on what to automate in Mesen Lua. The agent wrote the scripts; he decided what “pass” meant.

**Voice and copy.** Title strings, version, GitHub line, MIT attribution, and the Left+A dedication text.

## Cursor agent

**Implementation.** On the order of 99.9% of the committed code: Z-machine core, MMC1 banking, NMI and VRAM queue, text engine (wrap, status window, mixed case), title CHR split, pad UI, save/restore, sound blips, build (`build.ps1`, Makefile, story-bank split), and the Lua injectors.

The agent is fast at ca65 boilerplate, opcode tables, and “make this state machine match the spec.” It is not a substitute for knowing that MMC1 control overrides iNES mirroring, that Y≥240 wraps into the attribute table, that you must not bank WRAM from NMI, or that a black box on tile `$FF` is probably a CHR wipe rather than a nametable bug. Those catches came from Christopher.

## How to read the git history

Commits are Christopher’s project. Most diffs were typed by the agent under his review. A large commit does not mean the design was the agent’s; a small follow-up often means he found the real bug on hardware (or Mesen) and sent the agent back in.

## Credit

- **Christopher Griffin** — concept, NES-aware direction, art, palettes, nametables, playtesting, and sign-off  
- **Cursor agent** — nearly all source code and tooling  
- **Infocom / Microsoft (2025 MIT)** — Zork I story data; see `story/LICENSE`  
- **Chris’s dad** — the C-64 evenings this port is meant to remember
