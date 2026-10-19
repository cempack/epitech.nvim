int read_all(int fd, char *buffer)
{
    int size = 0;

    while (size < 10) {
        size = read(fd, buffer, 10);
        if (size <= 0)
            return size;
    }
    return size;
}
