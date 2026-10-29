#include "../../include/my.h"

void my_swap(int *a, int *b)
{
    int swap = *a;

    *a = *b;
    *b = swap;
}
