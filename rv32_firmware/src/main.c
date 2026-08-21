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

void print_hex32(uint32_t val) {
    static const char hex_chars[] = "0123456789ABCDEF";
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4) {
        uart_putc(hex_chars[(val >> i) & 0x0F]);
    }
}

int main(void) {
    // =========================================================================
    // 1. Immediate SDRAM Read/Write Verification Test (Executed FIRST)
    // =========================================================================
    // Performed immediately upon reset to trigger Wishbone Wishbone STB/CYC 
    // and verify the SDRAM FSM without blocking on UART peripheral polling.
    volatile uint32_t *sdram_ptr = (volatile uint32_t *)SDRAM_BASE;

    // Pattern 1: Single Word Direct Access
    uint32_t test_val = 0xDEADBEEF;
    sdram_ptr[0] = test_val;
    volatile uint32_t read_back = sdram_ptr[0];

    // Pattern 2: Multi-Word Burst/Row Access
    for (int i = 0; i < 4; i++) {
        sdram_ptr[i] = 0xA0A00000 + i;
    }

    volatile uint32_t multi_read[4];
    for (int i = 0; i < 4; i++) {
        multi_read[i] = sdram_ptr[i];
    }

    // =========================================================================
    // 2. Hardware Multiplier Test
    // =========================================================================
  //  uint32_t t_start = get_cycles();
    volatile uint32_t a = 1234567;
    volatile uint32_t b = 891011;
    volatile uint32_t product = a * b;
  //  uint32_t t_end = get_cycles();

    // =========================================================================
    // 3. UART Reporting & Verification Results
    // =========================================================================
    uart_puts("\r\n--- RISC-V RV32IM System Boot ---\r\n");

    uart_puts("M-Ext Test: ");
    print_hex32(a);
    uart_puts(" * ");
    print_hex32(b);
    uart_puts(" = ");
    print_hex32(product);
    uart_puts("\r\nCycles: ");
  //  print_hex32(t_end - t_start);
    uart_puts("\r\n");

    uart_puts("\r\n--- SDRAM Memory Verification Results ---\r\n");
    uart_puts("SDRAM [0x80000000] Write: ");
    print_hex32(test_val);
    uart_puts(" | Read: ");
    print_hex32(read_back);
    
    if (read_back == test_val) {
        uart_puts(" -> PASS\r\n");
    } else {
        uart_puts(" -> FAIL\r\n");
    }

    uart_puts("Sequential Multi-Word Check:\r\n");
    for (int i = 0; i < 4; i++) {
        uart_puts("SDRAM [");
        print_hex32((uint32_t)&sdram_ptr[i]);
        uart_puts("] = ");
        print_hex32(multi_read[i]);
        uart_puts("\r\n");
    }

    // =========================================================================
    // 4. Interactive GPIO Loop
    // =========================================================================
    uart_puts("\r\nAll checks finished. Entering GPIO loop...\r\n");
    uint32_t prev_keys = 0xFF;
    while (1) {
        uint32_t keys = GPIO_KEY_REG & 0x0F;
        GPIO_LED_REG = keys;
        if (keys != prev_keys) {
            uart_puts("Key State: ");
            print_hex32(keys);
            uart_puts("\r\n");
            prev_keys = keys;
        }
    }

    return 0;
}