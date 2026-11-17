/* KOVCHEG probe: prints the compile-time properties of the binary so a build
 * report can prove which architecture and libc actually produced it. */
#include <stdio.h>

#if defined(__x86_64__)
#  define KARCH "x86_64"
#elif defined(__i386__)
#  define KARCH "i386"
#elif defined(__aarch64__)
#  define KARCH "aarch64"
#elif defined(__arm__)
#  define KARCH "arm"
#elif defined(__riscv)
#  define KARCH "riscv"
#else
#  define KARCH "unknown"
#endif

#if defined(__BYTE_ORDER__) && defined(__ORDER_BIG_ENDIAN__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#  define KENDIAN "be"
#else
#  define KENDIAN "le"
#endif

#if defined(__GLIBC__)
#  define KLIBC "glibc"
#elif defined(__linux__)
#  define KLIBC "other"
#else
#  define KLIBC "unknown"
#endif

int main(void)
{
    printf("selftest arch=%s ptr=%u endian=%s libc=%s\n",
           KARCH, (unsigned)(sizeof(void *) * 8), KENDIAN, KLIBC);
    return 0;
}
