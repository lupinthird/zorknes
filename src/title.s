.include "nes.inc"

.import wait_vblank
.import read_keyboard, keyboard_poll_chars
.import read_pads
.import palette_cycle, palette_apply_title_text
.import zsave_erase
.import mmc1_set_prg
.import font_chr
.importzp str_ptr, frame_count
.importzp key_ready, key_ascii, kb_enable
.importzp pad1, pad1_pressed
.export title_show, title_nmi
.exportzp title_active, input_mode

; Locked at title dismiss: Enter → keyboard, Start → gamepad word picker.
INPUT_MODE_KB  = 0
INPUT_MODE_PAD = 1

; NMI on + BG $1000 (logo) / $0000 (font)
PPUCTRL_LOGO = %10010000
PPUCTRL_TEXT = %10000000

; Timed CHR split (sprite-0 was softlocking). Bias late into row-16 gutter.
SPLIT_OUTER = 25
SPLIT_INNER = 138

TILE_BLANK = $FF             ; color-0 blank in both banks (seam gutter)

; ~5 seconds at 60 Hz
ERASE_HOLD_FRAMES = 300
EGG_HOLD_FRAMES   = 300

; Keyboard: F1=$80 (palette), F8=$81 (erase save on title)
KEY_F1 = $80
KEY_F8 = $81

.segment "ZEROPAGE"
title_active: .res 1
input_mode:   .res 1
title_row:    .res 1
title_col:    .res 1
title_lo:     .res 1
title_hi:     .res 1
erase_hold:   .res 2       ; 16-bit frame counter while A+B held
egg_hold:     .res 2       ; 16-bit frame counter while Left+A held
title_egg:    .res 1       ; 1 = dedication page (no logo CHR split)
chr_plane0:   .res 8       ; scratch for title paper-font convert

.segment "CODE"

; Called from NMI when title_active ≠ 0.
.proc title_nmi
    bit PPUSTATUS
    jsr palette_apply_title_text
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda title_egg
    bne @egg
    ; Every frame so the timed logo/font split stays aligned.
    lda #PPUCTRL_LOGO
    sta PPUCTRL
    ldy #SPLIT_OUTER
@outer:
    ldx #SPLIT_INNER
@inner:
    dex
    bne @inner
    dey
    bne @outer
    lda #PPUCTRL_TEXT
    sta PPUCTRL
    rts
@egg:
    lda #PPUCTRL_TEXT
    sta PPUCTRL
    rts
.endproc

; CHR: font @ $0000, logo @ $1000. Leaves rendering off, NMI off.
.proc title_show
    bit PPUSTATUS
    jsr title_make_paper_font
    jsr title_upload_logo
    jsr title_prepare_split_chr
    jsr title_fill_paper
    jsr title_bank6_on
    jsr title_write_messages
    jsr title_bank6_off
    jsr title_setup_palettes
    jsr palette_apply_title_text

    lda #0
    sta erase_hold
    sta erase_hold+1
    sta egg_hold
    sta egg_hold+1
    sta title_egg

    lda #1
    sta kb_enable
    sta title_active

    jsr wait_vblank
    lda #PPUCTRL_LOGO
    sta PPUCTRL
    lda #PPUMASK_ON
    sta PPUMASK

@frame:
    lda frame_count
@wait:
    cmp frame_count
    beq @wait

    jsr read_pads

    ; SELECT → cycle game theme; title NMI applies it to palette 2.
    lda pad1_pressed
    and #PAD_SELECT
    beq @no_sel
    jsr palette_cycle
@no_sel:

    ; Hold A+B for ~5s to erase battery save slot
    lda pad1
    and #(PAD_A | PAD_B)
    cmp #(PAD_A | PAD_B)
    bne @ab_reset
    lda #0
    sta egg_hold
    sta egg_hold+1
    inc erase_hold
    bne @ab_chk
    inc erase_hold+1
@ab_chk:
    lda erase_hold
    cmp #<ERASE_HOLD_FRAMES
    lda erase_hold+1
    sbc #>ERASE_HOLD_FRAMES
    bcc @hold_done
    jsr title_do_erase
    jmp @hold_done
