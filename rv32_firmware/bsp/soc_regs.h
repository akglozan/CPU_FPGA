#ifndef SOC_REGS_H
#define SOC_REGS_H

#include <stdint.h>

#define GPIO_LED_ADDR  0xE0000000u
#define GPIO_KEY_ADDR  0xE0000004u
#define UART_TX_ADDR   0xE0000008u
#define UART_ST_ADDR   0xE000000Cu
#define TIMER_ADDR     0xE0000010u
/* Sticky bus-timeout flag, bit 0. Set when a slave failed to acknowledge
 * and bus_interconnect's watchdog synthesised an ack to unblock the CPU.
 * Any load that returned 0 while this is set should be treated as
 * invalid. Cleared only by reset. */
#define BUS_ERR_ADDR   0xE0000014u

/* VGA slave-2 window (Phase 4.2, see rv32im_soc.vhd around the
 * "VGA slave-2 window" comment). Word-addressed, 256 entries: entry N
 * is a 32-bit store to VGA_PALETTE_BASE + 4*N, only the low
 * PALETTE_BITS (3) bits of the stored word are kept -- one bit each of
 * R/G/B. Write-only, no readback port. */
#define VGA_PALETTE_BASE 0xC0000000u

/* Framebuffer: FB_WIDTH*FB_HEIGHT (320*200 = 64000) bytes at
 * FB_BASE_ADDR (rtl/video/vga_pkg.vhd), one byte per pixel, that byte
 * being a palette index. Ordinary SDRAM, reached through the same bus
 * window main.c already uses for FIRMWARE.BIN/DOOM1.WAD -- plain
 * byte stores work here the same way they do at those addresses. */
#define VGA_FB_BASE      0x807F0000u
#define VGA_FB_WIDTH     320u
#define VGA_FB_HEIGHT    200u

/* TEMP DIAGNOSTIC (2026-08-27, remove once the SDRAM back-to-back read
 * corruption is resolved): vga_line_fetch's raw wb_dat_i for word
 * positions 0/1 of whichever scanline it's currently fetching -- see
 * rtl/video/vga_line_fetch.vhd's dbg_word0_o/dbg_word1_o and
 * rtl/peripherals/periph_bridge.vhd. */
#define VGA_DBG_WORD0_ADDR 0xE0000018u
#define VGA_DBG_WORD1_ADDR 0xE000001Cu
#define VGA_DBG_WORD0 (*(volatile uint32_t *)VGA_DBG_WORD0_ADDR)
#define VGA_DBG_WORD1 (*(volatile uint32_t *)VGA_DBG_WORD1_ADDR)

#define GPIO_LED (*(volatile uint32_t *)GPIO_LED_ADDR)
#define GPIO_KEY (*(volatile uint32_t *)GPIO_KEY_ADDR)
#define UART_TX  (*(volatile uint32_t *)UART_TX_ADDR)
#define UART_ST  (*(volatile uint32_t *)UART_ST_ADDR)
#define TIMER    (*(volatile uint32_t *)TIMER_ADDR)
#define BUS_ERR  (*(volatile uint32_t *)BUS_ERR_ADDR)

#endif
