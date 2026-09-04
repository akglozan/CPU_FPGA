//
// w_file_mem.c -- CPU_FPGA bare-metal backend for doomgeneric's wad_file_class_t.
//
// The WAD is not on any filesystem: the ESP32 boot chain already DMA'd
// DOOM1.WAD into SDRAM at a fixed address (WAD_DEST_ADDR in
// esp32_firmware/src/main.cpp) before the CPU was even released from
// reset (see boot_loader.vhd). So "opening" the WAD is just handing back
// a wad_file_t that points straight at that address -- no fopen, no
// buffering, no syscalls.
//
// This replaces w_file_stdc.c. w_wad.c itself is unmodified.
//
// wad->mapped is deliberately left NULL, even though the WAD really is
// sitting in memory at a fixed address (that's the whole point of this
// file). Setting it non-NULL turns on w_wad.c's memory-mapped-file fast
// path in W_CacheLumpNum(), which hands out raw pointers straight into
// the WAD at lump->wad_file->mapped + lump->position for direct struct
// access (e.g. R_InitTextures reading a lump count as a 32-bit word).
// lump->position is an arbitrary byte offset from the WAD's own
// directory, not something under our control, and this CPU's pipeline
// does not handle a misaligned lw/sw the way x86 (what that fast path
// was written for) silently does -- confirmed on real hardware
// 2026-08-28: R_Init crashed with "Z_Malloc: failed on allocation of
// 91750424 bytes", a garbage lump-count read off an unaligned texture
// lump pointer. With mapped == NULL, W_CacheLumpNum instead always
// goes through Z_Malloc() + W_ReadLump() -> W_Mem_Read() below, which
// copies each lump byte-by-byte into a freshly zone-allocated (and
// therefore word-aligned) buffer before anything dereferences it as a
// struct. Slightly more zone memory and a few extra cycles per lump
// fetch; correct on this hardware, which matters more than the copy
// this was originally trying to save.
//

#include "w_file.h"
#include "z_zone.h"

#define WAD_BASE_ADDR   ((byte *)0x80100000u)
#define WAD_LENGTH      4207819u   /* DOOM1.WAD, shareware v1.0, confirmed size */

typedef struct
{
    wad_file_t wad;
} mem_wad_file_t;

extern wad_file_class_t mem_wad_file;

static wad_file_t *W_Mem_OpenFile(char *path)
{
    mem_wad_file_t *result;

    // We only ever have the one WAD, at the one fixed address. 'path' is
    // whatever synthetic name d_main.c was given (see soc_iwad.c) --
    // ignored, since there's nothing to look up.
    (void)path;

    result = Z_Malloc(sizeof(mem_wad_file_t), PU_STATIC, 0);
    result->wad.file_class = &mem_wad_file;
    result->wad.mapped = NULL;   /* see the file-level comment above */
    result->wad.length = WAD_LENGTH;

    return &result->wad;
}

static void W_Mem_CloseFile(wad_file_t *wad)
{
    // Nothing to release -- the WAD lives in SDRAM for the whole run.
    Z_Free(wad);
}

static size_t W_Mem_Read(wad_file_t *wad, unsigned int offset,
                          void *buffer, size_t buffer_len)
{
    size_t avail;

    if (offset >= wad->length)
    {
        return 0;
    }

    avail = wad->length - offset;
    if (buffer_len > avail)
    {
        buffer_len = avail;
    }

    // wad->mapped is NULL (see above), so the WAD's real base address
    // has to come from WAD_BASE_ADDR here, not wad->mapped.
    //
    // Byte loop, not memcpy: buffer==lump->cache came straight out of
    // Z_Malloc, but src can land on any byte offset into SDRAM, and
    // this core doesn't handle a misaligned word access -- the same
    // hazard this whole file exists to route around, so this can't
    // reach for a word-at-a-time memcpy either without reintroducing
    // it on the read side.
    {
        const byte *src = WAD_BASE_ADDR + offset;
        byte *dst = (byte *)buffer;
        size_t i;
        for (i = 0; i < buffer_len; i++)
        {
            dst[i] = src[i];
        }
    }

    return buffer_len;
}

wad_file_class_t mem_wad_file =
{
    W_Mem_OpenFile,
    W_Mem_CloseFile,
    W_Mem_Read,
};
