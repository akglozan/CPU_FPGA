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
> **Status:** 4.1 and 4.2 both implemented. 4.1 is hardware-toolchain
> verified (Questa, via `sim/tb_vga_timing_gen.vhd`); everything in this
> phase also now has a GHDL-runnable copy of its regression tests under
> `sim/ghdl/` (`sh sim/ghdl/run.sh tb_vga_timing_gen tb_vga_line_fetch`),
> which didn't exist before 4.2 — `run.sh`'s dependency list previously
> didn't include `vga_pll.vhd`, `rtl/video/*.vhd`, or (independently of
> anything VGA-related) `spi_slave.vhd`/`boot_loader.vhd`, so it couldn't
> have analyzed the full `rv32im_soc.vhd` top level; a behavioural
> `altpll` stand-in was also added to `sim/ghdl/altera_mf.vhd` (it only
> had `altsyncram` before), needed now that `vga_pll` is wired in. Not
> yet run on real hardware.
- [x] **4.1 Timing Generator**
  - [x] Configure ALTPLL in Quartus II to generate a 25 MHz pixel clock.
    - `vga_pll` (Quartus MegaWizard/IP Catalog, `INTENDED_DEVICE_FAMILY
      = "Cyclone IV E"`): `inclk0` 50 MHz → `c0` 25 MHz
      (`CLK0_MULTIPLY_BY=1`, `CLK0_DIVIDE_BY=2`), `areset` input and
      `locked` output both enabled. Instantiated in `rv32im_soc.vhd`
      as `u_vga_pll`, fed from the existing 50 MHz `clk` and
      `not rst_n_sync` (converting the project's active-low system
      reset to ALTPLL's active-high `areset`), driving a new internal
      `pix_clk` signal. `pix_clk`/`vga_pll_locked` are both currently
      unused past that point, same as the reserved-but-unconnected
      `s2_*` bus slot — pending `vga_timing_gen`'s own instantiation.
    - Hit (and worked around) a confirmed Quartus Prime Lite 25.1
      bug where the ALTPLL parameter editor renders with overlapping,
      unreadable text on Windows — documented by Altera at
      [community.altera.com KB 349903](https://community.altera.com/kb/knowledge-base/why-does-the-text-overlap-in-the-altpll-ip-parameter-editor/349903)
      with an official patch.
  - [x] Implement 640x480 @ 60 Hz VGA synchronization counters (`HSYNC`, `VSYNC`).
    - `rtl/video/vga_timing_gen.vhd`: single clocked process generating
      `hcnt`/`vcnt`, `hsync`/`vsync` (VESA active-low), `hblank`/`vblank`,
      `pixel_x`/`pixel_y`, and the 320x200-source-to-640x480-output
      mapping (`active_region`, `line_num`, `start_fetch`) for the
      letterboxed 2x pixel-doubled framebuffer described in 4.2.
    - Verified standalone (no bus, no other modules) in
      `sim/tb_vga_timing_gen.vhd` over two full simulated frames:
      `start_fetch` fires exactly 400 times (200/frame, once per source
      line — not per doubled output line); `line_num` sequences 0..199
      in order each frame with no skips/repeats; `active_region` is high
      for exactly 640,000 of the 840,000 total cycles (400 active lines
      x 800 cycles/line x 2 frames — it's a whole-line flag, not gated
      by `hblank`); total elapsed cycles match `H_TOTAL * V_TOTAL * 2`
      exactly, confirming no drift in the counter wrap logic.
    - Mirrored at `sim/ghdl/tb_vga_timing_gen.vhd` for the GHDL suite,
      with one deliberate difference: that copy releases reset and
      terminates by counting actual `pix_clk` rising edges instead of
      the original's raw `wait for <time>` values. The original's
      100 ns reset-release and 33,600,000/33,600,010 ns timeout both
      land exactly on a clock-edge boundary (100 ns is an exact
      multiple of the 40 ns period), so which simulator's delta-cycle
      scheduling wins that exact-time coincidence changes the final
      cycle count by one — Questa and GHDL resolve it in opposite
      directions (the `+10 ns` in the real file was tuned empirically
      against Questa; running that same file under GHDL instead gives
      `total_cycle_count = 840001`). Counting edges directly removes
      the race rather than chasing another simulator-specific constant.
      Not applied to the real file, since it already passes against
      the actual verification tool this project relies on.
- [x] **4.2 Framebuffer & Palette Conversion**
  - [x] Reserve a 320x200 pixel region within SDRAM.
    - `rtl/video/vga_pkg.vhd`: `FB_BASE_ADDR` is the last 64 KB of the
      8 MB SDRAM chip (`0x807F_0000`). Confirmed clear of the boot
      payload against this same file's own Phase 3 closeout section
      above: `FIRMWARE.BIN` at `0x8000_0000` and `DOOM1.WAD` (4,207,819
      bytes) at `0x8010_0000`, ending around `0x8050_33CB` — a good
      ~3 MB below `FB_BASE_ADDR`. Not yet cross-checked against whatever
      heap/stack layout Phase 5's linker script ends up using.
  - [x] Implement 2x2 pixel-doubling logic for 640x480 output.
    - Vertical doubling lives in `vga_timing_gen.vhd` (`line_num`, one
      value held for two output lines — this was already true of 4.1).
      Horizontal doubling is `vga_pixel_pipeline.vhd`: `pixel_x(9 downto 1)`
      addresses `vga_line_buffer`, i.e. each of the 320 fetched bytes is
      shown across 2 consecutive output columns.
  - [x] Implement 8-bit palette RAM lookup table (LUT) for 256-color output.
    - `rtl/video/vga_palette.vhd`: 256 x `PALETTE_BITS` (3, see below)
      true dual-port RAM. Write side is the CPU, via the VGA slave-2
      bus window (`0xC000_0000` + `4*index`, wired up in
      `rv32im_soc.vhd` — this is also what actually gives slave 2 a job;
      previously it was tied off entirely). Read side is
      `vga_pixel_pipeline.vhd`, indexed by the byte `vga_line_buffer`
      returns for the current column.
  - [x] Map output signals to board RGB and sync pins.
    - New top-level ports on `rv32im_soc` (`vga_hs_pin`/`vga_vs_pin`/
      `vga_r_pin`/`vga_g_pin`/`vga_b_pin`), driven by
      `vga_pixel_pipeline.vhd`. 1 bit each of R/G/B — this board has no
      resistor-ladder DAC, so 8 discrete colours is the real ceiling
      (established against the board's schematic earlier in this
      project); forced to black outside the letterboxed active area.
  - **New modules, beyond the four checklist items above:**
    `rtl/video/vga_line_buffer.vhd` (ping-pong scanline store — one bank
    being filled by the SDRAM fetch while the other is being scanned
    out, so a fetch landing mid-line can't tear the image),
    `rtl/video/vga_line_fetch.vhd` (Wishbone master that pulls one
    320-byte scanline out of SDRAM per `start_fetch` pulse — see its
    header for the pix_clk/sys_clk handshake), and
    `rtl/memory/sdram_arbiter.vhd` (a small 2-input priority arbiter
    sitting between `sdram_controller` and its two masters — the
    existing CPU/`boot_loader` path and the new line-fetch master —
    kept deliberately separate from the existing CPU/`boot_loader` mux
    rather than added as a third leg to it; see the arbiter's own header
    for why).
  - Verified in `sim/ghdl/tb_vga_line_fetch.vhd`: a fake Wishbone SDRAM
    slave that echoes its own address back as data makes every fetched
    byte's expected value predictable from address arithmetic alone.
    Checks the pix_clk→sys_clk handshake (including the FB_HEIGHT frame
    wrap, i.e. line 199 → line 0, not 200), the full 320-byte unpack
    into `vga_line_buffer`, and that the ping-pong bank keeps
    alternating correctly across three consecutive fetches (not just the
    first one). Along the way this also caught a real bug in
    `vga_line_fetch.vhd`'s address arithmetic — `unsigned * natural` in
    `numeric_std` returns a result twice as wide as the left operand,
    not the same width, so the un-resized product was silently 64 bits
    where 32 were expected; GHDL only caught it as a runtime bound-check
    failure, not at analysis time, since the mismatch runs through a
    function call. See that file's own comment at the fix site.
  - **Real fitter failure and fix — `vga_line_buffer.vhd` RAM inference.**
    The design didn't fit on first synthesis (`Error (170011): Design
    contains 9017 blocks of type combinational node. However, the
    device contains only 6272 blocks.` — this is an EP4CE6-class part).
    `output_files/CPU_FPGA.map.rpt` showed the entire overage traced to
    one module: `vga_line_buffer` synthesizing as 4112 combinational
    ALUTs + 5120 discrete registers + 0 memory bits, instead of one
    `altsyncram` block, the way `vga_palette.vhd`'s structurally similar
    dual-clock dual-port RAM correctly does (0 ALUTs, 768 memory bits).
    Two intermediate fix attempts both failed to trigger inference — a
    single address computed via a local variable with if/else (no
    change at all — the resynthesized numbers were byte-for-byte
    identical), then addressing rewritten as a plain bank & column
    concatenation staged through its own signal, computed by a separate
    concurrent assignment outside the clocked processes (made it worse:
    11434 vs. 6272, `vga_line_buffer` up to 6546 ALUTs / 8192
    registers). The report's own Analysis & Synthesis Messages section
    named the exact reason on that second attempt:
    `Info (276007): RAM logic "vga_line_buffer:u_vga_line_buffer|ram" is
    uninferred due to asynchronous read logic` — even though the array
    is only ever read inside a `rising_edge(rd_clk)` process. A fourth
    form — the bank/column concatenation moved inline into the `ram(...)`
    index itself, as textually close to `vga_palette`'s shape as the
    extra bank bit allows — produced the same message again.
    - **Resolution: stop inferring, instantiate.** The remaining
      difference from the working example isn't something the source can
      express away — `vga_palette`'s index is a plain port fed straight
      into `to_integer(unsigned(...))`, and a ping-pong buffer's cannot
      be, because its address is inherently bank & column. Four failed
      attempts at one full Quartus compile each was enough. So
      `vga_line_buffer.vhd` now instantiates `altsyncram` directly,
      following the precedent `bram_4kb.vhd` set in Phase 2 for exactly
      this class of problem (see its header — a different inference
      misfire, a 32-bit memory silently split into eight 8-bit
      primitives that dropped the `.mif`, resolved the same way). The
      mapping is now stated rather than inferred, so it also can't
      silently regress into logic if a later edit or Quartus version
      shifts what the template matcher accepts. Parameters mirror what
      Quartus itself picked for the palette's inferred instance, with
      the widths changed: `OPERATION_MODE DUAL_PORT`, `ADDRESS_REG_B`
      on `CLOCK1`, `OUTDATA_REG_B UNREGISTERED` — the same one-cycle
      read latency the array version had, so `vga_pixel_pipeline.vhd`'s
      latency matching is unchanged.
    - `sim/ghdl/altera_mf.vhd`'s `altsyncram` stand-in was extended to
      support `DUAL_PORT` (port A write-only on `clock0`, port B
      read-only on `clock1`) alongside the existing `BIDIR_DUAL_PORT`
      path it was originally written for; `tb_vga_line_fetch` still
      passes unchanged against it.
  - **Fit achieved.** With the line buffer in an M9K, the design fits and
    a `.sof` is produced: 4,928 / 6,272 logic elements (79 %), 2,245
    registers (36 %), 41,728 / 276,480 memory bits (15 %), 1 / 2 PLLs.
    The +8,192 memory bits over the previous build is exactly the line
    buffer (1024 × 8) landing in a block where it belongs. Timing closes
    on both domains — `sys_clk` Fmax 53.1 MHz against the 50 MHz
    requirement (setup slack +1.166 ns, hold +0.410 ns), `pix_clk`
    220.26 MHz against 25 MHz. **The `sys_clk` margin is only ~6 %**,
    which is worth remembering before adding anything else to the CPU's
    critical path.
  - **VGA pin assignments (`CPU_FPGA.qsf`).** The first fitting compile
    raised `Critical Warning (169085): No exact pin location
    assignment(s) for 5 pins` — the five new VGA outputs, which the
    Fitter then placed on pins 1, 2, 7, 10 and 11, nowhere near the
    board's VGA connector. Programming that image would have produced no
    video and driven five arbitrary pins. Now assigned explicitly:
    `vga_hs_pin` PIN_101, `vga_vs_pin` PIN_103, `vga_r_pin` PIN_104,
    `vga_g_pin` PIN_105, `vga_b_pin` PIN_106. **These came from public
    RZ-EasyFPGA A2.2 projects, not from the board schematic** — the same
    sources agree with this project's own existing `clk` (23), button
    (88–91) and LED (84–87) assignments, which is good corroboration
    that it is the same board, but they should still be checked against
    the board's own pin table before programming.
  - **`CPU_FPGA.sdc`** gained a `set_false_path` for the five VGA outputs
    (passive connector, no setup/hold to meet — same treatment the LEDs
    and `uart_tx` already had) and a `set_clock_groups -asynchronous`
    between `sys_clk` and the PLL's `clk[0]`. Both derive from the same
    oscillator, so `derive_pll_clocks` had TimeQuest timing every
    crossing as synchronous; the design instead handles all of them
    structurally (`rst_sync` for the pix_clk reset, the toggle-bit
    handshake in `vga_line_fetch`, the bank synchronizer in
    `vga_pixel_pipeline`, and the dual-clock RAM ports themselves).
  - **Remaining warnings, all reviewed and benign:** `vga_vblank` /
    `vga_pixel_y` assigned but never read (`vga_timing_gen` outputs the
    pixel pipeline doesn't need — line doubling keys off `line_num`, and
    blanking off `active_region`); `s2_sel` and `IF_Stage`'s
    `pc_plus4_wire` likewise unread, both pre-existing; `data_b` defined
    but never used (the line buffer's `altsyncram` write-side data on the
    read-only port B, tied off deliberately); `sdram_cke` stuck at VCC
    and `sdram_cs_n` at GND (both correct — the controller keeps the
    chip enabled and selected); `uart_rx` driving no logic (no receiver
    implemented yet).
  - **Not yet done:** run on real hardware. `FB_BASE_ADDR` is confirmed
    clear of the boot payload (see above) but not yet checked against
    Phase 5's linker script, which doesn't exist yet.

---

### Phase 5 Prerequisite Closeout — SDRAM Instruction Fetch, verified on hardware 2026-08-28

**The blocker.** Since Phase 3, instruction fetch was hardwired straight to
BRAM (`rv32im_soc.vhd` drove `bram_4kb`'s port A directly from `pc`), so the
CPU could read firmware/WAD data the ESP32 had DMA'd into SDRAM but could
never execute code living there. Resolving this was a prerequisite for all
of 5.1–5.3, since a linker script mapping code to SDRAM is pointless if the
core can't fetch from it.

**The fix — shared-bus fetch, no cache.** Instruction fetch now decodes the
address: BRAM-range fetches are unchanged (still the direct one-cycle path),
and SDRAM-range fetches go through a new small arbiter into the existing
`sdram_arbiter` → `sdram_controller` path, sharing it with the CPU's own
data accesses (data always wins on contention). An instruction cache was
considered and rejected for this phase — the added verification surface
wasn't worth it before Doom's actual performance profile is known.

* `rtl/memory/fetch_arbiter.vhd` (new) — 2-port Wishbone arbiter (DATA vs.
  FETCH, DATA always wins), with its own watchdog mirroring
  `bus_interconnect.vhd`'s existing pattern.
* `rtl/rv32im_soc.vhd` — address-decodes fetch to BRAM or SDRAM; SDRAM
  fetches route through `fetch_arbiter` into `sdram_arbiter`'s CPU-side port
  (previously wired directly to the CPU/`boot_loader` mux).
* `rtl/core/IF_Stage.vhd` — `IF_ID_Register`'s `pc_in` now uses the PC that
  actually corresponds to the arrived word (gated on `if_sdram_ack`) instead
  of assuming BRAM's fixed one-cycle latency, which SDRAM's variable latency
  breaks.
* `rtl/core/Hazard_Unit.vhd` — new dedicated stall case for an in-flight
  SDRAM fetch, freezing only IF/ID (not EX/MEM/WB) so a MEM-stage
  transaction with side effects (UART TX, GPIO, palette writes) can't be
  re-triggered by prolonging its stall past its own ack.
* `rtl/core/CPU_FPGA.vhd` — a branch-target latch (`pending_branch`/
  `pending_target`): if a branch/jump resolves while a fetch is still
  outstanding, the redirect is held and applied once the fetch completes,
  rather than dropped (the project's choice: never abandon an in-flight
  SDRAM transaction).

**A real bug found via the new integration test, not the plan.**
`Hazard_Unit.vhd` already had a `branch_pending` mechanism for discarding
the one stale pre-branch instruction that BRAM's fixed 1-cycle latency
fetches before a redirect takes effect. It stayed "pending" across however
many cycles `if_id_stall` next happened to be low, then fired the flush
then. That assumption — exactly one stale fetch, discarded at the next
opportunity — silently broke for a branch landing on an SDRAM address:
`if_bus_stall` asserts immediately and freezes IF/ID before any stale word
can land (so the freeze had already discarded it for free), but
`branch_pending` stayed set regardless and fired its flush many cycles
later, exactly when the *real*, correctly-fetched target instruction
arrived — silently replacing it with a bubble. `tb_if_sdram_fetch` caught
this directly: a `SW` instruction fetched from SDRAM was writing `0` to
`GPIO_LED` instead of `5`, traced back to the preceding `ADDI` never
reaching the ID stage at all. Fixed by making the discard a one-shot check
on exactly the cycle after a branch (`branch_just_taken`, a single
registered pulse) rather than an indefinitely-deferred one — see the
comment at that signal's declaration for the full timing argument.

**Verified in simulation.** `sim/ghdl/tb_fetch_arbiter.vhd` (new) is a unit
test against a fake echoing slave: DATA-only and FETCH-only passthrough,
DATA-wins-on-contention with FETCH still completing afterward (not
dropped), and the watchdog forcing a synthetic ack + sticky `bus_error` on
timeout. `sim/ghdl/tb_if_sdram_fetch.vhd` (new) is a full end-to-end
integration test — real `rv32im_soc`, real `sdram_model` on its physical
pins (unlike `tb_soc.vhd`, which floats them) — that stores three
hand-assembled instructions into SDRAM via ordinary data writes (the
Phase 3 path), then jumps into them: `ADDI x2,x0,5`, `SW x2,0(x3)` (to
`GPIO_LED`), `JAL x0,0` (self-loop). Passing means `GPIO_LED` reaches `0x5`,
i.e. the CPU decoded and executed real instructions straight out of SDRAM,
not just read them as data. This also incidentally exercises a branch
(the `JAL`) resolving while a fetch is outstanding, since the SDRAM
transaction latency naturally lands that way. Both new tests are in
`run.sh`'s default list; all 10 pre-existing tests still pass unchanged,
confirming the arbiter is a transparent no-op when only BRAM is fetched
from.

**Easy to miss: `CPU_FPGA.qsf` needed `fetch_arbiter.vhd` added as its own
`VHDL_FILE` assignment.** Unlike `run.sh`, which discovers everything in
its dependency list automatically, Quartus's project file lists every VHDL
source explicitly — a new entity referenced from `rv32im_soc.vhd` but
missing from the `.qsf` fails Analysis & Synthesis with `(10481): ... design
library "work" does not contain primary unit "fetch_arbiter"` even though
GHDL had already compiled and passed everything cleanly.

**Fit and timing.** 5,188 / 6,272 logic elements (83%, up from 4,928 /
6,272 at the Phase 4.2 closeout), 2,490 registers (up from 2,245), memory
bits and pin count unchanged (41,728 / 276,480; the arbiter added flops and
muxes, not RAM). Timing closes on both domains — `sys_clk` Fmax 51.12 MHz
against the 50 MHz requirement (setup slack +0.440 ns), `pix_clk` PLL
201.17 MHz. **The `sys_clk` margin dropped to ~2.2%**, down from Phase
4.2's ~6% — the fetch-address decode and arbiter sit on the instruction
fetch's critical path. Worth checking timing again before adding anything
else there.

**Confirmed on real hardware 2026-08-28.** Flashed and observed against the
Phase 4.2 baseline: ESP32 boot chain (SD mount, WAD/firmware read, SPI
transfer, `BOOT_DONE`), `FW[0]`/`WAD[0]` magic checks, `BUS_ERR = 0`, VGA
color-cycling test, and LED/button behavior all matched exactly, with no
regressions. This is the expected and correct result — the firmware
flashed is still Phase 3/4's, which never fetches from SDRAM, so a clean
repeat of prior behavior confirms the new fetch path is a true no-op for
existing code, matching what GHDL predicted. Actual SDRAM-resident code
execution on real hardware (as opposed to in `tb_if_sdram_fetch`) will
first be observable once Phase 5.1/5.2 produce firmware that's actually
linked to run from SDRAM.

---

### Phase 5.1 Bring-Up Bug — SDRAM fetch/data starvation, fixed 2026-08-28

First real SDRAM-resident firmware (`rv32_firmware`'s `crt0.s`+`main.c`,
linked via `linker_sdram.ld`, booted via a small BRAM `boot_stub.s`)
printed its immediate `"ABC"` greeting correctly on real hardware, then
produced garbled or missing output for everything after — every
`.rodata`-sourced string/table read, and everything touching the stack,
which `linker_sdram.ld` also placed in SDRAM.

**Root cause**: `if_fetch_stb`/`if_fetch_cyc` in `rv32im_soc.vhd` were
driven as a bare level — asserted for as long as PC sat in the SDRAM
range, with no gap between back-to-back fetches. `fetch_arbiter`'s grant
only re-arbitrates when its `m_cyc_o` goes idle, and fetch's own request
never did once the CPU started running SDRAM-resident code — so once
FETCH first won the grant, DATA (every stack push/pop, every `.rodata`
read) could never win the bus again, despite `fetch_arbiter`'s own header
comment promising "DATA always wins". The system only limped forward at
all because `bus_interconnect`'s watchdog — meant for genuine
unanswered-slave faults — eventually force-acked each starved DATA access
after its full 65536-cycle timeout. Reproduced in GHDL as the CPU parking
on a single `pc` for ~1.3 ms at a time (matching the watchdog period
exactly), `BUS_ERR` permanently latched, ~10.45 ms lost crawling through
just the first handful of `main()`'s prologue stores. A forced ack is not
a real completed transaction, which very plausibly explains the garbled
(rather than merely delayed) real-hardware output.

Found via a new GHDL reproduction testbench (`sim/ghdl/tb_firmware_sdram.vhd`)
that bit-bangs the *actual compiled* `rv32_firmware/build/firmware.bin`
over the real `spi_slave`/`boot_loader` RTL and decodes `uart_tx` like a
serial monitor — `tb_if_sdram_fetch.vhd`'s narrow hand-assembled sequence
never exercised the continuous, tightly-interleaved fetch+data access
pattern of a real program. (The reproduction effort also turned up two
testbench-only pitfalls worth remembering: starting the simulated SPI
transfer before the SoC's internal reset synchronizer/SDRAM power-on
sequence has settled silently drops the first MOSI bit and shifts every
byte after it; and `rv32im_soc`'s `get_baud_rate()` runs the UART at
12.5 MHz, not 115200, whenever `simulation=>true`.)

**Fix**: hold `if_fetch_stb`/`if_fetch_cyc` low for the one bubble cycle
`sdram_controller`'s own `ST_IDLE` already burns after every ack (see its
`wait_cnt<=1` comment in `ST_READ_DATA2`/`ST_WRITE_REC`) — this costs no
additional latency, since the controller was already going to ignore
`wb_cyc_i`/`wb_stb_i` for that one cycle regardless, but it finally makes
that idle cycle visible to `fetch_arbiter` as a genuine `m_cyc_o='0'`
moment, restoring its ability to actually re-arbitrate in DATA's favour.
The identical exposure existed one level up too — `fetch_arbiter`'s own
combined output could just as easily have starved `vga_line_fetch` out of
`sdram_arbiter`'s port A — never yet observed only because nothing had
gotten far enough to draw a frame; the same fix closes that gap as a
side effect, at its actual source, rather than patching each arbiter
individually.

`tb_firmware_sdram.vhd` is now a permanent regression test (added to
`run.sh`'s default list) checking three things after boot completes: the
`"ABC\r\n"` greeting arrives byte-for-byte intact, `GPIO_LED` reaches
`0xF` within 500 µs (versus the ~10.45 ms the bug produced), and
`BUS_ERR` never latches. All 13 GHDL testbenches pass with the fix in
place.

**Confirmed on real hardware (2026-08-28).** After flashing the fix, the CPU-side serial monitor showed the full expected sequence — `ABC` greeting, `FW[0]`/`WAD[0]` matching the expected magic bytes, and `BUS_ERR: 0x00000000` — followed by the VGA color-cycling smoke test running cleanly (RED/GREEN/BLUE/WHITE, no stalls). The `delay()` busy-wait in `vga_color_test()` was recalibrated at the same time: it had originally been tuned by feel assuming near-single-cycle BRAM execution, and once this code started genuinely running from SDRAM (each fetch costing ~7-10 cycles instead of BRAM's ~1) the observed pacing came out roughly 10x slower than intended. It's now retuned to land on the originally-intended ~3s per color, confirmed against the printed serial-monitor message.

---

### Phase 5: Software Toolchain & Bare-Metal Doom Porting
- [x] **5.1 GCC Setup**
  - [x] Install and configure `riscv32-unknown-elf-gcc` cross-compiler.
  - [x] Write custom linker script (`linker_sdram.ld`) mapping code and data sections to SDRAM.
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