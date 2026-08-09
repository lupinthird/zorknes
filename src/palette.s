.include "nes.inc"

.importzp theme_id, palette_dirty
.export palette_apply_now, palette_request_apply, palette_cycle
.export theme_tables, theme_green

.segment "CODE"

.proc palette_request_apply
    lda #1
    sta palette_dirty
    rts
.endproc

.proc palette_cycle
    lda theme_id
    clc
    adc #1
    cmp #THEME_COUNT
    bcc @ok
    lda #0
@ok:
    sta theme_id
    jmp palette_request_apply
.endproc

; Call only with rendering off or during vblank (NMI)
.proc palette_apply_now
    lda theme_id
    asl a
    asl a
    asl a
    asl a              ; *16
    tay
    bit PPUSTATUS      ; reset address latch
    lda #$3F
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldx #16
@loop:
    lda theme_green,y
    sta PPUDATA
    iny
    dex
    bne @loop
    lda theme_id
    asl a
    asl a
    asl a
    asl a
    tay
    ldx #16
@spr:
    lda theme_green,y
    sta PPUDATA
    iny
    dex
    bne @spr
    lda #0
    sta palette_dirty
    rts
.endproc

.segment "RODATA"
; color0 = backdrop, color1 = text foreground (16 bytes per theme)
theme_tables:
theme_green:
    .byte $0F, $2A, $0F, $0F
    .byte $0F, $2A, $0F, $0F
    .byte $0F, $2A, $0F, $0F
    .byte $0F, $2A, $0F, $0F
theme_gray:
    .byte $0F, $20, $0F, $0F
    .byte $0F, $20, $0F, $0F
    .byte $0F, $20, $0F, $0F
    .byte $0F, $20, $0F, $0F
theme_c64:
    .byte $0C, $31, $0F, $0F
    .byte $0C, $31, $0F, $0F
    .byte $0C, $31, $0F, $0F
    .byte $0C, $31, $0F, $0F
