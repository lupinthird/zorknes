.include "nes.inc"
.include "zmachine.inc"

; Gamepad word picker: build z_line_buf via category/word selection.

.export pad_ui_on_aread, pad_ui_poll, pad_ui_reset
.exportzp pad_cat, pad_idx

.import text_put_char, text_newline, text_poke_xy
.import z_aread_commit, z_line_buf
.import z_obj_addr, z_obj_parent, z_obj_child, z_obj_sibling, z_capture_obj_name
.import z_get_var
.import pad_name_buf, pad_name_len
.import zmem_loadb, zmem_loadw
.import sfx_boop
.importzp pad1_pressed
.importzp z_waiting_input, z_line_len, z_ops_lo, z_ops_hi, z_a
.importzp z_addr, z_tmpw
.importzp cursor_col, cursor_row, win_cur
.importzp input_mode

INPUT_MODE_PAD = 1
Z_LINE_MAX = 64
PAD_CAT_VERB = 0
PAD_CAT_ADJ  = 1
PAD_CAT_NOUN = 2
PAD_CAT_PREP = 3
PAD_CAT_ANS  = 4
PAD_CAT_NAV  = 5
PAD_CAT_COUNT = 6
PAD_NOUN_MAX = 32
; Solid Gold: ADVENTURER ("cretin"), not pseudo "you" (21 under IT).
PLAYER_OBJ = 46
; Global table index 107 → Z-var $7B (HERE init = West of House).
GVAR_HERE = $7B
HUD_ROW = 29

.segment "ZEROPAGE"
pad_cat:       .res 1
pad_idx:       .res 1
pad_noun_count:.res 1
pad_aread_arm: .res 1       ; 0 = need on_aread on next wait
pad_tmp:       .res 1
pad_walk:      .res 2       ; current object while walking
pad_room:      .res 2
pad_word_lo:   .res 1
pad_word_hi:   .res 1

.segment "BSS"
pad_noun_lo: .res PAD_NOUN_MAX
pad_noun_hi: .res PAD_NOUN_MAX

.segment "CODE"

.proc pad_ui_reset
    lda #0
    sta pad_aread_arm
    sta pad_cat
    sta pad_idx
    sta pad_noun_count
    rts
.endproc

; Call when z_waiting_input becomes true (once per aread).
.proc pad_ui_on_aread
    lda #0
    sta pad_cat
    sta pad_idx
    jsr pad_rebuild_nouns
    jsr pad_draw_hud
    rts
.endproc

; While waiting for line input — handle pad1_pressed edges.
.proc pad_ui_poll
    lda input_mode
    cmp #INPUT_MODE_PAD
    beq @modeok
    rts
@modeok:
    lda z_waiting_input
    cmp #ZWAIT_AREAD
    beq @go
    lda #0
    sta pad_aread_arm
    rts
@go:
    lda pad_aread_arm
    bne @armed
    lda #1
    sta pad_aread_arm
    jsr pad_ui_on_aread
@armed:
    lda pad1_pressed
    beq @ret
    sta pad_tmp

    lda pad_tmp
    and #PAD_LEFT
    beq @nr
    jsr pad_cat_prev
    jmp @hud
@nr:
    lda pad_tmp
    and #PAD_RIGHT
    beq @nu
    jsr pad_cat_next
    jmp @hud
@nu:
    lda pad_tmp
    and #PAD_UP
    beq @nd
    jsr pad_word_prev
    jmp @hud
@nd:
    lda pad_tmp
    and #PAD_DOWN
    beq @na
    jsr pad_word_next
    jmp @hud
@na:
    lda pad_tmp
    and #PAD_A
    beq @nb
    jsr pad_append_word
    jmp @ret
@nb:
    lda pad_tmp
    and #PAD_B
    beq @ns
    jsr pad_backspace
    jmp @ret
@ns:
    lda pad_tmp
    and #PAD_START
    beq @ret
    jsr pad_submit
@ret:
    rts
@hud:
    jsr sfx_boop
    jsr pad_draw_hud
    rts
.endproc

.proc pad_cat_next
    lda pad_cat
    clc
    adc #1
    cmp #PAD_CAT_COUNT
    bcc @ok
    lda #0
@ok:
    sta pad_cat
    lda #0
    sta pad_idx
    rts
.endproc

