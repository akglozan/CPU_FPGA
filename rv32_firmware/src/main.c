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
 * happening every clock cycle (which would just look dim/solid).
 * Calibrated 2026-08-28 against real hardware, running from SDRAM (this
 * loop and its stack both live there now, per linker_sdram.ld -- each
 * iteration costs an SDRAM instruction fetch, ~7-10 cycles, not BRAM's
 * ~1): the previous 2,000,000 count -- tuned back when this only ran
 * from BRAM -- measured out to ~30s per color in vga_color_test() below
 * (6 delay() calls per color) instead of the intended ~3s, a ~10x
 * slowdown matching the fetch-latency difference exactly. Scaled down
 * by that same ~1/6 to land back on a deliberately-chosen ~5s per
 * color; the loop body is not optimized away since 'i' is volatile,
 * forcing an actual memory read/compare/branch each pass. */
static void delay(void)
{
    volatile uint32_t i;
    for (i = 0; i < 111111u; i++) {
        /* spin */
    }
}

static void uart_print_hex32(uint32_t v)
{
    static const char digits[16] = "0123456789ABCDEF";
    int i;

    uart_putc('0');
    uart_putc('x');
    for (i = 28; i >= 0; i -= 4) {
        uart_putc(digits[(v >> i) & 0xFu]);
    }
}

static void uart_print_str(const char *s)
{
    while (*s) {
        uart_putc(*s++);
    }
}

/* Phase 3.3 verification: the CPU only ever fetches instructions from
 * BRAM, never SDRAM, so this can't "run" whatever boot_loader.vhd just
 * DMA'd in over SPI -- but it CAN peek at those bytes directly to
 * confirm they actually landed where the ESP32 firmware said to put
 * them. Checks the first word at each of bootSendFile's two
 * destination addresses (see esp32_firmware/src/main.cpp):
 *   0x80000000 -- start of FIRMWARE.BIN. No fixed expected value here
 *                 (compare by eye against the real file's first bytes,
 *                 e.g. via `xxd rv32_firmware/build/firmware.bin | head -1`).
 *   0x80100000 -- start of DOOM1.WAD. Should read 0x44415749: the
 *                 ASCII bytes 'I','W','A','D' packed little-endian
 *                 (byte0='I'=0x49 in bits 7:0 ... byte3='D'=0x44 in
 *                 bits 31:24), matching the WAD header the ESP32 already
 *                 verified before sending it.
 * Also prints BUS_ERR: if either read missed bus_interconnect's
 * address decode entirely, its watchdog synthesises an ack and the
 * sticky error bit sets, so a nonzero value here means treat the
 * reads above as invalid rather than "SDRAM has zeros in it".
 */
static void verify_sdram_boot_load(void)
{
    volatile uint32_t *fw_base  = (volatile uint32_t *)0x80000000u;
    volatile uint32_t *wad_base = (volatile uint32_t *)0x80100000u;

    uart_print_str("FW[0]:  ");
    uart_print_hex32(fw_base[0]);
    uart_print_str("\r\n");

    uart_print_str("WAD[0]: ");
    uart_print_hex32(wad_base[0]);
    uart_print_str(" (expect 0x44415749)\r\n");

    uart_print_str("BUS_ERR: ");
    uart_print_hex32(BUS_ERR);
    uart_print_str("\r\n");
}

/* One-shot VGA smoke test, added for Phase 4.2 hardware bring-up: there
 * is no Phase 5 software yet to draw anything, so with the palette at
 * its post-configuration all-zero default the screen is black no
 * matter what the SDRAM/pin/timing chain is doing underneath -- black
 * is the expected, uninformative result either way. This makes it
 * informative: fills the whole framebuffer, then points the palette
 * entries it used at white. If the VGA pipeline (pins, timing, line
 * buffer, palette lookup) is working, the entire screen goes solid
 * white; if it's still black afterward, the problem is upstream of
 * software (pin assignment, sync, or the pipeline itself), not "no one
 * told it what to draw yet".
 *
 * Framebuffer fill is a plain byte store per pixel, same bus path
 * verify_sdram_boot_load() already reads through -- 64,000 stores at
 * 50 MHz is a small fraction of a second, no need to make this fast.
 *
 * THE PATTERN MATTERS. Bytes 0 and 1 of every 32-bit word get
 * FB_PAT_LO, bytes 2 and 3 get FB_PAT_HI, so each word reads back as
 * 0xBBBBAAAA little-endian: SDRAM burst beat 1 = 0xAAAA, beat 2 =
 * 0xBBBB. This used to write 0x01 to every byte, which made the two
 * burst beats carry identical data and therefore indistinguishable on
 * readback -- and that is precisely what hid the BURST ALIGNMENT bug in
 * sdram_controller.vhd (odd start column, BL=2 sequential burst wrapping
 * backwards, beats swapped) through four rounds of hardware debugging.
 * A uniform fill cannot tell you which beat you got. Do not go back to
 * one. Byte stores are also deliberate: they are the access size that
 * triggered the bug, since word accesses are always burst-aligned.
 */
