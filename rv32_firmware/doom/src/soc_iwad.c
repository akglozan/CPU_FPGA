//
// soc_iwad.c -- replaces d_iwad.c for CPU_FPGA.
//
// Upstream d_iwad.c scans directories (and, on Windows, the registry)
// looking for an IWAD file. There is no filesystem here: DOOM1.WAD is
// already sitting in SDRAM at a fixed address before the CPU starts
// (see w_file_mem.c), so "finding" it is just returning a name --
// w_file_mem.c ignores the string content and always maps the fixed
// address. These are the only D_* iwad-lookup entry points anything
// outside d_iwad.c actually calls (checked by grepping the full
// doomgeneric source retained in this port); everything else in
// d_iwad.h's API is either unused here or was only ever called from
// within d_iwad.c itself.
//

#include <stddef.h>
#include "doomtype.h"
#include "d_mode.h"
#include "d_iwad.h"

char *D_FindIWAD(int mask, GameMission_t *mission)
{
    (void)mask;
    *mission = doom;
    return "DOOM1.WAD";
}

char *D_FindWADByName(char *filename)
{
    // Used for optional extras (e.g. chex.deh) that don't exist on this
    // build -- correctly reporting "not found" is the right answer.
    (void)filename;
    return NULL;
}

char *D_TryFindWADByName(char *filename)
{
    // Only reachable via -file/-deh/-iwad style command-line switches
    // (w_main.c); soc_main never passes those, so this never actually
    // runs, but it has to link.
    return filename;
}

char *D_SaveGameIWADName(GameMission_t mission)
{
    (void)mission;
    return "DOOM1";
}

char *D_SuggestGameName(GameMission_t mission, GameMode_t mode)
{
    // Only used to format an IWAD-mismatch I_Error() message -- can't
    // happen here since there's exactly one WAD and it's always this one.
    (void)mission;
    (void)mode;
    return "doom";
}
