static char *search_word(char *str, char const *word, int len)
{
    int i = 0;

    while (str[i]) {
        if (my_strncmp(str + i, word, len) == 0)
            return str + i;
        i++;
    }
    return NULL;
}

char *find_word(char *str, char const *word)
{
    int len = 0;

    while (word[len])
        len++;
    return search_word(str, word, len);
}
