#ifndef SOC_REGS_H
#define SOC_REGS_H

#include <stdint.h>

#define MMIO_BASE  0x80000000U

#define GPIO_LED_REG  (*(volatile uint32_t *)(MMIO_BASE + 0x00U))
#define GPIO_KEY_REG  (*(volatile uint32_t *)(MMIO_BASE + 0x04U))
#define UART_TX_DATA_REG (*(volatile uint32_t *)(MMIO_BASE + 0X08U))
#define UART_TX_STATUS_REG (*(volatile uint32_t *)(MMIO_BASE + 0x0CU))
#define TIMER_VAL_REG (*(volatile uint32_t *)(MMIO_BASE + 0x10U))

static inline void uart_putc(char c) {
    // 1. Wait while UART TX status busy bit (bit 0) is 1
    // 2. Write character 'c' to UART_TX_DATA_REG
}

static inline void uart_puts(const char *str) {
    // Walk the null-terminated string pointer and call uart_putc(*str++)
}




#endif // SOC_REGS_H