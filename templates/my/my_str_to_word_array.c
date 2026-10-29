#include <stdlib.h>
#include "../../include/my.h"

static int is_alphanumeric(char c)
{
    if (c >= 'a' && c <= 'z') {
        return 1;
    }
    if (c >= 'A' && c <= 'Z') {
        return 1;
    }
    return c >= '0' && c <= '9';
}

static int is_word_start(char const *str, int i)
{
    if (!is_alphanumeric(str[i])) {
        return 0;
    }
    return i == 0 || !is_alphanumeric(str[i - 1]);
}

static int count_words(char const *str)
{
    int count = 0;
    int i = 0;

    while (str[i] != '\0') {
        count += is_word_start(str, i);
        i++;
    }
    return count;
}

static char *copy_word(char const *str)
{
    char *word;
    int len = 0;

    while (is_alphanumeric(str[len])) {
        len++;
    }
    word = malloc(sizeof(char) * (len + 1));
    if (word == NULL) {
        return NULL;
    }
    my_strncpy(word, str, len);
    word[len] = '\0';
    return word;
}

char **my_str_to_word_array(char const *str)
{
    char **array = malloc(sizeof(char *) * (count_words(str) + 1));
    int word = 0;
    int i = 0;

    if (array == NULL) {
        return NULL;
    }
    while (str[i] != '\0') {
        if (is_word_start(str, i)) {
            array[word] = copy_word(str + i);
            word++;
        }
        i++;
    }
    array[word] = NULL;
    return array;
}
