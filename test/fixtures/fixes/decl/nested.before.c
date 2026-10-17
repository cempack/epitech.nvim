int walk(int n)
{
    int total = 0;

    while (n > 0) {
        int step = n % 3;

        total = total + step;
        n--;
    }
    return total;
}
