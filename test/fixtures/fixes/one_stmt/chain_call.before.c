int read_twice(int fd)
{
    int a;
    int b;

    a = b = read_value(fd);
    return a + b;
}
