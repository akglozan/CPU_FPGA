//
// soc_stubs.c -- trivial no-op stubs for subsystems that don't exist
// on this board: joystick (i_joystick.h -- no joystick hardware) and
// the "-statdump" debug feature (statdump.h -- a diagnostic dump for
// automated demo-comparison testing, irrelevant here). Restoring the
// real .c files for either would just pull in more file I/O / input
// APIs this SoC doesn't have, for functionality this build never
// otherwise uses (no -statdump argv is ever passed, and DG_GetKey
// covers the only input this board has). See docs/README.md Phase
// 5.2.
//

#include "doomtype.h"
#include "d_player.h"
#include "statdump.h"

void I_InitJoystick(void)
{
}

void I_BindJoystickVariables(void)
{
}

void StatDump(void)
{
}

void StatCopy(wbstartstruct_t *stats)
{
    (void)stats;
}
