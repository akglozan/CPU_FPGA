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
 * happening every clock cycle (which would just look dim/solid). Not
 * calibrated to a specific time -- just enough spin to be visible at
 * 50 MHz with -O2 (the loop body is not optimized away since 'i' is
 * volatile, forcing an actual memory read/compare/branch each pass). */
static void delay(void)
{
    volatile uint32_t i;
    for (i = 0; i < 2000000u; i++) {
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
 * informative: fills the whole framebuffer with palette index 1, then
 * writes palette entry 1 to white. If the VGA pipeline (pins, timing,
 * line buffer, palette lookup) is working, the entire screen goes
 * solid white; if it's still black afterward, the problem is upstream
 * of software (pin assignment, sync, or the pipeline itself), not "no
 * one told it what to draw yet".
 *
 * Framebuffer fill is a plain byte store per pixel, same bus path
 * verify_sdram_boot_load() already reads through -- 64,000 stores at
 * 50 MHz is a small fraction of a second, no need to make this fast.
 */
/* Byte value this fill writes at framebuffer offset i. Bytes 0 and 1 of
 * every 32-bit word get FB_PAT_LO, bytes 2 and 3 get FB_PAT_HI, so each
 * word reads back as 0xBBBBAAAA little-endian: low half (SDRAM burst
 * beat 1) = 0xAAAA, high half (beat 2) = 0xBBBB.
 *
 * WHY NOT A UNIFORM FILL (changed 2026-08-27): this used to write 0x01
 * to every byte, making every word 0x01010101 -- so beat 1 and beat 2
 * carried the SAME value and were indistinguishable on readback. That
 * left the central question of the stripe/corruption bug undecidable:
 * "low half correct, high half garbage" is produced identically by
 *   (a) capturing beat 1 correctly, then sampling a bus the chip has
 *       already stopped driving, and
 *   (b) the whole capture window sitting one cycle late, so beat 2
 *       lands in the LOW half and the dead bus lands in the high half.
 * Four rounds of hardware fixes were all aimed at (a) and none moved
 * the symptom. With the halves distinguishable, VGA_DBG_WORD0/1 answers
 * it outright: a low half of 0xAAAA means (a), a low half of 0xBBBB
 * means (b) and the fix is to sample both beats one cycle earlier.
 *
 * Kept as byte stores, deliberately: that is the write path all the
 * existing hardware evidence was gathered through, so only the data
 * pattern changes, not the access pattern. */
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

/* Diagnostic for the "80 clean vertical stripes" hardware finding
 * (2026-08-27): 80 is exactly vga_line_fetch's word count per scanline
 * (320 bytes / 4), and bypassing vga_line_fetch's real SDRAM path
 * entirely (feeding it a fixed word instead) made the screen go solid
 * white -- so everything from vga_line_fetch's own Wishbone request
 * outward is correct. What's still open is WHERE the bad bytes come
 * from: written wrong in the first place, or written right and read
 * back wrong specifically by vga_line_fetch's rapid back-to-back
 * access pattern.
 *
 * This reads the framebuffer back through the CPU's own bus access --
 * single, unhurried loads, the same trusted path that already read
 * WAD[0] back correctly -- and reports how many bytes aren't what
 * vga_smoke_test() just wrote, plus the first mismatch's offset/value.
 * All-correct here would mean the data really is right in SDRAM and
 * the corruption is specific to vga_line_fetch's read pattern, not the
 * fill; any mismatch would mean the write itself is already wrong and
 * vga_line_fetch is just showing the truth.
 *
 * SCOPE WIDENED TO THE WHOLE FRAMEBUFFER (2026-08-27): this used to
 * check only line 0 (320 bytes) and reported it clean, which was taken
 * as proof that "the data is correct in SDRAM". It proves no such
 * thing. vga_line_fetch's debug capture reports word 0/1 of whichever
 * scanline happens to be in flight when firmware reads the register --
 * essentially never line 0 -- so lines 1..199 (63,680 of the 64,000
 * bytes) had never been verified by anything at all. Line 1 onward is
 * also where the framebuffer first crosses a 512-byte SDRAM row
 * boundary, which line 0 never does.
 *
 * Counts are also split by halfword position, because the failing
 * fingerprint is specifically "low half fine, high half garbage": if
 * the WRITE path is what's broken, bad_hi will dominate here in the
 * CPU's own readback, and the read path is exonerated. */
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

    /* Word-granular readback of the two words vga_line_fetch reports
     * over VGA_DBG_WORD0/1, so the CPU's view of the exact same
     * locations can be compared side by side with the fetcher's. Both
     * must read 0xBBBBAAAA. */
    {
        volatile uint32_t *fbw = (volatile uint32_t *)VGA_FB_BASE;
        uart_print_str("FB word0/word1 via CPU: ");
        uart_print_hex32(fbw[0]);
        uart_print_str(" ");
        uart_print_hex32(fbw[1]);
        uart_print_str(" (expect 0xBBBBAAAA both)\r\n");
    }
}

/* TEMP DIAGNOSTIC (2026-08-27): dumps VGA_DBG_WORD0/1 -- the raw word
 * vga_line_fetch actually received from the real SDRAM path for word
 * positions 0 and 1 of whatever scanline it's currently mid-fetch on
 * -- five times, ~a frame apart (delay() is roughly a few ms; five
 * frames at ~60 Hz is under 100 ms either way, so this just needs to
 * be "more than one frame", not precisely timed). With the framebuffer
 * filled by vga_smoke_test()'s pattern, a correct read is 0xBBBBAAAA
 * every time.
 *
 * READING THE RESULT (see FB_PAT_LO's comment for the full reasoning):
 *   0xBBBBAAAA  -- read path is fine, look elsewhere
 *   0x????AAAA  -- beat 1 captured, then a bus the chip is no longer
 *                  driving: the burst really is delivering one beat
 *   0x????BBBB  -- beat 2 landed in the LOW half: the capture window
 *                  is one cycle late, and both sample points in
 *                  sdram_controller's ST_READ_DATA/ST_READ_DATA2 need
 *                  to move one cycle earlier
 * A garbage half whose set bits are a superset of the previous beat's
 * (e.g. bits 0 and 8 when the last driven value was 0x0101) is residual
 * charge on an undriven bus, not data.
 *
 * If they're RIGHT here but the screen is still wrong, the bug would
 * have to be in words 2..79, which this doesn't cover. */
static void vga_dbg_dump(void)
{
    int i;

    for (i = 0; i < 5; i++) {
        uart_print_str("VGA_DBG word0=");
        uart_print_hex32(VGA_DBG_WORD0);
        uart_print_str(" word1=");
        uart_print_hex32(VGA_DBG_WORD1);
        uart_print_str("\r\n");
        delay();
    }
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
    vga_dbg_dump();

    while (1) {
        GPIO_LED = 0x0u;  /* active-low: all LEDs ON */
        delay();
        GPIO_LED = 0xFu;  /* active-low: all LEDs OFF */
        delay();
    }

    return 0;
}
