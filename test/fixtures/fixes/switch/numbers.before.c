int get_score(int code)
{
    if (code == 1) {
        return 10;
    } else if (2 == code) {
        return 20;
    } else if (code == MAX_CODE) {
        return 30;
    }
    return 0;
}
