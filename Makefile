# NES Zork I — ca65 / cl65
# Requires GNU Make, Python 3, and cc65 (ca65/cl65).
#
#   make
#   make CC65=/path/to/cc65/bin
#   make PYTHON=python3
#
# Windows users can keep using .\build.ps1 (copies the ROM into Mesen).

ifeq ($(OS),Windows_NT)
  CC65   ?= C:/cc65/bin
  PYTHON ?= python
else
  PYTHON ?= python3
endif

ifdef CC65
  CA65 ?= $(CC65)/ca65
  CL65 ?= $(CC65)/cl65
else
  CA65 ?= ca65
  CL65 ?= cl65
endif

CFG      = cfg/sxrom.cfg
ROM      = build/neszork.nes
STORY_Z5 = story/zork1.z5
STORY_STAMP = build/story_banks/.stamp

# Same order as build.ps1
SRCS = header story story_font mmc1 palette pads sfx \
       keyboard zmem ppu_text title zvm zdecode zops ztoken zsave pad_ui nmi main
OBJ  = $(addprefix build/,$(addsuffix .o,$(SRCS)))

MESEN  ?= C:/Mesen/Mesen.exe
ROMDIR ?= C:/Mesen/ROMs

.PHONY: all clean mesen

all: $(ROM)

build:
	mkdir -p build

$(STORY_STAMP): $(STORY_Z5) scripts/split_story.py
	mkdir -p build/story_banks
	$(PYTHON) scripts/split_story.py
	touch $@

build/%.o: src/%.s | build
	$(CA65) -g -I src -o $@ $<

build/story.o: $(STORY_STAMP)
build/story_font.o: $(STORY_STAMP) chr/zork_font.chr chr/logo_tiles.chr
build/title.o: nam/zorklogont.s

$(ROM): $(OBJ) $(CFG)
	$(CL65) -t none -C $(CFG) -o $@ -Ln build/neszork.lbl -vm -m build/neszork.map $(OBJ)

mesen: $(ROM)
	cp $(ROM) $(ROMDIR)/neszork.nes
	$(MESEN) $(ROMDIR)/neszork.nes

clean:
	rm -rf build
