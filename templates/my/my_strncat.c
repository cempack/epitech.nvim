#include "../../include/my.h"

char *my_strncat(char *dest, char const *src, int nb)
{
    int start = 0;
    int i = 0;

    while (dest[start] != '\0') {
        start++;
    }
    while (i < nb && src[i] != '\0') {
        dest[start + i] = src[i];
        i++;
    }
    dest[start + i] = '\0';
    return dest;
}
