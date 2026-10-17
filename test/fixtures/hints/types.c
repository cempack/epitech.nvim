#include <unistd.h>

int my_putchar(char c);
int show(char *str);

int count_char(char *str, char c)
{
    int count = 0;

    for (int i = 0; str[i] != '\0'; i++) {
        if (str[i] == c) {
            count++;
        }
    }
    return count;
}

void fill(char *str, char c)
{
    str[0] = c;
}

void bump(int *value)
{
    (*value)++;
}

void set_name(struct player *player)
{
    player->name = 0;
}

int print_all(char *str)
{
    return write(1, str, 4);
}

int pass_on(char *str)
{
    return show(str);
}

char *give_back(char *str)
{
    return str;
}

int walk(char *str)
{
    int total = 0;

    while (*str) {
        total = total + my_putchar(*str);
        str++;
    }
    return total;
}

int get_hp(struct player *player)
{
    if (player == NULL || !player) {
        return 0;
    }
    return player->hp > 0;
}

int copy_out(struct player *player)
{
    int *hp = player->hps;

    return hp[0];
}

int deref_offset(char *str)
{
    return *(str + 1);
}

int write_offset(char *str)
{
    *(str + 1) = 'a';
    return 0;
}

int addr_of(char *str)
{
    return show(&str[1]);
}

int lengths(char const *str)
{
    int len = strlen(str);
    int size = sizeof(int);
    long ok = strlen(str);
    int later;

    later = my_strlen(str);
    later = 3;
    return len + size + ok + later;
}
