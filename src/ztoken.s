; Z-machine V5 tokenise / dictionary lookup
.include "nes.inc"
.include "zmachine.inc"

.import zmem_loadb, zmem_storeb, zmem_loadw, zmem_loadb_phys
.importzp z_addr, z_phys, z_ops_lo, z_ops_hi, z_opcount, z_tmpw, z_i
.export z_tokenise, z_op_tokenise
.exportzp tk_text, tk_parse, tk_dict, tk_flag
.exportzp tk_enc, tk_found, tk_elen, tk_nent, tk_dbase, tk_nwords, tk_wlen, tk_wstart, tk_tlen, tk_zc, tk_dict, tk_nsep

.segment "ZEROPAGE"
tk_text:      .res 2
tk_parse:     .res 2
tk_dict:      .res 2
tk_flag:      .res 1
tk_sep0:      .res 1
tk_sep1:      .res 1
tk_sep2:      .res 1
tk_nsep:      .res 1
tk_elen:      .res 1
tk_nent:      .res 2
tk_dbase:     .res 2
tk_maxw:      .res 1
tk_nwords:    .res 1
tk_tlen:      .res 1
tk_pos:       .res 1
tk_wstart:    .res 1
tk_wlen:      .res 1
tk_enc:       .res 6
tk_zc:        .res 9
tk_zi:        .res 1
tk_lo:        .res 2
tk_hi:        .res 2
tk_found:     .res 2
tk_ch:        .res 1
tk_cmp:       .res 1

.segment "CODE"

; VAR:251 tokenise text parse [dictionary] [flag]
.proc z_op_tokenise
    lda z_ops_lo
    ldx z_ops_hi
    sta tk_text
    stx tk_text+1
    lda z_ops_lo+1
    ldx z_ops_hi+1
    sta tk_parse
    stx tk_parse+1
    lda #0
    sta tk_dict
    sta tk_dict+1
    sta tk_flag
    lda z_opcount
    cmp #3
    bcc @go
    lda z_ops_lo+2
    ldx z_ops_hi+2
    sta tk_dict
    stx tk_dict+1
    lda z_opcount
    cmp #4
    bcc @go
    lda z_ops_lo+3
    sta tk_flag
@go:
    jmp z_tokenise
.endproc

; Tokenise text buffer into parse buffer using dictionary at tk_dict
; (0 = header dictionary). tk_flag: if set, leave unknown slots unchanged.
.proc z_tokenise
    ; resolve dictionary
    lda tk_dict
    ora tk_dict+1
    bne @have
    lda #$08
    sta z_phys
    lda #0
    sta z_phys+1
    sta z_phys+2
    jsr zmem_loadb_phys
    sta tk_dict+1
    lda #$09
    sta z_phys
    jsr zmem_loadb_phys
    sta tk_dict
@have:
    ; header: nsep, seps, elen, nent
    lda tk_dict
    sta z_addr
    lda tk_dict+1
    sta z_addr+1
    jsr zmem_loadb
    sta tk_nsep
    ; seps (up to 3 used)
    lda #0
    sta tk_sep0
    sta tk_sep1
    sta tk_sep2
    lda tk_nsep
    beq @noseps
    ; sep0 at dict+1
    lda tk_dict
    clc
    adc #1
    sta z_addr
    lda tk_dict+1
    adc #0
    sta z_addr+1
    jsr zmem_loadb
    sta tk_sep0
    lda tk_nsep
    cmp #2
    bcc @gotseps
    lda z_addr
    clc
    adc #1
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadb
    sta tk_sep1
    lda tk_nsep
    cmp #3
    bcc @gotseps
    lda z_addr
    clc
    adc #1
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jsr zmem_loadb
    sta tk_sep2
