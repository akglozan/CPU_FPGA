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
| `altera_mf.vhd` | Simulation-only stand-in for `altsyncram`, configured to match exactly what `CPU_FPGA.map.rpt` reports for `u_bram`: address register always present on both ports, selectable output register, `BIDIR_DUAL_PORT`, byte enables, read-old-data. Loads the real `.mif`. Also carries a **write monitor** that reports any port-B write outside words 1022/1023, the only legitimate stack slots. |
| `tb_soc.vhd` | Smoke test: reports every change of the LED register. |
| `tb_uart.vhd` | Decodes the `uart_tx` pin as a real 115200 8N1 receiver and prints each byte with its stop bit. Runs with `simulation => false` so the true baud divider is exercised. |
| `tb_rst.vhd` | Asserts reset at deliberately clock-misaligned offsets and fails if the LEDs stop moving afterwards. |
| `tb_bounce.vhd` | Models a real bouncing pushbutton — several chatter bursts on both press and release — and checks the SoC still runs. |
| `tb_mdiv.vhd` | Unit test for `M_Extension_Unit`'s divide path. 16 vectors covering unsigned, every signed sign combination, divide-by-zero for all four opcodes and `INT_MIN / -1`, plus back-to-back divides. Samples `m_result` on exactly the cycle `EX_MEM_Register` would latch it. |

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

`tb_mdiv` catches the third directly. The first two show up as the
firmware failing to blink or to emit `ABC\r\n`.

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
```
