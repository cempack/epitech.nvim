int loop_for_if(int a)
{
    while (a > 0) {
        for (int i = 0; i < a; i++) {
            if (i == 2) {
                return i;
            }
        }
        a--;
    }
    return a;
}

int chain_three_ifs(int a)
{
    if (a == 1) {
        return 1;
    } else if (a == 2) {
        return 2;
    } else if (a == 3) {
        return 3;
    }
    return 0;
}

int else_if_while(int a)
{
    if (a == 1) {
        return 1;
    } else if (a == 2) {
        while (a > 0) {
            a--;
        }
    }
    return a;
}

int chain_with_else(int a)
{
    if (a == 1) {
        return 1;
    } else if (a == 2) {
        return 2;
    } else {
        return 3;
    }
}

int loop_if(int a)
{
    while (a > 0) {
        if (a == 2) {
            return a;
        }
        a--;
    }
    return a;
}

int four_branches(int a)
{
    if (a == 1) {
        return 1;
    } else if (a == 2) {
        return 2;
    } else if (a == 3) {
        return 3;
    } else {
        return 4;
    }
}

int switch_level(int a)
{
    while (a > 0) {
        switch (a) {
            case 1:
                if (a == 1) {
                    return 1;
                }
                break;
            default:
                a--;
                break;
        }
    }
    return a;
}