.proc pad_cat_prev
    lda pad_cat
    bne @dec
    lda #PAD_CAT_COUNT
@dec:
    sec
    sbc #1
    sta pad_cat
    lda #0
    sta pad_idx
    rts
.endproc

.proc pad_word_next
    jsr pad_cat_count       ; A = count
    sta pad_tmp
    beq @ret
    lda pad_idx
    clc
    adc #1
    cmp pad_tmp
    bcc @ok
    lda #0
@ok:
    sta pad_idx
@ret:
    rts
.endproc

.proc pad_word_prev
    jsr pad_cat_count
    sta pad_tmp
    beq @ret
    lda pad_idx
    bne @dec
    lda pad_tmp
@dec:
    sec
    sbc #1
    sta pad_idx
@ret:
    rts
.endproc

; A = number of words in current category
.proc pad_cat_count
    lda pad_cat
    cmp #PAD_CAT_VERB
    beq @v
    cmp #PAD_CAT_ADJ
    beq @a
    cmp #PAD_CAT_NOUN
    beq @n
    cmp #PAD_CAT_PREP
    beq @p
    cmp #PAD_CAT_ANS
    beq @y
    lda #NAV_COUNT
    rts
@v:
    lda #VERB_COUNT
    rts
@a:
    lda #ADJ_COUNT
    rts
@n:
    lda pad_noun_count
    rts
@p:
    lda #PREP_COUNT
    rts
@y:
    lda #ANS_COUNT
    rts
.endproc

; Resolve current word → pad_word_lo/hi (null-terminated ASCII), C=0 ok / C=1 empty
.proc pad_resolve_word
    lda pad_cat
    cmp #PAD_CAT_NOUN
    beq @noun
    cmp #PAD_CAT_VERB
    beq @verb
    cmp #PAD_CAT_ADJ
    beq @adj
    cmp #PAD_CAT_PREP
    beq @prep
    cmp #PAD_CAT_ANS
    beq @ans
    ; nav
    lda pad_idx
    cmp #NAV_COUNT
    bcs @fail
    asl a
    tax
    lda nav_ptrs,x
    sta pad_word_lo
    lda nav_ptrs+1,x
    sta pad_word_hi
    clc
    rts
@verb:
    lda pad_idx
    cmp #VERB_COUNT
    bcs @fail
    asl a
    tax
    lda verb_ptrs,x
    sta pad_word_lo
    lda verb_ptrs+1,x
    sta pad_word_hi
    clc
    rts
@adj:
    lda pad_idx
    cmp #ADJ_COUNT
    bcs @fail
    asl a
    tax
    lda adj_ptrs,x
    sta pad_word_lo
    lda adj_ptrs+1,x
    sta pad_word_hi
    clc
    rts
@prep:
    lda pad_idx
    cmp #PREP_COUNT
    bcs @fail
    asl a
    tax
    lda prep_ptrs,x
    sta pad_word_lo
    lda prep_ptrs+1,x
    sta pad_word_hi
    clc
    rts
@ans:
    lda pad_idx
    cmp #ANS_COUNT
    bcs @fail
    asl a
    tax
    lda ans_ptrs,x
    sta pad_word_lo
    lda ans_ptrs+1,x
    sta pad_word_hi
    clc
    rts
@noun:
    lda pad_noun_count
    beq @fail
    lda pad_idx
    cmp pad_noun_count
    bcs @fail
    tax
    lda pad_noun_lo,x
    sta z_ops_lo
    lda pad_noun_hi,x
    sta z_ops_hi
    jsr z_capture_obj_name
    jsr pad_last_word_in_name
    ; pad_word points into pad_name_buf
    clc
    rts
@fail:
    sec
    rts
.endproc

; Find last space-separated token in pad_name_buf → pad_word_lo/hi
.proc pad_last_word_in_name
    lda #<pad_name_buf
    sta pad_word_lo
    lda #>pad_name_buf
    sta pad_word_hi
    ldy #0
    ldx #0                  ; start index of current token
@scan:
    lda pad_name_buf,y
    beq @done
    cmp #' '
    bne @nx
    iny
    tya
    tax                     ; next char starts a token
    jmp @scan
@nx:
    iny
    jmp @scan