#define FB_PAT_LO 0xAAu
#define FB_PAT_HI 0xBBu
#define FB_PAT_BYTE(i) (((i) & 2u) ? FB_PAT_HI : FB_PAT_LO)

static void vga_smoke_test(void)
{
    volatile uint8_t *fb = (volatile uint8_t *)VGA_FB_BASE;
    volatile uint32_t *palette = (volatile uint32_t *)VGA_PALETTE_BASE;
    uint32_t i;

    for (i = 0; i < VGA_FB_WIDTH * VGA_FB_HEIGHT; i++) {
        fb[i] = (uint8_t)FB_PAT_BYTE(i);
    }

    /* Both pattern indices map to white, so a fully correct pipeline
     * still produces the same solid-white screen the uniform fill did.
     * The visual pass criterion is unchanged -- only the underlying
     * data is now self-identifying. Anything not solid white is
     * corruption. */
    palette[FB_PAT_LO] = 0x7u;
    palette[FB_PAT_HI] = 0x7u;

    uart_print_str("VGA smoke test: framebuffer filled with 0xBBBBAAAA "
                   "pattern, palette set to white\r\n");
}

/* Permanent framebuffer smoke check: reads the whole framebuffer back
 * through the CPU's own bus accesses and reports how many bytes aren't
 * what vga_smoke_test() just wrote, plus the first mismatch.
 *
 * Counts are split by halfword position because that split is what
 * localises a fault: bytes 0..1 of each word come from SDRAM burst beat
 * 1 and bytes 2..3 from beat 2, so a failure confined to one column
 * says the two beats are being mismapped rather than the data being
 * generally wrong. That asymmetry is exactly how the BURST ALIGNMENT
 * bug was finally identified (32,000 bad bytes, all of them beat 1) --
 * see rtl/memory/sdram_controller.vhd's header.
 *
 * Kept in the firmware permanently: it is a few milliseconds at boot and
 * it verifies the entire SDRAM byte-write and burst-read path end to
 * end, which nothing else on the running system does.
 */
static void vga_readback_check(void)
{
    volatile uint8_t *fb = (volatile uint8_t *)VGA_FB_BASE;
    uint32_t i;
    uint32_t bad = 0;
    uint32_t bad_lo = 0;   /* bytes 0,1 of a word -- SDRAM burst beat 1 */
    uint32_t bad_hi = 0;   /* bytes 2,3 of a word -- SDRAM burst beat 2 */
    uint32_t first_bad_offset = 0xFFFFFFFFu;
    uint8_t first_bad_value = 0;

    for (i = 0; i < VGA_FB_WIDTH * VGA_FB_HEIGHT; i++) {
        uint8_t v = fb[i];
        if (v != (uint8_t)FB_PAT_BYTE(i)) {
            if (bad == 0) {
                first_bad_offset = i;
                first_bad_value  = v;
            }
            bad++;
            if (i & 2u) {
                bad_hi++;
            } else {
                bad_lo++;
            }
        }
    }

    uart_print_str("FB full readback: ");
    uart_print_hex32(bad);
    uart_print_str(" / 0x0000FA00 bytes wrong (lo half ");
    uart_print_hex32(bad_lo);
    uart_print_str(", hi half ");
    uart_print_hex32(bad_hi);
    uart_print_str(")");
    if (bad != 0) {
        uart_print_str(", first bad offset ");
        uart_print_hex32(first_bad_offset);
        uart_print_str(" value ");
        uart_print_hex32((uint32_t)first_bad_value);
    }
    uart_print_str("\r\n");

    /* Word-granular readback of the first two framebuffer words. A
     * 32-bit load shows both burst beats in one value, so beat
     * mismapping is visible directly rather than inferred from byte
     * counts. Both must read 0xBBBBAAAA. */
    {
        volatile uint32_t *fbw = (volatile uint32_t *)VGA_FB_BASE;
        uart_print_str("FB word0/word1 via CPU: ");
        uart_print_hex32(fbw[0]);
        uart_print_str(" ");
        uart_print_hex32(fbw[1]);
        uart_print_str(" (expect 0xBBBBAAAA both)\r\n");
    }
}

/* One-off diagnostic added 2026-08-28: with the pin-assignment and
 * pixel-pipeline fixes in, the screen went from black to a stable,
 * correctly-letterboxed image -- but the fill (palette index programmed
 * to "111", all three channels on) photographed as a pale
 * white-with-a-blue-cast rather than unambiguous white. That could be
 * nothing (camera white balance/moire against a self-lit screen), or it
 * could mean one channel isn't actually toggling. A mixed white doesn't
 * tell you which; three *separate* solid single-channel fills do,
 * because a dead channel shows up as that color simply never appearing
 * at all instead of just tinting a blend.
 *
 * PALETTE_BITS is 3 (see vga_pixel_pipeline.vhd): bit2=R, bit1=G,
 * bit0=B. Reuses whatever the smoke test already proved about the
 * data path (byte stores through this same SDRAM path are already
 * verified correct) -- this only exercises the palette lookup and the
 * three physical pins, cycling forever so each color can be observed
 * and photographed at leisure. Runs forever in place of the old
 * LED-blink idle loop; GPIO_LED still toggles each step as a "CPU is
 * alive" heartbeat.
 */
