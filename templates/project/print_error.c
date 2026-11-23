
#include <errno.h>
#include <unistd.h>
#include "my.h"
#include "@BASE@.h"

static char const *get_error_message(int error)
{
    switch (error) {
        case ENOENT:
            return "No such file or directory";
        case EACCES:
            return "Permission denied";
        case EISDIR:
            return "Is a directory";
        case ENOTDIR:
            return "Not a directory";
        case ENOMEM:
            return "Cannot allocate memory";
        case EINVAL:
            return "Invalid argument";
        case EIO:
            return "Input/output error";
        default:
            return "Unknown error";
    }
}

static void put_error(char const *str)
{
    write(STDERR_FILENO, str, my_strlen(str));
}

int print_error(char const *subject)
{
    char const *message = get_error_message(errno);

    put_error(PROGRAM_NAME);
    put_error(": ");
    put_error(subject);
    put_error(": ");
    put_error(message);
    put_error("\n");
    return EXIT_ERROR;
}

int print_error_message(char const *message)
{
    put_error(PROGRAM_NAME);
    put_error(": ");
    put_error(message);
    put_error("\n");
    return EXIT_ERROR;
}
