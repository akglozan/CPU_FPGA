#ifndef SOC_REGS_H
#define SOC_REGS_H

#include <stdint.h>

// Base Addresses & Register Definitions
#define UART_BASE       0x80000000
#define GPIO_BASE       0x80000100
#define TIMER_BASE      0x80000200

#define UART_DATA_REG   (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_STATUS_REG (*(volatile uint32_t *)(UART_BASE + 0x04))

#define GPIO_LED_REG    (*(volatile uint32_t *)(GPIO_BASE + 0x00))
#define GPIO_KEY_REG    (*(volatile uint32_t *)(GPIO_BASE + 0x04))

#define TIMER_VAL_REG   (*(volatile uint32_t *)(TIMER_BASE + 0x00))

// Basic UART Drivers
static inline void uart_putc(char c) {
    while (UART_STATUS_REG & 0x01); // Wait while TX FIFO full
    UART_DATA_REG = c;
}

static inline void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
}

// Cycle Counter Driver
static inline uint32_t get_cycles(void) {
    return TIMER_VAL_REG;
}

#endif // SOC_REGS_H