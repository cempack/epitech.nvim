#include "../../include/my.h"

int my_is_prime(int nb)
{
    int const first_prime = 2;
    int divisor = first_prime;

    if (nb < first_prime) {
        return 0;
    }
    while (divisor <= nb / divisor) {
        if (nb % divisor == 0) {
            return 0;
        }
        divisor++;
    }
    return 1;
}
