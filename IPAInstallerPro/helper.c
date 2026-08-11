#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sys/wait.h>

int main(int argc, char *argv[]) {
    if (setuid(0) != 0) {
        fprintf(stderr, "ipainstallerpro-helper: setuid(0) failed: %s\n", strerror(errno));
        return 1;
    }
    if (setgid(0) != 0) {
        fprintf(stderr, "ipainstallerpro-helper: setgid(0) failed: %s\n", strerror(errno));
        return 1;
    }

    if (argc < 2) {
        fprintf(stderr, "Usage: %s <command> [args...]\n", argv[0]);
        return 1;
    }

    size_t total_len = 0;
    for (int i = 1; i < argc; i++) {
        total_len += strlen(argv[i]) + 1;
    }

    char *cmd = malloc(total_len + 1);
    if (!cmd) {
        fprintf(stderr, "ipainstallerpro-helper: malloc failed\n");
        return 1;
    }

    cmd[0] = '\0';
    for (int i = 1; i < argc; i++) {
        if (i > 1) strcat(cmd, " ");
        strcat(cmd, argv[i]);
    }

    int ret = system(cmd);
    free(cmd);
    return WIFEXITED(ret) ? WEXITSTATUS(ret) : ret;
}
