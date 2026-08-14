PREFIX ?= C:/msys64/ucrt64/bin/riscv64-unknown-elf-
CC      = $(PREFIX)gcc
OBJDUMP = $(PREFIX)objdump
OBJCOPY = $(PREFIX)objcopy

CFLAGS  = -march=rv32im -mabi=ilp32 -O2 -nostdlib -Wall
LDFLAGS = -T bsp/linker.ld

BUILD_DIR = build
BSP_DIR   = bsp
SRC_DIR   = src

SRCS      = $(BSP_DIR)/crt0.s $(SRC_DIR)/main.c
TARGET    = $(BUILD_DIR)/firmware

# Output hex destinations for root and ModelSim simulation
HEX_ROOT  = ../boot_bram.hex
HEX_SIM   = ../sim/boot_bram.hex

.PHONY: all clean

all: $(BUILD_DIR) $(TARGET).hex $(TARGET).bin $(TARGET).dis
	@echo "=========================================="
	@echo "Firmware build successful."
	@echo "Generated 32-bit raw hex for BRAM."
	@echo "=========================================="

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(TARGET).elf: $(SRCS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRCS) -o $@

$(TARGET).dis: $(TARGET).elf
	$(OBJDUMP) -d $< > $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

# Convert binary to 32-bit little-endian hex words (1 word per line)
$(TARGET).hex: $(TARGET).bin
	python3 -c "import binascii; f=open('$<','rb').read(); [print(binascii.hexlify(f[i:i+4][::-1]).decode('ascii')) for i in range(0, len(f), 4)]" > $@
	cp $@ $(HEX_ROOT)
	cp $@ $(HEX_SIM)

clean:
	rm -rf $(BUILD_DIR) $(HEX_ROOT) $(HEX_SIM)