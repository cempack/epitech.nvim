#include "../../include/my.h"

char *my_strcat(char *dest, char const *src)
{
    int start = 0;
    int i = 0;

    while (dest[start] != '\0') {
        start++;
    }
    while (src[i] != '\0') {
        dest[start + i] = src[i];
        i++;
    }
    dest[start + i] = '\0';
    return dest;
}
