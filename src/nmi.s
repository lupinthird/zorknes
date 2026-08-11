.include "nes.inc"

.import palette_apply_now
.import text_flush_nmi
.import title_nmi
.export nmi, restore_scroll
.exportzp frame_count
.importzp palette_dirty
.importzp title_active
.importzp z_rng
.if ::SMOOTH_SCROLL
.import text_scroll_tick, scroll_snap_nmi
.importzp scroll_y
.endif

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

    lda title_active
    beq @game
    jsr title_nmi
    jmp @done

@game:
    lda palette_dirty
    beq @no_pal
    jsr palette_apply_now
@no_pal:
    jsr text_flush_nmi
.if ::SMOOTH_SCROLL
    jsr text_scroll_tick
    jsr scroll_snap_nmi
.endif
    jsr restore_scroll

@done:
    inc frame_count
    clc
    lda z_rng
    adc frame_count
    sta z_rng
    bcc @rngok
    inc z_rng+1
@rngok:
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
.if ::SMOOTH_SCROLL
    lda scroll_y
.else
    lda #0
.endif
    sta PPUSCROLL
    rts
.endproc

.proc irq
    rti
.endproc
.export irq
