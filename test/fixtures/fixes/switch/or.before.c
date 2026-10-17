int get_vowel_kind(char c)
{
    int kind = 0;

    if (c == 'a' || c == 'A') {
        kind = 1;
    } else if (c == 'e' || c == 'E') {
        kind = 2;
    } else if (c == 'i') {
        kind = 3;
    } else {
        kind = 4;
    }
    return kind;
}
