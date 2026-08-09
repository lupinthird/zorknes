; Bank 6: story tail (6960 bytes) + font CHR (8192) + pad

.export font_chr

.segment "STORY6"
story6_data:
    .incbin "../build/story_banks/story6.bin", 0, 6960
font_chr:
    .incbin "../chr/zmac.chr"
    .res 16384 - 6960 - 8192, $FF
