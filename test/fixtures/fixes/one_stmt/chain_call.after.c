int read_twice(int fd)
{
    int a;
    int b;

    b = read_value(fd);
    a = b;
    return a + b;
}