@gotseps:
@noseps:
    ; entry length at dict+1+nsep
    lda #1
    clc
    adc tk_nsep
    clc
    adc tk_dict
    sta z_addr
    lda tk_dict+1
    adc #0
    sta z_addr+1
    jsr zmem_loadb
    sta tk_elen
    ; entry count at dict+2+nsep
    lda #2
    clc
    adc tk_nsep
    clc
    adc tk_dict
    sta z_addr
    lda tk_dict+1
    adc #0
    sta z_addr+1
    jsr zmem_loadw
    sta tk_nent
    stx tk_nent+1
    ; base = dict+4+nsep
    lda #4
    clc
    adc tk_nsep
    clc
    adc tk_dict
    sta tk_dbase
    lda tk_dict+1
    adc #0
    sta tk_dbase+1

    ; parse max words
    lda tk_parse
    sta z_addr
    lda tk_parse+1
    sta z_addr+1
    jsr zmem_loadb
    sta tk_maxw
    lda #0
    sta tk_nwords

    ; text length (V5)
    lda tk_text
    clc
    adc #1
    sta z_addr
    lda tk_text+1
    adc #0
    sta z_addr+1
    jsr zmem_loadb
    sta tk_tlen

    lda #0
    sta tk_pos
@scan:
    lda tk_pos
    cmp tk_tlen
    bcs @done
    jsr tk_getchar
    ; skip spaces
    cmp #' '
    bne @tok
    inc tk_pos
    jmp @scan
@tok:
    ; separator alone?
    jsr tk_is_sep
    bcc @word
    ; single-char separator word
    lda tk_pos
    sta tk_wstart
    lda #1
    sta tk_wlen
    inc tk_pos
    jsr tk_add_word
    jmp @scan
@word:
    lda tk_pos
    sta tk_wstart
@wloop:
    lda tk_pos
    cmp tk_tlen
    bcs @wend
    jsr tk_getchar
    cmp #' '
    beq @wend
    jsr tk_is_sep
    bcs @wend
    inc tk_pos
    jmp @wloop
@wend:
    lda tk_pos
    sec
    sbc tk_wstart
    sta tk_wlen
    beq @scan
    jsr tk_add_word
    jmp @scan
@done:
    ; parse[1] = word count
    lda tk_parse
    clc
    adc #1
    sta z_addr
    lda tk_parse+1
    adc #0
    sta z_addr+1
    lda tk_nwords
    jmp zmem_storeb
.endproc

; A = char at text[2+tk_pos]
.proc tk_getchar
    clc
    lda tk_text
    adc #2
    sta z_addr
    lda tk_text+1
    adc #0
    sta z_addr+1
    clc
    lda z_addr
    adc tk_pos
    sta z_addr
    lda z_addr+1
    adc #0
    sta z_addr+1
    jmp zmem_loadb
.endproc

; C=1 if A is a word separator
.proc tk_is_sep
    cmp tk_sep0
    beq @yes
    ldx tk_nsep
    cpx #2
    bcc @no
    cmp tk_sep1
    beq @yes
    cpx #3
    bcc @no
    cmp tk_sep2
    beq @yes
@no:
    clc
    rts
@yes:
    sec
    rts
.endproc

.proc tk_add_word
    lda tk_nwords
    cmp tk_maxw
    bcc @ok
    rts
@ok:
    ; Encode clobbers tk_pos (rewinds to wstart, advances ≤9). Save the
    ; scan cursor past the full word so leftovers like ER in SCREWDRIVER
    ; are not re-tokenised as a second word.
    lda tk_pos
    pha
    jsr tk_encode
    jsr tk_lookup
    pla
    sta tk_pos
    ; write parse entry at parse+2+4*nwords
    lda tk_nwords
    asl a
    asl a
    clc
    adc #2
    adc tk_parse
    sta z_addr
    lda tk_parse+1
    adc #0
    sta z_addr+1
    ; if flag set and not found, skip write
    lda tk_flag
    beq @wr
    lda tk_found
    ora tk_found+1
    bne @wr
    jmp @inc
@wr:
    ; dict addr hi, lo (BE)
    lda tk_found+1
    jsr zmem_storeb
    inc z_addr
    bne :+
    inc z_addr+1
:
    lda tk_found
    jsr zmem_storeb
    inc z_addr
    bne :+
    inc z_addr+1
:
    lda tk_wlen
    jsr zmem_storeb
    inc z_addr
    bne :+
    inc z_addr+1
:
    ; position in text buffer = 2 + wstart (V5)
    lda tk_wstart
    clc
    adc #2
    jsr zmem_storeb
