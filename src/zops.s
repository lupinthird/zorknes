.include "nes.inc"
.include "zmachine.inc"

.import text_put_char, text_newline, text_clear, text_set_cursor_z, text_home
.import text_split_window, text_set_window, text_erase_window, text_erase_line
.import z_fetch_b, z_fetch_w, z_push, z_pop, z_get_var, z_put_var
.import z_get_var_ind, z_put_var_ind
.import z_do_store, z_branch_if, z_trap
.importzp z_ops_lo, z_ops_hi, z_opcount, z_a, z_b, z_tmpw, z_pc, z_sp, z_fp
.importzp z_running, z_result_var, z_call_has_store, z_abbrev_base
.importzp z_obj_base, z_str_inline
.importzp z_waiting_input, z_read_text, z_read_parse, z_line_len, z_i
.importzp z_extop
.importzp cursor_col, cursor_row, win_split, win_cur
.importzp frame_count
.import z_locals_lo, z_locals_hi, z_saved_lo, z_saved_hi
.import z_frame_ret0, z_frame_ret1, z_frame_ret2, z_frame_dest
.import z_frame_nlcl, z_frame_ofp, z_frame_osp, z_frame_argc, z_argc
.import z_dbg_a, z_dbg_b, z_dbg_c, z_dbg_d
.export z_op_call, z_op_ret, z_op_rtrue, z_op_rfalse, z_op_ret_popped, z_op_nop, z_op_quit
.export z_op_restart
.export z_op_print, z_op_print_paddr, z_op_print_addr, z_op_print_char, z_op_print_num, z_op_new_line
.export z_op_store, z_op_load, z_op_storew, z_op_loadw, z_op_storeb, z_op_loadb
.export z_op_add, z_op_sub, z_op_mul, z_op_div, z_op_mod, z_op_and, z_op_or
.export z_op_jz, z_op_je, z_op_jl, z_op_jg, z_op_jump, z_op_inc, z_op_dec
.export z_op_inc_chk, z_op_dec_chk, z_op_push, z_op_pull
.export z_op_get_prop, z_op_get_prop_addr, z_op_get_next_prop, z_op_get_prop_len
.export z_op_put_prop, z_op_test_attr, z_op_set_attr, z_op_clear_attr
.export z_op_jin, z_op_insert_obj, z_op_remove_obj
.export z_op_get_parent, z_op_get_sibling, z_op_get_child, z_op_print_obj
.export z_op_erase_window, z_op_split_window, z_op_set_window, z_op_set_text_style
.export z_op_set_cursor, z_op_get_cursor, z_op_erase_line
.export z_op_buffer_mode, z_op_output_stream, z_op_check_arg_count
.export z_op_aread, z_aread_commit, z_line_buf
.export z_op_read_char, z_read_char_commit
.export z_print_zscii, z_decode_string_at
.export z_word_flush, z_word_reset
.export z_obj_addr, z_obj_parent, z_obj_child, z_obj_sibling, z_capture_obj_name
.exportzp z_name_capture
.exportzp z_rng
.exportzp z_stream3_depth
.export pad_name_buf, pad_name_len
.export z_op_random

.import z_tokenise
.importzp tk_text, tk_parse, tk_dict, tk_flag

.import zmem_loadb, zmem_storeb, zmem_loadw, zmem_storew, zmem_loadb_phys
.importzp z_addr, z_phys

Z_LINE_MAX = 64

.segment "ZEROPAGE"
z_ch:     .res 1
z_shift:  .res 1
z_abbrev: .res 1
z_str_a:  .res 3
z_str_save: .res 3
z_shift_save: .res 1
z_zscii_hi: .res 1
z_prop_ptr: .res 2
z_obj_num:  .res 2
z_obj_dest: .res 2          ; insert_obj destination
z_obj_save: .res 2          ; target obj surviving z_obj_addr (clobbers z_obj_num)
z_attr:     .res 1
z_slot:     .res 1
z_paddr:    .res 3          ; 24-bit unpacked packed-address
z_stream3_depth: .res 1     ; output stream 3 nesting (0 = off)
z_name_capture:  .res 1     ; nonzero → z_print_zscii writes pad_name_buf
z_rng:           .res 2     ; PRNG state (never 0 once started)

PAD_NAME_MAX = 24

.segment "BSS"
pad_name_buf: .res PAD_NAME_MAX
pad_name_len: .res 1

.segment "CODE"

; --- Control ---

.proc z_op_nop
    rts
.endproc

.proc z_op_quit
    lda #0
    sta z_running
    lda #$FF                ; distinguish quit from opcode trap
    sta z_extop
    rts
.endproc

; Host soft-restart (no title): main sees $FE and reloads dynamic + zvm_boot.
.proc z_op_restart
    lda #0
    sta z_running
    lda #$FE
    sta z_extop
    rts
.endproc

.proc z_op_rtrue
    lda #1
    ldx #0
    jmp z_op_ret
.endproc

.proc z_op_rfalse
    lda #0
    ldx #0
    jmp z_op_ret
.endproc

.proc z_op_ret_popped
    jsr z_pop
    jmp z_op_ret
.endproc

; A=lo X=hi return value
.proc z_op_ret
    sta z_a
    stx z_a+1
    lda z_fp
    bne @ok
    lda #0
    sta z_running
    rts
@ok:
    dec z_fp
    ldy z_fp
    lda z_frame_ret0,y
    sta z_pc
    lda z_frame_ret1,y
    sta z_pc+1
    lda z_frame_ret2,y
    sta z_pc+2
    lda z_frame_osp,y
    sta z_sp
    jsr z_restore_locals
    lda z_frame_argc,y
    sta z_argc
    lda z_frame_dest,y
    tay
    lda z_a
    ldx z_a+1
    cpy #$FF
    beq @nostore
    jmp z_put_var
@nostore:
    rts
.endproc

; Save current locals into slot[z_fp]
.proc z_save_locals
    lda z_fp
    jsr z_frame_slot_base
    sta z_slot
    ldx #0
@lp:
    ldy z_slot
    lda z_locals_lo,x
    sta z_saved_lo,y
    lda z_locals_hi,x
    sta z_saved_hi,y
    inc z_slot
    inx
    cpx #15
    bcc @lp
    rts
.endproc

.proc z_restore_locals
    lda z_fp
    jsr z_frame_slot_base
    sta z_slot
    ldx #0
@lp:
    ldy z_slot
    lda z_saved_lo,y
    sta z_locals_lo,x
    lda z_saved_hi,y
    sta z_locals_hi,x
    inc z_slot
    inx
    cpx #15
    bcc @lp
    ldy z_fp
    rts
.endproc

; A = frame index → A = frame*15
.proc z_frame_slot_base
    sta z_tmpw
    asl a
    asl a
    asl a
    asl a           ; *16
    sec
    sbc z_tmpw      ; *15
    rts
.endproc

; Unpack packed address in A/X (lo/hi) → 24-bit byte address in z_paddr.
; V5: byte = packed * 4. Must be 24-bit — Zork's story is >64KiB.
; Result stays in z_paddr (not z_phys): z_fetch_b clobbers z_phys.
.proc z_unpack_paddr
    sta z_paddr
    stx z_paddr+1
    lda #0
    sta z_paddr+2
    asl z_paddr
    rol z_paddr+1
    rol z_paddr+2
    asl z_paddr
    rol z_paddr+1
    rol z_paddr+2
    rts
.endproc

; call*: ops[0]=packed routine, ops[1..]=args; store if z_call_has_store
.proc z_op_call
    lda z_ops_lo
    ora z_ops_hi
    bne @go
    lda #0
    sta z_a
    sta z_a+1
    lda z_call_has_store
    bne @st0
    rts
@st0:
    jmp z_do_store
@go:
    lda z_ops_lo
    ldx z_ops_hi
    jsr z_unpack_paddr
    ldy z_fp
    cpy #16
    bcc @nf
    lda #$FD
    jmp z_trap
