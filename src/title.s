.include "nes.inc"

.import wait_vblank
.import read_keyboard, keyboard_poll_chars
.import read_pads
.importzp str_ptr, frame_count
.importzp key_ready, key_ascii, kb_enable
.importzp pad1_pressed
.export title_show, title_nmi
.exportzp title_active

; NMI on + BG $1000 (logo) / $0000 (font)
PPUCTRL_LOGO = %10010000
PPUCTRL_TEXT = %10000000

; Delay from NMI (vblank start) to ~tile row 16. Tune if seam drifts.
SPLIT_OUTER = 24
SPLIT_INNER = 138

.segment "ZEROPAGE"
title_active: .res 1
title_row:    .res 1
title_col:    .res 1
title_lo:     .res 1
title_hi:     .res 1

.segment "CODE"

; Called from NMI when title_active ≠ 0. Runs the mid-frame CHR split
; with frame-locked timing (avoids wait_vblank drift from keyboard work).
.proc title_nmi
    bit PPUSTATUS
    lda #PPUCTRL_LOGO
    sta PPUCTRL
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL

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
.endproc

; CHR: font @ $0000, logo @ $1000. Leaves rendering off, NMI off.
.proc title_show
    bit PPUSTATUS
    jsr title_upload_logo
    jsr title_write_messages
    jsr title_setup_palettes

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
    lda pad1_pressed
    and #PAD_START
    bne @dismiss

    jsr read_keyboard
    jsr keyboard_poll_chars
    lda key_ready
    beq @frame
    lda #0
    sta key_ready
    lda key_ascii
    cmp #$0D
    bne @frame
@dismiss:
    lda #0
    sta title_active
    sta PPUMASK
    sta kb_enable
    sta PPUCTRL              ; NMI off until main re-enables
    jsr wait_vblank
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
    ldy #4
    jsr title_put_str_at

    lda #<msg_enter
    sta str_ptr
    lda #>msg_enter
    sta str_ptr+1
    ldx #22
    ldy #7
    jsr title_put_str_at

    lda #<msg_copy
    sta str_ptr
    lda #>msg_copy
    sta str_ptr+1
    ldx #26
    ldy #8
    jsr title_put_str_at
    rts
.endproc

.proc title_put_str_at
    stx title_row
    sty title_col
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
    ldy #0
@loop:
    lda (str_ptr),y
    beq @done
    cmp #'a'
    bcc @store
    cmp #'z'+1
    bcs @store
    sec
    sbc #$20
@store:
    sta PPUDATA
    iny
    bne @loop
@done:
    rts
.endproc

.proc title_setup_palettes
    bit PPUSTATUS
    lda #$3F
    sta PPUADDR
    lda #$00
    sta PPUADDR
    lda #$0F
    sta PPUDATA
    lda #$00
    sta PPUDATA
    lda #$10
    sta PPUDATA
    lda #$30
    sta PPUDATA
    lda #$0F
    sta PPUDATA
    lda #$17
    sta PPUDATA
    lda #$27
    sta PPUDATA
    lda #$37
    sta PPUDATA
    ; BG pal 2 — title text (white/gray swapped vs pal 0)
    lda #$0F
    sta PPUDATA             ; $3F08 backdrop mirror
    lda #$30
    sta PPUDATA             ; was $00 in pal 0
    lda #$10
    sta PPUDATA
    lda #$00
    sta PPUDATA             ; was $30 in pal 0
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

.segment "RODATA"
msg_kb:
    .byte "FAMILY BASIC KEYBOARD REQUIRED", 0
msg_f1:
    .byte "F1 = TOGGLE COLOR SCHEME", 0
msg_enter:
    .byte "ENTER TO CONTINUE", 0
msg_copy:
    .byte "(C) 2026 LUPIN3RD", 0

.include "../nam/zorklogont.s"
