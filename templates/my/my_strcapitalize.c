#include "../../include/my.h"

static int is_alphanumeric(char c)
{
    if (c >= 'a' && c <= 'z') {
        return 1;
    }
    if (c >= 'A' && c <= 'Z') {
        return 1;
    }
    return c >= '0' && c <= '9';
}

static int starts_word(char const *str, int i)
{
    return i == 0 || !is_alphanumeric(str[i - 1]);
}

char *my_strcapitalize(char *str)
{
    int i = 0;

    my_strlowcase(str);
    while (str[i] != '\0') {
        if (str[i] >= 'a' && str[i] <= 'z' && starts_word(str, i)) {
            str[i] = str[i] - 'a' + 'A';
        }
        i++;
    }
    return str;
}
