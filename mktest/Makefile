ARCH=riscv64-unknown-elf-
CC=$(ARCH)gcc
OBJDUMP=$(ARCH)objdump
CFLAGS=-march=rv64im -O0 -Wno-implicit-int -fPIC
STRIP=$(ARCH)strip

OBJECT_FILES=test

.PHONY: all clean

all: $(OBJECT_FILES)

clean:
	rm -f $(OBJECT_FILES) $(patsubst %,%.s,$(OBJECT_FILES))

%: %.c
	$(CC) $(CFLAGS) -Wl,-Tlinker.script -shared -nostartfiles -o $@ $<
	$(OBJDUMP) -S $@ > $@.s