@done:
    ; word starts at pad_name_buf,x
    clc
    txa
    adc #<pad_name_buf
    sta pad_word_lo
    lda #0
    adc #>pad_name_buf
    sta pad_word_hi
    rts
.endproc

.proc pad_append_word
    jsr pad_resolve_word
    bcs @ret
    jsr sfx_boop
    ldy #0
@copy:
    lda (pad_word_lo),y
    beq @sp
    sta pad_tmp
    lda z_line_len
    cmp #Z_LINE_MAX
    bcs @ret
    tax
    lda pad_tmp
    sta z_line_buf,x
    inc z_line_len
    tya
    pha
    lda pad_tmp
    jsr text_put_char
    pla
    tay
    iny
    jmp @copy
@sp:
    lda z_line_len
    cmp #Z_LINE_MAX
    bcs @ret
    tax
    lda #' '
    sta z_line_buf,x
    inc z_line_len
    jsr text_put_char
@ret:
    rts
.endproc

.proc pad_backspace
    lda z_line_len
    beq @ret
    jsr sfx_boop
    dec z_line_len
    lda #$08
    jsr text_put_char
@ret:
    rts
.endproc

.proc pad_submit
    jsr sfx_boop
    jsr text_newline
    jsr z_aread_commit
    lda #0
    sta pad_aread_arm
    rts
.endproc

; --- Noun list -----------------------------------------------------------
; Visible nouns only: inventory + HERE contents. Skip INVISIBLE.
; Recurse into a container only if OPENBIT, TRANSBIT, or SURFACEBIT.
; Flag numbers are from this Solid Gold z5 (not the German zap defaults).

ATTR_INVISIBLE  = 23
ATTR_SURFACEBIT = 27
ATTR_OPENBIT    = 28
ATTR_TRANSBIT   = 29
; Solid Gold room "GLOBAL" property — local-globals (WINDOW, HOUSE, …).
PROP_GLOBAL     = 37

.proc pad_rebuild_nouns
    lda #0
    sta pad_noun_count
    ; Room from HERE (correct even when boarded in a vehicle).
    ldy #GVAR_HERE
    jsr z_get_var
    sta pad_room
    stx pad_room+1
    ; Inventory: children of adventurer
    lda #<PLAYER_OBJ
    sta z_ops_lo
    lda #>PLAYER_OBJ
    sta z_ops_hi
    jsr pad_walk_visible
    ; Room contents
    lda pad_room
    ora pad_room+1
    beq @veh
    lda pad_room
    sta z_ops_lo
    lda pad_room+1
    sta z_ops_hi
    jsr pad_walk_visible
@veh:
    ; If parent(player) is a vehicle (≠ HERE), include its visible contents.
    lda #<PLAYER_OBJ
    sta z_ops_lo
    lda #>PLAYER_OBJ
    sta z_ops_hi
    jsr z_obj_parent
    lda z_a
    ora z_a+1
    beq @ret
    lda z_a
    cmp pad_room
    bne @diff
    lda z_a+1
    cmp pad_room+1
    beq @ret
@diff:
    lda z_a
    sta z_ops_lo
    lda z_a+1
    sta z_ops_hi
    jsr pad_walk_visible
@ret:
    ; Scenery often lives in the room GLOBAL property, not as children.
    jsr pad_add_room_globals
    rts
.endproc

; Add objects listed in HERE's GLOBAL property (Infocom local-globals).
.proc pad_add_room_globals
    lda pad_room
    ora pad_room+1
    bne @go
    rts
@go:
    lda pad_room
    sta z_ops_lo
    lda pad_room+1
    sta z_ops_hi
    jsr z_obj_addr
    clc
    lda z_addr
    adc #12
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw              ; A=lo X=hi → property table
    sta pad_word_lo
    stx pad_word_hi
    ; Skip short name: text-length byte (words) then 2*len bytes
    sta z_addr
    stx z_addr+1
    jsr zmem_loadb
    asl a
    sta pad_tmp
    clc
    lda pad_word_lo
    adc #1
    sta pad_word_lo
    lda pad_word_hi
    adc #0
    sta pad_word_hi
    clc
    lda pad_word_lo
    adc pad_tmp
    sta pad_word_lo
    lda pad_word_hi
    adc #0
    sta pad_word_hi
