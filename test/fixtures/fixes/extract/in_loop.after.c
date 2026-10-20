static void step_on(char **str, int *steps, sfVector2f *pos)
{
    if (**str == 'x') {
        (*steps)++;
        pos->x += 1;
        (*str)++;
    }
}

void walk(char *str, sfVector2f pos)
{
    int steps = 0;

    while (*str) {
        step_on(&str, &steps, &pos);
        str++;
    }
    my_put_nbr(steps);
}