@nf:
    jsr z_save_locals
    ; Fetch store byte BEFORE snapshotting return PC
    lda z_call_has_store
    beq @nost
    jsr z_fetch_b
    ldy z_fp
    sta z_frame_dest,y
    jmp @snap
@nost:
    lda #$FF
    ldy z_fp
    sta z_frame_dest,y
@snap:
    ldy z_fp
    lda z_pc
    sta z_frame_ret0,y
    lda z_pc+1
    sta z_frame_ret1,y
    lda z_pc+2
    sta z_frame_ret2,y
    lda z_sp
    sta z_frame_osp,y
    lda z_fp
    sta z_frame_ofp,y
    ; save caller's argc; then set argc for the new routine
    lda z_argc
    sta z_frame_argc,y
    lda z_opcount
    sec
    sbc #1
    sta z_argc
    inc z_fp

    lda z_paddr
    sta z_pc
    lda z_paddr+1
    sta z_pc+1
    lda z_paddr+2
    sta z_pc+2

    jsr z_fetch_b
    sta z_b
    ldy z_fp
    dey
    sta z_frame_nlcl,y
    ldx #0
    lda #0
@zl:
    sta z_locals_lo,x
    sta z_locals_hi,x
    inx
    cpx #15
    bcc @zl
    ldx #1
@acopy:
    cpx z_opcount
    bcs @done
    txa
    tay
    dey
    lda z_ops_lo,x
    sta z_locals_lo,y
    lda z_ops_hi,x
    sta z_locals_hi,y
    inx
    bne @acopy
@done:
    rts
.endproc

.proc z_op_jump
    ; signed offset from ops[0]; PC = PC + offset - 2 (24-bit)
    php
    sei
    lda z_ops_lo
    sta z_dbg_c
    lda z_ops_hi
    sta z_dbg_d
    ldy #0
    lda z_ops_hi
    bpl @pos
    ldy #$FF
@pos:
    clc
    lda z_pc
    adc z_ops_lo
    sta z_pc
    lda z_pc+1
    adc z_ops_hi
    sta z_pc+1
    tya
    adc z_pc+2
    sta z_pc+2
    sec
    lda z_pc
    sbc #2
    sta z_pc
    lda z_pc+1
    sbc #0
    sta z_pc+1
    lda z_pc+2
    sbc #0
    sta z_pc+2
    lda z_pc
    sta z_dbg_a
    lda z_pc+1
    sta z_dbg_b
    plp
    rts
.endproc

; --- Math / logic ---

.proc z_binop_prep
    lda z_ops_lo
    sta z_a
    lda z_ops_hi
    sta z_a+1
    lda z_ops_lo+1
    sta z_b
    lda z_ops_hi+1
    sta z_b+1
    rts
.endproc

.proc z_op_add
    jsr z_binop_prep
    clc
    lda z_a
    adc z_b
    sta z_a
    lda z_a+1
    adc z_b+1
    sta z_a+1
    jmp z_do_store
.endproc

.proc z_op_sub
    jsr z_binop_prep
    sec
    lda z_a
    sbc z_b
    sta z_a
    lda z_a+1
    sbc z_b+1
    sta z_a+1
    jmp z_do_store
.endproc

.proc z_op_mul
    ; 16x16 → 16 (low)
    jsr z_binop_prep
    lda #0
    sta z_tmpw
    sta z_tmpw+1
    ldx #16
@lp:
    lsr z_b+1
    ror z_b
    bcc @no
    clc
    lda z_tmpw
    adc z_a
    sta z_tmpw
    lda z_tmpw+1
    adc z_a+1
    sta z_tmpw+1
@no:
    asl z_a
    rol z_a+1
    dex
    bne @lp
    lda z_tmpw
    sta z_a
    lda z_tmpw+1
    sta z_a+1
    jmp z_do_store
.endproc

.proc z_op_div
    jsr z_binop_prep
    ; unsigned for now
    lda z_b
    ora z_b+1
    bne @ok
    lda #0
    sta z_a
    sta z_a+1
    jmp z_do_store
@ok:
    ; simplistic 16/16
    lda #0
    sta z_tmpw
    sta z_tmpw+1
    ldx #16
@lp:
    asl z_a
    rol z_a+1
    rol z_tmpw
    rol z_tmpw+1
    sec
    lda z_tmpw
    sbc z_b
    tay
    lda z_tmpw+1
    sbc z_b+1
    bcc @sk
    sta z_tmpw+1
    sty z_tmpw
    inc z_a
@sk:
    dex
    bne @lp
    jmp z_do_store
.endproc

.proc z_op_mod
    jsr z_binop_prep
    lda z_b
    ora z_b+1
    bne @ok
    lda #0
    sta z_a
    sta z_a+1
    jmp z_do_store
@ok:
    lda #0
    sta z_tmpw
    sta z_tmpw+1
    ldx #16
@lp:
    asl z_a
    rol z_a+1
    rol z_tmpw
    rol z_tmpw+1
    sec
    lda z_tmpw
    sbc z_b
    tay
    lda z_tmpw+1
    sbc z_b+1
    bcc @sk
    sta z_tmpw+1
    sty z_tmpw
    inc z_a
@sk:
    dex
    bne @lp
    lda z_tmpw
    sta z_a
    lda z_tmpw+1
    sta z_a+1
    jmp z_do_store
.endproc

.proc z_op_and
    jsr z_binop_prep
    lda z_a
    and z_b
    sta z_a
    lda z_a+1
    and z_b+1
    sta z_a+1
    jmp z_do_store
.endproc

.proc z_op_or
    jsr z_binop_prep
    lda z_a
    ora z_b
    sta z_a
    lda z_a+1
    ora z_b+1
    sta z_a+1
    jmp z_do_store
.endproc

; --- Load/store ---

.proc z_op_store
    ; store var value: ops[0]=var ref (by number), ops[1]=value
    ; var 0 = replace stack top in place (not push)
    ldy z_ops_lo
    lda z_ops_lo+1
    ldx z_ops_hi+1
    jmp z_put_var_ind
.endproc

.proc z_op_load
    ; var 0 = peek stack top (not pop)
    ldy z_ops_lo
    jsr z_get_var_ind
    sta z_a
    stx z_a+1
    jmp z_do_store
.endproc

.proc z_op_loadw
    ; array + 2*index
    lda z_ops_lo+1
    asl a
    sta z_b
    lda z_ops_hi+1
    rol a
    sta z_b+1
    clc
    lda z_ops_lo
    adc z_b
    sta z_addr
    lda z_ops_hi
    adc z_b+1
    sta z_addr+1
    jsr zmem_loadw
    sta z_a
    stx z_a+1
    jmp z_do_store
.endproc

.proc z_op_loadb
    clc
    lda z_ops_lo
    adc z_ops_lo+1
    sta z_addr
    lda z_ops_hi
    adc z_ops_hi+1
    sta z_addr+1
    jsr zmem_loadb
    sta z_a
    lda #0
    sta z_a+1
    jmp z_do_store
.endproc

.proc z_op_storew
    lda z_ops_lo+1
    asl a
    sta z_b
    lda z_ops_hi+1
    rol a
    sta z_b+1
    clc
    lda z_ops_lo
    adc z_b
    sta z_addr
    lda z_ops_hi
    adc z_b+1
    sta z_addr+1
    lda z_ops_lo+2
    ldx z_ops_hi+2
    jmp zmem_storew
.endproc

.proc z_op_storeb
    clc
    lda z_ops_lo
    adc z_ops_lo+1
    sta z_addr
    lda z_ops_hi
    adc z_ops_hi+1
    sta z_addr+1
    lda z_ops_lo+2
    jmp zmem_storeb
.endproc

.proc z_op_push
    lda z_ops_lo
    ldx z_ops_hi
    jmp z_push
