/*
** EPITECH PROJECT, 2026
** switch
** File description:
** A branch line that only fits before the switch indents it
*/

int print_flag(char flag)
{
    switch (flag) {
        case 'a':
            my_putstr(
                "this line is long enough to overflow once indented more");
            break;
        case 'b':
            return 2;
        case 'c':
            return 3;
        default:
            return 4;
    }
    return 0;
}
