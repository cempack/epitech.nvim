#include "../../include/my.h"

char *my_revstr(char *str)
{
    int start = 0;
    int end = 0;
    char swap;

    while (str[end] != '\0') {
        end++;
    }
    end--;
    while (start < end) {
        swap = str[start];
        str[start] = str[end];
        str[end] = swap;
        start++;
        end--;
    }
    return str;
}
