.include "nes.inc"

.import palette_cycle
.importzp title_active
.export read_keyboard, keyboard_poll_chars
.exportzp keys_cur, keys_prev, key_ascii, key_ready, kb_enable

.segment "ZEROPAGE"
keys_cur:   .res 9
keys_prev:  .res 9
key_ascii:  .res 1
key_ready:  .res 1
kb_row:     .res 1
kb_tmp:     .res 1
kb_mask:    .res 1
kb_enable:  .res 1

.segment "CODE"

; Must preserve X (row index).
.proc kb_delay50
    ldy #12
@d:
    dey
    bne @d
    rts
.endproc

; Scan 9 rows into keys_cur (active-low: 0 = pressed).
; Call from main under SEI (not NMI — too heavy for vblank).
.proc read_keyboard
    lda #$05
    sta JOY1
    nop
    nop
    nop
    nop
    nop
    nop
    ldx #0
@row:
    lda #$04
    sta JOY1
    jsr kb_delay50
    lda JOY2
    lsr a
    and #$0F
    sta kb_tmp
    lda #$06
    sta JOY1
    jsr kb_delay50
    lda JOY2
    asl a
    asl a
    asl a
    and #$F0
    ora kb_tmp
    sta keys_cur,x
    inx
    cpx #9
    bne @row
    lda #$00
    sta JOY1
    rts
.endproc

; Edge detect vs keys_prev. Main calls after NMI has scanned.
; If key_ready already set, keep it until main consumes (do not drop).
; map_first_bit uses X — reload row from kb_row after return.
.proc keyboard_poll_chars
    lda kb_enable
    beq @ret
    lda key_ready
    bne @ret

    ; Reject impossible all-zero rows; leave prev alone
    ldx #0
@nz:
    lda keys_cur,x
    beq @ret
    inx
    cpx #9
    bne @nz

    ; Idle matrix → resync prev (clears stuck false presses)
    ldx #0
    lda #$FF
@idle:
    and keys_cur,x
    inx
    cpx #9
    bne @idle
    cmp #$FF
    bne @edges
    ldx #0
    lda #$FF
@sync:
    sta keys_prev,x
    inx
    cpx #9
    bne @sync
    rts

@edges:
    ldx #0
@row:
    stx kb_row
    lda keys_cur,x
    eor #$FF
    and keys_prev,x
    beq @next
    sta kb_mask
    jsr map_first_bit
    ldx kb_row
    bcc @next
    cmp #$80
    bne @not_f1
    jsr palette_cycle
    jmp @saveprev
@not_f1:
    cmp #$81                 ; F8 — erase save (title only)
    bne @char
    lda title_active
    beq @saveprev
    lda #$81
    sta key_ascii
    lda #1
    sta key_ready
    jmp @saveprev
@char:
    sta key_ascii
    lda #1
    sta key_ready
    jmp @saveprev
@next:
    ldx kb_row
    inx
    cpx #9
    bne @row
@saveprev:
    ldx #0
@copy:
    lda keys_cur,x
    sta keys_prev,x
    inx
    cpx #9
    bne @copy
@ret:
    rts
.endproc

.proc map_first_bit
    lda kb_mask
    ldx #0
@find:
    lsr a
    bcs @got
    inx
    cpx #8
    bne @find
    clc
    rts
@got:
    lda kb_row
    asl a
    asl a
    asl a
    stx kb_tmp
    clc
    adc kb_tmp
    tax
    lda keymap,x
    beq @nomap
    sec
    rts
@nomap:
    clc
    rts
.endproc

.segment "RODATA"
keymap:
    ; Packed order = $4017 bit1..bit4 per column (reverse of wiki bit4..1 list).
    ; Row 0: F8 Return [ ] Kana RShift Yen Stop
    .byte $81, $0D, '[', ']', 0, 0, $5C, 0
    .byte 0, '@', ':', ';', '_', '/', '-', '^'
    .byte 0, 'O', 'L', 'K', '.', ',', 'P', '0'
    .byte 0, 'I', 'U', 'J', 'M', 'N', '9', '8'
    .byte 0, 'Y', 'G', 'H', 'B', 'V', '7', '6'
    .byte 0, 'T', 'R', 'D', 'F', 'C', '5', '4'
    .byte 0, 'W', 'S', 'A', 'X', 'Z', 'E', '3'
    ; Row 7: F1 Esc Q Ctrl LShift Grph 1 2
    .byte $80, 0, 'Q', 0, 0, 0, '1', '2'
    .byte 0, 0, 0, 0, 0, $20, $08, 0
