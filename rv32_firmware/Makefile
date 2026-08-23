# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Ozan Akgül
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

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

# Memory images. Every generated .hex/.mif in this project lives in sw/,
# and each one is written exactly once -- there is deliberately no copy
# left behind in build/ or sim/. The VHDL refers to these by the paths
# below, relative to the Quartus project directory:
#
#   rtl/memory/bram_4kb.vhd      hex_file default "sw/boot_bram.mif"
#   rtl/rv32im_soc.vhd           hex_file => "sw/boot_bram.mif"
#
# boot_bram.hex currently has no consumer in the design -- it was read
# by rtl/core/Instruction_Memory.vhd, which was dead code and has been
# removed. It is still generated because it is a useful human-readable
# dump of the image for eyeballing and diffing, and costs 693 bytes.
#
# So renaming or relocating anything here means updating those too.
SW_DIR    = ../sw
MIF_OUT   = $(SW_DIR)/boot_bram.mif
HEX_OUT   = $(SW_DIR)/boot_bram.hex
MIF_DEPTH = 1024

.PHONY: all clean

all: $(BUILD_DIR) $(SW_DIR) $(HEX_OUT) $(MIF_OUT) $(TARGET).bin $(TARGET).dis
	@echo "=========================================="
	@echo "Firmware build successful."
	@echo "Wrote $(HEX_OUT)"
	@echo "Wrote $(MIF_OUT)"
	@echo "=========================================="

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(SW_DIR):
	mkdir -p $(SW_DIR)

$(TARGET).elf: $(SRCS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRCS) -o $@

$(TARGET).dis: $(TARGET).elf
	$(OBJDUMP) -d $< > $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

# Convert binary to 32-bit little-endian hex words (1 word per line),
# written straight into sw/ -- no intermediate copy in build/.
$(HEX_OUT): $(TARGET).bin | $(SW_DIR)
	python3 -c "import binascii; f=open('$<','rb').read(); [print(binascii.hexlify(f[i:i+4][::-1]).decode('ascii')) for i in range(0, len(f), 4)]" > $@

# Convert binary to a Quartus Memory Initialization File (.mif). Any bytes
# beyond the program image are zero-padded out to MIF_DEPTH words, and any
# words beyond the raw file length default to zero (i.e. NOP / addi x0,x0,0).
# Written straight into sw/ -- no intermediate copy in build/.
$(MIF_OUT): $(TARGET).bin | $(SW_DIR)
	python3 -c "\
import struct; \
f = open('$<', 'rb').read(); \
depth = $(MIF_DEPTH); \
words = [struct.unpack('<I', f[i:i+4].ljust(4, b'\\x00'))[0] for i in range(0, len(f), 4)]; \
words = (words + [0] * depth)[:depth]; \
lines = ['WIDTH = 32;', 'DEPTH = %d;' % depth, 'ADDRESS_RADIX = HEX;', 'DATA_RADIX = HEX;', '', 'CONTENT BEGIN']; \
lines += ['%03X : %08x;' % (i, w) for i, w in enumerate(words)]; \
lines.append('END;'); \
open('$@', 'w').write('\\n'.join(lines) + '\\n')"

clean:
	rm -rf $(BUILD_DIR) $(HEX_OUT) $(MIF_OUT)