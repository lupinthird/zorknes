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
THEME_COUNT = 3

SCREEN_COLS = 32          ; full nametable width
SCREEN_ROWS = 30          ; tile rows (excl. attribute table)
TEXT_COL0   = 0
TEXT_ROW0   = 0           ; main top comes from win_split
