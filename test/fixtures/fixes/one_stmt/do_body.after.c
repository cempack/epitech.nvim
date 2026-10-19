int clear_tab(int *tab, int n)
{
    int j = 0;

    do {
        tab[j] = 0;
        j++;
    } while (j < n);
    return j;
}
