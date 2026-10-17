/*
** EPITECH PROJECT, 2026
** magic
** File description:
** Magic number fixture
*/

#define BUFFER_SIZE 4096

const int MAX_PLAYERS = 4;

enum color {
    RED = 2,
};

int read_all(int fd)
{
    char buffer[4096];
    int total = 0;

    total = total + 42 - 1 + 0;
    if (total == -5 || total == 0x10) {
        return 84;
    }
    return total * 2.5 + -1;
}
