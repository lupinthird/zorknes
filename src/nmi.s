.include "nes.inc"

.import palette_apply_now, palette_cycle
.import read_pads
.import text_flush_nmi
.export nmi, restore_scroll
.exportzp frame_count
.importzp palette_dirty, pad1_pressed, kb_enable

.segment "ZEROPAGE"
frame_count: .res 1

.segment "OAM"
oam: .res 256
.export oam

.segment "CODE"

.proc nmi
    pha
    txa
    pha
    tya
    pha

    ; No OAM DMA yet (no sprites). Do not bank WRAM/CHR here.

    lda kb_enable
    bne @no_pads
    jsr read_pads
    lda pad1_pressed
    and #PAD_SELECT
    beq @no_pads
    jsr palette_cycle
@no_pads:

    lda palette_dirty
    beq @no_pal
    jsr palette_apply_now
@no_pal:
    ; Drain VQ (no WRAM banking — keep MMC1 clear of the main thread).
    jsr text_flush_nmi
    jsr restore_scroll

    inc frame_count

    pla
    tay
    pla
    tax
    pla
    rti
.endproc

.proc restore_scroll
    bit PPUSTATUS
    lda #PPUCTRL_NMI
    sta PPUCTRL
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    rts
.endproc

.proc irq
    rti
.endproc
.export irq
