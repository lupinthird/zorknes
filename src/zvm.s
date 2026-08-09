.include "nes.inc"
.include "zmachine.inc"

.import zmem_loadb, zmem_storeb, zmem_loadw, zmem_storew, zmem_loadb_phys
.importzp z_addr, z_static_base, z_himem, z_pc_init, z_phys, z_wram_idx
.import z_decode_exec

.export zvm_boot, zvm_step, z_trap, z_fetch_b, z_fetch_w, z_pc_inc
.export z_push, z_pop, z_get_var, z_put_var, z_get_var_ind, z_put_var_ind
.exportzp z_pc, z_sp, z_fp, z_opcount, z_opcode, z_running, z_globals
.exportzp z_ops_lo, z_ops_hi, z_result_var, z_tmpw, z_a, z_b
.exportzp z_types, z_extop, z_i, z_call_has_store, z_abbrev_base
.exportzp z_obj_base, z_str_inline
.exportzp z_waiting_input, z_read_text, z_read_parse, z_line_len

.segment "ZEROPAGE"
z_pc:         .res 3
z_sp:         .res 1
z_fp:         .res 1
z_opcount:    .res 1
z_opcode:     .res 1
z_running:    .res 1
z_globals:    .res 2
z_ops_lo:     .res Z_MAX_OPS
z_ops_hi:     .res Z_MAX_OPS
z_result_var: .res 1
z_tmpw:       .res 2
z_a:          .res 2
z_b:          .res 2
z_types:      .res 1
z_extop:      .res 1
z_i:          .res 1
z_call_has_store: .res 1
z_abbrev_base: .res 2
z_obj_base:   .res 2
z_str_inline: .res 1
z_waiting_input: .res 1
z_read_text:  .res 2
z_read_parse: .res 2
z_line_len:   .res 1

.segment "BSS"
z_stack_lo:   .res Z_STACK_MAX
z_stack_hi:   .res Z_STACK_MAX
Z_FRAME_MAX = 16
z_frame_ret0: .res Z_FRAME_MAX
z_frame_ret1: .res Z_FRAME_MAX
z_frame_ret2: .res Z_FRAME_MAX
z_frame_dest: .res Z_FRAME_MAX
z_frame_nlcl: .res Z_FRAME_MAX
z_frame_ofp:  .res Z_FRAME_MAX
z_frame_osp:  .res Z_FRAME_MAX
z_frame_argc: .res Z_FRAME_MAX
z_locals_lo:  .res 15
z_locals_hi:  .res 15
z_saved_lo:   .res Z_FRAME_MAX * 15
z_saved_hi:   .res Z_FRAME_MAX * 15
z_argc:       .res 1
Z_TRAIL = 8
z_trail_lo:   .res Z_TRAIL
z_trail_hi:   .res Z_TRAIL
z_trail_i:    .res 1
z_dbg_a:      .res 1
z_dbg_b:      .res 1
z_dbg_c:      .res 1
z_dbg_d:      .res 1
.export z_locals_lo, z_locals_hi
.export z_frame_ret0, z_frame_ret1, z_frame_ret2, z_frame_dest
.export z_frame_nlcl, z_frame_ofp, z_frame_osp, z_frame_argc
.export z_saved_lo, z_saved_hi, z_argc
.export z_trail_lo, z_trail_hi, z_trail_i
.export z_dbg_a, z_dbg_b, z_dbg_c, z_dbg_d

.segment "CODE"

.proc z_pc_inc
    inc z_pc
    bne :+
    inc z_pc+1
    bne :+
    inc z_pc+2
:
    rts
.endproc

.proc z_fetch_b
    lda z_pc
    sta z_phys
    lda z_pc+1
    sta z_phys+1
    lda z_pc+2
    sta z_phys+2
    jsr zmem_loadb_phys
    pha
    jsr z_pc_inc
    pla
    rts
.endproc

.proc z_fetch_w
    jsr z_fetch_b
    sta z_tmpw+1
    jsr z_fetch_b
    sta z_tmpw
    lda z_tmpw
    ldx z_tmpw+1
    rts
.endproc

.proc z_push
    ldy z_sp
    cpy #Z_STACK_MAX
    bcs @ov
    sta z_stack_lo,y
    txa
    sta z_stack_hi,y
    inc z_sp
    rts
@ov:
    lda #$FB
    jmp z_trap
.endproc

.proc z_pop
    lda z_sp
    bne @ok
    lda #$FC
    jmp z_trap
@ok:
    dec z_sp
    ldy z_sp
    lda z_stack_lo,y
    ldx z_stack_hi,y
    rts
.endproc

