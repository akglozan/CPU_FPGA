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

    while (1) {
        GPIO_LED = 0x0u;  /* active-low: all LEDs ON */
        delay();
        GPIO_LED = 0xFu;  /* active-low: all LEDs OFF */
        delay();
    }

    return 0;
}
