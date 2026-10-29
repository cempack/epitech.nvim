#include "../../include/my.h"

int my_find_prime_sup(int nb)
{
    while (!my_is_prime(nb)) {
        nb++;
    }
    return nb;
}
