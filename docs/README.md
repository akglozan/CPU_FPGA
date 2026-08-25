## 📚 Documentation

Full VHDL API documentation (entities, ports, generics) is generated with
Sphinx + sphinx-vhdl and published at:
**[akglozan.github.io/CPU_FPGA](https://akglozan.github.io/CPU_FPGA/)**

The site rebuilds automatically on every push that touches `docs/`, via
[`.github/workflows/docs.yml`](../.github/workflows/docs.yml). To build it
locally: `cd docs && pip install sphinx sphinx-vhdl && make html`, then open
`docs/_build/html/index.html`.

## 📋 Detailed Progress Checklist

### Phase 1: Core CPU Pipeline & Microarchitecture
- [x] **1.1 Instruction Set Architecture (ISA)**
  - [x] Define opcode maps and instruction formats (R, I, S, B, U, J) for RV32I.
  - [x] Specify register layout ($x0$ hardwired to zero, $x1$–$x31$ general-purpose).
- [x] **1.2 Program Counter (PC)**
  - [x] Implement synchronous PC register logic in VHDL.
  - [x] Verify `pc_write` (stall) and `pc_load` (branch/jump) control paths.
- [x] **1.3 Instruction Fetch & Decode**
  - [x] Implement instruction extraction logic for source/destination registers.
  - [x] Add sign-extension logic for all immediate fields.
- [x] **1.4 Register File**
  - [x] Create 32-word $\times$ 32-bit dual-read, single-write register array.
  - [x] Verify asynchronous read and synchronous write operations in simulation.
- [x] **1.5 Arithmetic Logic Unit (ALU)**
  - [x] Implement core operations (`ADD`, `SUB`, `AND`, `OR`, `XOR`, `SLT`, `SLTU`).
  - [x] Implement logical and arithmetic bit shifts (`SLL`, `SRL`, `SRA`).
- [x] **1.6 Phase 1 Verification**
  - [x] Simulate full execution loop in ModelSim with a test assembly sequence.
  - [x] Synthesize in Quartus II targeting `EP4CE6E22C8N` to verify resource usage.

---

### Phase 2: Memory Hierarchy & SDRAM Controller
- [x] **2.1 SDRAM Controller Interface**
  - [x] Implement or port a 16-bit SDRAM controller in VHDL for the 64 Mbit chip.
  - [x] Handle power-up initialization and auto-refresh timing parameters.
  - [x] Verify row activation, read, and write command sequences.
- [x] **2.2 System Interconnect & Memory Map**
  - [x] Build central bus decoder module in VHDL.
  - [x] Map `0x0000_0000`–`0x0000_FFFF` to Internal BRAM (4 KB Bootloader, 64 KB decoded window).
  - [x] Map `0x8000_0000`–`0x87FF_FFFF` to External SDRAM (64 Mbit / 8 MB chip, 128 MB decoded window).
  - [x] Map `0xE000_0000`–`0xE000_FFFF` to Memory-Mapped I/O (MMIO).
- [x] **2.3 Phase 2 Verification**
  - [x] Run physical memory test on hardware to verify SDRAM stability.

---

### Phase 3: ESP32 Co-Processor & Ingestion Link
- [x] **3.1 ESP32 Firmware**
  - [x] Set up MicroSD card initialization via SDMMC/SPI in ESP-IDF/Arduino.
  - [x] Implement binary file parser to open and read `DOOM1.WAD` and code binaries.
- [x] **3.2 FPGA Receiver Interface**
  - [x] Implement high-speed SPI/Parallel Slave receiver module in VHDL.
  - [x] Route incoming bytes directly to SDRAM via DMA bus controller.
- [x] **3.3 Boot Handshaking**
  - [x] Assert FPGA CPU `RESET` line on initial power-up.
  - [x] Stream executable and WAD bytes from ESP32 into FPGA SDRAM.
  - [x] Toggle `BOOT_DONE` signal from ESP32 to release FPGA CPU reset.

---

### Phase 3 Closeout — verified on hardware 2026-08-25

**The link as built.** The ESP32 reads files from the MicroSD card and
streams them to the FPGA over a dedicated SPI link (Mode 0, MSB-first,
1 MHz, on GPIOs separate from the SDMMC pins). Each file is one CS-low
session carrying an 8-byte little-endian header — 4-byte destination
address, then 4-byte length — followed by its payload.
`rtl/memory/spi_slave.vhd` turns the bit stream into bytes;
`rtl/memory/boot_loader.vhd` parses that framing and DMAs the payload
into SDRAM as its own Wishbone master, while the CPU is held in reset and
off the bus. When both files are sent the ESP32 raises `BOOT_DONE`, and
the SoC hands the bus to the CPU and releases it. A full transfer —
`FIRMWARE.BIN` (288 B) to `0x8000_0000` and `DOOM1.WAD` (4,207,819 B) to
`0x8010_0000` — takes roughly 30 s.

**Evidence.** The RV32 core reads back `FW[0] = 0x00001117` (matching the
binary's own first word) and `WAD[0] = 0x44415749` (the `IWAD` magic),
with `BUS_ERR = 0`. Temporary instrumentation confirmed the transfer was
byte-exact — all 4,208,123 bytes received and all 1,052,027 word writes
acknowledged — bit-identical across repeated resets and at both 100 kHz
and 1 MHz. That instrumentation has since been removed; the four-LED boot
progress display in `rv32im_soc.vhd` was kept, since it shows how far the
SPI → `boot_loader` → SDRAM chain got with no instrumentation at all.

**Three real bugs were fixed to get here.**

* `MEM_Stage.vhd` had no load byte/halfword extraction at all — every
  `LB`/`LBU`/`LH`/`LHU` returned the whole bus word unmodified. Latent
  since the beginning: this was the first firmware to do sub-word loads.
* `boot_done` was latched from a 2-cycle synchronizer with no debounce,
  so a transient released the CPU mid-transfer and the "missing bytes"
  it produced were really a counter being read while the ESP32 was still
  sending. It now requires ~1.3 ms continuously high, and the ESP32
  drives the pin low at the top of `setup()` rather than leaving it
  floating through SD-card init.
* `sdram_controller.vhd` drove a 9-bit column address at a 256-column
  part (Winbond W9864G6KH-6), discarding byte-address bit 9 so that every
  pair of addresses 512 B apart aliased onto the same cells — corrupting
  exactly half of every transfer larger than 512 B.

**On that last one.** `sim/sdram_model.vhd` had encoded the *same* wrong
512-column assumption as the controller, so the simulation reproduced the
design's own mistake and could never fail on it — `tb_boot_path` passed
cleanly against genuinely broken RTL. Both halves are now fixed: the
model decodes 8 column bits like the real part, and `sim/tb_boot_path.vhd`
writes two files across the 512 B alias stride. That test has been
observed **failing** on the deliberately reintroduced bug and passing on
the fix, so its teeth are verified rather than assumed.

**Known limitation, deferred to Phase 5.** Instruction fetch is still
hardwired to BRAM (`rv32im_soc.vhd` drives `bram_4kb`'s port A from `pc`
directly), so the CPU cannot yet *execute* the firmware image it has just
been handed — it can only read it as data. Running code from SDRAM is a
Phase 5 concern.

---

### Phase 4: VGA Framebuffer Engine
> **Status:** Not started. The bus already reserves address space for it —
> `bus_interconnect.vhd` decodes `0xC000_0000`–`0xC007_FFFF` (512 KB window)
> as slave 2 — but no VGA module exists yet: `rv32im_soc.vhd` ties the slot
> off (`s2_ack_i <= '0'`, data/address ports left open), so any access to
> that range currently hangs until the bus watchdog forces a timeout.
- [ ] **4.1 Timing Generator**
  - [ ] Configure ALTPLL in Quartus II to generate a 25 MHz pixel clock.
  - [ ] Implement 640x480 @ 60 Hz VGA synchronization counters (`HSYNC`, `VSYNC`).
- [ ] **4.2 Framebuffer & Palette Conversion**
  - [ ] Reserve a 320x200 pixel region within SDRAM.
  - [ ] Implement $2 \times 2$ pixel-doubling logic for 640x480 output.
  - [ ] Implement 8-bit palette RAM lookup table (LUT) for 256-color output.
  - [ ] Map output signals to board RGB and sync pins.

---

### Phase 5: Software Toolchain & Bare-Metal Doom Porting
- [ ] **5.1 GCC Setup**
  - [ ] Install and configure `riscv32-unknown-elf-gcc` cross-compiler.
  - [ ] Write custom linker script (`linker.ld`) mapping code and data sections to SDRAM.
- [ ] **5.2 Engine Porting**
  - [ ] Strip OS-dependent calls (`malloc`, `printf`, file I/O) from Doom source code.
  - [ ] Redirect `I_ReadFile` calls to memory pointers referencing the SDRAM WAD location.
  - [ ] Redirect frame rendering buffer updates (`I_FinishUpdate`) to MMIO framebuffer address.
- [ ] **5.3 Arithmetic Operations**
  - [ ] Enforce 16.16 fixed-point math operations across the engine.
  - [ ] Add software integer multiplication routines (or hardware `RV32M` multiplier if LE budget allows).

---

### Phase 6: Input Controls & Final Polish
- [ ] **6.1 Input Integration**
  - [ ] Implement GPIO button reading **OR** UART receiver for ESP32 Bluetooth controller packets.
  - [ ] Map input signals to MMIO register address range.
- [ ] **6.2 System Optimization & Closure**
  - [ ] Run Quartus II TimeQuest Timing Analyzer to fix setup/hold violations.
  - [ ] Optimize VHDL code to keep total logic usage strictly under ~5,000 LEs.

## Hardware Schematic

<table width="100%">
  <tr>
    <td align="center" width="50%">
      <strong>CPU_FPGA</strong> &mdash; 5-stage RV32IM pipeline core
      <br>
      <img src="./rtl_schematic.svg?v=3" alt="CPU_FPGA RTL Schematic" width="100%" style="background-color: white; padding: 10px; border-radius: 8px;">
    </td>
    <td align="center" width="50%">
      <strong>rv32im_soc</strong> &mdash; top-level SoC (CPU + memory + peripherals)
      <br>
      <img src="./rtl_schematic_soc.svg?v=1" alt="rv32im_soc RTL Schematic" width="100%" style="background-color: white; padding: 10px; border-radius: 8px;">
    </td>
  </tr>
</table>



## License
This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.