@ab_reset:
    lda #0
    sta erase_hold
    sta erase_hold+1
    ; Hold Left+A (without B) for ~5s → dedication
    lda pad1
    and #(PAD_A | PAD_B | PAD_LEFT)
    cmp #(PAD_A | PAD_LEFT)
    bne @egg_reset
    inc egg_hold
    bne @egg_chk
    inc egg_hold+1
@egg_chk:
    lda egg_hold
    cmp #<EGG_HOLD_FRAMES
    lda egg_hold+1
    sbc #>EGG_HOLD_FRAMES
    bcc @hold_done
    jsr title_easter_egg
    jmp @hold_done
@egg_reset:
    lda #0
    sta egg_hold
    sta egg_hold+1
@hold_done:

    lda pad1_pressed
    and #PAD_START
    beq @try_kb
    lda #INPUT_MODE_PAD
    sta input_mode
    jmp @dismiss

@try_kb:
    jsr read_keyboard
    jsr keyboard_poll_chars
    lda key_ready
    beq @frame
    lda #0
    sta key_ready
    lda key_ascii
    cmp #KEY_F8
    bne @not_f8
    jsr title_do_erase
    jmp @frame
@not_f8:
    cmp #$0D
    beq @got_enter
    jmp @frame
@got_enter:
    lda #INPUT_MODE_KB
    sta input_mode
@dismiss:
    lda #0
    sta title_active
    sta PPUMASK
    sta kb_enable
    sta PPUCTRL              ; NMI off until main re-enables
    jsr wait_vblank
    rts
.endproc

.proc title_do_erase
    lda #0
    sta erase_hold
    sta erase_hold+1
    sta PPUMASK
    jsr wait_vblank
    jsr zsave_erase
    jsr title_bank6_on
    lda #<msg_erased
    sta str_ptr
    lda #>msg_erased
    sta str_ptr+1
    ldx #22
    ldy #1
    jsr title_put_str_at
    jsr title_bank6_off
    jsr wait_vblank
    lda #PPUCTRL_LOGO
    sta PPUCTRL
    lda #PPUMASK_ON
    sta PPUMASK
    rts
.endproc

; Full-screen dedication. NMI uses font CHR only (no logo split).
.proc title_easter_egg
    lda #0
    sta egg_hold
    sta egg_hold+1
    lda #1
    sta title_egg
    lda #0
    sta PPUMASK
    jsr wait_vblank
    jsr title_fill_all_paper
    jsr title_bank6_on
    lda #<msg_egg
    sta str_ptr
    lda #>msg_egg
    sta str_ptr+1
    ldx #3
    ldy #0
    jsr title_put_str_at
    jsr title_bank6_off
    jsr wait_vblank
    lda #PPUCTRL_TEXT
    sta PPUCTRL
    lda #PPUMASK_ON
    sta PPUMASK
@wait:
    lda frame_count
@w:
    cmp frame_count
    beq @w
    jsr read_pads
    lda pad1_pressed
    and #PAD_START
    bne @done
    jsr read_keyboard
    jsr keyboard_poll_chars
    lda key_ready
    beq @wait
    lda #0
    sta key_ready
    lda key_ascii
    cmp #$0D
    bne @wait
@done:
    lda #0
    sta PPUMASK
    jsr wait_vblank
    jsr title_upload_logo
    jsr title_fill_paper
    jsr title_bank6_on
    jsr title_write_messages
    jsr title_bank6_off
    jsr title_setup_palettes
    jsr palette_apply_title_text
    lda #0
    sta title_egg
    jsr wait_vblank
    lda #PPUCTRL_LOGO
    sta PPUCTRL
    lda #PPUMASK_ON
    sta PPUMASK
    ; Don't re-fire until Left+A are released.
@rel:
    lda frame_count
@relw:
    cmp frame_count
    beq @relw
    jsr read_pads
    lda pad1
    and #(PAD_A | PAD_LEFT)
    bne @rel
    lda #0
    sta egg_hold
    sta egg_hold+1
    rts
.endproc

.proc title_bank6_on
    lda #6
    jmp mmc1_set_prg
.endproc

.proc title_bank6_off
    lda #0
    jmp mmc1_set_prg
.endproc

.proc title_fill_all_paper
    bit PPUSTATUS
    lda #$20
    sta PPUADDR
    lda #$00
    sta PPUADDR
    lda #' '
    ldx #30
@row:
    ldy #32
