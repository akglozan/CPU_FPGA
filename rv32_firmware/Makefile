PREFIX ?= C:/msys64/ucrt64/bin/riscv64-unknown-elf-
CC      = $(PREFIX)gcc
OBJDUMP = $(PREFIX)objdump
OBJCOPY = $(PREFIX)objcopy

CFLAGS  = -march=rv32im -mabi=ilp32 -O2 -nostdlib -Wall

BUILD_DIR = build
BSP_DIR   = bsp
SRC_DIR   = src
SW_DIR    = ../sw

MIF_DEPTH = 1024

# -- BRAM boot stub: jumps to SDRAM, nothing else. Feeds sw/boot_bram.mif,
#    which Quartus bakes into bram_4kb at synthesis time.
STUB_SRCS  = $(BSP_DIR)/boot_stub.s
STUB_LD    = $(BSP_DIR)/linker.ld
STUB_ELF   = $(BUILD_DIR)/boot_stub.elf
MIF_OUT    = $(SW_DIR)/boot_bram.mif
HEX_OUT    = $(SW_DIR)/boot_bram.hex

# -- Real SDRAM-resident program. Feeds build/firmware.bin, which gets
#    copied onto the microSD card as FIRMWARE.BIN for the ESP32 to DMA
#    into SDRAM at 0x8000_0000.
FW_SRCS    = $(BSP_DIR)/crt0.s $(SRC_DIR)/main.c
FW_LD      = $(BSP_DIR)/linker_sdram.ld
FW_ELF     = $(BUILD_DIR)/firmware.elf

.PHONY: all clean

all: $(BUILD_DIR) $(SW_DIR) $(HEX_OUT) $(MIF_OUT) $(BUILD_DIR)/firmware.bin $(BUILD_DIR)/firmware.dis
	@echo "=========================================="
	@echo "Firmware build successful."
	@echo "Wrote $(HEX_OUT)               (BRAM boot stub)"
	@echo "Wrote $(MIF_OUT)               (BRAM boot stub)"
	@echo "Wrote $(BUILD_DIR)/firmware.bin (SDRAM program -- copy to SD card as FIRMWARE.BIN)"
	@echo "=========================================="

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(SW_DIR):
	mkdir -p $(SW_DIR)

$(STUB_ELF): $(STUB_SRCS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -T $(STUB_LD) $(STUB_SRCS) -o $@

$(BUILD_DIR)/firmware.elf: $(FW_SRCS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -T $(FW_LD) $(FW_SRCS) -o $@

$(BUILD_DIR)/firmware.dis: $(BUILD_DIR)/firmware.elf
	$(OBJDUMP) -d $< > $@

$(BUILD_DIR)/firmware.bin: $(BUILD_DIR)/firmware.elf
	$(OBJCOPY) -O binary $< $@

$(HEX_OUT): $(STUB_ELF) | $(SW_DIR)
	$(OBJCOPY) -O binary $< $(BUILD_DIR)/boot_stub.bin
	python3 -c "import binascii; f=open('$(BUILD_DIR)/boot_stub.bin','rb').read(); [print(binascii.hexlify(f[i:i+4][::-1]).decode('ascii')) for i in range(0, len(f), 4)]" > $@

$(MIF_OUT): $(STUB_ELF) | $(SW_DIR)
	$(OBJCOPY) -O binary $< $(BUILD_DIR)/boot_stub.bin
	python3 -c "\
import struct; \
f = open('$(BUILD_DIR)/boot_stub.bin', 'rb').read(); \
depth = $(MIF_DEPTH); \
words = [struct.unpack('<I', f[i:i+4].ljust(4, b'\\x00'))[0] for i in range(0, len(f), 4)]; \
words = (words + [0] * depth)[:depth]; \
lines = ['WIDTH = 32;', 'DEPTH = %d;' % depth, 'ADDRESS_RADIX = HEX;', 'DATA_RADIX = HEX;', '', 'CONTENT BEGIN']; \
lines += ['%03X : %08x;' % (i, w) for i, w in enumerate(words)]; \
lines.append('END;'); \
open('$@', 'w').write('\\n'.join(lines) + '\\n')"

clean:
	rm -rf $(BUILD_DIR) $(HEX_OUT) $(MIF_OUT)

	