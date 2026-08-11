#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sys/wait.h>
#include <spawn.h>

extern char **environ;

int main(int argc, char *argv[]) {
    if (setuid(0) != 0) {
        fprintf(stderr, "ipainstallerpro_helper: setuid(0) failed: %s\n", strerror(errno));
        return 1;
    }
    if (setgid(0) != 0) {
        fprintf(stderr, "ipainstallerpro_helper: setgid(0) failed: %s\n", strerror(errno));
        return 1;
    }

    if (argc < 2) {
        fprintf(stderr, "Usage: %s <command> [args...]\n", argv[0]);
        return 1;
    }

    pid_t pid;
    int status = posix_spawn(&pid, argv[1], NULL, NULL, argv + 1, environ);
    if (status != 0) {
        fprintf(stderr, "ipainstallerpro_helper: posix_spawn failed: %s\n", strerror(status));
        return 1;
    }

    int waitStatus;
    waitpid(pid, &waitStatus, 0);
    return WIFEXITED(waitStatus) ? WEXITSTATUS(waitStatus) : waitStatus;
}