.endproc

.proc z_op_pull
    jsr z_pop
    sta z_a
    stx z_a+1
    ldy z_ops_lo
    lda z_a
    ldx z_a+1
    jmp z_put_var_ind
.endproc

.proc z_op_inc
    ldy z_ops_lo
    jsr z_get_var_ind
    clc
    adc #1
    sta z_a
    txa
    adc #0
    tax
    stx z_a+1
    ldy z_ops_lo
    lda z_a
    ldx z_a+1
    jmp z_put_var_ind
.endproc

.proc z_op_dec
    ldy z_ops_lo
    jsr z_get_var_ind
    sec
    sbc #1
    sta z_a
    txa
    sbc #0
    tax
    stx z_a+1
    ldy z_ops_lo
    lda z_a
    ldx z_a+1
    jmp z_put_var_ind
.endproc

; --- Branches ---

.proc z_op_jz
    lda z_ops_lo
    ora z_ops_hi
    beq @t
    lda #0
    jmp z_branch_if
@t:
    lda #1
    jmp z_branch_if
.endproc

.proc z_op_je
    ; compare ops[0] to ops[1..]
    ldx #1
@lp:
    cpx z_opcount
    bcs @no
    lda z_ops_lo
    cmp z_ops_lo,x
    bne @nx
    lda z_ops_hi
    cmp z_ops_hi,x
    beq @yes
@nx:
    inx
    bne @lp
@no:
    lda #0
    jmp z_branch_if
@yes:
    lda #1
    jmp z_branch_if
.endproc

.proc z_op_jl
    ; signed compare a < b
    lda z_ops_lo
    cmp z_ops_lo+1
    lda z_ops_hi
    sbc z_ops_hi+1
    bvc @v
    eor #$80
@v:
    bmi @t
    lda #0
    jmp z_branch_if
@t:
    lda #1
    jmp z_branch_if
.endproc

.proc z_op_jg
    lda z_ops_lo+1
    cmp z_ops_lo
    lda z_ops_hi+1
    sbc z_ops_hi
    bvc @v
    eor #$80
@v:
    bmi @t
    lda #0
    jmp z_branch_if
@t:
    lda #1
    jmp z_branch_if
.endproc

.proc z_op_inc_chk
    ; Increment in place, then branch if new value > ops[1].
    ; Do not re-read via get_var (would pop stack for var 0).
    ldy z_ops_lo
    jsr z_get_var_ind
    clc
    adc #1
    sta z_a
    txa
    adc #0
    tax
    stx z_a+1
    ldy z_ops_lo
    lda z_a
    ldx z_a+1
    jsr z_put_var_ind
    lda z_ops_lo+1
    cmp z_a
    lda z_ops_hi+1
    sbc z_a+1
    bvc @v
    eor #$80
@v:
    bmi @t
    lda #0
    jmp z_branch_if
@t:
    lda #1
    jmp z_branch_if
.endproc

.proc z_op_dec_chk
    ldy z_ops_lo
    jsr z_get_var_ind
    sec
    sbc #1
    sta z_a
    txa
    sbc #0
    tax
    stx z_a+1
    ldy z_ops_lo
    lda z_a
    ldx z_a+1
    jsr z_put_var_ind
    lda z_a
    cmp z_ops_lo+1
    lda z_a+1
    sbc z_ops_hi+1
    bvc @v
    eor #$80
@v:
    bmi @t
    lda #0
    jmp z_branch_if
@t:
    lda #1
    jmp z_branch_if
.endproc
; --- Text ---

STREAM3_MAX = 4

.segment "BSS"
z_line_buf: .res Z_LINE_MAX
z_stream3_addr_lo: .res STREAM3_MAX
z_stream3_addr_hi: .res STREAM3_MAX
z_stream3_cnt_lo:  .res STREAM3_MAX
z_stream3_cnt_hi:  .res STREAM3_MAX
; word_buf aliases z_line_buf (flushed before aread fills the line buffer)
word_len:          .res 1

.segment "CODE"

; VAR:7 random range -> result
;  range > 0: uniform 1..range
;  range < 0: seed to |range|, return 0
;  range = 0: reseed from frame counter, return 0
.proc z_op_random
    lda z_ops_hi
    bmi @seed_neg
    ora z_ops_lo
    beq @seed_time
    ; positive range → 1..range
    jsr z_rng_next
    lda z_ops_lo
    sta z_b
    lda z_ops_hi
    sta z_b+1
    bne @mod16
    ; Fast path: range fits in 8 bits (combat / dice)
    lda z_a
@mod8:
    cmp z_b
    bcc @mod8done
    sbc z_b
    jmp @mod8
@mod8done:
    sta z_a
    lda #0
    sta z_a+1
    jmp @add1
@mod16:
    lda z_a+1
    cmp z_b+1
    bcc @moddone
    bne @sub
    lda z_a
    cmp z_b
    bcc @moddone
@sub:
    sec
    lda z_a
    sbc z_b
    sta z_a
    lda z_a+1
    sbc z_b+1
    sta z_a+1
    jmp @mod16
@moddone:
@add1:
    inc z_a
    bne :+
    inc z_a+1
:
    jmp z_do_store

