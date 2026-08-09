.include "nes.inc"

.import mmc1_init
.import wait_vblank, ppu_load_font, ppu_clear_nt, text_clear, text_put_str, text_newline
.import text_clear_tile0
.import palette_apply_now
.import read_keyboard, keyboard_poll_chars, sfx_boop
.import text_put_char, text_flush_frame
.import zmem_init, zmem_copy_dynamic
.import zvm_boot, zvm_step
.import z_aread_commit, z_line_buf
.import title_show
.import nmi, irq
.importzp cursor_col, cursor_row, text_dirty, nt_resync, str_ptr, frame_count
.importzp text_nmi_ok
.importzp key_ready, key_ascii, keys_prev, kb_enable
.importzp z_running, z_extop, z_pc, z_waiting_input, z_line_len

.export main, reset
.exportzp theme_id, palette_dirty

.segment "ZEROPAGE"
theme_id:      .res 1
palette_dirty: .res 1
hex_tmp:       .res 1
vm_frame:      .res 1
z_trap_shown:  .res 1

Z_LINE_MAX = 64

.segment "CODE"

.proc reset
    sei
    cld
    ldx #$40
    stx JOY2
    ldx #$FF
    txs
    inx
    stx PPUCTRL
    stx PPUMASK
    stx SND_CHN

    jsr wait_vblank
    jsr wait_vblank

    ldx #0
    lda #0
@clr:
    sta $0000,x
    sta $0100,x
    sta $0200,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne @clr

    lda #$FF
    ldx #0
@kprev:
    sta keys_prev,x
    inx
    cpx #9
    bne @kprev
    lda #0
    sta kb_enable

    jsr mmc1_init
    jsr zmem_init
    jsr zmem_copy_dynamic

    bit PPUSTATUS
    jsr ppu_load_font
    jsr title_show              ; logo nametable, ~4s, BG from $1000

    jsr ppu_clear_nt
    lda #THEME_GREEN
    sta theme_id
    jsr palette_apply_now
    jsr restore_scroll_init     ; BG pattern back to $0000 (font)
    jsr text_clear

    lda #PPUCTRL_NMI
    sta PPUCTRL
    lda #1
    sta text_nmi_ok
    jsr wait_vblank
    lda #PPUMASK_ON
    sta PPUMASK

    lda #1
    sta kb_enable
    jsr zvm_boot
    ; zvm_boot leaves z_running=1 — run until aread/trap
    lda #0
    sta z_trap_shown

    jmp main
.endproc

.proc print_hex8
    sta hex_tmp
    lsr a
    lsr a
    lsr a
    lsr a
    jsr print_hex_digit
    lda hex_tmp
    and #$0F
    jmp print_hex_digit
.endproc

.proc print_hex_digit
    and #$0F
    cmp #10
    bcc @dec
    clc
    adc #'A' - 10
    jmp text_put_char
@dec:
    clc
    adc #'0'
    jmp text_put_char
.endproc

.proc restore_scroll_init
    lda #PPUCTRL_NMI
    sta PPUCTRL
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    rts
.endproc

.proc main
@loop:
    lda frame_count
@wait:
    cmp frame_count
    beq @wait

@input:
    sei
    jsr read_keyboard
    cli
    jsr keyboard_poll_chars
    lda key_ready
    beq @vm
    lda key_ascii
    sta hex_tmp
    lda #0
    sta key_ready

    ; Line editing only while VM is blocked on aread
    lda z_waiting_input
    beq @vm
    jsr sfx_boop
    lda hex_tmp
    cmp #$0D
    beq @commit
    cmp #$08
    beq @bs
    cmp #$20
    bcc @vm
    ; append if room
    lda z_line_len
    cmp #Z_LINE_MAX
    bcs @vm
    tax
    lda hex_tmp
    sta z_line_buf,x
    inc z_line_len
    lda hex_tmp
    jsr text_put_char
    ; Echo via VQ in NMI — avoid full NT blank/copy per key (flicker + ghost)
    jmp @vm

@bs:
    lda z_line_len
    beq @vm
    dec z_line_len
    lda #$08
    jsr text_put_char
    jmp @vm

@commit:
    jsr text_newline
    jsr z_aread_commit
    jmp @vm

@vm:
    lda z_running
    bne @run
    lda z_waiting_input
    beq @stopped
    ; Idle: VQ drains in NMI; only scroll/clear need a main-thread resync.
    lda nt_resync
    beq @loop
    jsr text_flush_frame
    jmp @loop
@stopped:
    ; Stopped and not waiting → trap/quit (show once)
    lda z_trap_shown
    bne @loop
    lda #1
    sta z_trap_shown
    jsr text_newline
    lda z_extop
    cmp #$FF
    bne @trap
    lda #<msg_quit
    sta str_ptr
    lda #>msg_quit
    sta str_ptr+1
    jsr text_put_str
    jmp @trapdone
@trap:
    lda #<msg_trap
    sta str_ptr
    lda #>msg_trap
    sta str_ptr+1
    jsr text_put_str
    lda z_extop
    jsr print_hex8
    lda #' '
    jsr text_put_char
    lda #'@'
    jsr text_put_char
    lda z_pc+1
    jsr print_hex8
    lda z_pc
    jsr print_hex8
@trapdone:
    jsr text_newline
    jsr text_clear_tile0
    jmp @loop

@run:
    ; Run until frame boundary. Tile updates via VQ in NMI; scroll/clear
    ; resync blanks once on the main thread when nt_resync is set.
    lda frame_count
    sta vm_frame
@steps:
    jsr zvm_step
    lda z_running
    beq @to_input
    lda frame_count
    cmp vm_frame
    beq @steps
    lda nt_resync
    beq @run_in
    jsr text_flush_frame
@run_in:
    jmp @input
@to_input:
    lda nt_resync
    beq @run_in
    jsr text_flush_frame
    jmp @input
.endproc

.segment "RODATA"
msg_trap:
    .byte "TRAP OP ", 0
msg_quit:
    .byte "GAME QUIT", 0

.segment "VECTORS"
    .word nmi
    .word reset
    .word irq
