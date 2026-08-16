// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Ozan Akgül
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "../bsp/soc_regs.h"

// Convert and transmit a 32-bit value in hexadecimal ASCII over UART
void print_hex32(uint32_t val) {
    static const char hex_chars[] = "0123456789ABCDEF";
    uart_puts("0x");
    
    for (int i = 28; i >= 0; i -= 4) {
        uart_putc(hex_chars[(val >> i) & 0x0F]);
    }
}

int main(void) {
    // 1. Boot Banner
    uart_puts("\r\n--- RISC-V RV32IM System Boot ---\r\n");
    
    // 2. Hardware Multiplier Benchmark (M-Extension Validation)
    uint32_t t_start = get_cycles();

    volatile uint32_t a = 1234567;
    volatile uint32_t b = 891011;
    volatile uint32_t product = a * b; // Emits hardware 'mul' instruction
    
    uint32_t t_end = get_cycles();

    uart_puts("M-Ext Test: ");
    print_hex32(a);
    uart_puts(" * ");
    print_hex32(b);
    uart_puts(" = ");
    print_hex32(product);
    uart_puts("\r\nCycles elapsed: ");
    print_hex32(t_end - t_start);
    uart_puts("\r\n");

    // 3. Interactive GPIO Loop
    uart_puts("Entering GPIO loop. Push buttons to mirror on LEDs...\r\n");

    uint32_t prev_keys = 0xFF; // Initialize with dummy value to trigger initial state display
    
    while (1) {
        uint32_t keys = GPIO_KEY_REG & 0x0F;

        // Drive LEDs directly with active button states
        GPIO_LED_REG = keys;

        // Print to UART only on state change
        if (keys != prev_keys) {
            uart_puts("Key State: ");
            print_hex32(keys);
            uart_puts("\r\n");
            prev_keys = keys;
        }
    }
    
    return 0;
}