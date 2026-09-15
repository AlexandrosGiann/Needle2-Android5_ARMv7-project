/*
 * android5_compat.c
 *
 * Compatibility symbols for Android 5.x (API 21/22).
 *
 * Android API < 23 exposes the standard streams through __sF[] rather than
 * exported stdin/stdout/stderr pointer symbols.  The official prebuilt
 * Needle ARMv7 archive was built with a newer NDK and directly references
 * stderr, so provide the newer symbol names while pointing at the old Bionic
 * stream objects.
 */

#include <stdio.h>

#if defined(__ANDROID__) && (__ANDROID_API__ < 23)

extern FILE __sF[];

#undef stdin
#undef stdout
#undef stderr

FILE *stdin  = &__sF[0];
FILE *stdout = &__sF[1];
FILE *stderr = &__sF[2];

#endif
