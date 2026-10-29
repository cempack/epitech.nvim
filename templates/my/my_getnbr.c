#include <limits.h>
#include "../../include/my.h"

int my_getnbr(char const *str)
{
    long nb = 0;
    int sign = 1;
    int i = 0;

    while (str[i] == '-' || str[i] == '+') {
        if (str[i] == '-') {
            sign = -sign;
        }
        i++;
    }
    while (str[i] >= '0' && str[i] <= '9') {
        nb = nb * 10 + str[i] - '0';
        if (nb * sign > INT_MAX || nb * sign < INT_MIN) {
            return 0;
        }
        i++;
    }
    return nb * sign;
}
