Top-Level SoC
=============

The synthesis top level that instantiates the CPU core, memory hierarchy,
and peripherals into a complete RV32IM system-on-chip, plus the reset
synchronizer that cleans up the board's raw pushbutton reset signal.

.. vhdl:autoentity:: rv32im_soc

.. vhdl:autoentity:: rst_sync
