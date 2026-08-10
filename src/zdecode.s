.include "nes.inc"
.include "zmachine.inc"

.import z_fetch_b, z_fetch_w, z_get_var, z_put_var, z_trap, z_pop, z_push
.import z_op_call, z_op_ret, z_op_print, z_op_print_paddr, z_op_print_addr
.import z_op_print_char, z_op_print_num, z_op_new_line, z_op_quit
.import z_op_restart
.import z_op_store, z_op_load, z_op_storew, z_op_loadw, z_op_storeb, z_op_loadb
.import z_op_add, z_op_sub, z_op_mul, z_op_div, z_op_mod, z_op_and, z_op_or
.import z_op_jz, z_op_je, z_op_jl, z_op_jg, z_op_jump, z_op_inc, z_op_dec
.import z_op_inc_chk, z_op_dec_chk, z_op_rtrue, z_op_rfalse, z_op_ret_popped, z_op_nop
.import z_op_push, z_op_pull
.import z_op_get_prop, z_op_get_prop_addr, z_op_get_next_prop, z_op_get_prop_len
.import z_op_put_prop, z_op_test_attr, z_op_set_attr, z_op_clear_attr
.import z_op_jin, z_op_insert_obj, z_op_remove_obj
.import z_op_get_parent, z_op_get_sibling, z_op_get_child, z_op_print_obj
.import z_op_erase_window, z_op_split_window, z_op_set_window, z_op_set_text_style
.import z_op_set_cursor, z_op_get_cursor, z_op_erase_line
.import z_op_buffer_mode, z_op_output_stream, z_op_check_arg_count
.import z_op_tokenise
.import z_op_aread
.import z_op_read_char
.import z_op_random
.import z_op_save, z_op_restore
.importzp z_opcode, z_opcount, z_ops_lo, z_ops_hi, z_types, z_extop, z_i
.importzp z_pc, z_tmpw, z_a, z_b, z_call_has_store
.export z_decode_exec, z_do_store, z_branch_if

.segment "ZEROPAGE"
z_opbyte: .res 1
z_br0:    .res 1

.segment "CODE"

.proc z_load_one_op
    cmp #ZTYPE_OMIT
    beq @omit
    cmp #ZTYPE_LARGE
    beq @lg
    cmp #ZTYPE_SMALL
    beq @sm
    jsr z_fetch_b
    tay
    jsr z_get_var
    jmp @st
@lg:
    jsr z_fetch_w
    jmp @st
@sm:
    jsr z_fetch_b
    ldx #0
@st:
    ldy z_opcount
    sta z_ops_lo,y
    txa
    sta z_ops_hi,y
    inc z_opcount
    clc
    rts
@omit:
    sec
    rts
.endproc

; Like z_load_one_op, but VARIABLE type yields the variable *number*
; (the fetched byte), not the variable's value. Used by load/store/inc/dec/pull.
.proc z_load_varnum
    cmp #ZTYPE_OMIT
    beq @omit
    cmp #ZTYPE_LARGE
    beq @lg
    ; SMALL and VAR: one byte = variable number
    jsr z_fetch_b
    ldx #0
    jmp @st
@lg:
    jsr z_fetch_w
@st:
    ldy z_opcount
    sta z_ops_lo,y
    txa
    sta z_ops_hi,y
    inc z_opcount
    clc
    rts
@omit:
    sec
    rts
.endproc

.proc z_parse_types_byte
    lda #0
    sta z_i
@loop:
    lda z_i
    cmp #4
    bcs @done
    lda z_types
    ldx z_i
    beq @got
@shl:
    asl a
    asl a
    dex
    bne @shl
@got:
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    and #3
    jsr z_load_one_op
    bcs @done
    inc z_i
    jmp @loop
@done:
    rts
.endproc

; VAR form of 2OP (except je): fetch at most 2 operands even if the
; types byte lists more (spec: unused slots should be omit).
.proc z_parse_types_byte_2op
    lda #0
    sta z_i
@loop:
    lda z_i
    cmp #2
    bcs @done
    lda z_types
    ldx z_i
    beq @got
@shl:
    asl a
    asl a
    dex
    bne @shl
@got:
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    and #3
    jsr z_load_one_op
    bcs @done
    inc z_i
    jmp @loop
@done:
    rts
.endproc