@scan:
    lda pad_word_lo
    sta z_addr
    lda pad_word_hi
    sta z_addr+1
    jsr zmem_loadb
    sta pad_tmp                 ; size byte
    bne @scango
    rts
@scango:
    lda pad_tmp
    and #$80
    bne @long
    ; Short form: num in bits 5-0, len 1/2 from bit6
    lda pad_tmp
    and #$3F
    cmp #PROP_GLOBAL
    bne @skip_s
    lda pad_tmp
    and #$40
    beq @s1
    lda #2
    bne @short_data
@s1: lda #1
@short_data:
    sta pad_tmp                 ; length
    clc
    lda pad_word_lo
    adc #1
    sta pad_walk
    lda pad_word_hi
    adc #0
    sta pad_walk+1
    jmp @add_list
@skip_s:
    lda pad_tmp
    and #$40
    beq @ss1
    lda #2
    bne @sadv
@ss1:
    lda #1
@sadv:
    clc
    adc #1                      ; size byte + data
    jmp @advance
@long:
    lda pad_tmp
    and #$3F
    cmp #PROP_GLOBAL
    bne @skip_l
    ; Second size byte = length
    clc
    lda pad_word_lo
    adc #1
    sta z_addr
    lda pad_word_hi
    adc #0
    sta z_addr+1
    jsr zmem_loadb
    and #$3F
    bne @llen
    lda #64
@llen:
    sta pad_tmp
    clc
    lda pad_word_lo
    adc #2
    sta pad_walk
    lda pad_word_hi
    adc #0
    sta pad_walk+1
    jmp @add_list
@skip_l:
    clc
    lda pad_word_lo
    adc #1
    sta z_addr
    lda pad_word_hi
    adc #0
    sta z_addr+1
    jsr zmem_loadb
    and #$3F
    bne @ladv
    lda #64
@ladv:
    clc
    adc #2                      ; two size bytes + data
@advance:
    clc
    adc pad_word_lo
    sta pad_word_lo
    lda pad_word_hi
    adc #0
    sta pad_word_hi
    jmp @scan

; pad_walk → data, pad_tmp → byte length (words of object ids)
@add_list:
@aloop:
    lda pad_tmp
    beq @ret
    cmp #2
    bcc @ret                    ; need at least one word
    lda pad_walk
    sta z_addr
    lda pad_walk+1
    sta z_addr+1
    jsr zmem_loadw              ; A=lo X=hi object number
    sta z_ops_lo
    stx z_ops_hi
    ; Skip 0 and the Infocom trailing "1" sentinel often seen in GLOBAL lists
    ora z_ops_hi
    beq @anext
    lda z_ops_lo
    cmp #1
    bne @aok
    lda z_ops_hi
    beq @anext
@aok:
    jsr pad_try_add_obj
@anext:
    clc
    lda pad_walk
    adc #2
    sta pad_walk
    lda pad_walk+1
    adc #0
    sta pad_walk+1
    lda pad_tmp
    sec
    sbc #2
    sta pad_tmp
    jmp @aloop
@ret:
    rts
.endproc

; Walk visible children of object in z_ops (recursive into open/see-through).
.proc pad_walk_visible
    jsr z_obj_child
    lda z_a
    sta pad_walk
    lda z_a+1
    sta pad_walk+1
@loop:
    lda pad_walk
    ora pad_walk+1
    beq @done
    lda pad_walk
    sta z_ops_lo
    lda pad_walk+1
    sta z_ops_hi
    ; skip invisible (still advance sibling)
    lda #ATTR_INVISIBLE
    jsr pad_test_attr
    bne @next
    jsr pad_try_add_obj
    ; peek inside only if open / transparent / surface
    lda pad_walk
    sta z_ops_lo
    lda pad_walk+1
    sta z_ops_hi
    jsr pad_can_see_inside
    beq @next
    ; recurse: push sibling, walk this object's children, pop sibling
    lda pad_walk
    pha
    lda pad_walk+1
    pha
    lda pad_walk
    sta z_ops_lo
    lda pad_walk+1
    sta z_ops_hi
    jsr pad_walk_visible
    pla
    sta pad_walk+1
    pla
    sta pad_walk
@next:
    lda pad_walk
    sta z_ops_lo
    lda pad_walk+1
    sta z_ops_hi
    jsr z_obj_sibling
    lda z_a
    sta pad_walk
    lda z_a+1
    sta pad_walk+1
    jmp @loop
