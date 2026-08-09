.include "nes.inc"

.export read_pads
.exportzp pad1, pad1_prev, pad1_pressed

.segment "ZEROPAGE"
pad1:         .res 1
pad1_prev:    .res 1
pad1_pressed: .res 1

.segment "CODE"

; Call from NMI shortly after OAM DMA (not from main mid-frame).
.proc read_pads
    lda pad1
    sta pad1_prev
    lda #1
    sta JOY1
    lda #0
    sta JOY1
    ldx #8
    lda #0
    sta pad1
@bit:
    lda JOY1
    lsr a              ; bit0 → carry (ignore open-bus high bits)
    ror pad1
    dex
    bne @bit
    lda pad1_prev
    eor #$FF
    and pad1
    sta pad1_pressed
    rts
.endproc
