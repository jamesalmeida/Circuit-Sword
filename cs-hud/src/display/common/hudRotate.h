//-------------------------------------------------------------------------
// Optional 180-degree rotation of HUD layers.
//
// Under the Bookworm fkms driver the firmware no longer applies
// display_rotate, so DispmanX layers must rotate themselves. Set
// CS_HUD_ROTATE=180 in the environment to enable. The firmware rotates each
// element about the display, so destination rectangles stay unchanged.
//-------------------------------------------------------------------------

#ifndef HUD_ROTATE_H
#define HUD_ROTATE_H

#include <stdlib.h>
#include <string.h>

#include "bcm_host.h"

static inline DISPMANX_TRANSFORM_T hudTransform(void)
{
    static int enabled = -1;
    if (enabled < 0)
    {
        const char *value = getenv("CS_HUD_ROTATE");
        enabled = (value != NULL && strcmp(value, "180") == 0);
    }
    return enabled ? DISPMANX_ROTATE_180 : DISPMANX_NO_ROTATE;
}

#endif
