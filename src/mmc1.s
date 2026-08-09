.include "nes.inc"

.export mmc1_reset, mmc1_init, mmc1_set_prg, mmc1_set_wram
.export mmc1_write_ctrl, mmc1_write_chr0, mmc1_write_prg
.exportzp mmc1_tmp, mmc1_prgbank, mmc1_wram_bank

.segment "ZEROPAGE"
mmc1_tmp:       .res 1
mmc1_prgbank:   .res 1
mmc1_wram_bank: .res 1

.segment "CODE"

; MMC1 uses a 5-bit shift register. NMI must never nest inside a
; serial write (text flush also banks WRAM via CHR0).

.proc mmc1_reset
    php
    sei
    lda #$80
    sta MMC1_CTRL
    plp
    rts
.endproc

.proc mmc1_write_ctrl
    sta mmc1_tmp
    php
    sei
    lda #$80
    sta MMC1_CTRL
    lda mmc1_tmp
    ldx #5
@loop:
    sta MMC1_CTRL
    lsr a
    dex
    bne @loop
    plp
    rts
.endproc

.proc mmc1_write_chr0
    sta mmc1_tmp
    php
    sei
    lda #$80
    sta MMC1_CHRB
    lda mmc1_tmp
    ldx #5
@loop:
    sta MMC1_CHRB
    lsr a
    dex
    bne @loop
    plp
    rts
.endproc

.proc mmc1_write_prg
    sta mmc1_tmp
    php
    sei
    lda #$80
    sta MMC1_PRG
    lda mmc1_tmp
    ldx #5
@loop:
    sta MMC1_PRG
    lsr a
    dex
    bne @loop
    plp
    rts
.endproc

; 16K PRG @ $8000, fixed last @ $C000; 8K CHR (SXROM CHR-RAM);
; vertical mirroring. Control: CHR8K, PRG mode 3, mirror V → %01110
.proc mmc1_init
    jsr mmc1_reset
    lda #%01110
    jsr mmc1_write_ctrl
    lda #0
    sta mmc1_prgbank
    jsr mmc1_write_prg
    lda #0
    jsr mmc1_set_wram
    rts
.endproc

.proc mmc1_set_prg
    and #$0F
    sta mmc1_prgbank
    jmp mmc1_write_prg
.endproc

; SXROM: WRAM bank in CHR bank0 bits 3..2. With 8K CHR-RAM the low
; bank bit is ignored, so font patterns stay put across WRAM switches.
.proc mmc1_set_wram
    and #$03
    asl a
    asl a
    sta mmc1_wram_bank
    jmp mmc1_write_chr0
.endproc
