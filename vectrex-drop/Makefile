LWASM ?= tools/lwtools/lwasm/lwasm
CC ?= cc

.PHONY: all test clean
all: build/vector-drop.bin

build:
	mkdir -p build

build/vector-drop.bin: src/vector-drop.asm scripts/pad_rom.py | build
	$(LWASM) --6809 --format=raw --output=build/vector-drop.raw --list=build/vector-drop.lst --symbol-dump=build/vector-drop.sym $<
	python3 scripts/pad_rom.py build/vector-drop.raw $@

build/vecx-test.so: tests/emulator.c tests/prepare_emulator.py tools/vecx/vecx.c tools/vecx/e6809.c | build
	python3 tests/prepare_emulator.py
	$(CC) -shared -fPIC -O2 -Itools/vecx -o $@ tests/emulator.c

test: all build/vecx-test.so
	python3 tests/test_rom.py

clean:
	rm -rf build
