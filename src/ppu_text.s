.include "nes.inc"

.import zmem_wram_text_on, zmem_wram_text_off
.import mmc1_set_prg
.import font_chr
.importzp frame_count
.export ppu_clear_nt, ppu_load_font, text_clear, text_put_str, text_put_char
.export text_flush_all, text_flush_nmi, text_flush_frame, text_newline, text_home
.export text_clear_tile0, text_set_cursor, text_set_cursor_z
.export text_split_window, text_set_window, text_erase_window
.exportzp cursor_col, cursor_row, text_dirty, str_ptr
.exportzp win_split, win_cur
.exportzp tile_off_lo, tile_off_hi, tile_value
.exportzp text_nmi_ok
.export nt_mirror
.export wait_vblank

VQ_MAX = 64
NT_MIRROR_SIZE = 1024     ; nametable tiles + attributes
; Vblank budget (~2270 cy). Stay well under so $2006/$2007 never
; run into visible time (that scatters wrong tiles across the NT).
FLUSH_PER_NMI = 32
PROGRESS_PER_NMI = 24

.segment "ZEROPAGE"
cursor_col:   .res 1
cursor_row:   .res 1
text_dirty:   .res 1
ppu_tmp:      .res 1
str_ptr:      .res 2
vq_head:      .res 1
vq_tail:      .res 1
tile_off_lo:  .res 1
tile_off_hi:  .res 1
tile_value:   .res 1
mirror_ptr:   .res 2
nt_resync:    .res 1
nt_flush_lo:  .res 1
nt_flush_hi:  .res 1
win_split:    .res 1      ; upper window lines (0 = no status split)
win_cur:      .res 1      ; 0 = lower/main, 1 = upper/status
; Per-window cursors (screen-absolute). Spec: each window keeps its own
; cursor; selecting the upper window resets it to top-left.
win0_col:     .res 1
win0_row:     .res 1
win1_col:     .res 1
win1_row:     .res 1
scroll_tmp:   .res 1
scroll_ptr:   .res 2
text_nmi_ok:  .res 1      ; 1 once NMI is enabled (VQ can wait on drain)
.exportzp nt_resync


.segment "BSS"
vq_lo:        .res VQ_MAX
vq_hi:        .res VQ_MAX
vq_tile:      .res VQ_MAX

.segment "WRAM"
nt_mirror:   .res 1024

.segment "CODE"

.proc wait_vblank
:   bit PPUSTATUS
    bpl :-
    rts
.endproc

; A = row (0..29) → tile_off = row * 32.
; Five ASLs alone drop the carry from bit7→C on rows ≥16; must ROL hi each shift.
.proc row_to_tile_off
    sta tile_off_lo
    lda #0
    sta tile_off_hi
    asl tile_off_lo
    rol tile_off_hi
    asl tile_off_lo
    rol tile_off_hi
    asl tile_off_lo
    rol tile_off_hi
    asl tile_off_lo
    rol tile_off_hi
    asl tile_off_lo
    rol tile_off_hi
    rts
.endproc

.proc ppu_load_font
    lda #6
    jsr mmc1_set_prg
    lda #$00
    sta PPUADDR
    sta PPUADDR
    lda #<font_chr
    sta str_ptr
    lda #>font_chr
    sta str_ptr+1
    ldx #0
    ldy #0
@page:
    lda (str_ptr),y
    sta PPUDATA
    iny
    bne @page
    inc str_ptr+1
    inx
    cpx #32
    bne @page
    lda #0
    jsr mmc1_set_prg
    rts
.endproc

.proc ppu_clear_nt
    lda #$20
    sta PPUADDR
    lda #$00
    sta PPUADDR
    lda #' '
    ldx #4
    ldy #0
@loop:
    sta PPUDATA
    iny
    bne @loop
    dex
    bne @loop
    rts
.endproc

.proc text_clear
    lda #0
    sta win_split
    sta win_cur
    sta win0_col
    sta win0_row
    sta win1_col
    sta win1_row
    jsr zmem_wram_text_on
    lda #' '
    ldx #0
@fill:
    sta nt_mirror,x
    sta nt_mirror+$100,x
    sta nt_mirror+$200,x
    sta nt_mirror+$300,x
    inx
    bne @fill
    ldx #0
    lda #0
@attr:
    sta nt_mirror+$3C0,x
    inx
    cpx #64
    bne @attr
    jsr zmem_wram_text_off
    jsr text_home
    jsr begin_nt_resync
    rts
.endproc

; Start a progressive mirror→PPU copy in NMI (no screen blanking).
.proc begin_nt_resync
    lda #0
    sta vq_head
    sta vq_tail
    sta nt_flush_lo
    sta nt_flush_hi
    lda #1
    sta nt_resync
    sta text_dirty
    rts
.endproc

