int walk(int n)
{
    int total = 0;
    int step;

    while (n > 0) {
        step = n % 3;
        total = total + step;
        n--;
    }
    return total;
}
