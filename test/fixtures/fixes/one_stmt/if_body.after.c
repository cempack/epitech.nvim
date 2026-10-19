int reset(int a, int b)
{
    if (a > 0) {
        a = 0;
        b = 0;
    } else
        b++;
    return a + b;
}