#define VGA_COLOR_TEST_INDEX 0x01u
#define VGA_COLOR_RED   0x4u   /* "100" */
#define VGA_COLOR_GREEN 0x2u   /* "010" */
#define VGA_COLOR_BLUE  0x1u   /* "001" */
#define VGA_COLOR_WHITE 0x7u   /* "111" */

static void vga_color_test(void)
{
    volatile uint8_t *fb = (volatile uint8_t *)VGA_FB_BASE;
    volatile uint32_t *palette = (volatile uint32_t *)VGA_PALETTE_BASE;
    uint32_t i;
    uint32_t step = 0;

    /* Solid fill, single index -- no beat pattern needed here, that was
     * only ever to catch the (now-fixed) burst-alignment bug. */
    for (i = 0; i < VGA_FB_WIDTH * VGA_FB_HEIGHT; i++) {
        fb[i] = (uint8_t)VGA_COLOR_TEST_INDEX;
    }

    uart_print_str("VGA color test: cycling RED / GREEN / BLUE / WHITE, "
                   "~3s each, forever\r\n");

    while (1) {
        uint32_t color;
        const char *name;

        switch (step & 3u) {
        case 0: color = VGA_COLOR_RED;   name = "RED";   break;
        case 1: color = VGA_COLOR_GREEN; name = "GREEN"; break;
        case 2: color = VGA_COLOR_BLUE;  name = "BLUE";  break;
        default: color = VGA_COLOR_WHITE; name = "WHITE"; break;
        }

        palette[VGA_COLOR_TEST_INDEX] = color;
        uart_print_str("VGA color test: now showing ");
        uart_print_str(name);
        uart_print_str("\r\n");

        GPIO_LED = 0x0u;  /* active-low: all LEDs ON -- alive heartbeat */
        delay();
        delay();
        delay();
        GPIO_LED = 0xFu;  /* active-low: all LEDs OFF */
        delay();
        delay();
        delay();

        step++;
    }
}

/* Phase 6.1 bring-up: gpio_key.vhd, its MMIO wiring, and the four
 * PIN_88..91 button assignments (see CPU_FPGA.qsf) have existed since
 * early in the project but were never actually exercised end to end --
 * nothing before this read GPIO_KEY. This is the same kind of one-shot
 * hardware confirmation as vga_smoke_test() above: poll the register
 * for a short window, print every state change over UART, and mirror
 * it live onto the LEDs, so a button press is visible two independent
 * ways at once.
 *
 * Both GPIO_KEY and GPIO_LED are active-low 4-bit fields on this board
 * (see the "Push Buttons / Keys (Active-Low Inputs)" comment in
 * CPU_FPGA.qsf, and GPIO_LED's own active-low note in main() below), so
 * a straight copy of one into the other lights each LED exactly under
 * the button that drives it -- no inversion needed.
 *
 * Confirmed on hardware 2026-08-28: the first version of this test
 * called delay() once per poll (~0.5s each, 20 iterations), so it only
 * ever sampled GPIO_KEY 20 times across the whole window -- a quick tap
 * that didn't happen to land on one of those instants was silently
 * missed, matching exactly what was observed (only a press held across
 * a sample point registered). Fixed by dropping delay() from the loop
 * entirely and sampling every iteration instead; the iteration count
 * below is scaled up by the same ~0.5s/111111-iterations ratio so the
 * window is still ~10s overall, just sampled continuously rather than
 * at 20 checkpoints.
 */
#define GPIO_KEY_TEST_ITERS (20u * 111111u)

static void gpio_key_test(void)
{
    uint32_t last = 0xFFFFFFFFu; /* force one print on the first read */
    uint32_t iter;

    uart_print_str("GPIO key test: press KEY0-3 now (~10s window), "
                   "LEDs mirror button state live\r\n");

    for (iter = 0; iter < GPIO_KEY_TEST_ITERS; iter++) {
        uint32_t keys = GPIO_KEY & 0xFu;

        if (keys != last) {
            uart_print_str("KEY state: ");
            uart_print_hex32(keys);
            uart_print_str("\r\n");
            last = keys;
        }

        GPIO_LED = keys;
    }

    GPIO_LED = 0xFu; /* back to all-off before vga_color_test's heartbeat */
    uart_print_str("GPIO key test: done\r\n");
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

    verify_sdram_boot_load();
    vga_smoke_test();
    vga_readback_check();
    gpio_key_test();
    vga_color_test();

    return 0;
}
