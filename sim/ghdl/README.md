# GHDL regression suite

Full-design simulation of `rv32im_soc` running the real firmware image,
plus a unit test for the divider. Needs only GHDL (>= 3, VHDL-2008) — no
ModelSim licence and no Quartus.

```sh
sh sim/ghdl/run.sh            # analyse and run everything
sh sim/ghdl/run.sh tb_mdiv    # run one testbench
```

Exit status is 0 only if every testbench passes, so this drops straight
into CI.

Everything executes with the **project root** as the working directory,
because `rv32im_soc.vhd` loads `sw/boot_bram.mif` by that relative path —
the same string Quartus resolves against the project directory. The
script cd's itself, so it can be invoked from anywhere.

## What is here

| File | Purpose |
|---|---|
| `altera_mf.vhd` | Simulation-only stand-in for `altsyncram`, configured to match exactly what `CPU_FPGA.map.rpt` reports for `u_bram`: address register always present on both ports, selectable output register, `BIDIR_DUAL_PORT`, byte enables, read-old-data. Loads the real `.mif`. Also carries a **write monitor** that reports any port-B write outside words 1022/1023, the only legitimate stack slots. Also now carries a behavioural `altpll` stand-in (added for Phase 4.2), since `vga_pll.vhd` instantiates one and nothing previously provided a matching entity — the full `rv32im_soc` top level could not elaborate under GHDL before this. |
| `tb_vga_timing_gen.vhd` | Phase 4.1 regression for `vga_timing_gen.vhd` alone (no bus, no other modules): checks `start_fetch` pulse count, `line_num` sequencing, `active_region` cycle count, and total elapsed cycles over two simulated frames. Mirrors `sim/tb_vga_timing_gen.vhd` (the real, Questa-verified copy), with one deliberate difference: reset release and termination are counted in actual `pix_clk` edges rather than raw `wait for <time>` values, which dodges a simulator-specific off-by-one the original's exact-edge-boundary timing hits differently under GHDL vs Questa (see the comment at the top of this file's `stim_process` for the full explanation). |
| `tb_vga_line_fetch.vhd` | Phase 4.2 regression for `vga_line_fetch.vhd` + `vga_line_buffer.vhd` together: a fake Wishbone slave echoes its own address back as data, making every fetched byte predictable from address arithmetic alone. Checks the pix_clk/sys_clk handshake (including the FB_HEIGHT frame-wrap case), the full unpack into the line buffer, and that the ping-pong write bank keeps alternating across three consecutive fetches. |
| `tb_soc.vhd` | Smoke test: reports every change of the LED register. |
| `tb_uart.vhd` | Decodes the `uart_tx` pin as a real 115200 8N1 receiver and prints each byte with its stop bit. Runs with `simulation => false` so the true baud divider is exercised. |
| `tb_rst.vhd` | Asserts reset at deliberately clock-misaligned offsets and fails if the LEDs stop moving afterwards. |
| `tb_bounce.vhd` | Models a real bouncing pushbutton — several chatter bursts on both press and release — and checks the SoC still runs. |
| `tb_buserr.vhd` | Bus watchdog. Proves a slave that never acknowledges can no longer wedge the CPU: healthy slaves and unmapped addresses are untouched, the tied-low VGA slave and a mute SDRAM slave both time out and return zero, `bus_error` is sticky, and the bus stays usable afterwards. `TIMEOUT_CYCLES` is overridden small so the test is quick. |
| `tb_sdram.vhd` | SDRAM controller bring-up. Drives `sdram_controller`'s Wishbone port against `sim/sdram_model.vhd`: power-on init, single write/read, consecutive words (catches address overlap), a second row and bank, back-to-back access, a request pending exactly at boot completion (tMRD), byte-enables via `wb_sel` (a full write followed by `sel="0011"`, `"1100"`, and `"0000"` partial writes, checking only the masked bytes change), and 96 back-to-back word round trips — long enough to guarantee at least one real `ST_REFRESH` lands mid-stream, checked by re-reading every word afterward. Every access is bounded by a timeout, because neither `bus_interconnect` (before the watchdog existed) nor `MEM_Stage` originally had one — on hardware a controller that fails to ack freezes the CPU with no diagnostic. |
| `tb_mdiv.vhd` | Unit test for `M_Extension_Unit`. 24 vectors. Multiply: all four of `MUL`/`MULH`/`MULHSU`/`MULHU`, including one operand pair (`rs1 = rs2 = 0xFFFFFFFF`) whose three high-word answers are all different, so a unit that extends its operands wrongly cannot pass all three — plus a check that multiplies never stall. Divide: unsigned, every signed sign combination, divide-by-zero for all four opcodes, `INT_MIN / -1`, and back-to-back divides. Samples `m_result` on exactly the cycle `EX_MEM_Register` would latch it. |

