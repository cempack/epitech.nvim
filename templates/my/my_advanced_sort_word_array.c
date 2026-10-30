#include <stddef.h>
#include "../../include/my.h"

static int sort_pass(char **tab, int (*cmp)(char const *, char const *))
{
    char *swap;
    int swapped = 0;
    int i = 0;

    while (tab[i] != NULL && tab[i + 1] != NULL) {
        if (cmp(tab[i], tab[i + 1]) > 0) {
            swap = tab[i];
            tab[i] = tab[i + 1];
            tab[i + 1] = swap;
            swapped = 1;
        }
        i++;
    }
    return swapped;
}

int my_advanced_sort_word_array(char **tab,
    int (*cmp)(char const *, char const *))
{
    int swapped = 1;

    while (swapped) {
        swapped = sort_pass(tab, cmp);
    }
    return 0;
}
