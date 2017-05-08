ARCH=riscv64-unknown-elf-
CC=$(ARCH)gcc
LD=$(ARCH)ld
OBJDUMP=$(ARCH)objdump
CFLAGS=-march=rv64im -O0 -Wno-implicit-int
STRIP=$(ARCH)strip

OBJECT_FILES=test

.PHONY: all clean

all: $(OBJECT_FILES)

clean:
	rm -f $(OBJECT_FILES) $(patsubst %,%.s,$(OBJECT_FILES))

%: %.c
	$(CC) $(CFLAGS) -c $<
	$(LD) -o $@ -Tlinker.script $@.o
	$(OBJDUMP) -S $@ > $@.s
