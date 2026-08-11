; Bank 6: story tail (6960 bytes) + font CHR (4 KiB) + logo CHR (4 KiB) + title strings

.export font_chr

.segment "STORY6"
story6_data:
    .incbin "../build/story_banks/story6.bin", 0, 6960
font_chr:
    .incbin "../chr/zork_font.chr"       ; $0000–$0FFF (BG text)
    .incbin "../chr/logo_tiles.chr"  ; $1000–$1FFF (title logo)
    ; Remainder of STORY6: title strings (title.s) then $FF pad from the linker.
