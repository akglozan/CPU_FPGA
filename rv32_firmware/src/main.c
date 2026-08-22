#include <stdint.h>
#include "soc_regs.h"

static void uart_putc(uint8_t c)
{
    UART_TX = (uint32_t)c;
}

int main(void)
{
    GPIO_LED = 0x00000000u;

    uart_putc('A');
    uart_putc('B');
    uart_putc('C');
    uart_putc('\r');
    uart_putc('\n');

    while (1) {
        GPIO_LED = 0x00000000u;
    }

    return 0;
}