; First operand as varnum, remaining as normal values (store/inc_chk/dec_chk/pull)
.proc z_parse_types_byte_ref0
    lda #0
    sta z_i
@loop:
    lda z_i
    cmp #4
    bcs @done
    ; store/inc_chk/dec_chk/pull are 2OP — stop after 2 operands
    cmp #2
    bcs @done
    lda z_types
    ldx z_i
    beq @got
@shl:
    asl a
    asl a
    dex
    bne @shl
@got:
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    and #3
    ldx z_i
    bne @val
    jsr z_load_varnum
    jmp @nxt
@val:
    jsr z_load_one_op
@nxt:
    bcs @done
    inc z_i
    jmp @loop
@done:
    rts
.endproc

.proc z_decode_exec
    lda #0
    sta z_opcount
    jsr z_fetch_b
    sta z_opbyte
    cmp #$BE
    bne @n1
    jsr z_fetch_b
    sta z_extop
    jsr z_fetch_b
    sta z_types
    jsr z_parse_types_byte
    lda z_extop
    sta z_opcode
    jmp z_disp_ext
@n1:
    cmp #$E0
    bcc @n2
    and #$1F
    sta z_opcode
    jsr z_fetch_b
    sta z_types
    ; pull (VAR:9): first operand is a variable number
    lda z_opcode
    cmp #9
    bne @vnorm
    jsr z_parse_types_byte_ref0
    jmp @vs2chk
@vnorm:
    jsr z_parse_types_byte
@vs2chk:
    ; call_vs2 / call_vn2: second operand-types byte (up to 8 ops)
    lda z_opcode
    cmp #12
    beq @vs2
    cmp #26
    bne @vdisp
@vs2:
    jsr z_fetch_b
    sta z_types
    jsr z_parse_types_byte
@vdisp:
    jmp z_disp_var
@n2:
    cmp #$C0
    bcc @n3
    and #$1F
    sta z_opcode
    jsr z_fetch_b
    sta z_types
    ; 2OP in VAR form: store/inc_chk/dec_chk need varnum for op0
    lda z_opcode
    cmp #4
    beq @ref2
    cmp #5
    beq @ref2
    cmp #13
    beq @ref2
    ; je (op 1) may take up to 4 operands; all other VAR-2OP take exactly 2
    cmp #1
    beq @je2
    jsr z_parse_types_byte_2op
    jmp z_disp_2op
@je2:
    jsr z_parse_types_byte
    jmp z_disp_2op
@ref2:
    jsr z_parse_types_byte_ref0
    jmp z_disp_2op
@n3:
    cmp #$B0
    bcc @n4
    and #$0F
    sta z_opcode
    jmp z_disp_0op
@n4:
    cmp #$80
    bcc @long
    sta z_opbyte
    and #$0F
    sta z_opcode
    lda z_opbyte
    lsr a
    lsr a
    lsr a
    lsr a
    and #3
    ; 1OP: inc/dec/load take a variable number
    tax
    lda z_opcode
    cmp #5
    beq @ref1
    cmp #6
    beq @ref1
    cmp #14
    beq @ref1
    txa
    jsr z_load_one_op
    jmp z_disp_1op
@ref1:
    txa
    jsr z_load_varnum
    jmp z_disp_1op
@long:
    sta z_opbyte
    and #$1F
    sta z_opcode
    ; Long 2OP: store/inc_chk/dec_chk — first operand is varnum
    lda z_opcode
    cmp #4
    beq @longref
    cmp #5
    beq @longref
    cmp #13
    beq @longref
    lda z_opbyte
    and #$40
    beq @s1
    lda #ZTYPE_VAR
    bne @o1
@s1:
    lda #ZTYPE_SMALL
@o1:
    jsr z_load_one_op
    lda z_opbyte
    and #$20
    beq @s2
    lda #ZTYPE_VAR
    bne @o2
@s2:
    lda #ZTYPE_SMALL
@o2:
    jsr z_load_one_op
    jmp z_disp_2op
@longref:
    lda z_opbyte
    and #$40
    beq @rs1
    lda #ZTYPE_VAR
    bne @ro1
@rs1:
    lda #ZTYPE_SMALL
@ro1:
    jsr z_load_varnum
    lda z_opbyte
    and #$20
    beq @rs2
    lda #ZTYPE_VAR
    bne @ro2
@rs2:
    lda #ZTYPE_SMALL
@ro2:
    jsr z_load_one_op
    jmp z_disp_2op
