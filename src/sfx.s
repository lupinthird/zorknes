.include "nes.inc"

.export sfx_boop

.segment "CODE"

; Soft typewriter / CRT boop on pulse 1
.proc sfx_boop
    lda #%00000001
    sta SND_CHN
    lda #%00010001      ; duty 00, length runs, const vol, vol=1
    sta $4000
    lda #$00
    sta $4001
    lda #$A0
    sta $4002
    lda #%00011010      ; short length, timer high
    sta $4003
    rts
.endproc
