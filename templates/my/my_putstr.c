#include <unistd.h>
#include "../../include/my.h"

int my_putstr(char const *str)
{
    write(STDOUT_FILENO, str, my_strlen(str));
    return 0;
}
