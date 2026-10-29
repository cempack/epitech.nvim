#include <stdlib.h>
#include "../../include/my.h"

char *my_strdup(char const *src)
{
    char *copy = malloc(sizeof(char) * (my_strlen(src) + 1));

    if (copy == NULL) {
        return NULL;
    }
    return my_strcpy(copy, src);
}
