int read_all(int fd, char *buffer)
{
    int size = 0;

    while (size < 10)
        if ((size = read(fd, buffer, 10)) <= 0)
            return size;
    return size;
}
