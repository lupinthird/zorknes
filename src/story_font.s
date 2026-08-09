; Bank 6: story tail (6960 bytes) + font CHR (4 KiB) + logo CHR (4 KiB) + pad

.export font_chr

.segment "STORY6"
story6_data:
    .incbin "../build/story_banks/story6.bin", 0, 6960
font_chr:
    .incbin "../chr/zmac.chr"       ; $0000–$0FFF (BG text)
    .incbin "../chr/logotiles.chr"  ; $1000–$1FFF (title logo)
    .res 16384 - 6960 - 8192, $FF
