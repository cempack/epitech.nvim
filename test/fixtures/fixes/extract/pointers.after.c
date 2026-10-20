static void add_lines(int count, int *total, char **lines, char *buffer)
{
    for (int i = 0; i < count; i++) {
        *total += my_strlen(lines[i]);
        buffer[i % 64] = lines[i][0];
    }
}

int sum_lines(char **lines, int count)
{
    int total = 0;
    char buffer[64];

    add_lines(count, &total, lines, buffer);
    my_putstr(buffer);
    return total;
}
