int parse_flag(char flag, int *options)
{
    if (flag == 'l') {
        options[0] = 1;
    } else if (flag == 'a') {
        options[1] = 1;
    } else if (flag == 'R') {
        options[2] = 1;
    } else {
        return 84;
    }
    return 0;
}
