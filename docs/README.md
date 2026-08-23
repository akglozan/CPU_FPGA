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
- [ ] **1.1 Instruction Set Architecture (ISA)**
  - [ ] Define opcode maps and instruction formats (R, I, S, B, U, J) for RV32I.
  - [ ] Specify register layout ($x0$ hardwired to zero, $x1$–$x31$ general-purpose).
- [ ] **1.2 Program Counter (PC)**
  - [ ] Implement synchronous PC register logic in VHDL.
  - [ ] Verify `pc_write` (stall) and `pc_load` (branch/jump) control paths.
- [ ] **1.3 Instruction Fetch & Decode**
  - [ ] Implement instruction extraction logic for source/destination registers.
  - [ ] Add sign-extension logic for all immediate fields.
- [ ] **1.4 Register File**
  - [ ] Create 32-word $\times$ 32-bit dual-read, single-write register array.
  - [ ] Verify asynchronous read and synchronous write operations in simulation.
- [ ] **1.5 Arithmetic Logic Unit (ALU)**
  - [ ] Implement core operations (`ADD`, `SUB`, `AND`, `OR`, `XOR`, `SLT`, `SLTU`).
  - [ ] Implement logical and arithmetic bit shifts (`SLL`, `SRL`, `SRA`).
- [ ] **1.6 Phase 1 Verification**
  - [ ] Simulate full execution loop in ModelSim with a test assembly sequence.
  - [ ] Synthesize in Quartus II targeting `EP4CE6E22C8N` to verify resource usage.

---

### Phase 2: Memory Hierarchy & SDRAM Controller
- [ ] **2.1 SDRAM Controller Interface**
  - [ ] Implement or port a 16-bit SDRAM controller in VHDL for the 64 Mbit chip.
  - [ ] Handle power-up initialization and auto-refresh timing parameters.
  - [ ] Verify row activation, read, and write command sequences.
- [ ] **2.2 System Interconnect & Memory Map**
  - [ ] Build central bus decoder module in VHDL.
  - [ ] Map `0x0000_0000`–`0x0000_3FFF` to Internal BRAM (16 KB Bootloader).
  - [ ] Map `0x8000_0000`–`0x807F_FFFF` to 8 MB External SDRAM.
  - [ ] Map `0xC000_0000`–`0xC000_00FF` to Memory-Mapped I/O (MMIO).
- [ ] **2.3 Phase 2 Verification**
  - [ ] Run physical memory test on hardware to verify SDRAM stability.

---

### Phase 3: ESP32 Co-Processor & Ingestion Link
- [ ] **3.1 ESP32 Firmware**
  - [ ] Set up MicroSD card initialization via SDMMC/SPI in ESP-IDF/Arduino.
  - [ ] Implement binary file parser to open and read `DOOM1.WAD` and code binaries.
- [ ] **3.2 FPGA Receiver Interface**
  - [ ] Implement high-speed SPI/Parallel Slave receiver module in VHDL.
  - [ ] Route incoming bytes directly to SDRAM via DMA bus controller.
- [ ] **3.3 Boot Handshaking**
  - [ ] Assert FPGA CPU `RESET` line on initial power-up.
  - [ ] Stream executable and WAD bytes from ESP32 into FPGA SDRAM.
  - [ ] Toggle `BOOT_DONE` signal from ESP32 to release FPGA CPU reset.

---

### Phase 4: VGA Framebuffer Engine
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