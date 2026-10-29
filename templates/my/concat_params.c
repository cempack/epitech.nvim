#include <stdlib.h>
#include "../../include/my.h"

static int get_params_size(int argc, char **argv)
{
    int size = 0;
    int i = 0;

    while (i < argc) {
        size += my_strlen(argv[i]) + 1;
        i++;
    }
    return size;
}

char *concat_params(int argc, char **argv)
{
    char *result = malloc(sizeof(char) * (get_params_size(argc, argv) + 1));
    int i = 0;

    if (result == NULL) {
        return NULL;
    }
    result[0] = '\0';
    while (i < argc) {
        my_strcat(result, argv[i]);
        if (i < argc - 1) {
            my_strcat(result, "\n");
        }
        i++;
    }
    return result;
}
