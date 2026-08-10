; NES 2.0 header — MMC1 (mapper 1), SXROM-style RAM sizes
; 128 KiB PRG-ROM, 0 CHR-ROM, 32 KiB battery PRG-RAM, 8 KiB CHR-RAM

.segment "HEADER"
    .byte "NES", $1A
    .byte 8                 ; 8 x 16 KiB PRG (128 KiB)
    .byte 0                 ; CHR-ROM = 0 (use CHR-RAM)
    .byte $12               ; mapper low=1, battery-backed PRG-RAM, vertical mirroring
    .byte $08               ; NES 2.0, mapper high nibble 0
    .byte $00               ; submapper 0 (sizes imply SXROM WRAM banking)
    .byte $00               ; PRG/CHR size MSB
    ; Byte 10: lo-nibble = volatile PRG-RAM shift, hi-nibble = battery PRG-NVRAM shift
    ; shift 9 → 64<<9 = 32 KiB. Battery bit (byte 6) required when NVRAM nibble ≠ 0.
    .byte $90               ; 32 KiB non-volatile PRG-RAM, 0 volatile
    .byte $07               ; CHR-RAM volatile shift 7 → 64<<7 = 8 KiB
    .byte $00               ; timing NTSC
    .byte $00               ; vs system
    .byte $00               ; misc ROMs
    .byte $23               ; set expansion device to Family Basic Keyboard
