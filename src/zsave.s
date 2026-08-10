; Single-slot battery save in WRAM banks 2+3 (16 KiB).
; EXT:0 save / EXT:1 restore — V5 store: 0=fail, 1=saved, 2=restored-here.

.include "nes.inc"
.include "zmachine.inc"

.import zmem_set_wram, zmem_loadb, zmem_storeb
.import z_do_store
.import z_header_rst
.import z_stack_lo, z_stack_hi
.import z_locals_lo, z_locals_hi
.import z_saved_lo, z_saved_hi
.import z_frame_ret0, z_frame_ret1, z_frame_ret2, z_frame_dest
.import z_frame_nlcl, z_frame_ofp, z_frame_osp, z_frame_argc
.import z_argc
.importzp z_pc, z_sp, z_fp, z_a, z_addr, z_static_base
.importzp z_tmpw, z_i, z_phys

.export z_op_save, z_op_restore, zsave_erase

Z_FRAME_MAX = 16

.segment "ZEROPAGE"
sv_ptr:    .res 2
sv_bank:   .res 1
sv_flags2: .res 2
sv_byte:   .res 1
sv_count:  .res 1
sv_src:    .res 2

.segment "CODE"

.proc sv_rewind
    lda #WRAM_BANK_SAVE0
    sta sv_bank
    jsr zmem_set_wram
    lda #$00
    sta sv_ptr
    lda #$60
    sta sv_ptr+1
    rts
.endproc

.proc sv_advance
    inc sv_ptr
    bne @ok
    inc sv_ptr+1
    lda sv_ptr+1
    cmp #$80
    bcc @ok
    lda #WRAM_BANK_SAVE1
    sta sv_bank
    jsr zmem_set_wram
    lda #$00
    sta sv_ptr
    lda #$60
    sta sv_ptr+1
@ok:
    rts
.endproc

; MMC1 serial writes clobber X — preserve X/Y so callers can loop with dex.
.proc sv_put
    sta sv_byte
    txa
    pha
    tya
    pha
    lda sv_bank
    jsr zmem_set_wram
    ldy #0
    lda sv_byte
    sta (sv_ptr),y
    jsr sv_advance
    pla
    tay
    pla
    tax
    rts
.endproc

.proc sv_get
    txa
    pha
    tya
    pha
    lda sv_bank
    jsr zmem_set_wram
    ldy #0
    lda (sv_ptr),y
    sta sv_byte
    jsr sv_advance
    pla
    tay
    pla
    tax
    lda sv_byte
    rts
.endproc

; Write A bytes from address sv_src
.proc sv_put_mem
    sta sv_count
    ldy #0
@lp:
    cpy sv_count
    bcs @done
    lda (sv_src),y
    sty z_i
    jsr sv_put
    ldy z_i
    iny
    bne @lp
@done:
    rts
.endproc

.proc sv_get_mem
    sta sv_count
    ldy #0
@lp:
    cpy sv_count
    bcs @done
    sty z_i
    jsr sv_get
    ldy z_i
    sta (sv_src),y
    iny
    bne @lp
@done:
    rts
.endproc

.proc sv_write_header
    lda #'Z'
    jsr sv_put
    lda #'K'
    jsr sv_put
    lda #'S'
    jsr sv_put
    lda #'1'
    jsr sv_put
    lda z_static_base+1
    jsr sv_put
    lda z_static_base
    jsr sv_put
    ; release @ $02
    lda #$02
    sta z_addr
    lda #0
    sta z_addr+1
    jsr zmem_loadb
    jsr sv_put
    lda #$03
    sta z_addr
    jsr zmem_loadb
    jsr sv_put
    ; serial @ $12..$17
    lda #0
    sta z_i
@ser:
    lda z_i
    clc
    adc #$12
    sta z_addr
    lda #0
    sta z_addr+1
    jsr zmem_loadb
    jsr sv_put
    inc z_i
    lda z_i
    cmp #6
    bcc @ser
    lda #0
    jsr sv_put
    jsr sv_put                 ; pad to $10
    ; PC / SP / FP / argc
    lda z_pc
    jsr sv_put
    lda z_pc+1
    jsr sv_put
    lda z_pc+2
    jsr sv_put
    lda z_sp
    jsr sv_put
    lda z_fp
    jsr sv_put
    lda z_argc
    jsr sv_put
    lda #0
    ldx #10
