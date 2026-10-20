#include <unistd.h>

typedef struct stats_s {
    int words;
    int lines;
} stats_t;

static void count_words(char const *str, char separator, stats_t *stats)
{
    int in_word = 0;
    int i = 0;

    while (str[i] != '\0') {
        if (str[i] != separator && !in_word) {
            stats->words++;
            in_word = 1;
        }
        if (str[i] == separator)
            in_word = 0;
        if (str[i] == '\n')
            stats->lines++;
        i++;
    }
}

/*
** Counts words and lines, then prints them.
*/
int count_text(char const *str, char separator)
{
    stats_t stats = {0, 0};

    count_words(str, separator, &stats);
    write(1, &stats, sizeof(stats));
    return stats.words;
}