@done:
    rts
.endproc

; Object in z_ops → A=1 if contents are visible, else 0.
.proc pad_can_see_inside
    lda #ATTR_OPENBIT
    jsr pad_test_attr
    bne @yes
    lda #ATTR_TRANSBIT
    jsr pad_test_attr
    bne @yes
    lda #ATTR_SURFACEBIT
    jsr pad_test_attr
    bne @yes
    lda #0
    rts
@yes:
    lda #1
    rts
.endproc

; Object in z_ops_lo/hi, attr # in A → A≠0 if attribute set.
.proc pad_test_attr
    sta pad_tmp                 ; attribute number
    jsr z_obj_addr
    lda pad_tmp
    lsr a
    lsr a
    lsr a                       ; byte index
    clc
    adc z_addr
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadb
    pha                         ; attribute byte
    lda pad_tmp
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
    sta pad_tmp
    pla
    and pad_tmp                 ; A≠0 if bit set
    rts
.endproc

.proc pad_try_add_obj
    lda z_ops_lo
    ora z_ops_hi
    beq @ret
    ; skip player
    lda z_ops_lo
    cmp #PLAYER_OBJ
    bne @ok
    lda z_ops_hi
    bne @ok
    rts
@ok:
    ldx pad_noun_count
    cpx #PAD_NOUN_MAX
    bcs @ret
    ; skip duplicates
    ldy #0
@dup:
    cpy pad_noun_count
    bcs @add
    lda pad_noun_lo,y
    cmp z_ops_lo
    bne @dn
    lda pad_noun_hi,y
    cmp z_ops_hi
    beq @ret
@dn:
    iny
    jmp @dup
@add:
    lda z_ops_lo
    sta pad_noun_lo,x
    lda z_ops_hi
    sta pad_noun_hi,x
    inx
    stx pad_noun_count
@ret:
    rts
.endproc

; --- HUD (row 29) — poke tiles; never move the text cursor / scroll -----

.proc pad_draw_hud
    ; Clear row without begin_nt_resync (erase_line scrolls/jumps the view).
    ldx #0
@clr:
    txa
    pha
    lda #' '
    ldy #HUD_ROW
    jsr text_poke_xy
    pla
    tax
    inx
    cpx #SCREEN_COLS
    bcc @clr

    ; prefix letter
    lda pad_cat
    cmp #PAD_CAT_VERB
    beq @pv
    cmp #PAD_CAT_ADJ
    beq @pa
    cmp #PAD_CAT_NOUN
    beq @pn
    cmp #PAD_CAT_PREP
    beq @pp
    cmp #PAD_CAT_ANS
    beq @py
    lda #'G'
    jmp @pout
@pv:
    lda #'V'
    jmp @pout
@pa:
    lda #'A'
    jmp @pout
@pn:
    lda #'N'
    jmp @pout
@pp:
    lda #'P'
    jmp @pout
@py:
    lda #'Y'
@pout:
    ldx #0
    ldy #HUD_ROW
    jsr text_poke_xy
    lda #':'
    ldx #1
    ldy #HUD_ROW
    jsr text_poke_xy

    jsr pad_resolve_word
    bcs @empty
    ldy #0
    ldx #2                      ; column
@w:
    lda (pad_word_lo),y
    beq @done
    sta pad_tmp
    tya
    pha
    txa
    pha
    lda pad_tmp
    ldy #HUD_ROW
    jsr text_poke_xy            ; A=char, X=col, Y=row
    pla
    tax
    pla
    tay
    inx
    cpx #SCREEN_COLS
    bcs @done
    iny
    jmp @w
@empty:
    lda #'-'
    ldx #2
    ldy #HUD_ROW
    jsr text_poke_xy
@done:
    rts
.endproc

; --- Word tables ---------------------------------------------------------

.segment "RODATA"

VERB_COUNT = 43
verb_ptrs:
    .word v_look, v_examine, v_take, v_drop, v_put, v_open, v_close, v_read
    .word v_attack, v_kill, v_inv, v_wait, v_again, v_enter, v_exit, v_climb, v_turn
    .word v_move, v_pull, v_push, v_give, v_throw, v_tie, v_untie, v_light
    .word v_extinguish, v_eat, v_drink, v_fill, v_empty, v_say, v_ask, v_tell
    .word v_diagnose, v_score, v_save, v_restore, v_restart, v_quit
    .word v_verbose, v_brief, v_wave, v_break