@pad:
    jsr sv_put
    dex
    bne @pad
    rts
.endproc

.proc sv_check_header
    jsr sv_get
    cmp #'Z'
    bne @bad
    jsr sv_get
    cmp #'K'
    bne @bad
    jsr sv_get
    cmp #'S'
    bne @bad
    jsr sv_get
    cmp #'1'
    bne @bad
    jsr sv_get
    cmp z_static_base+1
    bne @bad
    jsr sv_get
    cmp z_static_base
    bne @bad
    ; skip release+serial+pad (2+6+2 = 10)
    ldx #10
@sk:
    jsr sv_get
    dex
    bne @sk
    clc
    rts
@bad:
    sec
    rts
.endproc

.proc sv_write_host
    ; stack
    lda #<z_stack_lo
    sta sv_src
    lda #>z_stack_lo
    sta sv_src+1
    lda #Z_STACK_MAX
    jsr sv_put_mem
    lda #<z_stack_hi
    sta sv_src
    lda #>z_stack_hi
    sta sv_src+1
    lda #Z_STACK_MAX
    jsr sv_put_mem
    ; frames
    lda #<z_frame_ret0
    sta sv_src
    lda #>z_frame_ret0
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_put_mem
    lda #<z_frame_ret1
    sta sv_src
    lda #>z_frame_ret1
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_put_mem
    lda #<z_frame_ret2
    sta sv_src
    lda #>z_frame_ret2
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_put_mem
    lda #<z_frame_dest
    sta sv_src
    lda #>z_frame_dest
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_put_mem
    lda #<z_frame_nlcl
    sta sv_src
    lda #>z_frame_nlcl
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_put_mem
    lda #<z_frame_ofp
    sta sv_src
    lda #>z_frame_ofp
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_put_mem
    lda #<z_frame_osp
    sta sv_src
    lda #>z_frame_osp
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_put_mem
    lda #<z_frame_argc
    sta sv_src
    lda #>z_frame_argc
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_put_mem
    ; locals
    lda #<z_locals_lo
    sta sv_src
    lda #>z_locals_lo
    sta sv_src+1
    lda #15
    jsr sv_put_mem
    lda #<z_locals_hi
    sta sv_src
    lda #>z_locals_hi
    sta sv_src+1
    lda #15
    jsr sv_put_mem
    ; saved locals
    lda #<z_saved_lo
    sta sv_src
    lda #>z_saved_lo
    sta sv_src+1
    lda #<(Z_FRAME_MAX * 15)
    jsr sv_put_mem
    lda #<z_saved_hi
    sta sv_src
    lda #>z_saved_hi
    sta sv_src+1
    lda #<(Z_FRAME_MAX * 15)
    jsr sv_put_mem
    rts
.endproc

.proc sv_read_host
    lda #<z_stack_lo
    sta sv_src
    lda #>z_stack_lo
    sta sv_src+1
    lda #Z_STACK_MAX
    jsr sv_get_mem
    lda #<z_stack_hi
    sta sv_src
    lda #>z_stack_hi
    sta sv_src+1
    lda #Z_STACK_MAX
    jsr sv_get_mem
    lda #<z_frame_ret0
    sta sv_src
    lda #>z_frame_ret0
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_get_mem
    lda #<z_frame_ret1
    sta sv_src
    lda #>z_frame_ret1
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_get_mem
    lda #<z_frame_ret2
    sta sv_src
    lda #>z_frame_ret2
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_get_mem
    lda #<z_frame_dest
    sta sv_src
    lda #>z_frame_dest
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_get_mem
    lda #<z_frame_nlcl
    sta sv_src
    lda #>z_frame_nlcl
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_get_mem
    lda #<z_frame_ofp
    sta sv_src
    lda #>z_frame_ofp
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_get_mem
    lda #<z_frame_osp
    sta sv_src
    lda #>z_frame_osp
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_get_mem
    lda #<z_frame_argc
    sta sv_src
    lda #>z_frame_argc
    sta sv_src+1
    lda #Z_FRAME_MAX
    jsr sv_get_mem
    lda #<z_locals_lo
    sta sv_src
    lda #>z_locals_lo
    sta sv_src+1
    lda #15
    jsr sv_get_mem
    lda #<z_locals_hi
    sta sv_src
    lda #>z_locals_hi
    sta sv_src+1
    lda #15
    jsr sv_get_mem
    lda #<z_saved_lo
    sta sv_src
    lda #>z_saved_lo
    sta sv_src+1
    lda #<(Z_FRAME_MAX * 15)
    jsr sv_get_mem
    lda #<z_saved_hi
    sta sv_src
    lda #>z_saved_hi
    sta sv_src+1
    lda #<(Z_FRAME_MAX * 15)
    jsr sv_get_mem
    rts
