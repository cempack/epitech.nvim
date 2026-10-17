int get_vowel_kind(char c)
{
    int kind = 0;

    switch (c) {
        case 'a':
        case 'A':
            kind = 1;
            break;
        case 'e':
        case 'E':
            kind = 2;
            break;
        case 'i':
            kind = 3;
            break;
        default:
            kind = 4;
            break;
    }
    return kind;
}