.endproc

.proc z_do_store
    jsr z_fetch_b
    tay
    lda z_a
    ldx z_a+1
    jmp z_put_var
.endproc

.proc z_branch_if
    sta z_b
    jsr z_fetch_b
    sta z_br0
    and #$40
    bne @short
    lda z_br0
    and #$3F
    sta z_tmpw+1
    jsr z_fetch_b
    sta z_tmpw
    lda z_tmpw+1
    and #$20
    beq @sg
    lda z_tmpw+1
    ora #$C0
    sta z_tmpw+1
    jmp @sg
@short:
    ; Spec 4.7: short offset is UNSIGNED 0..63 (only long branches are signed).
    lda z_br0
    and #$3F
    sta z_tmpw
    lda #0
    sta z_tmpw+1
    jmp @sg
@sg:
    lda z_br0
    and #$80
    beq @want0
    lda z_b
    bne @go
    rts
@want0:
    lda z_b
    beq @go
    rts
@go:
    lda z_tmpw
    ora z_tmpw+1
    bne @nz
    lda #0
    ldx #0
    jmp z_op_ret
@nz:
    lda z_tmpw+1
    bne @dojmp
    lda z_tmpw
    cmp #1
    bne @dojmp
    lda #1
    ldx #0
    jmp z_op_ret
@dojmp:
    ; Add signed 16-bit offset to 24-bit PC, then PC = PC - 2
    php
    sei
    ldx #0
    lda z_tmpw+1
    bpl @pos
    ldx #$FF
@pos:
    clc
    lda z_pc
    adc z_tmpw
    sta z_pc
    lda z_pc+1
    adc z_tmpw+1
    sta z_pc+1
    txa
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
    plp
    rts
.endproc

.proc z_disp_ext
    lda z_extop
    bne @1
    jmp z_op_save
@1: cmp #1
    bne @u
    jmp z_op_restore
@u: jmp z_unimpl
.endproc

.proc z_unimpl
    lda z_opcode
    jmp z_trap
.endproc

.proc z_disp_0op
    lda z_opcode
    bne @1
    jmp z_op_rtrue
@1: cmp #1
    bne @2
    jmp z_op_rfalse
@2: cmp #2
    bne @3
    jmp z_op_print
@3: cmp #3
    bne @7
    jsr z_op_print
    jmp z_op_rtrue
@7: cmp #7
    bne @8
    jmp z_op_restart
@8: cmp #8
    bne @a
    jmp z_op_ret_popped
@a: cmp #10
    bne @b
    jmp z_op_quit
@b: cmp #11
    bne @d
    jmp z_op_new_line
@d: cmp #13
    bne @u
    jmp z_op_nop
@u: jmp z_unimpl
.endproc

.proc z_call_s
    lda #1
    sta z_call_has_store
    jmp z_op_call
.endproc

.proc z_call_n
    lda #0
    sta z_call_has_store
    jmp z_op_call
.endproc

.proc z_disp_1op
    lda z_opcode
    bne @1
    jmp z_op_jz
@1: cmp #1
    bne @2
    jmp z_op_get_sibling
@2: cmp #2
    bne @3
    jmp z_op_get_child
@3: cmp #3
    bne @4
    jmp z_op_get_parent
@4: cmp #4
    bne @5
    jmp z_op_get_prop_len
@5: cmp #5
    bne @6
    jmp z_op_inc
@6: cmp #6
    bne @7
    jmp z_op_dec
@7: cmp #7
    bne @8
    jmp z_op_print_addr
@8: cmp #8
    bne @9
    jmp z_call_s
@9: cmp #9
    bne @a
    jmp z_op_remove_obj
@a: cmp #10
    bne @b
    jmp z_op_print_obj
@b: cmp #11
    bne @c
    lda z_ops_lo
    ldx z_ops_hi
    jmp z_op_ret
@c: cmp #12
    bne @d
    jmp z_op_jump
@d: cmp #13
    bne @e
    jmp z_op_print_paddr
@e: cmp #14
    bne @f
    jmp z_op_load
@f: cmp #15
    bne @u
    jmp z_call_n
@u: jmp z_unimpl
.endproc

.proc z_disp_2op
    lda z_opcode
    cmp #1
    bne @2
    jmp z_op_je
@2: cmp #2
    bne @3
    jmp z_op_jl
@3: cmp #3
    bne @4
    jmp z_op_jg
