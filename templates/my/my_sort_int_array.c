#include "../../include/my.h"

static int sort_pass(int *tab, int size)
{
    int swapped = 0;
    int i = 0;

    while (i < size - 1) {
        if (tab[i] > tab[i + 1]) {
            my_swap(&tab[i], &tab[i + 1]);
            swapped = 1;
        }
        i++;
    }
    return swapped;
}

void my_sort_int_array(int *tab, int size)
{
    int swapped = 1;

    while (swapped) {
        swapped = sort_pass(tab, size);
    }
}
