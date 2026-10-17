int open_file(char const *path)
{
    int fd;

    if ((fd = open(path, O_RDONLY)) == -1) {
        return 84;
    }
    return fd;
}
