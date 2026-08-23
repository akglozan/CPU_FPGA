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

#define GPIO_LED (*(volatile uint32_t *)GPIO_LED_ADDR)
#define GPIO_KEY (*(volatile uint32_t *)GPIO_KEY_ADDR)
#define UART_TX  (*(volatile uint32_t *)UART_TX_ADDR)
#define UART_ST  (*(volatile uint32_t *)UART_ST_ADDR)
#define TIMER    (*(volatile uint32_t *)TIMER_ADDR)
#define BUS_ERR  (*(volatile uint32_t *)BUS_ERR_ADDR)

#endif