@col:
    sta PPUDATA
    dey
    bne @col
    dex
    bne @row
    lda #$AA                    ; all quads = text palette 2
    ldx #64
@attr:
    sta PPUDATA
    dex
    bne @attr
    rts
.endproc

.proc title_make_paper_font
    ; Reload BG font with color0→color2 so “empty” pixels use palette
    ; color 2 (paper) instead of universal $3F00. Ink stays color 1.
    ; plane1_new = plane1 | ~plane0. Logo CHR @ $1000 untouched.
    lda #6
    jsr mmc1_set_prg
    bit PPUSTATUS
    lda #$00
    sta PPUADDR
    sta PPUADDR
    lda #<font_chr
    sta str_ptr
    lda #>font_chr
    sta str_ptr+1
    lda #0
    sta title_row               ; 256 tiles
@tile:
    ldy #0
@p0:
    lda (str_ptr),y
    sta chr_plane0,y
    sta PPUDATA
    iny
    cpy #8
    bne @p0
    ldy #0
@p1:
    tya
    clc
    adc #8
    tay
    lda (str_ptr),y
    sta title_lo
    tya
    sec
    sbc #8
    tay
    lda chr_plane0,y
    eor #$FF
    ora title_lo
    sta PPUDATA
    iny
    cpy #8
    bne @p1
    clc
    lda str_ptr
    adc #16
    sta str_ptr
    bcc @nc
    inc str_ptr+1
@nc:
    inc title_row
    bne @tile
    lda #0
    jsr mmc1_set_prg
    rts
.endproc

; Tile row 16: blank gutter (hides CHR-switch jitter). Rows 17–29: paper.
.proc title_fill_paper
    bit PPUSTATUS
    lda #$22
    sta PPUADDR
    lda #$00
    sta PPUADDR
    lda #TILE_BLANK
    ldy #32
@gutter:
    sta PPUDATA
    dey
    bne @gutter
    lda #' '
    ldx #13                     ; rows 17–29
@row:
    ldy #32
@col:
    sta PPUDATA
    dey
    bne @col
    dex
    bne @row
    rts
.endproc

; Blank tile $FF in both CHR banks (row-16 gutter hides timed-split jitter).
.proc title_prepare_split_chr
    bit PPUSTATUS
    lda #$0F
    sta PPUADDR
    lda #$F0
    sta PPUADDR
    ldx #16
    lda #0
@font:
    sta PPUDATA
    dex
    bne @font
    lda #$1F
    sta PPUADDR
    lda #$F0
    sta PPUADDR
    ldx #16
    lda #0
@logo:
    sta PPUDATA
    dex
    bne @logo
    rts
.endproc

.proc title_upload_logo
    lda #$20
    sta PPUADDR
    lda #$00
    sta PPUADDR
    lda #<zorklogo
    sta str_ptr
    lda #>zorklogo
    sta str_ptr+1
    ldx #4
    ldy #0
@page:
    lda (str_ptr),y
    sta PPUDATA
    iny
    bne @page
    inc str_ptr+1
    dex
    bne @page
    rts
.endproc

.proc title_write_messages
    lda #<msg_ver
    sta str_ptr
    lda #>msg_ver
    sta str_ptr+1
    ldx #17
    ldy #1
    jsr title_put_str_at

    lda #<msg_kb
    sta str_ptr
    lda #>msg_kb
    sta str_ptr+1
    ldx #18
    ldy #1
    jsr title_put_str_at

    lda #<msg_f1
    sta str_ptr
    lda #>msg_f1
    sta str_ptr+1
    ldx #20
    ldy #2
    jsr title_put_str_at

    lda #<msg_erase
    sta str_ptr
    lda #>msg_erase
    sta str_ptr+1
    ldx #22
    ldy #1
    jsr title_put_str_at

    lda #<msg_nofsale
    sta str_ptr
    lda #>msg_nofsale
    sta str_ptr+1
    ldx #24
    ldy #1
    jsr title_put_str_at

    lda #<msg_copy
    sta str_ptr
    lda #>msg_copy
    sta str_ptr+1
    ldx #26
    ldy #1
    jsr title_put_str_at

    lda #<msg_mit
    sta str_ptr
    lda #>msg_mit
    sta str_ptr+1
    ldx #28
    ldy #1
    jsr title_put_str_at
    rts
.endproc

