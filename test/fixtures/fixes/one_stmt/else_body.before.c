int fill_tab(int *tab, int j, int n)
{
    if (n < 0) {
        return 0;
    } else
        tab[j++] = n;
    return j;
}
