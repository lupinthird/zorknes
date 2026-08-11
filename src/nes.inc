; NES hardware registers and common masks

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
OAMADDR   = $2003
OAMDATA   = $2004
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
OAMDMA    = $4014
SND_CHN   = $4015
JOY1      = $4016
JOY2      = $4017

; MMC1 (any address in bank selects register by A14/A13)
MMC1_CTRL = $8000
MMC1_CHRB = $A000
MMC1_CHRA = $C000
MMC1_PRG  = $E000

PAD_A      = %00000001
PAD_B      = %00000010
PAD_SELECT = %00000100
PAD_START  = %00001000
PAD_UP     = %00010000
PAD_DOWN   = %00100000
PAD_LEFT   = %01000000
PAD_RIGHT  = %10000000

; PPUCTRL: NMI on, BG from $0000, sprites $1000, NT $2000
PPUCTRL_NMI = %10001000
; BG on (incl. leftmost 8); sprites off — zeroed OAM would show tile 0 as a "0"
PPUMASK_ON  = %00001010

THEME_GREEN = 0
THEME_GRAY  = 1
THEME_C64   = 2
THEME_AMBER = 3
THEME_COUNT = 4

SCREEN_COLS = 32          ; physical nametable width
SCREEN_ROWS = 30          ; tile rows (excl. attribute table)
; Story may use rows 0..STORY_ROWS-1; row 29 reserved for pad HUD / margin.
STORY_ROWS  = 29
; Smooth scroll: append into NT2 ($2800) under horizontal mirroring, then
; fine-Y scroll. Set SMOOTH_SCROLL=0 to use legacy tile-copy scroll only.
SMOOTH_SCROLL = 1
; NT2 has 30 rows; stay under 240px fine-Y (attribute wrap at 240).
STORY_BUF     = 28
; Header width = physical width. Solid Gold's startup check (jl width 38)
; is patched to 32 in story/zork1.z5 so it accepts NES columns.
Z_HDR_COLS  = SCREEN_COLS
TEXT_COL0   = 0
TEXT_ROW0   = 0           ; main top comes from win_split

; SXROM 32K WRAM banks (MMC1 CHR0 bits). Dynamic uses 0-1 for Zork I.
WRAM_BANK_TEXT  = 1       ; nametable mirror after dynamic (not in save banks)
WRAM_BANK_SAVE0 = 2       ; battery save image (banks 2+3 = 16 KiB)
WRAM_BANK_SAVE1 = 3
; Zork I static_base $3B3E → bank1 offset $1B3E; mirror starts at $1B40.
NT_MIRROR_OFF   = $1B40