; Home cursor in the current window (screen absolute).
.proc text_home
    lda #0
    sta cursor_col
    lda win_cur
    bne @upper
    lda win_split
    sta cursor_row
    sta win0_row
    lda #0
    sta win0_col
    rts
@upper:
    lda #0
    sta cursor_row
    sta win1_col
    sta win1_row
    rts
.endproc

; A = column 0-based screen, X = row 0-based screen
.proc text_set_cursor
    cmp #SCREEN_COLS
    bcc @cok
    lda #SCREEN_COLS-1
@cok:
    sta cursor_col
    txa
    cmp #SCREEN_ROWS
    bcc @rok
    lda #SCREEN_ROWS-1
@rok:
    sta cursor_row
    ; Keep the active window's saved cursor in sync
    lda win_cur
    bne @u
    lda cursor_col
    sta win0_col
    lda cursor_row
    sta win0_row
    rts
@u:
    lda cursor_col
    sta win1_col
    lda cursor_row
    sta win1_row
    rts
.endproc

; Z-machine set_cursor: A=col 1-based, X=line 1-based in current window
.proc text_set_cursor_z
    ; col
    cmp #0
    bne @c
    lda #1
@c:
    sec
    sbc #1
    sta ppu_tmp
    ; line → screen row
    txa
    bne @l
    ldx #1
    txa
@l:
    dex                     ; 0-based line in window
    lda win_cur
    bne @up
    txa
    clc
    adc win_split
    tax
    jmp @go
@up:
    ; clamp to upper window
    cpx win_split
    bcc @go
    ldx win_split
    beq @go
    dex
@go:
    lda ppu_tmp
    jmp text_set_cursor
.endproc

.proc text_clear_tile0
    lda #0
    sta tile_off_lo
    sta tile_off_hi
    lda #' '
    sta tile_value
    jsr zmem_wram_text_on
    lda #' '
    sta nt_mirror
    jsr zmem_wram_text_off
    jsr begin_nt_resync
    rts
.endproc

.proc text_newline
    lda #0
    sta cursor_col
    inc cursor_row
    lda win_cur
    bne @upper
    ; main window: scroll when past bottom
    lda cursor_row
    cmp #SCREEN_ROWS
    bcc @ok
    jsr text_scroll_main
    lda #SCREEN_ROWS-1
    sta cursor_row
@ok:
    lda cursor_col
    sta win0_col
    lda cursor_row
    sta win0_row
    rts
@upper:
    lda cursor_row
    cmp win_split
    bcc @uok
    ; stay on last status line
    lda win_split
    beq @uok
    sec
    sbc #1
    sta cursor_row
@uok:
    lda cursor_col
    sta win1_col
    lda cursor_row
    sta win1_row
    rts
.endproc

; Scroll main window (rows win_split..29) up one line; clear bottom row.
.proc text_scroll_main
    jsr zmem_wram_text_on
    lda win_split
    sta scroll_tmp
@rows:
    lda scroll_tmp
    cmp #SCREEN_ROWS-1
    bcs @blank
    ; dest = row*32, src = dest+32
    lda scroll_tmp
    jsr row_to_tile_off
    lda #<nt_mirror
    clc
    adc tile_off_lo
    sta mirror_ptr
    lda #>nt_mirror
    adc tile_off_hi
    sta mirror_ptr+1
    ; src = dest + 32
    lda mirror_ptr
    clc
    adc #32
    sta scroll_ptr
    lda mirror_ptr+1
    adc #0
    sta scroll_ptr+1
    ldy #0
@copy:
    lda (scroll_ptr),y
    sta (mirror_ptr),y
    iny
    cpy #32
    bne @copy
    inc scroll_tmp
    jmp @rows
@blank:
    ; clear last row (29)
    lda #SCREEN_ROWS-1
    jsr row_to_tile_off
    lda #<nt_mirror
    clc
    adc tile_off_lo
    sta mirror_ptr
    lda #>nt_mirror
    adc tile_off_hi
    sta mirror_ptr+1
    ldy #0
    lda #' '
@b:
    sta (mirror_ptr),y
    iny
    cpy #32
    bne @b
    jsr zmem_wram_text_off
    jsr begin_nt_resync
    rts
.endproc

; Clear rows [A, X] inclusive (0-based), spaces only.
.proc text_erase_rows
    sta scroll_tmp          ; start row
    stx ppu_tmp             ; end row
    jsr zmem_wram_text_on
@row:
    lda scroll_tmp
    cmp ppu_tmp
    beq @do
    bcs @done
@do:
    lda scroll_tmp
    jsr row_to_tile_off
    lda #<nt_mirror
    clc
    adc tile_off_lo
    sta mirror_ptr
    lda #>nt_mirror
    adc tile_off_hi
    sta mirror_ptr+1
    ldy #0
    lda #' '
