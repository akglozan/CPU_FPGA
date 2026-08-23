#!/usr/bin/env sh
#
# GHDL regression suite for the RV32IM SoC.
#
#   sh sim/ghdl/run.sh              # analyse + run everything
#   sh sim/ghdl/run.sh tb_mdiv      # run one testbench
#
# Needs only GHDL (>= 3, VHDL-2008). No ModelSim licence, no Quartus.
#
# Everything runs with the PROJECT ROOT as the working directory, because
# rv32im_soc.vhd loads its memory image from the relative path
# "sw/boot_bram.mif" -- the same string Quartus resolves against the
# project directory. Run this from anywhere; the script cd's itself.

set -e

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work="$here/work"

cd "$root"

rm -rf "$work"
mkdir -p "$work"

GA="ghdl -a --std=08 --workdir=$work -P$work"

# Simulation-only stand-in for the altsyncram primitive, configured to
# match what CPU_FPGA.map.rpt reports for u_bram. Also carries the write
# monitor that flags any BRAM write outside the two stack slots.
$GA --work=altera_mf "$here/altera_mf.vhd"

# Design, in dependency order.
for f in \
    rtl/core/ALU.vhd \
    rtl/core/Control_Unit.vhd \
    rtl/core/ImmGen.vhd \
    rtl/core/RegFile.vhd \
    rtl/core/Program_Counter.vhd \
    rtl/core/IF_ID_Register.vhd \
    rtl/core/IF_Stage.vhd \
    rtl/core/ID_EX_Register.vhd \
    rtl/core/ID_Stage.vhd \
    rtl/core/Forwarding_Unit.vhd \
    rtl/core/M_Extension_Unit.vhd \
    rtl/core/EX_MEM_Register.vhd \
    rtl/core/EX_Stage.vhd \
    rtl/core/MEM_WB_Register.vhd \
    rtl/core/MEM_Stage.vhd \
    rtl/core/Hazard_Unit.vhd \
    rtl/core/CPU_FPGA.vhd \
    rtl/memory/bram_4kb.vhd \
    rtl/memory/bus_interconnect.vhd \
    rtl/memory/sdram_controller.vhd \
    rtl/peripherals/periph_bridge.vhd \
    rtl/peripherals/gpio_led.vhd \
    rtl/peripherals/gpio_key.vhd \
    rtl/peripherals/timer.vhd \
    rtl/peripherals/uart_tx.vhd \
    rtl/rst_sync.vhd \
    rtl/rv32im_soc.vhd
do
    $GA "$f"
done

# Behavioural SDRAM chip model, used only by tb_sdram. Lives in sim/
# rather than sim/ghdl/ because the ModelSim flow uses it too.
$GA sim/sdram_model.vhd

for tb in "$here"/tb_*.vhd; do
    $GA "$tb"
done

if [ -n "$1" ]; then
    list="$*"
else
    list="tb_mdiv tb_buserr tb_sdram tb_uart tb_soc tb_rst tb_bounce"
fi

status=0

for tb in $list; do
    echo
    echo "=============================================================="
    echo "  $tb"
    echo "=============================================================="
    log="$work/$tb.log"
    if ghdl -r --std=08 --workdir="$work" -P"$work" "$tb" > "$log" 2>&1; then
        rc=0
    else
        rc=$?
    fi

    # numeric_std emits a metavalue warning for every 'U' before reset;
    # harmless and very noisy, so drop those lines from the report.
    grep -v "metavalue detected" "$log" || true

    # Match only real failure markers. Note "FAILURES: 0" is the SUCCESS
    # line of tb_mdiv, so a bare grep for "FAIL" is wrong here.
    if [ "$rc" -ne 0 ] ||
       grep -qE '\(report warning\): FAIL|\(assertion error\)|UNEXPECTED BRAM WRITE|-> DEAD|FAILURES: [1-9]' "$log"; then
        echo ">>> $tb FAILED"
        status=1
    else
        echo ">>> $tb ok"
    fi
done

echo
if [ "$status" -eq 0 ]; then
    echo "ALL TESTBENCHES PASSED"
else
    echo "REGRESSIONS PRESENT -- see above"
fi
exit "$status"
