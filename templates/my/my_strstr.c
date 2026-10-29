#include <stddef.h>
#include "../../include/my.h"

char *my_strstr(char *str, char const *to_find)
{
    int len = 0;
    int i = 0;

    while (to_find[len] != '\0') {
        len++;
    }
    if (len == 0) {
        return str;
    }
    while (str[i] != '\0') {
        if (my_strncmp(str + i, to_find, len) == 0) {
            return str + i;
        }
        i++;
    }
    return NULL;
}
