//
// doomgeneric_soc.c -- CPU_FPGA platform layer for doomgeneric.
//
// Implements the five hooks doomgeneric.h asks any port to provide.
// DOOMGENERIC_RESX/RESY are set to 320x200 at build time (see the
// Makefile) so this is a 1:1 pixel copy into VGA_FB_BASE, never a
// scale -- doomgeneric's internal renderer already resolves Doom's
// 256-color palette into a full 32-bit ARGB DG_ScreenBuffer before
// handing it to DG_DrawFrame, so the only work left here is
// quantizing each pixel down to the 8 colors vga_pixel_pipeline.vhd's
// 3-bit (1 bit/channel) palette can actually display. See
// docs/README.md Phase 5.2.
//

#include <stdint.h>
#include "doomgeneric.h"
#include "soc_regs.h"

#if DOOMGENERIC_RESX != VGA_FB_WIDTH || DOOMGENERIC_RESY != VGA_FB_HEIGHT
#error "doomgeneric_soc.c assumes DOOMGENERIC_RESX/RESY match the VGA framebuffer exactly -- check the Makefile's -D flags"
#endif

static uint8_t volatile * const vga_fb = (uint8_t volatile *)VGA_FB_BASE;

// ---- UART (diagnostics only -- see also soc_syscalls.c, which routes
// stdio through the same uart_putc) ------------------------------------

void uart_putc(uint8_t c)
{
    while (UART_ST & 1u) {
        // tx busy
    }
    UART_TX = (uint32_t)c;
}

void uart_print_str(const char *s)
{
    while (*s) {
        uart_putc((uint8_t)*s++);
    }
}

// ---- DG_Init -----------------------------------------------------------

void DG_Init(void)
{
    unsigned i;

    // Blank the framebuffer to palette index 0 before the first real
    // frame lands, so there's no garbage on screen during WAD/level load.
    for (i = 0; i < (unsigned)(VGA_FB_WIDTH * VGA_FB_HEIGHT); i++) {
        vga_fb[i] = 0;
    }

    uart_print_str("DG_Init: doomgeneric platform layer up\r\n");
}

// ---- DG_DrawFrame --------------------------------------------------------
//
// DG_ScreenBuffer is pixel_t = uint32_t, byte order 0xAARRGGBB (see
// doomgeneric.h / i_video.c's I_FinishUpdate -> DG_DrawFrame call).
// vga_pixel_pipeline.vhd keeps only the low 3 bits of each palette
// entry (PALETTE_BITS = 3, one bit each R/G/B), and main.c's palette
// setup (Phase 4.2) writes entry N's low 3 bits as {R,G,B} each
// thresholded on/off -- so an index built the same way here,
// (r<<2)|(g<<1)|b with r/g/b each a single "is this channel bright"
// bit, lands on the same 8 colors that palette already defines.
//
// A flat per-channel threshold at 128 (the original version of this
// function) throws away almost the entire picture: Doom's palette is
// mostly mid-tones (shading, brown/gray walls, the maroon of the
// DOOM logo itself), and *all* of that rounds down to black/off,
// leaving only the brightest highlight pixels -- confirmed on real
// hardware 2026-08-29, title screen showed only scattered bevel-edge
// pixels, rest of the picture gone. Ordered (Bayer) dithering fixes
// this without touching the 3-bit hardware palette: instead of one
// fixed threshold, the threshold varies per pixel position in a
// repeating 4x4 pattern, so a mid-tone channel value ends up above
// the threshold at some positions and below it at others. The result
// is a dot pattern whose *average* density approximates the true
// brightness -- the standard trick for getting more perceived shades
// out of fewer real ones.

static const uint8_t bayer4x4[4][4] = {
    {  0, 8, 2, 10 },
    { 12, 4, 14, 6 },
    {  3, 11, 1, 9 },
    { 15, 7, 13, 5 },
};

static void uart_print_udec(uint32_t v)
{
    char digits[10];
    int n = 0;

    if (v == 0) {
        uart_putc('0');
        return;
    }
    while (v > 0 && n < 10) {
        digits[n++] = (char)('0' + (v % 10u));
        v /= 10u;
    }
    while (n > 0) {
        uart_putc((uint8_t)digits[--n]);
    }
}