v_look: .byte "LOOK", 0
v_examine: .byte "EXAMINE", 0
v_take: .byte "TAKE", 0
v_drop: .byte "DROP", 0
v_put: .byte "PUT", 0
v_open: .byte "OPEN", 0
v_close: .byte "CLOSE", 0
v_read: .byte "READ", 0
v_attack: .byte "ATTACK", 0
v_kill: .byte "KILL", 0
v_inv: .byte "INVENTORY", 0
v_wait: .byte "WAIT", 0
v_again: .byte "AGAIN", 0
v_enter: .byte "ENTER", 0
v_exit: .byte "EXIT", 0
v_climb: .byte "CLIMB", 0
v_turn: .byte "TURN", 0
v_move: .byte "MOVE", 0
v_pull: .byte "PULL", 0
v_push: .byte "PUSH", 0
v_give: .byte "GIVE", 0
v_throw: .byte "THROW", 0
v_tie: .byte "TIE", 0
v_untie: .byte "UNTIE", 0
v_light: .byte "LIGHT", 0
v_extinguish: .byte "EXTINGUISH", 0
v_eat: .byte "EAT", 0
v_drink: .byte "DRINK", 0
v_fill: .byte "FILL", 0
v_empty: .byte "EMPTY", 0
v_say: .byte "SAY", 0
v_ask: .byte "ASK", 0
v_tell: .byte "TELL", 0
v_diagnose: .byte "DIAGNOSE", 0
v_score: .byte "SCORE", 0
v_save: .byte "SAVE", 0
v_restore: .byte "RESTORE", 0
v_restart: .byte "RESTART", 0
v_quit: .byte "QUIT", 0
v_verbose: .byte "VERBOSE", 0
v_brief: .byte "BRIEF", 0
v_wave: .byte "WAVE", 0
v_break: .byte "BREAK", 0

ADJ_COUNT = 12
adj_ptrs:
    .word a_brass, a_old, a_small, a_large, a_red, a_blue
    .word a_white, a_black, a_wooden, a_magic, a_burning, a_nasty

a_brass: .byte "BRASS", 0
a_old: .byte "OLD", 0
a_small: .byte "SMALL", 0
a_large: .byte "LARGE", 0
a_red: .byte "RED", 0
a_blue: .byte "BLUE", 0
a_white: .byte "WHITE", 0
a_black: .byte "BLACK", 0
a_wooden: .byte "WOODEN", 0
a_magic: .byte "MAGIC", 0
a_burning: .byte "BURNING", 0
a_nasty: .byte "NASTY", 0

PREP_COUNT = 10
prep_ptrs:
    .word p_with, p_in, p_on, p_from, p_to, p_at, p_out, p_over, p_under, p_about

p_with: .byte "WITH", 0
p_in: .byte "IN", 0
p_on: .byte "ON", 0
p_from: .byte "FROM", 0
p_to: .byte "TO", 0
p_at: .byte "AT", 0
p_out: .byte "OUT", 0
p_over: .byte "OVER", 0
p_under: .byte "UNDER", 0
p_about: .byte "ABOUT", 0

; Finish / YES? prompts (Solid Gold: YES/Y/NO/N/HINT + menu verbs elsewhere)
ANS_COUNT = 5
ans_ptrs:
    .word y_yes, y_no, y_y, y_n, y_hint

y_yes: .byte "YES", 0
y_no: .byte "NO", 0
y_y: .byte "Y", 0
y_n: .byte "N", 0
y_hint: .byte "HINT", 0

NAV_COUNT = 10
nav_ptrs:
    .word n_north, n_nw, n_west, n_sw, n_south, n_se, n_east, n_ne, n_up, n_down

n_north: .byte "NORTH", 0
n_nw: .byte "NORTHWEST", 0
n_west: .byte "WEST", 0
n_sw: .byte "SOUTHWEST", 0
n_south: .byte "SOUTH", 0
n_se: .byte "SOUTHEAST", 0
n_east: .byte "EAST", 0
n_ne: .byte "NORTHEAST", 0
n_up: .byte "UP", 0
n_down: .byte "DOWN", 0
