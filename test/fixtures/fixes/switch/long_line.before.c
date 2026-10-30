/*
** EPITECH PROJECT, 2026
** switch
** File description:
** A branch line that only fits before the switch indents it
*/

int print_flag(char flag)
{
    if (flag == 'a') {
        my_putstr("this line is long enough to overflow once indented more");
    } else if (flag == 'b') {
        return 2;
    } else if (flag == 'c') {
        return 3;
    } else {
        return 4;
    }
    return 0;
}
