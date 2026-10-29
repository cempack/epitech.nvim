#include "../../include/my.h"

static void put_hex_byte(unsigned char c)
{
    char const *digits = "0123456789abcdef";
    int const base = 16;

    my_putchar('\\');
    my_putchar(digits[c / base]);
    my_putchar(digits[c % base]);
}

int my_showstr(char const *str)
{
    int i = 0;

    while (str[i] != '\0') {
        if (str[i] >= ' ' && str[i] <= '~') {
            my_putchar(str[i]);
        } else {
            put_hex_byte(str[i]);
        }
        i++;
    }
    return 0;
}
