// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Ozan Akgül

#ifndef SOC_REGS_H
#define SOC_REGS_H

#include <stdint.h>

// Base Addresses & Memory Map
#define BRAM_BASE       0x00000000
#define SDRAM_BASE      0x80000000
#define VGA_BASE        0xC0000000
#define PERIPH_BASE     0xE0000000

#define UART_BASE       (PERIPH_BASE + 0x00)
#define GPIO_BASE       (PERIPH_BASE + 0x10)
#define TIMER_BASE      (PERIPH_BASE + 0x20)

// Register Access Macros
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