@seed_neg:
    ; seed = -range (two's complement of ops)
    lda #0
    sec
    sbc z_ops_lo
    sta z_rng
    lda #0
    sbc z_ops_hi
    sta z_rng+1
    jmp @seed_done

@seed_time:
    lda frame_count
    eor #$A5
    sta z_rng
    lda frame_count
    asl a
    eor #$5A
    sta z_rng+1
@seed_done:
    lda z_rng
    ora z_rng+1
    bne @z
    lda #1
    sta z_rng
@z:
    lda #0
    sta z_a
    sta z_a+1
    jmp z_do_store
.endproc

; Advance z_rng (xorshift16), return value in z_a.
; Mixes frame_count so timing jitter (title wait, typing) diversifies sequences.
.proc z_rng_next
    lda z_rng
    ora z_rng+1
    bne @go
    lda frame_count
    eor #$31
    sta z_rng
    lda #$41
    eor frame_count
    sta z_rng+1
@go:
    ; Fold live timing into state before step (breaks lockstep script seeds a bit,
    ; and makes human play less dependent on the first seed alone).
    lda z_rng
    eor frame_count
    sta z_rng
    ; x ^= x << 7
    lda z_rng
    sta z_tmpw
    lda z_rng+1
    sta z_tmpw+1
    ldx #7
@shl:
    asl z_tmpw
    rol z_tmpw+1
    dex
    bne @shl
    lda z_rng
    eor z_tmpw
    sta z_rng
    lda z_rng+1
    eor z_tmpw+1
    sta z_rng+1
    ; x ^= x >> 9  (hi=0, lo = old_hi >> 1)
    lda z_rng+1
    lsr a
    eor z_rng
    sta z_rng
    ; x ^= x << 8  (hi ^= lo)
    lda z_rng
    eor z_rng+1
    sta z_rng+1
    ; Never allow a zero state
    lda z_rng
    ora z_rng+1
    bne @out
    inc z_rng
@out:
    lda z_rng
    sta z_a
    lda z_rng+1
    sta z_a+1
    rts
.endproc

.proc z_op_new_line
    lda #13
    jmp z_print_zscii
.endproc

; VAR:4 aread — pause VM for a line of input (Z5 store = terminating char).
; PC is left on the store operand; z_aread_commit finishes via z_do_store.
.proc z_op_aread
    lda z_ops_lo
    sta z_read_text
    lda z_ops_hi
    sta z_read_text+1
    lda #0
    sta z_read_parse
    sta z_read_parse+1
    lda z_opcount
    cmp #2
    bcc @pause
    lda z_ops_lo+1
    sta z_read_parse
    lda z_ops_hi+1
    sta z_read_parse+1
@pause:
    jsr z_word_flush
    lda #0
    sta z_line_len
    lda #ZWAIT_AREAD
    sta z_waiting_input
    lda #0
    sta z_running
    rts
.endproc

; Copy z_line_buf into the story text buffer, stub-parse, store 13, resume.
.proc z_aread_commit
    lda z_read_text
    sta z_addr
    lda z_read_text+1
    sta z_addr+1
    jsr zmem_loadb
    sta z_b                 ; max chars
    lda z_line_len
    cmp z_b
    bcc @lenok
    lda z_b
@lenok:
    sta z_b+1               ; actual len
    ; text[1] = len
    lda z_read_text
    clc
    adc #1
    sta z_addr
    lda z_read_text+1
    adc #0
    sta z_addr+1
    lda z_b+1
    jsr zmem_storeb
    ; text[2..] = chars (lowercase A-Z)
    lda #0
    sta z_i
@copy:
    lda z_i
    cmp z_b+1
    bcs @copydone
    tax
    lda z_line_buf,x
    cmp #'A'
    bcc @st
    cmp #'Z'+1
    bcs @st
    ora #$20
@st:
    sta z_tmpw
    clc
    lda z_read_text
    adc #2
    sta z_addr
    lda z_read_text+1
    adc #0
    sta z_addr+1
    clc
    lda z_addr
    adc z_i
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    lda z_tmpw
    jsr zmem_storeb
    inc z_i
    jmp @copy
@copydone:
    ; lexical analysis into parse buffer (if provided)
    lda z_read_parse
    ora z_read_parse+1
    beq @nostore
    lda z_read_text
    sta tk_text
    lda z_read_text+1
    sta tk_text+1
    lda z_read_parse
    sta tk_parse
    lda z_read_parse+1
    sta tk_parse+1
    lda #0
    sta tk_dict
    sta tk_dict+1
    sta tk_flag
    jsr z_tokenise
@nostore:
    lda #0
    sta z_line_len
    sta z_waiting_input
    lda #13
    sta z_a
    lda #0
    sta z_a+1
    jsr z_do_store
    lda #1
    sta z_running
    rts
.endproc

; VAR:22 read_char — pause for one ZSCII key (HINT menus, etc.).
; time/routine timed input not implemented (treated as wait forever).
.proc z_op_read_char
    jsr z_word_flush
    lda #ZWAIT_CHAR
    sta z_waiting_input
    lda #0
    sta z_running
    rts
.endproc

; A = ZSCII character; store result and resume VM.
.proc z_read_char_commit
    sta z_a
    lda #0
    sta z_a+1
    sta z_waiting_input
    jsr z_do_store
    lda #1
    sta z_running
    rts
.endproc

.proc z_op_print_char
    lda z_ops_lo
    jmp z_print_zscii
.endproc

.proc z_op_print_num
    ; Print as unsigned decimal (simple)
    lda z_ops_lo
    sta z_a
    lda z_ops_hi
    sta z_a+1
    bne @go
    lda z_a
    bne @go
    lda #'0'
    jmp z_print_zscii
@go:
    lda #0
    sta z_b                 ; digit count on stack via PHA
@divlp:
    lda z_a
    ora z_a+1
    beq @print
    ; rem = a % 10, a = a / 10
    lda #0
    sta z_tmpw
    sta z_tmpw+1
    ldx #16
@bit:
    asl z_a
    rol z_a+1
    rol z_tmpw
    sec
    lda z_tmpw
    sbc #10
    bcc @nb
    sta z_tmpw
    inc z_a
@nb:
    dex
    bne @bit
    lda z_tmpw
    clc
    adc #'0'
    pha
    inc z_b
    jmp @divlp
@print:
    pla
    jsr z_print_zscii
    dec z_b
    bne @print
    rts
.endproc

.proc z_op_print
    lda #1
    sta z_str_inline
    lda z_pc
    sta z_str_a
    lda z_pc+1
    sta z_str_a+1
    lda z_pc+2
    sta z_str_a+2
    jmp z_decode_string_at
.endproc

.proc z_op_print_paddr
    lda #0
    sta z_str_inline
    lda z_ops_lo
    ldx z_ops_hi
    jsr z_unpack_paddr
    lda z_paddr
    sta z_str_a
    lda z_paddr+1
    sta z_str_a+1
    lda z_paddr+2
    sta z_str_a+2
    jmp z_decode_string_at
.endproc

.proc z_op_print_addr
    lda #0
    sta z_str_inline
    lda z_ops_lo
    sta z_str_a
    lda z_ops_hi
    sta z_str_a+1
    lda #0
    sta z_str_a+2
    jmp z_decode_string_at
.endproc

; Decode Z-string at z_str_a; updates z_pc only if z_str_inline
.proc z_decode_string_at
    lda #0
    sta z_shift
    sta z_abbrev
    sta z_zscii_hi
@word:
    lda z_str_a
    sta z_phys
    lda z_str_a+1
    sta z_phys+1
    lda z_str_a+2
    sta z_phys+2
    jsr zmem_loadb_phys
    sta z_tmpw+1
    inc z_str_a
    bne :+
    inc z_str_a+1
    bne :+
    inc z_str_a+2
:
    lda z_str_a
    sta z_phys
    lda z_str_a+1
    sta z_phys+1
    lda z_str_a+2
    sta z_phys+2
    jsr zmem_loadb_phys
    sta z_tmpw
    inc z_str_a
    bne :+
    inc z_str_a+1
    bne :+
    inc z_str_a+2
:
    lda z_tmpw+1
    lsr a
    lsr a
    and #$1F
    jsr z_emit_zchar
    lda z_tmpw+1
    asl a
    asl a
    asl a
    and #$18
    sta z_ch
    lda z_tmpw
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    ora z_ch
    and #$1F
    jsr z_emit_zchar
    lda z_tmpw
    and #$1F
    jsr z_emit_zchar
    lda z_tmpw+1
    and #$80
    beq @word
    lda z_str_inline
    beq @done
    lda z_str_a
    sta z_pc
    lda z_str_a+1
    sta z_pc+1
    lda z_str_a+2
    sta z_pc+2
@done:
    rts
.endproc

.proc z_emit_zchar
    sta z_ch
    lda z_zscii_hi
    beq @nesc
    cmp #$FF
    bne @zslo
    ; high 5 bits of multi-byte ZSCII
    lda z_ch
    ora #$80
    sta z_zscii_hi
    rts
@zslo:
    and #$1F
    asl a
    asl a
    asl a
    asl a
    asl a
    ora z_ch
    ldx #0
    stx z_zscii_hi
    jmp z_print_zscii
@nesc:
    lda z_abbrev
    beq @nabb
    jmp z_do_abbrev
@nabb:
    lda z_ch
    cmp #6
    bcs @alpha
    cmp #0
    bne @1
    lda #' '
    jmp z_print_zscii
@1:
    cmp #1
    beq @ab1
    cmp #2
    beq @ab2
    cmp #3
    beq @ab3
    cmp #4
    beq @sh1
    cmp #5
    beq @sh2
    rts
@ab1:
    lda #1
    sta z_abbrev
    rts
@ab2:
    lda #2
    sta z_abbrev
    rts
@ab3:
    lda #3
    sta z_abbrev
    rts
@sh1:
    lda #1
    sta z_shift
    rts
@sh2:
    lda #2
    sta z_shift
    rts
@alpha:
    sec
    sbc #6
    tax
    lda z_shift
    beq @a0
    cmp #1
    beq @a1
    cpx #0
    bne @a2c
    lda #$FF
    sta z_zscii_hi
    lda #0
    sta z_shift
    rts
@a2c:
    lda a2tab,x
    jmp @out
@a0:
    lda a0tab,x
    jmp @out
@a1:
    lda a1tab,x
@out:
    ldx #0
    stx z_shift
    jmp z_print_zscii
.endproc

; Expand abbreviation (z_abbrev=1..3, z_ch=zchar)
.proc z_do_abbrev
    lda z_tmpw
    pha
    lda z_tmpw+1
    pha
    lda z_abbrev
    sec
    sbc #1
    asl a
    asl a
    asl a
    asl a
    asl a
    clc
    adc z_ch
    sta z_tmpw
    lda #0
    sta z_tmpw+1
    asl z_tmpw
    rol z_tmpw+1
    clc
    lda z_abbrev_base
    adc z_tmpw
    sta z_addr
    lda z_abbrev_base+1
    adc z_tmpw+1
    sta z_addr+1
    lda #0
    sta z_abbrev
    jsr zmem_loadw
    ; Abbreviation table holds word addresses (byte addr = word * 2).
    ; 24-bit: word>=$8000 lives above 64KiB.
    sta z_paddr
    stx z_paddr+1
    lda #0
    sta z_paddr+2
    asl z_paddr
    rol z_paddr+1
    rol z_paddr+2
    lda z_str_a
    sta z_str_save
    lda z_str_a+1
    sta z_str_save+1
    lda z_str_a+2
    sta z_str_save+2
    lda z_shift
    sta z_shift_save
    lda z_str_inline
    pha
    lda #0
    sta z_str_inline
    lda z_paddr
    sta z_str_a
    lda z_paddr+1
    sta z_str_a+1
    lda z_paddr+2
    sta z_str_a+2
    jsr z_decode_string_at
    pla
    sta z_str_inline
    lda z_str_save
    sta z_str_a
    lda z_str_save+1
    sta z_str_a+1
    lda z_str_save+2
    sta z_str_a+2
    lda z_shift_save
    sta z_shift
    pla
    sta z_tmpw+1
    pla
    sta z_tmpw
    rts
.endproc

.proc z_print_zscii
    ; Name capture (pad UI / helpers) — no screen, no stream 3.
    ldx z_name_capture
    beq @nostream
    cmp #32
    bcc @capdone
    cmp #126
    bcs @capdone
    cmp #'a'
    bcc @cap
    cmp #'z'+1
    bcs @cap
    sec
    sbc #$20
@cap:
    ldx pad_name_len
    cpx #PAD_NAME_MAX-1
    bcs @capdone
    sta pad_name_buf,x
    inx
    stx pad_name_len
    lda #0
    sta pad_name_buf,x
@capdone:
    rts
@nostream:
    ; Stream 3: divert to memory table (no screen output).
    ldx z_stream3_depth
    beq @screen
    dex
    cmp #13
    beq @st3
    cmp #32
    bcc @st3done
    cmp #126
    bcs @st3done
@st3:
    sta z_ch
    txa
    pha                     ; save stream index (zmem_* clobbers)
    ; addr = table + 2 + count
    lda z_stream3_addr_lo,x
    clc
    adc #2
    sta z_addr
    lda z_stream3_addr_hi,x
    adc #0
    sta z_addr+1
    lda z_addr
    clc
    adc z_stream3_cnt_lo,x
    sta z_addr
    lda z_addr+1
    adc z_stream3_cnt_hi,x
    sta z_addr+1
    lda z_ch
    jsr zmem_storeb
    pla
    tax
    ; count++
    inc z_stream3_cnt_lo,x
    bne @st3done
    inc z_stream3_cnt_hi,x
@st3done:
    rts
@screen:
    ; Upper/status window: immediate put (clip in text_put_char).
    ldx win_cur
    bne @immediate

    cmp #13
    bne @not_cr
    jsr z_word_flush
    jmp text_newline
@not_cr:
    cmp #' '
    bne @not_sp
    jsr z_word_flush
    lda cursor_col
    beq @scrdone              ; no leading space after wrap
    cmp #SCREEN_COLS-1
    bcc @sp_put
    ; Trailing space would only force a wrap — newline instead.
    jmp text_newline
@sp_put:
    lda #' '
    jmp text_put_char
@not_sp:
    cmp #32
    bcc @scrdone
    cmp #126
    bcs @scrdone
    cmp #'a'
    bcc @accum
    cmp #'z'+1
    bcs @accum
    sec
    sbc #$20
@accum:
    ldx word_len
    sta z_line_buf,x
    inx
    stx word_len
    cpx #SCREEN_COLS
    bcc @scrdone
    jmp z_word_flush          ; hard-break overlong token

@immediate:
    cmp #13
    bne @imm_n
    jmp text_newline
@imm_n:
    cmp #32
    bcc @scrdone
    cmp #126
    bcs @scrdone
    cmp #'a'
    bcc @imm_put
    cmp #'z'+1
    bcs @imm_put
    sec
    sbc #$20
@imm_put:
    jmp text_put_char
@scrdone:
    rts
.endproc

; Emit buffered main-window word; wrap first if it won't fit on this line.
.proc z_word_flush
    lda word_len
    beq @ret
    lda cursor_col
    beq @emit
    clc
    adc word_len
    cmp #SCREEN_COLS+1        ; col+len > 32 → need newline
    bcc @emit
    jsr text_newline
@emit:
    ldx #0
@loop:
    cpx word_len
    beq @clear
    lda z_line_buf,x
    stx z_ch                  ; text_put_char clobbers X
    jsr text_put_char
    ldx z_ch
    inx
    bne @loop
@clear:
    lda #0
    sta word_len
@ret:
    rts
.endproc

; Discard pending word (screen clear / new session).
.proc z_word_reset
    lda #0
    sta word_len
    rts
.endproc

.proc z_op_output_stream
    ; ops[0]=stream (+select / -deselect / 0=nop); ops[1]=table if selecting 3
    lda z_ops_lo
    ora z_ops_hi
    beq @ret
    lda z_ops_hi
    bmi @desel
    ; select
    lda z_ops_lo
    cmp #3
    bne @ret                 ; 1 always on; 2/4 ignored
    ldx z_stream3_depth
    cpx #STREAM3_MAX
    bcs @ret
    lda z_ops_lo+1
    sta z_stream3_addr_lo,x
    lda z_ops_hi+1
    sta z_stream3_addr_hi,x
    lda #0
    sta z_stream3_cnt_lo,x
    sta z_stream3_cnt_hi,x
    inc z_stream3_depth
@ret:
    rts
@desel:
    ; absolute stream number
    lda #0
    sec
    sbc z_ops_lo
    cmp #3
    bne @ret
    ldx z_stream3_depth
    beq @ret
    dex
    stx z_stream3_depth
    ; write character count to table word
    lda z_stream3_addr_lo,x
    sta z_addr
    lda z_stream3_addr_hi,x
    sta z_addr+1
    lda z_stream3_cnt_lo,x
    pha
    lda z_stream3_cnt_hi,x
    tax
    pla
    jmp zmem_storew
.endproc

; --- Objects / properties (v4+ 14-byte objects) ---

; A = short-form size byte → A = data length (V4+).
; bit6 clear → 1 byte; bit6 set → 2 bytes. (Not V3's (bits6-5)+1.)
.proc z_prop_short_size
    and #$40
    beq @one
    lda #2
    rts
@one:
    lda #1
    rts
.endproc

; object number in z_ops_lo/hi → z_addr = object struct
; Clobbers z_a, z_tmpw, z_obj_num. Does NOT touch z_b (remove/insert
; keep child/sibling *field addresses* in z_b across this call).
.proc z_obj_addr
    ; addr = obj_base + 126 + (obj-1)*14
    lda z_ops_lo
    sta z_obj_num
    lda z_ops_hi
    sta z_obj_num+1
    ; (obj-1)*14 = (obj-1)*8 + (obj-1)*4 + (obj-1)*2
    lda z_obj_num
    sec
    sbc #1
    sta z_a
    lda z_obj_num+1
    sbc #0
    sta z_a+1
    asl z_a
    rol z_a+1       ; *2
    lda z_a
    sta z_tmpw
    lda z_a+1
    sta z_tmpw+1
    asl z_a
    rol z_a+1       ; *4
    clc
    lda z_a
    adc z_tmpw
    sta z_tmpw
    lda z_a+1
    adc z_tmpw+1
    sta z_tmpw+1    ; *6
    asl z_a
    rol z_a+1       ; *8 from *4
    clc
    lda z_a
    adc z_tmpw
    sta z_tmpw
    lda z_a+1
    adc z_tmpw+1
    sta z_tmpw+1    ; *14
    clc
    lda z_obj_base
    adc #126
    sta z_addr
    lda z_obj_base+1
    adc #0
    sta z_addr+1
    clc
    lda z_addr
    adc z_tmpw
    sta z_addr
    lda z_addr+1
    adc z_tmpw+1
    sta z_addr+1
    rts
.endproc

.proc z_obj_prop_table
    jsr z_obj_addr
    clc
    lda z_addr
    adc #12
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw
    sta z_prop_ptr
    stx z_prop_ptr+1
    ; skip short name: len byte * 2
    lda z_prop_ptr
    sta z_addr
    lda z_prop_ptr+1
    sta z_addr+1
    jsr zmem_loadb
    asl a
    clc
    adc #1
    adc z_prop_ptr
    sta z_prop_ptr
    lda z_prop_ptr+1
    adc #0
    sta z_prop_ptr+1
    rts
.endproc

; Object # in z_ops_lo/hi → parent in z_a (no store).
.proc z_obj_parent
    jsr z_obj_addr
    clc
    lda z_addr
    adc #6
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw
    sta z_a
    stx z_a+1
    rts
.endproc

; Object # in z_ops_lo/hi → sibling in z_a (no store).
.proc z_obj_sibling
    jsr z_obj_addr
    clc
    lda z_addr
    adc #8
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw
    sta z_a
    stx z_a+1
    rts
.endproc

; Object # in z_ops_lo/hi → child in z_a (no store).
.proc z_obj_child
    jsr z_obj_addr
    clc
    lda z_addr
    adc #10
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw
    sta z_a
    stx z_a+1
    rts
.endproc

; Decode object short name into pad_name_buf (uppercase), pad_name_len set.
; Object # in z_ops_lo/hi.
.proc z_capture_obj_name
    lda #0
    sta pad_name_len
    sta pad_name_buf
    lda #1
    sta z_name_capture
    jsr z_obj_addr
    clc
    lda z_addr
    adc #12
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw
    sta z_str_a
    stx z_str_a+1
    lda #0
    sta z_str_a+2
    lda z_str_a
    sta z_addr
    lda z_str_a+1
    sta z_addr+1
    jsr zmem_loadb
    inc z_str_a
    bne :+
    inc z_str_a+1
:
    lda #0
    sta z_str_inline
    jsr z_decode_string_at
    lda #0
    sta z_name_capture
    rts
.endproc

.proc z_op_get_parent
    jsr z_obj_addr
    clc
    lda z_addr
    adc #6
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw
    sta z_a
    stx z_a+1
    jmp z_do_store
.endproc

.proc z_op_get_sibling
    jsr z_obj_addr
    clc
    lda z_addr
    adc #8
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw
    sta z_a
    stx z_a+1
    jsr z_do_store
    lda z_a
    ora z_a+1
    beq @z
    lda #1
    jmp z_branch_if
@z:
    lda #0
    jmp z_branch_if
.endproc

.proc z_op_get_child
    jsr z_obj_addr
    clc
    lda z_addr
    adc #10
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw
    sta z_a
    stx z_a+1
    jsr z_do_store
    lda z_a
    ora z_a+1
    beq @z
    lda #1
    jmp z_branch_if
@z:
    lda #0
    jmp z_branch_if
.endproc

.proc z_op_jin
    ; branch if ops[0] is child of ops[1] — parent(obj1)==obj2
    jsr z_obj_addr
    clc
    lda z_addr
    adc #6
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw
    cmp z_ops_lo+1
    bne @no
    cpx z_ops_hi+1
    bne @no
    lda #1
    jmp z_branch_if
@no:
    lda #0
    jmp z_branch_if
.endproc

.proc z_op_test_attr
    jsr z_obj_addr
    lda z_ops_lo+1
    sta z_attr
    ; byte = attr/8, bit = 7-(attr&7)
    lsr a
    lsr a
    lsr a
    clc
    adc z_addr
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadb
    sta z_ch
    lda z_attr
    and #7
    tax
    lda #$80
@sh:
    cpx #0
    beq @got
    lsr a
    dex
    bne @sh
@got:
    and z_ch
    beq @no
    lda #1
    jmp z_branch_if
@no:
    lda #0
    jmp z_branch_if
.endproc

.proc z_op_set_attr
    jsr z_obj_addr
    lda z_ops_lo+1
    sta z_attr
    lsr a
    lsr a
    lsr a
    clc
    adc z_addr
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadb
    sta z_ch
    lda z_attr
    and #7
    tax
    lda #$80
@sh:
    cpx #0
    beq @got
    lsr a
    dex
    bne @sh
@got:
    ora z_ch
    jmp zmem_storeb
.endproc

.proc z_op_clear_attr
    jsr z_obj_addr
    lda z_ops_lo+1
    sta z_attr
    lsr a
    lsr a
    lsr a
    clc
    adc z_addr
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadb
    sta z_ch
    lda z_attr
    and #7
    tax
    lda #$80
@sh:
    cpx #0
    beq @got
    lsr a
    dex
    bne @sh
@got:
    eor #$FF
    and z_ch
    jmp zmem_storeb
.endproc

.proc z_op_get_prop_addr
    jsr z_obj_prop_table
    lda z_ops_lo+1
    sta z_attr
@scan:
    lda z_prop_ptr
    sta z_addr
    lda z_prop_ptr+1
    sta z_addr+1
    jsr zmem_loadb
    sta z_ch
    beq @miss
    ; v4+: bit7 clear → num=bits5-0, len=1 or 2 from bit6; bit7 set → two size bytes
    lda z_ch
    and #$80
    bne @long
    lda z_ch
    and #$3F
    cmp z_attr
    bne @skip1
    clc
    lda z_prop_ptr
    adc #1
    sta z_a
    lda z_prop_ptr+1
    adc #0
    sta z_a+1
    jmp z_do_store
@skip1:
    lda z_ch
    jsr z_prop_short_size
    jmp @adv
@long:
    lda z_ch
    and #$3F
    cmp z_attr
    bne @skip2
    clc
    lda z_prop_ptr
    adc #2
    sta z_a
    lda z_prop_ptr+1
    adc #0
    sta z_a+1
    jmp z_do_store
@skip2:
    inc z_prop_ptr
    bne :+
    inc z_prop_ptr+1
:
    lda z_prop_ptr
    sta z_addr
    lda z_prop_ptr+1
    sta z_addr+1
    jsr zmem_loadb
    and #$3F
    bne :+
    lda #64
:
@adv:
    clc
    adc #1
    adc z_prop_ptr
    sta z_prop_ptr
    lda z_prop_ptr+1
    adc #0
    sta z_prop_ptr+1
    jmp @scan
@miss:
    lda #0
    sta z_a
    sta z_a+1
    jmp z_do_store
.endproc

.proc z_op_get_prop
    jsr z_obj_prop_table
    lda z_ops_lo+1
    sta z_attr
@scan:
    lda z_prop_ptr
    sta z_addr
    lda z_prop_ptr+1
    sta z_addr+1
    jsr zmem_loadb
    sta z_ch
    bne @nz
    jmp @def
@nz:
    and #$80
    bne @long
    lda z_ch
    and #$3F
    cmp z_attr
    bne @s1
    lda z_ch
    jsr z_prop_short_size
    sta z_tmpw
    clc
    lda z_prop_ptr
    adc #1
    sta z_addr
    lda z_prop_ptr+1
    adc #0
    sta z_addr+1
    jmp @read
@s1:
    lda z_ch
    jsr z_prop_short_size
    jmp @adv
@long:
    lda z_ch
    and #$3F
    cmp z_attr
    bne @s2
    inc z_prop_ptr
    bne :+
    inc z_prop_ptr+1
:
    lda z_prop_ptr
    sta z_addr
    lda z_prop_ptr+1
    sta z_addr+1
    jsr zmem_loadb
    and #$3F
    bne :+
    lda #64
:
    sta z_tmpw
    clc
    lda z_prop_ptr
    adc #1
    sta z_addr
    lda z_prop_ptr+1
    adc #0
    sta z_addr+1
    jmp @read
@s2:
    inc z_prop_ptr
    bne :+
    inc z_prop_ptr+1
:
    lda z_prop_ptr
    sta z_addr
    lda z_prop_ptr+1
    sta z_addr+1
    jsr zmem_loadb
    and #$3F
    bne :+
    lda #64
:
@adv:
    clc
    adc #1
    adc z_prop_ptr
    sta z_prop_ptr
    lda z_prop_ptr+1
    adc #0
    sta z_prop_ptr+1
    jmp @scan
@read:
    lda z_tmpw
    cmp #1
    bne @w
    jsr zmem_loadb
    sta z_a
    lda #0
    sta z_a+1
    jmp z_do_store
@w:
    jsr zmem_loadw
    sta z_a
    stx z_a+1
    jmp z_do_store
@def:
    lda z_attr
    sec
    sbc #1
    asl a
    clc
    adc z_obj_base
    sta z_addr
    lda z_obj_base+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw
    sta z_a
    stx z_a+1
    jmp z_do_store
.endproc

.proc z_op_get_next_prop
    ; ops[0]=obj ops[1]=prop (0=first)
    lda z_ops_lo+1
    sta z_attr
    jsr z_obj_prop_table
    lda z_attr
    bne @find
    ; first prop number
    lda z_prop_ptr
    sta z_addr
    lda z_prop_ptr+1
    sta z_addr+1
    jsr zmem_loadb
    beq @zero
    and #$3F
    sta z_a
    lda #0
    sta z_a+1
    jmp z_do_store
@zero:
    lda #0
    sta z_a
    sta z_a+1
    jmp z_do_store
@find:
    ; scan until match then return next
@scan:
    lda z_prop_ptr
    sta z_addr
    lda z_prop_ptr+1
    sta z_addr+1
    jsr zmem_loadb
    sta z_ch
    beq @zero
    and #$80
    bne @long
    lda z_ch
    and #$3F
    cmp z_attr
    beq @next1
    lda z_ch
    jsr z_prop_short_size
    jmp @adv
@next1:
    lda z_ch
    jsr z_prop_short_size
    clc
    adc #1
    adc z_prop_ptr
    sta z_prop_ptr
    lda z_prop_ptr+1
    adc #0
    sta z_prop_ptr+1
    jmp @first
@long:
    lda z_ch
    and #$3F
    cmp z_attr
    beq @next2
    inc z_prop_ptr
    bne :+
    inc z_prop_ptr+1
:
    lda z_prop_ptr
    sta z_addr
    lda z_prop_ptr+1
    sta z_addr+1
    jsr zmem_loadb
    and #$3F
    bne :+
    lda #64
:
    jmp @adv
@next2:
    ; ptr at long header byte0; skip 2 header bytes + data
    lda z_prop_ptr
    clc
    adc #1
    sta z_addr
    lda z_prop_ptr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadb
    and #$3F
    bne :+
    lda #64
:
    clc
    adc #2
    adc z_prop_ptr
    sta z_prop_ptr
    lda z_prop_ptr+1
    adc #0
    sta z_prop_ptr+1
@first:
    lda z_prop_ptr
    sta z_addr
    lda z_prop_ptr+1
    sta z_addr+1
    jsr zmem_loadb
    and #$3F
    sta z_a
    lda #0
    sta z_a+1
    jmp z_do_store
@adv:
    clc
    adc #1
    adc z_prop_ptr
    sta z_prop_ptr
    lda z_prop_ptr+1
    adc #0
    sta z_prop_ptr+1
    jmp @scan
.endproc

.proc z_op_get_prop_len
    ; ops[0] = address of prop data (byte after size byte(s))
    lda z_ops_lo
    sta z_addr
    lda z_ops_hi
    sta z_addr+1
    ; back up 1
    lda z_addr
    bne :+
    dec z_addr+1
:
    dec z_addr
    jsr zmem_loadb
    sta z_ch
    and #$80
    bne @long
    lda z_ch
    jsr z_prop_short_size
    sta z_a
    lda #0
    sta z_a+1
    jmp z_do_store
@long:
    ; size in this byte (we backed into size byte for long form - actually data-1 is size byte)
    lda z_ch
    and #$3F
    bne :+
    lda #64
:
    sta z_a
    lda #0
    sta z_a+1
    jmp z_do_store
.endproc

.proc z_op_put_prop
    ; find prop addr then store 1 or 2 bytes
    lda z_ops_lo
    pha
    lda z_ops_hi
    pha
    lda z_ops_lo+1
    pha
    ; reuse get_prop_addr logic into z_a without store
    jsr z_obj_prop_table
    lda z_ops_lo+1
    sta z_attr
@scan:
    lda z_prop_ptr
    sta z_addr
    lda z_prop_ptr+1
    sta z_addr+1
    jsr zmem_loadb
    sta z_ch
    bne @nz
    jmp @done
@nz:
    and #$80
    bne @long
    lda z_ch
    and #$3F
    cmp z_attr
    bne @s1
    lda z_ch
    jsr z_prop_short_size
    sta z_tmpw
    clc
    lda z_prop_ptr
    adc #1
    sta z_addr
    lda z_prop_ptr+1
    adc #0
    sta z_addr+1
    jmp @write
@s1:
    lda z_ch
    jsr z_prop_short_size
    jmp @adv
@long:
    lda z_ch
    and #$3F
    cmp z_attr
    bne @s2
    inc z_prop_ptr
    bne :+
    inc z_prop_ptr+1
:
    lda z_prop_ptr
    sta z_addr
    lda z_prop_ptr+1
    sta z_addr+1
    jsr zmem_loadb
    and #$3F
    bne :+
    lda #64
:
    sta z_tmpw
    clc
    lda z_prop_ptr
    adc #1
    sta z_addr
    lda z_prop_ptr+1
    adc #0
    sta z_addr+1
    jmp @write
@s2:
    inc z_prop_ptr
    bne :+
    inc z_prop_ptr+1
:
    lda z_prop_ptr
    sta z_addr
    lda z_prop_ptr+1
    sta z_addr+1
    jsr zmem_loadb
    and #$3F
    bne :+
    lda #64
:
@adv:
    clc
    adc #1
    adc z_prop_ptr
    sta z_prop_ptr
    lda z_prop_ptr+1
    adc #0
    sta z_prop_ptr+1
    jmp @scan
@write:
    lda z_tmpw
    cmp #1
    bne @w2
    lda z_ops_lo+2
    jsr zmem_storeb
    jmp @done
@w2:
    lda z_ops_lo+2
    ldx z_ops_hi+2
    jsr zmem_storew
@done:
    pla
    pla
    pla
    rts
.endproc

; Unlink ops[0] from parent/sibling chain; clear its parent+sibling.
; NOTE: z_obj_addr overwrites z_obj_num from z_ops — keep the target in z_obj_save.
.proc z_op_remove_obj
    lda z_ops_lo
    sta z_obj_save
    lda z_ops_hi
    sta z_obj_save+1
    jsr z_obj_addr
    clc
    lda z_addr
    adc #6
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw              ; parent
    sta z_a
    stx z_a+1
    ora z_a+1
    bne @has
    rts
@has:
    ; z_b = parent's child field address; A/X = parent's child obj
    lda z_a
    sta z_ops_lo
    lda z_a+1
    sta z_ops_hi
    jsr z_obj_addr
    clc
    lda z_addr
    adc #10
    sta z_b
    lda z_addr+1
    adc #0
    sta z_b+1
    lda z_b
    sta z_addr
    lda z_b+1
    sta z_addr+1
    jsr zmem_loadw
    cmp z_obj_save
    bne @walk
    cpx z_obj_save+1
    bne @walk
    ; parent.child = obj.sibling
    jsr @load_obj_sibling
    lda z_b
    sta z_addr
    lda z_b+1
    sta z_addr+1
    lda z_tmpw
    ldx z_tmpw+1
    jsr zmem_storew
    jmp @clear
@walk:
    ; A/X = current node in sibling chain
@wloop:
    sta z_ops_lo
    stx z_ops_hi
    jsr z_obj_addr
    clc
    lda z_addr
    adc #8
    sta z_b                     ; address of this.sibling
    lda z_addr+1
    adc #0
    sta z_b+1
    lda z_b
    sta z_addr
    lda z_b+1
    sta z_addr+1
    jsr zmem_loadw              ; sibling
    sta z_tmpw
    stx z_tmpw+1
    cmp z_obj_save
    bne @adv
    cpx z_obj_save+1
    beq @relink
@adv:
    lda z_tmpw
    ora z_tmpw+1
    beq @clear
    lda z_tmpw
    ldx z_tmpw+1
    jmp @wloop
@relink:
    jsr @load_obj_sibling       ; tmpw = obj.sibling
    lda z_b
    sta z_addr
    lda z_b+1
    sta z_addr+1
    lda z_tmpw
    ldx z_tmpw+1
    jsr zmem_storew
@clear:
    lda z_obj_save
    sta z_ops_lo
    lda z_obj_save+1
    sta z_ops_hi
    jsr z_obj_addr
    clc
    lda z_addr
    adc #6
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    lda #0
    tax
    jsr zmem_storew             ; parent=0
    lda z_obj_save
    sta z_ops_lo
    lda z_obj_save+1
    sta z_ops_hi
    jsr z_obj_addr
    clc
    lda z_addr
    adc #8
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    lda #0
    tax
    jmp zmem_storew             ; sibling=0

@load_obj_sibling:
    lda z_obj_save
    sta z_ops_lo
    lda z_obj_save+1
    sta z_ops_hi
    jsr z_obj_addr
    clc
    lda z_addr
    adc #8
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw
    sta z_tmpw
    stx z_tmpw+1
    rts
.endproc

.proc z_op_insert_obj
    ; ops[0]=obj ops[1]=dest
    ; z_obj_addr clobbers z_obj_num from ops — keep identities in save/dest.
    lda z_ops_lo
    sta z_obj_save
    lda z_ops_hi
    sta z_obj_save+1
    lda z_ops_lo+1
    sta z_obj_dest
    lda z_ops_hi+1
    sta z_obj_dest+1
    jsr z_op_remove_obj         ; uses ops[0]=obj (still set at entry)
    ; dest.child → will become obj.sibling
    lda z_obj_dest
    sta z_ops_lo
    lda z_obj_dest+1
    sta z_ops_hi
    jsr z_obj_addr
    clc
    lda z_addr
    adc #10
    sta z_b
    lda z_addr+1
    adc #0
    sta z_b+1
    lda z_b
    sta z_addr
    lda z_b+1
    sta z_addr+1
    jsr zmem_loadw
    pha                         ; old child lo (z_tmpw dies in z_obj_addr)
    txa
    pha                         ; old child hi
    ; dest.child = obj
    lda z_b
    sta z_addr
    lda z_b+1
    sta z_addr+1
    lda z_obj_save
    ldx z_obj_save+1
    jsr zmem_storew
    ; obj.parent = dest
    lda z_obj_save
    sta z_ops_lo
    lda z_obj_save+1
    sta z_ops_hi
    jsr z_obj_addr
    clc
    lda z_addr
    adc #6
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    lda z_obj_dest
    ldx z_obj_dest+1
    jsr zmem_storew
    ; obj.sibling = old child
    lda z_obj_save
    sta z_ops_lo
    lda z_obj_save+1
    sta z_ops_hi
    jsr z_obj_addr
    clc
    lda z_addr
    adc #8
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    pla
    tax
    pla
    jmp zmem_storew
.endproc

.proc z_op_print_obj
    jsr z_obj_addr
    clc
    lda z_addr
    adc #12
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw
    sta z_str_a
    stx z_str_a+1
    lda #0
    sta z_str_a+2
    ; short name: skip len byte, print z-string
    lda z_str_a
    sta z_addr
    lda z_str_a+1
    sta z_addr+1
    jsr zmem_loadb
    ; advance past length byte
    inc z_str_a
    bne :+
    inc z_str_a+1
:
    lda #0
    sta z_str_inline
    jmp z_decode_string_at
.endproc

.proc z_op_erase_window
    ; window: 0=lower, 1=upper, $FF(-1)=unsplit+clear all, $FE(-2)=clear all
    lda z_ops_lo
    jmp text_erase_window
.endproc

.proc z_op_erase_line
    ; Spec: value is usually 1 — erase from cursor to end of line.
    ; Other values undefined; treat like 1. Value 0 = no-op.
    lda z_ops_lo
    ora z_ops_hi
    beq @ret
    jmp text_erase_line
@ret:
    rts
.endproc

.proc z_op_split_window
    lda z_ops_lo
    jmp text_split_window
.endproc
.proc z_op_set_window
    lda z_ops_lo
    jmp text_set_window
.endproc
.proc z_op_set_cursor
    ; V4+: ops[0]=line (1-based in window), ops[1]=column (1-based)
    lda z_ops_lo+1
    ldx z_ops_lo
    jmp text_set_cursor_z
.endproc

; VAR:240 get_cursor array — NOT a store opcode. Writes row/col words
; into the given array (1-based, relative to the current window).
.proc z_op_get_cursor
    lda z_ops_lo
    sta z_addr
    lda z_ops_hi
    sta z_addr+1
    ; row
    lda win_cur
    bne @urow
    lda cursor_row
    sec
    sbc win_split
    ; if somehow above main, report line 1
    bcs @r1
    lda #0
@r1:
    clc
    adc #1
    jmp @strow
@urow:
    lda cursor_row
    clc
    adc #1
@strow:
    ldx #0
    jsr zmem_storew
    ; col at array+2 (zmem_storew already advanced z_addr by 1 after hi,
    ; then wrote lo — actually ends with z_addr at array+1. Need array+2.)
    ; zmem_storew: stores hi at addr, inc, stores lo at addr+1, leaves addr at array+1.
    ; We need word at array+2 = col. Reset to array+2.
    lda z_ops_lo
    clc
    adc #2
    sta z_addr
    lda z_ops_hi
    adc #0
    sta z_addr+1
    lda cursor_col
    clc
    adc #1
    ldx #0
    jmp zmem_storew
.endproc

.proc z_op_set_text_style
    rts
.endproc
.proc z_op_buffer_mode
    rts
.endproc
; (z_op_output_stream defined with z_print_zscii above)

.proc z_op_check_arg_count
    ; branch if z_argc >= ops[0]
    lda z_argc
    cmp z_ops_lo
    bcc @no
    lda #1
    jmp z_branch_if
@no:
    lda #0
    jmp z_branch_if
.endproc

.segment "RODATA"
a0tab:
    .byte "abcdefghijklmnopqrstuvwxyz"
a1tab:
    .byte "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
; index = zchar-6; [0]=escape (unused), [1]=newline, [2..]=symbols
a2tab:
    .byte $00,$0D,"0123456789.,!?_#'",'"',"/\\-:()"
