.include "nes.inc"
.include "zmachine.inc"

.import mmc1_init
.import wait_vblank, ppu_load_font, ppu_clear_nt, text_clear, text_put_str, text_newline
.import text_clear_tile0
.import palette_apply_now
.import read_keyboard, keyboard_poll_chars, sfx_boop
.import read_pads
.import palette_cycle
.import text_put_char, text_flush_frame
.import zmem_init, zmem_copy_dynamic
.import zvm_boot, zvm_step
.import z_aread_commit, z_line_buf
.import z_read_char_commit
.import pad_ui_poll, pad_ui_reset
.import title_show
.import nmi, irq
.importzp cursor_col, cursor_row, text_dirty, nt_resync, str_ptr, frame_count
.importzp text_nmi_ok
.importzp key_ready, key_ascii, keys_prev, kb_enable
.importzp z_running, z_extop, z_pc, z_waiting_input, z_line_len
.importzp pad1_pressed
.importzp input_mode
.importzp z_stream3_depth

INPUT_MODE_KB  = 0
INPUT_MODE_PAD = 1

.export main, reset
.exportzp theme_id, palette_dirty, host_char

.segment "ZEROPAGE"
theme_id:      .res 1
palette_dirty: .res 1
hex_tmp:       .res 1
vm_frame:      .res 1
z_trap_shown:  .res 1
host_char:     .res 1      ; nonzero → deliver to read_char (HINT); then cleared

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
    jsr title_show              ; logo nametable; locks input_mode
    jsr begin_play_session
    jmp main
.endproc

; After title (or soft restart): clear screen, enable NMI, boot VM.
.proc begin_play_session
    jsr ppu_load_font           ; restore normal color0/1 glyphs after title
    jsr ppu_clear_nt
    ; Keep theme_id from title SELECT/F1 cycle; apply full BG+sprite pals.
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
    lda #0
    sta z_stream3_depth
    sta key_ready
    sta host_char
    jsr pad_ui_reset
    jsr zvm_boot
    lda #0
    sta z_trap_shown
    sta z_extop
    rts
.endproc

; QUIT opcode → title screen, then a fresh session (input mode chosen again).
.proc return_to_title
    sei
    lda #0
    sta PPUCTRL
    sta PPUMASK
    sta text_nmi_ok
    sta kb_enable
    sta z_waiting_input
    sta key_ready
    jsr wait_vblank
    jsr zmem_copy_dynamic
    bit PPUSTATUS
    jsr ppu_load_font
    jsr title_show
    jsr begin_play_session
    cli
    jmp main
.endproc

; RESTART opcode → reload story dynamic + boot VM (no title).
.proc soft_restart_game
    sei
    lda #0
    sta PPUCTRL
    sta PPUMASK
    sta text_nmi_ok
    sta kb_enable
    sta z_waiting_input
    sta key_ready
    jsr wait_vblank
    jsr zmem_copy_dynamic
    jsr begin_play_session
    cli
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
    lda z_waiting_input
    cmp #ZWAIT_CHAR
    bne @not_char
    jmp @read_char
@not_char:
    ; SELECT = theme (either mode). Pad read must be atomic vs NMI.
    sei
    jsr read_pads
    cli
    lda pad1_pressed
    and #PAD_SELECT
    beq @no_sel
    jsr palette_cycle
@no_sel:
    ; Keyboard scan (JOY1 bitbang) after pad read so FBK does not clobber it.
    sei
    jsr read_keyboard
    cli
    jsr keyboard_poll_chars

    lda input_mode
    cmp #INPUT_MODE_PAD
    bne @kb_path
    jsr pad_ui_poll
    ; Drop any FBK chars so they cannot mix into the pad-built line
    lda #0
    sta key_ready
    jmp @vm

@kb_path:
    lda key_ready
    beq @vm
    lda key_ascii
    sta hex_tmp
    lda #0
    sta key_ready

    ; Line editing only while VM is blocked on aread
    lda z_waiting_input
    cmp #ZWAIT_AREAD
    bne @vm
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
    bne @idle_flush
    jmp @loop
@idle_flush:
    jsr text_flush_frame
    jmp @loop
@stopped:
    lda z_extop
    cmp #$FF
    bne @not_quit
    jmp return_to_title
@not_quit:
    cmp #$FE
    bne @trap_check
    jmp soft_restart_game
@trap_check:
    ; Unimplemented opcode trap — show once, then idle
    lda z_trap_shown
    beq @show_stop
    jmp @loop
@show_stop:
    lda #1
    sta z_trap_shown
    jsr text_newline
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

; Single-key input (HINT / read_char).
; Invisiclues expects N/P/Return/Q. While waiting for a char:
;   host_char (if set), else pad remap Up=P Down=N A/Start=Return B=Q,
;   else FBK key_ready.
@read_char:
    lda host_char
    beq @no_host
    ldx #0
    stx host_char
    jmp @rc_commit_a
@no_host:
    ; Pad remap (either title mode) — re-read under SEI for clean edges
    sei
    jsr read_pads
    cli
    lda pad1_pressed
    beq @rc_kb
    sta hex_tmp
    and #PAD_UP
    beq @cd
    lda #'P'
    jmp @rc_commit_a
@cd:
    lda hex_tmp
    and #PAD_DOWN
    beq @ca
    lda #'N'
    jmp @rc_commit_a
@ca:
    lda hex_tmp
    and #PAD_A
    bne @cret
    lda hex_tmp
    and #PAD_START
    bne @cret
    lda hex_tmp
    and #PAD_B
    beq @rc_kb
    lda #'Q'
    jmp @rc_commit_a
@cret:
    lda #ZSCII_RET
    jmp @rc_commit_a

@rc_kb:
    sei
    jsr read_keyboard
    cli
    jsr keyboard_poll_chars
    lda key_ready
    beq @rc_vm
    lda key_ascii
    ldx #0
    stx key_ready
    ; Ignore non-printables except Return
    cmp #ZSCII_RET
    beq @rc_commit_a
    cmp #$20
    bcc @rc_vm
@rc_commit_a:
    sta hex_tmp
    jsr sfx_boop
    lda hex_tmp
    jsr z_read_char_commit
@rc_vm:
    jmp @vm
.endproc

.segment "RODATA"
msg_trap:
    .byte "TRAP OP ", 0

.segment "VECTORS"
    .word nmi
    .word reset
    .word irq
