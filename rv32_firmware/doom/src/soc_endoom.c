//
// soc_endoom.c -- stub for i_endoom.c on CPU_FPGA.
//
// Upstream renders the DOS text-mode ENDOOM screen (16-color CGA text
// art, shown briefly on quit) using ncurses/console APIs this board
// doesn't have. d_main.c's D_Endoom() calls this unconditionally on
// shutdown (registered as an I_AtExit hook) when show_endoom is set,
// so it needs to exist and return -- there's no text console to draw
// it on here, so it's just skipped.
//

#include "doomtype.h"

void I_Endoom(byte *data)
{
    (void)data;
}