@c:
    sta (mirror_ptr),y
    iny
    cpy #32
    bne @c
    lda scroll_tmp
    cmp ppu_tmp
    bcs @done
    inc scroll_tmp
    jmp @row
@done:
    jsr zmem_wram_text_off
    jsr begin_nt_resync
    rts
.endproc

.proc text_split_window
    ; A = lines in upper window (V5: do not clear; appearance unchanged)
    cmp #15
    bcc @ok
    lda #1
@ok:
    sta win_split
    ; Spec: if main cursor is no longer in main, move to main origin
    lda win_cur
    bne @ret
    lda cursor_row
    cmp win_split
    bcs @ret
    lda #0
    sta cursor_col
    sta win0_col
    lda win_split
    sta cursor_row
    sta win0_row
@ret:
    rts
.endproc

.proc text_set_window
    ; A = 0 main / 1 upper
    ; Save the cursor of the window we are leaving, then select.
    tax
    lda win_cur
    bne @from_u
    lda cursor_col
    sta win0_col
    lda cursor_row
    sta win0_row
    jmp @sel
@from_u:
    lda cursor_col
    sta win1_col
    lda cursor_row
    sta win1_row
@sel:
    stx win_cur
    txa
    bne @to_u
    ; Restore lower-window cursor (do NOT home)
    lda win0_col
    sta cursor_col
    lda win0_row
    ; If split moved under the cursor, clamp into main
    cmp win_split
    bcs @rok
    lda win_split
@rok:
    sta cursor_row
    rts
@to_u:
    ; Spec: selecting upper resets cursor to top-left.
    ; Clear upper so status redraws don't leave leftover main text.
    lda win_split
    beq @uhome
    lda #0
    ldx win_split
    dex
    jsr text_erase_rows
@uhome:
    lda #0
    sta cursor_col
    sta cursor_row
    sta win1_col
    sta win1_row
    rts
.endproc

.proc text_erase_window
    ; A = window: 0 main, 1 upper, $FF all(+unsplit), $FE all
    ; Spec: erasing window 0/1 moves THAT window's cursor to top-left
    ; but does not change which window is selected (-1 selects lower).
    cmp #$FF
    beq @all_unsplit
    cmp #$FE
    beq @all
    cmp #1
    beq @upper
    ; main
    lda win_split
    ldx #SCREEN_ROWS-1
    jsr text_erase_rows
    lda #0
    sta win0_col
    lda win_split
    sta win0_row
    lda win_cur
    bne @ret
    lda #0
    sta cursor_col
    lda win_split
    sta cursor_row
    rts
@upper:
    lda win_split
    beq @ret
    lda #0
    ldx win_split
    dex
    jsr text_erase_rows
    lda #0
    sta win1_col
    sta win1_row
    lda win_cur
    beq @ret
    lda #0
    sta cursor_col
    sta cursor_row
    rts
@all_unsplit:
    lda #0
    sta win_split
@all:
    lda #0
    ldx #SCREEN_ROWS-1
    jsr text_erase_rows
    lda #0
    sta win_cur
    sta win0_col
    sta win0_row
    sta win1_col
    sta win1_row
    sta cursor_col
    sta cursor_row
@ret:
    rts
.endproc

.proc vq_push
    ; Ring buffer: if full, wait one frame for NMI to drain (no blanking).
    ; Before NMI is live, fall back to progressive mirror resync.
@retry:
    ldy vq_head
    iny
    cpy #VQ_MAX
    bcc @nh
    ldy #0
@nh:
    cpy vq_tail
    bne @space
    lda text_nmi_ok
    beq @boot
    lda frame_count
@wait:
    cmp frame_count
    beq @wait
    jmp @retry
@boot:
    jmp begin_nt_resync
@space:
    ldy vq_head
    lda tile_off_lo
    sta vq_lo,y
    lda tile_off_hi
    sta vq_hi,y
    lda tile_value
    sta vq_tile,y
    iny
    cpy #VQ_MAX
    bcc @store
    ldy #0
@store:
    sty vq_head
    rts
.endproc

; Update WRAM nametable mirror. PPU catch-up is VQ and/or progressive
; NMI resync — never a multi-frame PPUMASK blank copy.
.proc store_mirror_tile
    sta tile_value
    ; Main window must never draw into the status rows
    lda win_cur
    bne @pos
    lda cursor_row
    cmp win_split
    bcs @pos
    lda win_split
    sta cursor_row
    sta win0_row
@pos:
    lda cursor_row
    jsr row_to_tile_off
    lda tile_off_lo
    clc
    adc cursor_col
    sta tile_off_lo
    bcc :+
    inc tile_off_hi
