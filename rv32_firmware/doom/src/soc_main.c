//
// soc_main.c -- entry point for the CPU_FPGA bare-metal Doom build.
//
// crt0.s (rv32_firmware/bsp/crt0.s) clears .bss and calls main() with
// no arguments set up -- this build passes doomgeneric a fixed, empty
// argv rather than anything from crt0, since there's no command line
// on this hardware. doomgeneric's own main loop (doomgeneric_Create()
// once, then doomgeneric_Tick() forever) replaces what each upstream
// platform frontend (doomgeneric_sdl.c etc, all excluded from this
// build) would normally provide.
//

#include "doomgeneric.h"

int main(void)
{
    doomgeneric_Create(0, (char **)0);

    for (;;) {
        doomgeneric_Tick();
    }

    return 0;
}