## Why it exists

These were written to find and confirm the bring-up bugs documented in
`docs/notes/bringup_bug_report_2026-08-23.txt`. Three of those bugs are
the kind that come straight back the moment someone touches memory
latency, the stall logic or the divider FSM:

- **BRAM read latency** — `bram_4kb.vhd`'s `outdata_reg_a/b` must stay
  `"UNREGISTERED"`. Setting them to `"CLOCK0"` adds a second register
  stage, making latency 2 cycles when `IF_Stage`'s `pc_delayed` and
  `Hazard_Unit`'s `branch_pending` are retimed for 1.
- **Instruction dropped on a stall** — `IF_Stage.vhd` rewinds
  `pc_fetch_out` to `pc_delayed` while stalled. Remove that and every
  stall silently skips an instruction.
- **Divider sign correction** — `M_Extension_Unit.vhd` releases `stall_m`
  in `HOLD`, not `DONE`, so the pipeline samples the corrected result.

`tb_mdiv` catches the third directly; the first two show up as the firmware
failing to blink or to emit `ABC\r\n`.

`tb_mdiv` also supersedes the older `sim/M_Extension_Unit_tb.vhd`, which
asserts reset with inverted polarity — it drives `rst_n` low and never
releases it, so the unit sits in reset for the whole run, its `MUL`/`MULH`
checks pass only because `mult_prod` is combinational, and it then hangs
forever on the first divide.

## Caveat on run length

`main()`'s delay loop is 2,000,000 iterations, so a full blink period is
about 0.4 s of simulated time — too slow to simulate end to end. `tb_soc`
and `tb_uart` therefore verify startup and the first LED transitions
rather than sustained blinking.

To watch many blink cycles, build a short-delay image: patch words `017`
and `019` of the `.mif` (the `lui a4,0x1e8` / `addi a4,a4,1151` pair that
loads the delay constant) to `00000737` and `01470713`, which sets the
constant to 20 instead of 1,999,999.

## Known-good output

```
tb_mdiv    ================ FAILURES: 0 ================
tb_uart    UART byte: 'A' 'B' 'C' CR LF, all with valid stop bits
tb_soc     LEDs -> 1111 then 0000 after the ~1.3 ms power-on reset
tb_rst     every reset recovers
tb_bounce  every bouncy press recovers, no unexpected BRAM writes
tb_vga_timing_gen  ALL CHECKS PASSED (see the testbench's own summary)
tb_vga_line_fetch  tb_vga_line_fetch: ALL CHECKS PASSED
```

### Currently failing: the four full-SoC benches

`tb_uart`, `tb_soc`, `tb_rst` and `tb_bounce` all fail today with
`firmware did not reach main()`. **There is no SPI flash model in this
suite.** Those four instantiate the whole `rv32im_soc`, which since
Phase 3 holds the CPU in reset until `boot_loader` finishes copying the
payload in over SPI — with nothing driving `spi_miso`, `boot_done` never
asserts, the CPU never starts, and the LED register never moves.

This is not a Phase 4.2 regression, and it is not caused by
`vga_line_buffer.vhd`'s switch to a directly instantiated `altsyncram`
(verified by re-running `tb_soc` against the previous behavioural-array
version of that file — identical failure). It predates the VGA work:
`run.sh`'s dependency list was missing `spi_slave.vhd` and
`boot_loader.vhd` entirely until Phase 4.2 added them, so these four
benches could not even analyse the full top level before, let alone run
it. The "known-good" lines above date from before the boot loader
existed and are kept as the target to restore.

Fixing this needs a behavioural SPI flash model (respond to the 0x03
READ command, stream the payload back on `spi_miso`) wired into those
four testbenches. Not yet written.
