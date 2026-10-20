char *find_word(char *str, char const *word)
{
    int i = 0;
    int len = 0;

    while (word[len])
        len++;
    while (str[i]) {
        if (my_strncmp(str + i, word, len) == 0)
            return str + i;
        i++;
    }
    return NULL;
}
