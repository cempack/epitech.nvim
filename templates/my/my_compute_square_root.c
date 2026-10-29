#include "../../include/my.h"

int my_compute_square_root(int nb)
{
    long root = 1;

    if (nb <= 0) {
        return 0;
    }
    while (root * root < nb) {
        root++;
    }
    if (root * root == nb) {
        return root;
    }
    return 0;
}