; Peek top of stack (no SP change). Used by indirect var-0 ops.
.proc z_stack_peek
    lda z_sp
    bne @ok
    lda #$FC
    jmp z_trap
@ok:
    tay
    dey
    lda z_stack_lo,y
    ldx z_stack_hi,y
    rts
.endproc

; Replace top of stack. If empty, push (store-to-sp on empty stack).
.proc z_stack_poke
    ldy z_sp
    bne @rep
    jmp z_push
@rep:
    dey
    sta z_stack_lo,y
    txa
    sta z_stack_hi,y
    rts
.endproc

.proc z_get_var
    cpy #0
    bne @n
    jmp z_pop
@n:
    cpy #$10
    bcs @g
    dey
    lda z_locals_lo,y
    ldx z_locals_hi,y
    rts
@g:
    tya
    sec
    sbc #$10
    asl a
    sta z_addr
    lda #0
    rol a
    sta z_addr+1
    lda z_addr
    clc
    adc z_globals
    sta z_addr
    lda z_addr+1
    adc z_globals+1
    sta z_addr+1
    jmp zmem_loadw
.endproc

.proc z_put_var
    cpy #0
    bne @n
    jmp z_push
@n:
    cpy #$10
    bcs @g
    dey
    sta z_locals_lo,y
    txa
    sta z_locals_hi,y
    rts
@g:
    sta z_tmpw
    stx z_tmpw+1
    tya
    sec
    sbc #$10
    asl a
    sta z_addr
    lda #0
    rol a
    sta z_addr+1
    lda z_addr
    clc
    adc z_globals
    sta z_addr
    lda z_addr+1
    adc z_globals+1
    sta z_addr+1
    lda z_tmpw
    ldx z_tmpw+1
    jmp zmem_storew
.endproc

; load/store/inc/dec/pull: var 0 is in-place stack peek/poke (Z-spec 6.3)
.proc z_get_var_ind
    cpy #0
    bne @n
    jmp z_stack_peek
@n:
    jmp z_get_var
.endproc

.proc z_put_var_ind
    cpy #0
    bne @n
    jmp z_stack_poke
@n:
    jmp z_put_var
.endproc

.proc zvm_boot
    lda #$0C
    sta z_phys
    lda #0
    sta z_phys+1
    sta z_phys+2
    jsr zmem_loadb_phys
    sta z_globals+1
    lda #$0D
    sta z_phys
    jsr zmem_loadb_phys
    sta z_globals

    lda #$18
    sta z_phys
    jsr zmem_loadb_phys
    sta z_abbrev_base+1
    lda #$19
    sta z_phys
    jsr zmem_loadb_phys
    sta z_abbrev_base

    lda #$0A
    sta z_phys
    jsr zmem_loadb_phys
    sta z_obj_base+1
    lda #$0B
    sta z_phys
    jsr zmem_loadb_phys
    sta z_obj_base

    ; V5 header: screen geometry (matches physical SCREEN_COLS/ROWS).
    ; story/zork1.z5 startup check patched to accept width 32.
    lda #0
    sta z_addr+1
    lda #$20
    sta z_addr
    lda #SCREEN_ROWS
    jsr zmem_storeb
    lda #$21
    sta z_addr
    lda #Z_HDR_COLS
    jsr zmem_storeb
    lda #$22
    sta z_addr
    lda #Z_HDR_COLS         ; width in units (1x1 font)
    jsr zmem_storeb
    lda #$23
    sta z_addr
    lda #0
    jsr zmem_storeb
    lda #$24
    sta z_addr
    lda #SCREEN_ROWS
    jsr zmem_storeb
    lda #$25
    sta z_addr
    lda #0
    jsr zmem_storeb
    lda #$26
    sta z_addr
    lda #1                  ; font width
    jsr zmem_storeb
    lda #$27
    sta z_addr
    lda #1                  ; font height
    jsr zmem_storeb

    lda #0
    sta z_sp
    sta z_fp
    sta z_pc+2
    sta z_waiting_input
    sta z_line_len
    sta z_trail_i
    lda z_pc_init
    sta z_pc
    lda z_pc_init+1
    sta z_pc+1
    lda #1
    sta z_running
    lda #0
    sta z_call_has_store
    rts
.endproc

.proc z_trap
    sta z_extop
    lda #0
    sta z_running
    rts
.endproc

.exportzp z_extop

.proc zvm_step
    lda z_running
    beq :+
    ldx z_trail_i
    lda z_pc
    sta z_trail_lo,x
    lda z_pc+1
    sta z_trail_hi,x
    inx
    cpx #Z_TRAIL
    bcc @ts
    ldx #0
@ts:
    stx z_trail_i
    jsr z_decode_exec
:
    rts
.endproc
