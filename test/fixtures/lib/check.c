/*
** Behaviour of the libmy templates (templates/my/), compiled and run by
** test/lib.lua when a C compiler is available. Prints each failure and
** exits 1 when there is one.
*/

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "my.h"

static int failures = 0;

static void check(int ok, char const *what)
{
    if (!ok) {
        printf("FAILED: %s\n", what);
        failures++;
    }
}

static int reverse_cmp(char const *a, char const *b)
{
    return strcmp(b, a);
}

static void check_numbers(void)
{
    int tab[] = {4, -2, 9, 0, 3};

    check(my_getnbr("--+-42abc") == -42, "my_getnbr signs");
    check(my_getnbr("2147483647") == INT_MAX, "my_getnbr INT_MAX");
    check(my_getnbr("-2147483648") == INT_MIN, "my_getnbr INT_MIN");
    check(my_getnbr("2147483648") == 0, "my_getnbr overflow");
    check(my_compute_power_rec(2, 10) == 1024, "power");
    check(my_compute_power_rec(2, -1) == 0, "power < 0");
    check(my_compute_power_rec(5, 0) == 1, "power 0");
    check(my_compute_power_rec(2, 31) == 0, "power overflow");
    check(my_compute_square_root(49) == 7, "square root");
    check(my_compute_square_root(50) == 0, "square root not whole");
    check(my_compute_square_root(INT_MAX) == 0, "square root INT_MAX");
    check(my_is_prime(2) && my_is_prime(97) && !my_is_prime(1), "is_prime");
    check(!my_is_prime(-7) && !my_is_prime(91), "is_prime negatives");
    check(my_find_prime_sup(90) == 97 && my_find_prime_sup(-5) == 2, "prime sup");
    my_sort_int_array(tab, 5);
    check(tab[0] == -2 && tab[2] == 3 && tab[4] == 9, "sort int array");
}

static void check_strings(void)
{
    char buffer[64];
    char hay[] = "hello world";

    check(my_strlen("hello") == 5 && my_strlen("") == 0, "strlen");
    check(strcmp(my_strcpy(buffer, "abc"), "abc") == 0, "strcpy");
    check(strcmp(my_strcat(buffer, "def"), "abcdef") == 0, "strcat");
    check(strcmp(my_strncat(buffer, "ghij", 2), "abcdefgh") == 0, "strncat");
    my_strncpy(buffer, "xy", 4);
    check(buffer[0] == 'x' && buffer[2] == '\0' && buffer[3] == '\0', "strncpy");
    check(my_strcmp("abc", "abd") < 0 && my_strcmp("b", "a") > 0, "strcmp");
    check(my_strcmp("abc", "abc") == 0, "strcmp equal");
    check(my_strncmp("abcx", "abcy", 3) == 0, "strncmp");
    check(my_strncmp("abcx", "abcy", 4) < 0, "strncmp differs");
    check(my_strstr(hay, "wor") == hay + 6 && my_strstr(hay, "") == hay, "strstr");
    check(my_strstr(hay, "xyz") == NULL, "strstr missing");
    my_strcpy(buffer, "abcd");
    check(strcmp(my_revstr(buffer), "dcba") == 0, "revstr");
    my_strcpy(buffer, "hey, how are you? 42WORds forty-two; fifty+one");
    check(strcmp(my_strcapitalize(buffer),
        "Hey, How Are You? 42words Forty-Two; Fifty+One") == 0, "capitalize");
    check(strcmp(my_strupcase(buffer), "HEY, HOW ARE YOU? 42WORDS FORTY-TWO; FIFTY+ONE") == 0, "upcase");
    check(my_str_isnum("123") && !my_str_isnum("12a"), "isnum");
    check(my_str_isalpha("abC") && !my_str_isalpha("ab1"), "isalpha");
    check(my_str_islower("abc") && !my_str_islower("aBc"), "islower");
    check(my_str_isupper("ABC") && !my_str_isupper("AbC"), "isupper");
    check(my_str_isprintable("a b~") && !my_str_isprintable("a\tb"), "isprintable");
}

static void check_arrays(void)
{
    char **words = my_str_to_word_array("  hello,world 42 ");
    char *argv[] = {"./a.out", "one", "two"};
    char *joined = concat_params(3, argv);
    char *copy = my_strdup("copy");

    check(words != NULL && strcmp(words[0], "hello") == 0, "word array 0");
    check(strcmp(words[1], "world") == 0 && strcmp(words[2], "42") == 0, "word array 1, 2");
    check(words[3] == NULL, "word array end");
    my_sort_word_array(words);
    check(strcmp(words[0], "42") == 0 && strcmp(words[2], "world") == 0, "sort words");
    my_advanced_sort_word_array(words, reverse_cmp);
    check(strcmp(words[0], "world") == 0 && strcmp(words[2], "42") == 0, "advanced sort");
    check(strcmp(joined, "./a.out\none\ntwo") == 0, "concat_params");
    check(strcmp(copy, "copy") == 0, "strdup");
    free(joined);
    free(copy);
}

int main(void)
{
    char *words[] = {"a", "b", NULL};
    int a = 1;
    int b = 2;

    check_numbers();
    check_strings();
    check_arrays();
    my_swap(&a, &b);
    check(a == 2 && b == 1, "swap");
    fflush(stdout);
    my_put_nbr(INT_MIN);
    my_putchar(' ');
    my_put_nbr(0);
    my_putchar(' ');
    my_putstr("x");
    my_isneg(-1);
    my_showstr("a\tb\n");
    my_putchar('\n');
    my_show_word_array(words);
    return failures > 0;
}