:
    jsr zmem_wram_text_on
    lda #<nt_mirror
    clc
    adc tile_off_lo
    sta mirror_ptr
    lda #>nt_mirror
    adc tile_off_hi
    sta mirror_ptr+1
    ldy #0
    lda tile_value
    sta (mirror_ptr),y
    jsr zmem_wram_text_off
    ; While a full resync is streaming, skip VQ (mirror is truth).
    lda nt_resync
    bne @dirty
    jsr vq_push
@dirty:
    lda #1
    sta text_dirty
    rts
.endproc

.proc text_put_char
    cmp #$0D
    beq @nl
    cmp #$08
    beq @bs
    cmp #$20
    bcc @done
    cmp #'a'
    bcc @store
    cmp #'z'+1
    bcs @store
    sec
    sbc #$20
@store:
    ; Clip (don't wrap) in the upper/status window — we claim width 40
    ; in the header so Zork runs, but only have 32 NES columns.
    ; A must remain the glyph until store_mirror_tile.
    ldx cursor_col
    cpx #SCREEN_COLS
    bcs @done
    jsr store_mirror_tile
    inc cursor_col
    ; keep saved cursor current for window switches
    lda win_cur
    bne @su
    lda cursor_col
    sta win0_col
    lda cursor_row
    sta win0_row
    jmp @wrap
@su:
    lda cursor_col
    sta win1_col
    lda cursor_row
    sta win1_row
@wrap:
    lda cursor_col
    cmp #SCREEN_COLS
    bcc @done
    lda win_cur
    bne @done                 ; upper: clip
    jsr text_newline
@done:
    rts
@nl:
    jmp text_newline
@bs:
    lda cursor_col
    beq @done
    dec cursor_col
    lda #' '
    jsr store_mirror_tile
    rts
.endproc

.proc text_put_str
    ldy #0
@loop:
    lda (str_ptr),y
    beq @done
    sty ppu_tmp
    jsr text_put_char
    ldy ppu_tmp
    iny
    bne @loop
@done:
    rts
.endproc

.proc text_flush_all
    ; Must not run with NMI touching PPUADDR
    php
    sei
    jsr zmem_wram_text_on
    bit PPUSTATUS
    lda #$20
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldx #0
@p0:
    lda nt_mirror,x
    sta PPUDATA
    inx
    bne @p0
@p1:
    lda nt_mirror+$100,x
    sta PPUDATA
    inx
    bne @p1
@p2:
    lda nt_mirror+$200,x
    sta PPUDATA
    inx
    bne @p2
@p3:
    lda nt_mirror+$300,x
    sta PPUDATA
    inx
    bne @p3
    jsr zmem_wram_text_off
    lda #0
    sta text_dirty
    sta vq_head
    sta vq_tail
    plp
    rts
.endproc

; NMI: drain VQ only. Do NOT bank WRAM here — MMC1 CHR/WRAM serial
; writes racing the main thread's PRG banking corrupt fetches (random
; TRAP OP). Scroll/clear resync runs on the main thread instead.
.proc text_flush_nmi
    lda vq_tail
    cmp vq_head
    beq @clean
    bit PPUSTATUS
    ldx #FLUSH_PER_NMI
@more:
    lda vq_tail
    cmp vq_head
    beq @vq_empty
    tay
    lda vq_hi,y
    ora #$20
    sta PPUADDR
    lda vq_lo,y
    sta PPUADDR
    lda vq_tile,y
    sta PPUDATA
    iny
    cpy #VQ_MAX
    bcc @nt
    ldy #0
@nt:
    sty vq_tail
    dex
    bne @more
    rts
@vq_empty:
@clean:
    lda #0
    sta text_dirty
    rts
.endproc

; Main-thread catch-up for scroll/clear (nt_resync). Brief blank — only
; when the whole mirror must replace the nametable. Normal printing uses
; VQ and never enters here.
.proc text_flush_frame
    lda nt_resync
    beq @ret
    php
    sei
    lda #0
    sta PPUMASK
    bit PPUSTATUS
    jsr zmem_wram_text_on
    lda #$20
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldx #0
@p0:
    lda nt_mirror,x
    sta PPUDATA
    inx
    bne @p0
@p1:
    lda nt_mirror+$100,x
    sta PPUDATA
    inx
    bne @p1
@p2:
    lda nt_mirror+$200,x
    sta PPUDATA
    inx
    bne @p2
@p3:
    lda nt_mirror+$300,x
    sta PPUDATA
    inx
    bne @p3
    jsr zmem_wram_text_off
    lda #0
    sta nt_resync
    sta nt_flush_lo
    sta nt_flush_hi
    sta text_dirty
    sta vq_head
    sta vq_tail
    bit PPUSTATUS
    lda #PPUCTRL_NMI
    sta PPUCTRL
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda #PPUMASK_ON
    sta PPUMASK
    plp
@ret:
    rts
.endproc
