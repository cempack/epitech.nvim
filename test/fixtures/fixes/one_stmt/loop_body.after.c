void copy_str(char *dest, char const *src)
{
    while (*src) {
        *dest = *src;
        dest++;
        src++;
    }
    *dest = '\0';
}