void DG_DrawFrame(void)
{
    unsigned x, y;
    const uint32_t *row = DG_ScreenBuffer;
    uint8_t volatile *fb_row = vga_fb;

    // Diagnostic: how long since the previous frame finished, so we
    // can tell "the game is responding but slowly" apart from "the
    // game is stuck" -- see the 2026-08-29 button-latency question.
    // DG_GetTicksMs is defined further down in this file but declared
    // in doomgeneric.h, which is included above.
    {
        static uint32_t last_ms = 0;
        uint32_t now_ms = DG_GetTicksMs();
        uart_print_str("DG_DrawFrame: +");
        uart_print_udec(now_ms - last_ms);
        uart_print_str("ms\r\n");
        last_ms = now_ms;
    }

    for (y = 0; y < VGA_FB_HEIGHT; y++) {
        const uint8_t *bayer_row = bayer4x4[y & 3u];

        for (x = 0; x < VGA_FB_WIDTH; x++) {
            uint32_t px = row[x];
            uint32_t r = (px >> 16) & 0xFFu;
            uint32_t g = (px >> 8) & 0xFFu;
            uint32_t b = px & 0xFFu;

            // Doom's actual art (title screen included) leans dark --
            // confirmed on real hardware 2026-08-29, dithering alone
            // still left most of the picture black. A flat brightness
            // boost before quantizing pulls those mid-low tones up
            // into the dither's visible range; without it they're
            // below every threshold in the 4x4 tile and never light
            // up no matter how fine the dither pattern is. 3/2 gain,
            // clamped -- tune BRIGHTNESS_NUM/DEN if it's still too
            // dark or starts blowing out to solid color.
#define BRIGHTNESS_NUM 3
#define BRIGHTNESS_DEN 2
            r = (r * BRIGHTNESS_NUM) / BRIGHTNESS_DEN;
            g = (g * BRIGHTNESS_NUM) / BRIGHTNESS_DEN;
            b = (b * BRIGHTNESS_NUM) / BRIGHTNESS_DEN;
            if (r > 255u) r = 255u;
            if (g > 255u) g = 255u;
            if (b > 255u) b = 255u;

            // bayer_row[x&3] in 0..15 -> threshold in 0..240, spread
            // evenly across the 4x4 tile so each channel's 16 possible
            // "brightness buckets" get their own on/off crossover point.
            uint8_t threshold = (uint8_t)(bayer_row[x & 3u] << 4);

            uint8_t idx = (uint8_t)(((r > threshold) << 2) |
                                     ((g > threshold) << 1) |
                                     (b > threshold));

            fb_row[x] = idx;
        }

        row += VGA_FB_WIDTH;
        fb_row += VGA_FB_WIDTH;
    }
}

// ---- Timing --------------------------------------------------------------
//
// TIMER (timer.vhd) is a free-running 32-bit up-counter, +1 every clk
// (sys_clk = 50 MHz, CPU_FPGA.sdc), wrapping every ~85.9s. 50000
// counts/ms. Unsigned subtraction below is wraparound-safe as long as
// the true elapsed time never exceeds ~85s between two ticks queried,
// which holds for anything frame-rate related.

#define TIMER_COUNTS_PER_MS 50000u

uint32_t DG_GetTicksMs(void)
{
    return TIMER / TIMER_COUNTS_PER_MS;
}

void DG_SleepMs(uint32_t ms)
{
    uint32_t start = TIMER;
    uint32_t target = ms * TIMER_COUNTS_PER_MS;

    while ((TIMER - start) < target) {
        // spin -- no interrupt/idle infrastructure on this SoC yet
    }
}

// ---- Input -----------------------------------------------------------------
//
// GPIO_KEY: 4 buttons, active-low, debounced in RTL (gpio_key.vhd,
// hardware-confirmed 2026-08-28). Only 4 raw inputs exist on this
// board, so this first-cut mapping covers fire/use/forward/turn only
// -- no strafe, no menu Enter/Escape, no backward movement yet. That's
// enough to validate rendering and WAD loading; revisit once Doom is
// actually up on hardware and it's clear what's most worth having a
// button for.
//
// GPIO_LED: nothing else in this firmware ever writes it, so whatever
// it shows on boot is just the register's reset default -- not
// meaningful, and definitely not evidence either way about whether
// button presses reach the CPU. Mirroring the raw GPIO_KEY read onto
// it here turns the LEDs into a live probe: if the LED pattern
// changes while a button is held, GPIO_KEY is updating and the fault
// (if any) is downstream of this file, in how doomgeneric turns the
// key event into game input. If the LEDs never move no matter what's
// pressed, GPIO_KEY itself is stuck -- a hardware/RTL question
// (wiring, pull resistors, gpio_key.vhd debounce logic), not
// something this file can fix. See also the uart_print_str below,
// which gives the same read but as an explicit press/release log on
// the UART instead of something that has to be eyeballed on the
// board -- confirmed on real hardware 2026-08-29: LEDs stuck fully
// on since boot, buttons apparently inert; not yet known which side
// of this boundary the fault is on.

#include "doomkeys.h"

static const unsigned char key_map[4] = {
    KEY_FIRE,       // BTN0
    KEY_USE,        // BTN1
    KEY_UPARROW,    // BTN2 -- move forward
    KEY_RIGHTARROW, // BTN3 -- turn right
};

static uint32_t key_prev_state = 0xFu; // active-low idle = all released (1s)
static uint32_t key_scan_state;
static int key_scan_idx = 0;

static void uart_print_hex_nibble(uint8_t v)
{
    uart_putc((uint8_t)((v < 10) ? ('0' + v) : ('a' + (v - 10))));
}

int DG_GetKey(int *pressed, unsigned char *key)
{
    if (key_scan_idx == 0) {
        key_scan_state = GPIO_KEY & 0xFu;

        // Diagnostic: raw button state, unfiltered, straight onto the
        // LEDs every poll -- see the file-level comment above.
        GPIO_LED = key_scan_state;
    }

    for (; key_scan_idx < 4; key_scan_idx++) {
        uint32_t mask = 1u << key_scan_idx;
        uint32_t now = key_scan_state & mask;
        uint32_t prev = key_prev_state & mask;

        if (now != prev) {
            *pressed = (now == 0u); // active-low: 0 = pressed
            *key = key_map[key_scan_idx];
            key_prev_state = (key_prev_state & ~mask) | now;
            key_scan_idx++;

            uart_print_str("DG_GetKey: BTN");
            uart_print_hex_nibble((uint8_t)(key_scan_idx - 1));
            uart_print_str(*pressed ? " down\r\n" : " up\r\n");

            return 1;
        }
    }

    key_scan_idx = 0;
    return 0;
}

void DG_SetWindowTitle(const char *title)
{
    (void)title; // no window to title
}