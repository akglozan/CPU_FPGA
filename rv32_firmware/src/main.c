#include <stdint.h>
#include "../bsp/soc_regs.h"

/* uart_tx.vhd ignores tx_start while a frame is in flight, and one frame
 * at 115200 takes 4340 clocks. Without this poll the five calls below
 * issue their stores about 8 clocks apart, so only the FIRST byte is ever
 * transmitted and 'B', 'C', '\r', '\n' are silently dropped -- which is
 * exactly the "one 'A' per reset" seen on hardware. Bit 0 of UART_ST is
 * uart_tx's tx_busy (see uart_status in rv32im_soc.vhd), so spin until
 * the transmitter is idle before handing it the next byte. */
static void uart_putc(uint8_t c)
{
    while (UART_ST & 1u) {
        /* transmitter still busy with the previous frame */
    }
    UART_TX = (uint32_t)c;
}

/* Crude busy-wait delay so the blink is visible to the eye rather than
 * happening every clock cycle (which would just look dim/solid). Not
 * calibrated to a specific time -- just enough spin to be visible at
 * 50 MHz with -O2 (the loop body is not optimized away since 'i' is
 * volatile, forcing an actual memory read/compare/branch each pass). */
static void delay(void)
{
    volatile uint32_t i;
    for (i = 0; i < 2000000u; i++) {
        /* spin */
    }
}

static void uart_print_hex32(uint32_t v)
{
    static const char digits[16] = "0123456789ABCDEF";
    int i;

    uart_putc('0');
    uart_putc('x');
    for (i = 28; i >= 0; i -= 4) {
        uart_putc(digits[(v >> i) & 0xFu]);
    }
}

static void uart_print_str(const char *s)
{
    while (*s) {
        uart_putc(*s++);
    }
}

/* Phase 3.3 verification: the CPU only ever fetches instructions from
 * BRAM, never SDRAM, so this can't "run" whatever boot_loader.vhd just
 * DMA'd in over SPI -- but it CAN peek at those bytes directly to
 * confirm they actually landed where the ESP32 firmware said to put
 * them. Checks the first word at each of bootSendFile's two
 * destination addresses (see esp32_firmware/src/main.cpp):
 *   0x80000000 -- start of FIRMWARE.BIN. No fixed expected value here
 *                 (compare by eye against the real file's first bytes,
 *                 e.g. via `xxd rv32_firmware/build/firmware.bin | head -1`).
 *   0x80100000 -- start of DOOM1.WAD. Should read 0x44415749: the
 *                 ASCII bytes 'I','W','A','D' packed little-endian
 *                 (byte0='I'=0x49 in bits 7:0 ... byte3='D'=0x44 in
 *                 bits 31:24), matching the WAD header the ESP32 already
 *                 verified before sending it.
 * Also prints BUS_ERR: if either read missed bus_interconnect's
 * address decode entirely, its watchdog synthesises an ack and the
 * sticky error bit sets, so a nonzero value here means treat the
 * reads above as invalid rather than "SDRAM has zeros in it".
 */
static void verify_sdram_boot_load(void)
{
    volatile uint32_t *fw_base  = (volatile uint32_t *)0x80000000u;
    volatile uint32_t *wad_base = (volatile uint32_t *)0x80100000u;

    uart_print_str("FW[0]:  ");
    uart_print_hex32(fw_base[0]);
    uart_print_str("\r\n");

    uart_print_str("WAD[0]: ");
    uart_print_hex32(wad_base[0]);
    uart_print_str(" (expect 0x44415749)\r\n");

    uart_print_str("BUS_ERR: ");
    uart_print_hex32(BUS_ERR);
    uart_print_str("\r\n");
}

int main(void)
{
    /* LEDs on this board are active-low: writing 0x0 turns every LED ON
     * (not off), and since that was the only value ever written here,
     * the LEDs would appear solidly lit but never visibly "change" --
     * indistinguishable from the CPU never having run at all. 0xF drives
     * all four LEDs to their off state instead, so the very first thing
     * that happens after reset is a visible transition (whatever the
     * LEDs' physical power-up/pre-configuration state was, to off). */
    GPIO_LED = 0xFu;

    uart_putc('A');
    uart_putc('B');
    uart_putc('C');
    uart_putc('\r');
    uart_putc('\n');

    verify_sdram_boot_load();

    while (1) {
        GPIO_LED = 0x0u;  /* active-low: all LEDs ON */
        delay();
        GPIO_LED = 0xFu;  /* active-low: all LEDs OFF */
        delay();
    }

    return 0;
}
