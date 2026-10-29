#include <unistd.h>
#include "../../include/my.h"

void my_putchar(char c)
{
    write(STDOUT_FILENO, &c, 1);
}
