#include "../../include/my.h"

static int is_alpha(char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

int my_str_isalpha(char const *str)
{
    int i = 0;

    while (str[i] != '\0') {
        if (!is_alpha(str[i])) {
            return 0;
        }
        i++;
    }
    return 1;
}
