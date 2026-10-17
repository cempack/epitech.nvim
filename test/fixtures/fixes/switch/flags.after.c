int parse_flag(char flag, int *options)
{
    switch (flag) {
        case 'l':
            options[0] = 1;
            break;
        case 'a':
            options[1] = 1;
            break;
        case 'R':
            options[2] = 1;
            break;
        default:
            return 84;
    }
    return 0;
}