.proc title_seek
    lda #0
    sta title_hi
    lda title_row
    asl a
    rol title_hi
    asl a
    rol title_hi
    asl a
    rol title_hi
    asl a
    rol title_hi
    asl a
    rol title_hi
    clc
    adc title_col
    sta title_lo
    lda title_hi
    adc #$20
    bit PPUSTATUS
    sta PPUADDR
    lda title_lo
    sta PPUADDR
    rts
.endproc

; Mixed-case; $0A newline. Walks str_ptr (strings may be >255 bytes).
.proc title_put_str_at
    stx title_row
    sty title_col
    jsr title_seek
@loop:
    ldy #0
    lda (str_ptr),y
    beq @done
    cmp #$0A
    beq @nl
    sta PPUDATA
@adv:
    inc str_ptr
    bne @loop
    inc str_ptr+1
    jmp @loop
@nl:
    inc title_row
    jsr title_seek
    jmp @adv
@done:
    rts
.endproc

.proc title_setup_palettes
    bit PPUSTATUS
    lda #$3F
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ; BG pal 0 — logo (fixed)
    lda #$0F
    sta PPUDATA
    lda #$00
    sta PPUDATA
    lda #$10
    sta PPUDATA
    lda #$30
    sta PPUDATA
    ; BG pal 1 — logo accents (door / gold)
    lda #$0F
    sta PPUDATA
    lda #$17
    sta PPUDATA
    lda #$27
    sta PPUDATA
    lda #$37
    sta PPUDATA
    ; BG pal 2 — title text: c0 unused, c1 ink, c2 paper (theme fills next)
    lda #$0F
    sta PPUDATA
    lda #$2A
    sta PPUDATA
    lda #$0F
    sta PPUDATA
    lda #$0F
    sta PPUDATA
    ; BG pal 3 unused
    ldx #4
    lda #$0F
@pad:
    sta PPUDATA
    dex
    bne @pad

    bit PPUSTATUS
    lda #$23
    sta PPUADDR
    lda #$C2
    sta PPUADDR
    lda #$50
    sta PPUDATA
    sta PPUDATA
    lda #$23
    sta PPUADDR
    lda #$CA
    sta PPUADDR
    lda #$55
    sta PPUDATA
    sta PPUDATA
    lda #$23
    sta PPUADDR
    lda #$D2
    sta PPUADDR
    lda #$55
    sta PPUDATA
    sta PPUDATA
    lda #$23
    sta PPUADDR
    lda #$DA
    sta PPUADDR
    lda #$55
    sta PPUDATA
    sta PPUDATA

    ; Lower screen (tile rows 16–29) → palette 2 for title text
    lda #$23
    sta PPUADDR
    lda #$E0                ; ay=4, ax=0
    sta PPUADDR
    lda #$AA                ; all quads = palette 2
    ldx #32                 ; ay 4..7 (4 rows × 8 bytes)
@attr:
    sta PPUDATA
    dex
    bne @attr
    rts
.endproc

; Title copy lives in PRG bank 6 (ROM7 is full). Bank 6 in before printing.
.segment "STORY6"
msg_ver:
    .byte "                          v1.0", 0
msg_kb:
    .byte "Enter=Keyboard   Start=Gamepad", 0
msg_f1:
    .byte "F1 / Select = Color Scheme", 0
msg_erase:
    .byte "F8 / Hold A+B 5s = Erase Save", 0
msg_erased:
    .byte "Save Data Erased.             ", 0
msg_nofsale:
    .byte "Not for sale or commercial use", 0
msg_copy:
    .byte "github.com/lupinthird/zorknes", 0
msg_mit:
    .byte "Zork I  MIT (c) 2025 Microsoft", 0
msg_egg:
    .byte "Thank you for trying this game.", $0A
    .byte "My dad and I played this on our", $0A
    .byte "C-64 when I was a kid. He's gone", $0A
    .byte "now, but I wanted to commemorate", $0A
    .byte "our time by bringing this game", $0A
    .byte "to the best retro console ever,", $0A
    .byte "the NES.", $0A, $0A
    .byte "Let me know what you thought!", $0A
    .byte "Chris", $0A
    .byte "lupin3rd@gmail.com", $0A, $0A
    .byte "Press START or ENTER to exit.", 0

.segment "RODATA"
.include "../nam/zorklogont.s"