@inc:
    inc tk_nwords
    rts
.endproc

; Encode word → tk_enc (6 bytes, end bit set)
.proc tk_encode
    ldx #0
    lda #5
@pad:
    sta tk_zc,x
    inx
    cpx #9
    bne @pad
    lda #0
    sta tk_zi
    lda tk_wstart
    sta tk_pos
@loop:
    lda tk_zi
    cmp #9
    bcs @pack
    lda tk_pos
    sec
    sbc tk_wstart
    cmp tk_wlen
    bcs @pack
    jsr tk_getchar
    sta tk_ch
    inc tk_pos
    cmp #'A'
    bcc @lo
    cmp #'Z'+1
    bcs @lo
    ora #$20
@lo:
    cmp #'a'
    bcc @sym
    cmp #'z'+1
    bcs @sym
    sec
    sbc #'a'
    clc
    adc #6
    ldx tk_zi
    sta tk_zc,x
    inc tk_zi
    jmp @loop
@sym:
    cmp #' '
    bne @sym2
    ldx tk_zi
    lda #0
    sta tk_zc,x
    inc tk_zi
    jmp @loop
@sym2:
    ldx tk_zi
    cpx #8
    bcs @pack
    lda #5
    sta tk_zc,x
    inc tk_zi
    ; digits and punctuation → A2 zchar 8+
    lda tk_ch
    ldx #0
@find:
    cmp a2enc,x
    beq @got
    inx
    cpx #a2enc_len
    bcc @find
    lda #6                 ; unused esc as filler
    jmp @put
@got:
    txa
    clc
    adc #8
@put:
    ldx tk_zi
    sta tk_zc,x
    inc tk_zi
    jmp @loop
@pack:
    ldx #0
    ldy #0
@pw:
    ; enc[y] = (z0<<2)|(z1>>3); enc[y+1]=(z1<<5)|z2
    lda tk_zc,x
    asl a
    asl a
    sta z_tmpw
    lda tk_zc+1,x
    lsr a
    lsr a
    lsr a
    ora z_tmpw
    sta tk_enc,y
    iny
    lda tk_zc+1,x
    asl a
    asl a
    asl a
    asl a
    asl a
    ora tk_zc+2,x
    sta tk_enc,y
    iny
    inx
    inx
    inx
    cpx #9
    bcc @pw
    lda tk_enc+4
    ora #$80
    sta tk_enc+4
    rts
.endproc

; Linear search tk_enc in dictionary → tk_found (0 if missing)
; (binary search can be restored once encode is proven)
.proc tk_lookup
    lda #0
    sta tk_found
    sta tk_found+1
    lda tk_nent
    ora tk_nent+1
    bne @go
    rts
@go:
    lda tk_dbase
    sta z_addr
    lda tk_dbase+1
    sta z_addr+1
    lda tk_nent
    sta tk_lo
    lda tk_nent+1
    sta tk_lo+1
@loop:
    lda tk_lo
    ora tk_lo+1
    bne @more
    rts
@more:
    ; save entry address
    lda z_addr
    sta tk_hi
    lda z_addr+1
    sta tk_hi+1
    ldy #0
@cmp:
    sty tk_cmp
    jsr zmem_loadb
    ldy tk_cmp
    cmp tk_enc,y
    bne @next
    iny
    cpy #6
    bcs @hit
    inc z_addr
    bne @cmp
    inc z_addr+1
    jmp @cmp
@next:
    ; advance to next entry: hi + elen
    clc
    lda tk_hi
    adc tk_elen
    sta z_addr
    lda tk_hi+1
    adc #0
    sta z_addr+1
    ; dec count
    lda tk_lo
    bne :+
    dec tk_lo+1
:
    dec tk_lo
    jmp @loop
@hit:
    lda tk_hi
    sta tk_found
    lda tk_hi+1
    sta tk_found+1
    rts
.endproc

.segment "RODATA"
; A2 printable for encode (zchar = index+8). Matches a2tab[2..].
a2enc:
    .byte "0123456789.,!?_#'"
    .byte '"'
    .byte "/", $5C, "-:()"
a2enc_len = * - a2enc
