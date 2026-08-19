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

// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Ozan Akgül

#include "../bsp/soc_regs.h"

void print_hex32(uint32_t val) {
    static const char hex_chars[] = "0123456789ABCDEF";
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4) {
        uart_putc(hex_chars[(val >> i) & 0x0F]);
    }
}

int main(void) {
    uart_puts("\r\n--- RISC-V RV32IM System Boot ---\r\n");

    // 1. Hardware Multiplier Test
    uint32_t t_start = get_cycles();
    volatile uint32_t a = 1234567;
    volatile uint32_t b = 891011;
    volatile uint32_t product = a * b;
    uint32_t t_end = get_cycles();

    uart_puts("M-Ext Test: ");
    print_hex32(a);
    uart_puts(" * ");
    print_hex32(b);
    uart_puts(" = ");
    print_hex32(product);
    uart_puts("\r\nCycles: ");
    print_hex32(t_end - t_start);
    uart_puts("\r\n");

    // 2. SDRAM Read/Write Verification Test
    uart_puts("\r\n--- Starting SDRAM Memory Verification ---\r\n");
    volatile uint32_t *sdram_ptr = (volatile uint32_t *)SDRAM_BASE;

    // Pattern 1: Direct 32-bit Word Write & Read
    uint32_t test_val = 0xDEADBEEF;
    sdram_ptr[0] = test_val;
    uint32_t read_back = sdram_ptr[0];

    uart_puts("SDRAM [0x80000000] Write: ");
    print_hex32(test_val);
    uart_puts(" | Read: ");
    print_hex32(read_back);
    
    if (read_back == test_val) {
        uart_puts(" -> PASS\r\n");
    } else {
        uart_puts(" -> FAIL\r\n");
    }

    // Pattern 2: Multi-word Row Test
    uart_puts("Writing sequential pattern...\r\n");
    for (int i = 0; i < 4; i++) {
        sdram_ptr[i] = 0xA0A00000 + i;
    }

    for (int i = 0; i < 4; i++) {
        uint32_t val = sdram_ptr[i];
        uart_puts("SDRAM [");
        print_hex32((uint32_t)&sdram_ptr[i]);
        uart_puts("] = ");
        print_hex32(val);
        uart_puts("\r\n");
    }

    // 3. Interactive GPIO Loop
    uart_puts("\r\nAll SDRAM checks finished. Entering GPIO loop...\r\n");
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