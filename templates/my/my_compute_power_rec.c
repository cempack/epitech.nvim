#include <limits.h>
#include "../../include/my.h"

int my_compute_power_rec(int nb, int p)
{
    long result = nb;

    if (p < 0) {
        return 0;
    }
    if (p == 0) {
        return 1;
    }
    result = result * my_compute_power_rec(nb, p - 1);
    if (result > INT_MAX || result < INT_MIN) {
        return 0;
    }
    return result;
}
