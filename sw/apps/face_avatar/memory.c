#include <stddef.h>
/* Required by compiler-generated structure copies in the freestanding image. */
void *memcpy(void *destination,const void *source,size_t bytes) {
    volatile unsigned char *d=destination;
    const volatile unsigned char *s=source;
    size_t i;for(i=0;i<bytes;++i)d[i]=s[i];return destination;
}
void *memset(void *destination,int value,size_t bytes) {
    volatile unsigned char *d=destination;
    size_t i;for(i=0;i<bytes;++i)d[i]=(unsigned char)value;return destination;
}
