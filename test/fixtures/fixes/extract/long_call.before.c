int handle_everything(char const *configuration_path, int maximum_iterations)
{
    int processed_entries_count = 0;

    if (maximum_iterations > 0) {
        while (processed_entries_count < maximum_iterations) {
            processed_entries_count += my_strlen(configuration_path);
            my_putstr(configuration_path);
        }
    }
    return processed_entries_count;
}
