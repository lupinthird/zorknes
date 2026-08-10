.include "nes.inc"

.import zmem_wram_text_on, zmem_wram_text_off
.import mmc1_set_prg
.import font_chr
.import z_word_reset
.importzp frame_count
.export ppu_clear_nt, ppu_load_font, text_clear, text_put_str, text_put_char
.export text_flush_all, text_flush_nmi, text_flush_frame, text_newline, text_home
.export text_clear_tile0, text_set_cursor, text_set_cursor_z
.export text_split_window, text_set_window, text_erase_window, text_erase_line
.export text_poke_xy, text_capture_vram
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
; Mapped when WRAM bank 1 is selected (WRAM_BANK_TEXT).
; Lives after the live dynamic image in this bank (zaddrs $2000–$3B3D).
; Must NOT share banks 2–3 with the battery save slot.
.res NT_MIRROR_OFF
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
    jsr z_word_reset
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

; Copy live PPU nametable → WRAM mirror (after SAVE overwrites bank 2).
.proc text_capture_vram
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
    lda PPUDATA                 ; drop buffered read
    ldx #0
@p0:
    lda PPUDATA
    sta nt_mirror,x
    inx
    bne @p0
@p1:
    lda PPUDATA
    sta nt_mirror+$100,x
    inx
    bne @p1
@p2:
    lda PPUDATA
    sta nt_mirror+$200,x
    inx
    bne @p2
@p3:
    lda PPUDATA
    sta nt_mirror+$300,x
    inx
    bne @p3
    jsr zmem_wram_text_off
    lda #0
    sta vq_head
    sta vq_tail
    sta nt_resync
    sta text_dirty
    bit PPUSTATUS
    lda #PPUCTRL_NMI
    sta PPUCTRL
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda #PPUMASK_ON
    sta PPUMASK
    plp
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
    cmp #STORY_ROWS
    bcc @rok
    lda #STORY_ROWS-1
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

; Z-machine set_cursor: A=col 1-based, X=line 1-based in current window.
; V4/V5: no effect when the lower window is selected.
.proc text_set_cursor_z
    ldy win_cur
    beq @ret

    pha
    txa
    pha
    jsr text_ensure_split1
    pla
    tax
    cpx win_split
    beq @rest_col
    bcc @rest_col
    txa
    pha
    jsr text_split_window
    pla
    tax
@rest_col:
    pla

    cmp #0
    bne @c
    lda #1
@c:
    sec
    sbc #1
    cmp #SCREEN_COLS
    bcc @col_ok
    lda #SCREEN_COLS-1
@col_ok:
    sta ppu_tmp
    txa
    bne @l
    ldx #1
@l:
    dex
    cpx win_split
    bcc @go
    ldx win_split
    beq @go
    dex
@go:
    lda ppu_tmp
    jmp text_set_cursor
@ret:
    rts
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
    cmp #STORY_ROWS
    bcc @ok
    jsr text_scroll_main
    lda #STORY_ROWS-1
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

; Scroll main window (rows win_split..STORY_ROWS-1) up one line; clear bottom story row.
.proc text_scroll_main
    jsr zmem_wram_text_on
    lda win_split
    sta scroll_tmp
@rows:
    lda scroll_tmp
    cmp #STORY_ROWS-1
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
    ; clear last story row (STORY_ROWS-1); leave HUD row alone
    lda #STORY_ROWS-1
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

; Erase from cursor_col through end of cursor_row (Z erase_line value=1).
; Also used as the building block when games clear by printing spaces —
; keeping the mirror row consistent avoids prefix ghosts.
.proc text_erase_line
    jsr zmem_wram_text_on
    lda cursor_row
    jsr row_to_tile_off
    lda #<nt_mirror
    clc
    adc tile_off_lo
    sta mirror_ptr
    lda #>nt_mirror
    adc tile_off_hi
    sta mirror_ptr+1
    ldy cursor_col
    lda #' '
@loop:
    cpy #SCREEN_COLS
    bcs @done
    sta (mirror_ptr),y
    iny
    bne @loop
@done:
    jsr zmem_wram_text_off
    jsr begin_nt_resync
    rts
.endproc

; A = glyph, X = column (0..31), Y = row (0..29).
; Writes one nametable tile without moving the text cursor or wrapping.
.proc text_poke_xy
    cmp #'a'
    bcc @ch
    cmp #'z'+1
    bcs @ch
    sec
    sbc #$20
@ch:
    sta tile_value
    stx ppu_tmp                 ; column
    tya
    jsr row_to_tile_off
    lda tile_off_lo
    clc
    adc ppu_tmp
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
    lda nt_resync
    bne @dirty
    jsr vq_push
@dirty:
    lda #1
    sta text_dirty
    rts
.endproc

.proc text_split_window
    ; A = lines in upper window.
    ; Never fully unsplit on NES: Solid Gold draws status then split(0),
    ; which would let main text clobber the status row. Keep ≥1 line.
    ; Large splits (HINT uses screen_h-1 ≈ 29) must be allowed — an older
    ; clamp of ≥15→1 collapsed the Invisiclues UI and wiped lines on CURSET.
    cmp #0
    bne @nz
    lda #1
@nz:
    cmp #STORY_ROWS
    bcc @ok
    lda #STORY_ROWS-1
@ok:
    sta ppu_tmp                 ; requested split
    cmp win_split
    beq @same
    bcc @shrink
    ; Growing / creating: clear rows [0 .. new_split)
    lda ppu_tmp
    beq @store
    lda #0
    ldx ppu_tmp
    dex
    jsr text_erase_rows
    jmp @store
@shrink:
@same:
@store:
    lda ppu_tmp
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

; Ensure upper window exists (Solid Gold may set_window/set_cursor while
; split is still 0; without a split, main text overwrites the status row).
.proc text_ensure_split1
    lda win_split
    bne @ret
    lda #1
    jmp text_split_window
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
    ; Spec: selecting upper resets cursor to top-left (does not clear).
    txa
    pha
    jsr text_ensure_split1
    pla
    tax
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
    ldx #STORY_ROWS-1
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
    ; Spec: unsplit. On NES keep a 1-line split so the status row
    ; stays reserved (Solid Gold redraws status after this).
    lda #1
    sta win_split
@all:
    lda #0
    ldx #STORY_ROWS-1
    jsr text_erase_rows
    lda #0
    sta win_cur
    sta win0_col
    sta win1_col
    sta win1_row
    sta cursor_col
    ; Main origin is below the status split — not row 0
    lda win_split
    sta win0_row
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
    ; Main window must never draw into the status rows or HUD row
    lda win_cur
    bne @pos
    lda cursor_row
    cmp win_split
    bcs @in_main
    lda win_split
    sta cursor_row
    sta win0_row
@in_main:
    lda cursor_row
    cmp #STORY_ROWS
    bcc @pos
    lda #STORY_ROWS-1
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
    ; Clip (don't wrap) in the upper/status window — header claims
    ; Z_HDR_COLS but we only have SCREEN_COLS of tiles.
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
    bne @uclip                ; upper: stay on last visible column
    jsr text_newline
@done:
    rts
@uclip:
    lda #SCREEN_COLS-1
    sta cursor_col
    sta win1_col
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
