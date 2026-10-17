int open_file(char const *path)
{
    int fd;

    fd = open(path, O_RDONLY);
    if (fd == -1) {
        return 84;
    }
    return fd;
}
