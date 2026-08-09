.include "nes.inc"

.import mmc1_set_prg, mmc1_set_wram
.export zmem_init, zmem_loadb, zmem_storeb, zmem_loadw, zmem_storew
.export zmem_copy_dynamic, zmem_loadb_phys
.export zmem_wram_text_on, zmem_wram_text_off
.exportzp z_addr, z_static_base, z_himem, z_pc_init, z_phys, z_wram_idx

WRAM_BANK_TEXT = 2

.segment "ZEROPAGE"
z_addr:         .res 2
z_phys:         .res 3
z_static_base:  .res 2
z_himem:        .res 2
z_pc_init:      .res 2
z_ptr:          .res 2
z_tmp:          .res 1
z_tmp2:         .res 1
z_wram_idx:     .res 1      ; current WRAM bank 0-3
z_wram_save:    .res 1
z_wram_text_depth: .res 1   ; nest count (NMI flush vs main text)

.segment "CODE"

.proc set_wram
    and #$03
    sta z_wram_idx
    ; Always poke MMC1 — skipping when z_wram_idx already matches can
    ; desync from hardware (e.g. after other MMC1 writes), which made
    ; text land in the wrong WRAM bank while flush read an empty mirror.
    jmp mmc1_set_wram
.endproc

; Select WRAM bank 2 for nt_mirror. Nest-safe: NMI text_flush may
; re-enter while main is already in a text_on region.
.proc zmem_wram_text_on
    lda z_wram_text_depth
    bne @inc
    lda z_wram_idx
    sta z_wram_save
    lda #WRAM_BANK_TEXT
    jsr set_wram
@inc:
    inc z_wram_text_depth
    rts
.endproc

.proc zmem_wram_text_off
    lda z_wram_text_depth
    beq @force
    dec z_wram_text_depth
    bne @done
@force:
    lda #0
    sta z_wram_text_depth
    lda z_wram_save
    jmp set_wram
@done:
    rts
.endproc

; Map z_phys (24-bit) → MMC1 PRG bank + z_ptr at $8000|off
.proc map_phys
    ; bank = phys >> 14
    lda z_phys+1
    sta z_tmp
    lda z_phys+2
    lsr a
    ror z_tmp
    lsr a
    ror z_tmp
    lsr a
    ror z_tmp
    lsr a
    ror z_tmp
    lsr a
    ror z_tmp
    lsr a
    ror z_tmp
    lda z_tmp
    jsr mmc1_set_prg
    lda z_phys
    sta z_ptr
    lda z_phys+1
    and #$3F
    ora #$80
    sta z_ptr+1
    rts
.endproc

.proc zmem_loadb_phys
    jsr map_phys
    ldy #0
    lda (z_ptr),y
    rts
.endproc

; A = byte at 16-bit Z address z_addr
.proc zmem_loadb
    lda z_addr+1
    cmp z_static_base+1
    bcc @dyn
    bne @rom
    lda z_addr
    cmp z_static_base
    bcc @dyn
@rom:
    lda z_addr
    sta z_phys
    lda z_addr+1
    sta z_phys+1
    lda #0
    sta z_phys+2
    jmp zmem_loadb_phys
@dyn:
    lda z_addr+1
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    jsr set_wram
    lda z_addr
    sta z_ptr
    lda z_addr+1
    and #$1F
    ora #$60
    sta z_ptr+1
    ldy #0
    lda (z_ptr),y
    rts
.endproc

; Store A at z_addr (dynamic only)
.proc zmem_storeb
    sta z_tmp
    lda z_addr+1
    cmp z_static_base+1
    bcc @dyn
    bne @done
    lda z_addr
    cmp z_static_base
    bcs @done
@dyn:
    lda z_addr+1
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    jsr set_wram
    lda z_addr
    sta z_ptr
    lda z_addr+1
    and #$1F
    ora #$60
    sta z_ptr+1
    ldy #0
    lda z_tmp
    sta (z_ptr),y
@done:
    rts
.endproc

; Big-endian word at z_addr → A = low, X = high
.proc zmem_loadw
    php
    sei
    jsr zmem_loadb
    sta z_tmp2              ; high byte of value
    inc z_addr
    bne :+
    inc z_addr+1
:
    jsr zmem_loadb          ; low byte
    ldx z_tmp2
    plp
    rts
.endproc

; Store word A=low X=high (big-endian) at z_addr
.proc zmem_storew
    php
    sei
    sta z_tmp2              ; low byte (z_tmp is clobbered by storeb)
    txa
    jsr zmem_storeb         ; store high first
    inc z_addr
    bne :+
    inc z_addr+1
:
    lda z_tmp2
    jsr zmem_storeb
    plp
    rts
.endproc

; Read header fields from story ROM via physical addresses only
.proc zmem_init
    lda #0
    sta z_wram_idx
    sta z_wram_text_depth
    sta z_wram_save
    jsr set_wram

    ; static base @ $0E (BE)
    lda #$0E
    sta z_phys
    lda #0
    sta z_phys+1
    sta z_phys+2
    jsr zmem_loadb_phys
    sta z_static_base+1
    lda #$0F
    sta z_phys
    jsr zmem_loadb_phys
    sta z_static_base

    ; himem @ $04
    lda #$04
    sta z_phys
    jsr zmem_loadb_phys
    sta z_himem+1
    lda #$05
    sta z_phys
    jsr zmem_loadb_phys
    sta z_himem

    ; initial PC @ $06
    lda #$06
    sta z_phys
    jsr zmem_loadb_phys
    sta z_pc_init+1
    lda #$07
    sta z_phys
    jsr zmem_loadb_phys
    sta z_pc_init
    rts
.endproc

; Copy [0, static_base) from story PRG into WRAM (bank-coalesced)
.proc zmem_copy_dynamic
    lda #0
    sta z_phys
    sta z_phys+1
    sta z_phys+2
    sta z_addr
    sta z_addr+1
    lda #$FF
    sta z_tmp2              ; last PRG bank sentinel
    ; z_wram_idx tracked by set_wram
@loop:
    lda z_addr+1
    cmp z_static_base+1
    bcc @copy
    bne @done
    lda z_addr
    cmp z_static_base
    bcs @done
@copy:
    ; PRG bank = phys >> 14
    lda z_phys+1
    sta z_tmp
    lda z_phys+2
    lsr a
    ror z_tmp
    lsr a
    ror z_tmp
    lsr a
    ror z_tmp
    lsr a
    ror z_tmp
    lsr a
    ror z_tmp
    lsr a
    ror z_tmp
    lda z_tmp
    cmp z_tmp2
    beq @same_prg
    sta z_tmp2
    jsr mmc1_set_prg
@same_prg:
    lda z_phys
    sta z_ptr
    lda z_phys+1
    and #$3F
    ora #$80
    sta z_ptr+1
    ldy #0
    lda (z_ptr),y
    sta z_tmp

    lda z_addr+1
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    cmp z_wram_idx
    beq @same_wram
    jsr set_wram
@same_wram:
    lda z_addr
    sta z_ptr
    lda z_addr+1
    and #$1F
    ora #$60
    sta z_ptr+1
    ldy #0
    lda z_tmp
    sta (z_ptr),y

    inc z_phys
    bne :+
    inc z_phys+1
    bne :+
    inc z_phys+2
:
    inc z_addr
    bne @loop
    inc z_addr+1
    jmp @loop
@done:
    lda #0
    jsr set_wram
    rts
.endproc
