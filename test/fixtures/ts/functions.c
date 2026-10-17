/*
** EPITECH PROJECT, 2026
** finder
** File description:
** Function finder fixture
*/

#include <stdarg.h>

int print_help();
char **split_words(char const *str, char sep);

static int is_separator(char c)
{
    return c == ' ' || c == '\t';
}

char *dup_str(char const *str)
{
    return 0;
}

int sum_all(int count, ...)
{
    int total = 0;

    return total + count;
}

int add_long_names(int first_long_parameter_name,
    int second_long_parameter_name)
{
    return first_long_parameter_name + second_long_parameter_name;
}

int main(void)
{
    return 0;
}

int print_help()
{
    return 0;
}
