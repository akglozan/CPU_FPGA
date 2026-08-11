PREFIX  ?= C:/msys64/ucrt64/bin/riscv64-unknown-elf-
CC       = $(PREFIX)gcc
OBJDUMP  = $(PREFIX)objdump
OBJCOPY  = $(PREFIX)objcopy

CFLAGS   = -march=rv32im -mabi=ilp32 -O2 -nostdlib -Wall
# Use Windows-style backslashes for the linker script flag
LDFLAGS  = -T bsp\linker.ld

BUILD_DIR = build
BSP_DIR   = bsp
SRC_DIR   = src

SRCS      = $(BSP_DIR)/crt0.s $(SRC_DIR)/main.c
TARGET    = $(BUILD_DIR)/firmware

.PHONY: all clean

all: $(BUILD_DIR) $(TARGET).hex $(TARGET).bin $(TARGET).dis

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(TARGET).elf: $(SRCS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRCS) -o $@

$(TARGET).dis: $(TARGET).elf
	$(OBJDUMP) -d $< > $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

$(TARGET).hex: $(TARGET).elf
	$(OBJCOPY) -O ihex $< $@

clean:
	rm -rf $(BUILD_DIR)