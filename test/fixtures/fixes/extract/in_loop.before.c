void walk(char *str, sfVector2f pos)
{
    int steps = 0;

    while (*str) {
        if (*str == 'x') {
            steps++;
            pos.x += 1;
            str++;
        }
        str++;
    }
    my_put_nbr(steps);
}