@4: cmp #4
    bne @5
    jmp z_op_dec_chk
@5: cmp #5
    bne @6
    jmp z_op_inc_chk
@6: cmp #6
    bne @7
    jmp z_op_jin
@7: cmp #7
    bne @8
    ; test: branch if (ops0 & ops1) == ops1
    lda z_ops_lo
    and z_ops_lo+1
    cmp z_ops_lo+1
    bne @tno
    lda z_ops_hi
    and z_ops_hi+1
    cmp z_ops_hi+1
    bne @tno
    lda #1
    jmp z_branch_if
@tno:
    lda #0
    jmp z_branch_if
@8: cmp #8
    bne @9
    jmp z_op_or
@9: cmp #9
    bne @a
    jmp z_op_and
@a: cmp #10
    bne @b
    jmp z_op_test_attr
@b: cmp #11
    bne @c
    jmp z_op_set_attr
@c: cmp #12
    bne @d
    jmp z_op_clear_attr
@d: cmp #13
    bne @e
    jmp z_op_store
@e: cmp #14
    bne @f
    jmp z_op_insert_obj
@f: cmp #15
    bne @10
    jmp z_op_loadw
@10: cmp #16
    bne @11
    jmp z_op_loadb
@11: cmp #17
    bne @12
    jmp z_op_get_prop
@12: cmp #18
    bne @13
    jmp z_op_get_prop_addr
@13: cmp #19
    bne @14
    jmp z_op_get_next_prop
@14: cmp #20
    bne @15
    jmp z_op_add
@15: cmp #21
    bne @16
    jmp z_op_sub
@16: cmp #22
    bne @17
    jmp z_op_mul
@17: cmp #23
    bne @18
    jmp z_op_div
@18: cmp #24
    bne @19
    jmp z_op_mod
@19: cmp #25
    bne @1a
    jmp z_call_s
@1a: cmp #26
    bne @u
    jmp z_call_n
@u: jmp z_unimpl
.endproc

.proc z_disp_var
    lda z_opcode
    bne @1
    jmp z_call_s
@1: cmp #1
    bne @2
    jmp z_op_storew
@2: cmp #2
    bne @3
    jmp z_op_storeb
@3: cmp #3
    bne @4
    jmp z_op_put_prop
@4: cmp #4
    bne @5
    jmp z_op_aread            ; aread / sread — block for line input
@5: cmp #5
    bne @6
    jmp z_op_print_char
@6: cmp #6
    bne @7
    jmp z_op_print_num
@7: cmp #7
    bne @8
    jmp z_op_random
@8: cmp #8
    bne @9
    jmp z_op_push
@9: cmp #9
    bne @a
    jmp z_op_pull
@a: cmp #10
    bne @b
    jmp z_op_split_window
@b: cmp #11
    bne @c
    jmp z_op_set_window
@c: cmp #12
    bne @d
    jmp z_call_s
@d: cmp #13
    bne @e
    jmp z_op_erase_window
@e: cmp #14
    bne @f
    jmp z_op_erase_line
@f: cmp #15
    bne @10
    jmp z_op_set_cursor
@10: cmp #16
    bne @11
    jmp z_op_get_cursor
@11: cmp #17
    bne @12
    jmp z_op_set_text_style
@12: cmp #18
    bne @13
    jmp z_op_buffer_mode
@13: cmp #19
    bne @14
    jmp z_op_output_stream
@14: cmp #20
    bne @15
    jmp z_op_nop              ; input_stream
@15: cmp #21
    bne @16
    jmp z_op_nop              ; sound_effect
@16: cmp #22
    bne @17
    jmp z_op_read_char
@17: cmp #23
    bne @18
    jmp z_unimpl              ; scan_table
@18: cmp #24
    bne @19
    jmp z_op_not_var
@19: cmp #25
    bne @1a
    jmp z_call_n
@1a: cmp #26
    bne @1b
    jmp z_call_n
@1b: cmp #27
    bne @1f
    jmp z_op_tokenise
@1f: cmp #31
    bne @u
    jmp z_op_check_arg_count
@u: jmp z_unimpl
.endproc

; VAR:24 not — ones complement
.proc z_op_not_var
    lda z_ops_lo
    eor #$FF
    sta z_a
    lda z_ops_hi
    eor #$FF
    sta z_a+1
    jmp z_do_store
.endproc