.endproc

; Copy live dynamic (banks 0/1) → save stream.
.proc sv_write_dynamic
    lda #0
    sta z_addr
    sta z_addr+1
@lp:
    lda z_addr+1
    cmp z_static_base+1
    bcc @go
    bne @done
    lda z_addr
    cmp z_static_base
    bcs @done
@go:
    jsr zmem_loadb
    jsr sv_put
    inc z_addr
    bne @lp
    inc z_addr+1
    jmp @lp
@done:
    rts
.endproc

.proc sv_read_dynamic
    lda #0
    sta z_addr
    sta z_addr+1
@lp:
    lda z_addr+1
    cmp z_static_base+1
    bcc @go
    bne @done
    lda z_addr
    cmp z_static_base
    bcs @done
@go:
    jsr sv_get
    jsr zmem_storeb
    inc z_addr
    bne @lp
    inc z_addr+1
    jmp @lp
@done:
    rts
.endproc

.proc z_op_save
    ; Optional EXT operands ignored (filename/region) — always slot 0.
    jsr sv_rewind
    jsr sv_write_header
    jsr sv_write_host
    jsr sv_write_dynamic
    lda #0
    jsr zmem_set_wram
    lda #1
    sta z_a
    lda #0
    sta z_a+1
    jmp z_do_store
.endproc

.proc z_op_restore
    ; Preserve Flags2 from the *current* game (spec 6.1.2).
    lda #$10
    sta z_addr
    lda #0
    sta z_addr+1
    jsr zmem_loadb
    sta sv_flags2+1
    lda #$11
    sta z_addr
    jsr zmem_loadb
    sta sv_flags2

    jsr sv_rewind
    jsr sv_check_header
    bcs @fail

    jsr sv_get
    sta z_pc
    jsr sv_get
    sta z_pc+1
    jsr sv_get
    sta z_pc+2
    jsr sv_get
    sta z_sp
    jsr sv_get
    sta z_fp
    jsr sv_get
    sta z_argc
    ldx #10
@pad:
    jsr sv_get
    dex
    bne @pad

    jsr sv_read_host
    jsr sv_read_dynamic

    ; Restore preserved Flags2
    lda #$10
    sta z_addr
    lda #0
    sta z_addr+1
    lda sv_flags2+1
    jsr zmem_storeb
    lda #$11
    sta z_addr
    lda sv_flags2
    jsr zmem_storeb

    jsr z_header_rst
    lda #0
    jsr zmem_set_wram

    ; Resume as if SAVE stored 2
    lda #2
    sta z_a
    lda #0
    sta z_a+1
    jmp z_do_store

@fail:
    lda #0
    jsr zmem_set_wram
    lda #0
    sta z_a
    sta z_a+1
    jmp z_do_store
.endproc

; Wipe battery save slot (WRAM banks 2+3). Safe to call from title.
.proc zsave_erase
    lda #WRAM_BANK_SAVE0
    jsr zmem_set_wram
    jsr @fill_bank
    lda #WRAM_BANK_SAVE1
    jsr zmem_set_wram
    jsr @fill_bank
    lda #0
    jmp zmem_set_wram

@fill_bank:
    lda #$00
    sta sv_ptr
    lda #$60
    sta sv_ptr+1
    lda #0
    tay
@lp:
    sta (sv_ptr),y
    iny
    bne @lp
    inc sv_ptr+1
    ldx sv_ptr+1
    cpx #$80
    bcc @lp
    rts
.endproc
