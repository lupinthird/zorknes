# NES Zork I — ca65 / cl65 build



CC65     = C:/cc65/bin

CA65     = $(CC65)/ca65

CL65     = $(CC65)/cl65

MESEN    = C:/Mesen/Mesen.exe

ROMDIR   = C:/Mesen/ROMs



CFG      = cfg/sxrom.cfg

SRC      = src/header.s src/mmc1.s src/palette.s src/pads.s src/sfx.s \

           src/keyboard.s src/ppu_text.s src/nmi.s src/main.s

OBJ      = $(patsubst src/%.s,build/%.o,$(SRC))

ROM      = build/neszork.nes



.PHONY: all clean mesen



all: $(ROM)



build:

	mkdir -p build



build/%.o: src/%.s | build

	$(CA65) -g -I src -o $@ $<



$(ROM): $(OBJ) $(CFG)

	$(CL65) -t none -C $(CFG) -o $@ -Ln build/neszork.lbl -vm -m build/neszork.map $(OBJ)



mesen: $(ROM)

	cp $(ROM) $(ROMDIR)/neszork.nes

	$(MESEN) $(ROMDIR)/neszork.nes



clean:

	rm -f build/*.o build/*.nes build/*.lbl build/*.dbg

