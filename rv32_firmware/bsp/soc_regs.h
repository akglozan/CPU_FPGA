#ifndef SOC_REGS_H
#define SOC_REGS_H

#include <stdint.h>

#define GPIO_LED_ADDR  0xE0000000u
#define GPIO_KEY_ADDR  0xE0000004u
#define UART_TX_ADDR   0xE0000008u
#define UART_ST_ADDR   0xE000000Cu
#define TIMER_ADDR     0xE0000010u

#define GPIO_LED (*(volatile uint32_t *)GPIO_LED_ADDR)
#define GPIO_KEY (*(volatile uint32_t *)GPIO_KEY_ADDR)
#define UART_TX  (*(volatile uint32_t *)UART_TX_ADDR)
#define UART_ST  (*(volatile uint32_t *)UART_ST_ADDR)
#define TIMER    (*(volatile uint32_t *)TIMER_ADDR)

#endif