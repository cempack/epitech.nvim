int get_score(int code)
{
    switch (code) {
        case 1:
            return 10;
        case 2:
            return 20;
        case MAX_CODE:
            return 30;
    }
    return 0;
}
