Peripherals
===========

Memory-mapped I/O peripherals, reachable through the peripheral bridge at
the ``0xC000_0000``-``0xC000_00FF`` MMIO region: UART transmit, GPIO
buttons/LEDs, and a free-running timer. ``Bus_Decoder`` is an earlier,
now-superseded MMIO decoder kept for reference.

.. vhdl:autoentity:: periph_bridge

.. vhdl:autoentity:: uart_tx

.. vhdl:autoentity:: gpio_led

.. vhdl:autoentity:: gpio_key

.. vhdl:autoentity:: timer

.. vhdl:autoentity:: Bus_Decoder
