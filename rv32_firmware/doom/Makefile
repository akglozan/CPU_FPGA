# rv32_firmware/doom/Makefile -- CPU_FPGA Phase 5.2 (bare-metal Doom port)
#
# Builds doomgeneric (linuxdoom-1.10 lineage, see docs/README.md Phase 5.2)
# for this SoC: rv32im/ilp32, no OS, WAD read straight out of SDRAM
# (w_file_mem.c), frame presentation into the VGA framebuffer
# (doomgeneric_soc.c). Produces build/doom_firmware.bin -- copy that to
# the SD card as FIRMWARE.BIN in place of the existing test firmware
# (rv32_firmware/build/firmware.bin) to boot Doom instead.
#
# PREFIX matches rv32_firmware/Makefile's convention (MSYS2 toolchain on
# Windows). Override on the command line to point at a different
# toolchain, e.g. for a sanity-check build with a Linux-hosted
# bare-metal RISC-V GCC:
#   make PREFIX=/path/to/riscv-none-elf-

PREFIX  ?= C:/msys64/ucrt64/bin/riscv64-unknown-elf-
CC      = $(PREFIX)gcc
OBJDUMP = $(PREFIX)objdump
OBJCOPY = $(PREFIX)objcopy
SIZE    = $(PREFIX)size

BSP_DIR   = ../bsp
SRC_DIR   = src
BUILD_DIR = build

# -ffreestanding + -nostartfiles (not -nostdlib!): we supply our own
# _start (crt0.s) and want newlib-nano's libc/libm linked in for
# string.h/printf, just not its own startup code or syscalls -- those
# come from soc_syscalls.c. --specs=nosys.specs supplies weak
# fallback stubs (return failure) for any syscall newlib pulls in
# that soc_syscalls.c doesn't override; our strong definitions there
# win over these for the ones we actually care about (_write, _sbrk,
# _exit).
CFLAGS  = -march=rv32im -mabi=ilp32 -O2 -g \
          -ffreestanding -nostartfiles \
          --specs=nano.specs --specs=nosys.specs \
          -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200 \
          -I$(SRC_DIR) -I$(BSP_DIR) \
          -Wall -Wno-unused-but-set-variable \
          -ffunction-sections -fdata-sections

LDFLAGS = -Wl,--gc-sections -Wl,-Map,$(BUILD_DIR)/doom_firmware.map

# -l:libm.a (not -lm): nano.specs rewrites a bare -lm to -lm_nano, and
# some toolchain packagings (confirmed on a real MSYS2
# riscv64-unknown-elf-gcc 15.1.0 install, 2026-08-28) ship libc_nano.a
# but not libm_nano.a, which fails the link with "cannot find
# -lm_nano". Naming the file directly sidesteps that spec-substitution
# rule entirely -- verified this produces the identical binary size as
# a toolchain that does have libm_nano.a (--gc-sections strips the
# unused difference away regardless).
LIBS    = -l:libm.a -lc -lgcc

SRCS_S  = $(BSP_DIR)/crt0.s
SRCS_C  = $(wildcard $(SRC_DIR)/*.c)

OBJS    = $(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%.o,$(SRCS_C)) \
          $(BUILD_DIR)/crt0.o

FW_LD   = $(BSP_DIR)/linker_sdram.ld
FW_ELF  = $(BUILD_DIR)/doom_firmware.elf

.PHONY: all clean size

all: $(BUILD_DIR)/doom_firmware.bin $(BUILD_DIR)/doom_firmware.dis size

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/crt0.o: $(BSP_DIR)/crt0.s | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(FW_ELF): $(OBJS)
	$(CC) $(CFLAGS) -T $(FW_LD) $(LDFLAGS) $(OBJS) $(LIBS) -o $@

$(BUILD_DIR)/doom_firmware.dis: $(FW_ELF)
	$(OBJDUMP) -d $< > $@

$(BUILD_DIR)/doom_firmware.bin: $(FW_ELF)
	$(OBJCOPY) -O binary $< $@

size: $(FW_ELF)
	@$(SIZE) $(FW_ELF)

clean:
	rm -rf $(BUILD_DIR)
