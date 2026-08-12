//
// helper.c
// IPAInstallerPro
//
// Root helper for privileged operations.
// Dopamine 3.0 / Rootless compatible.
//

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <spawn.h>

extern char **environ;

int main(int argc, char **argv) {
    // Dopamine 3.0: setuid alone may not be sufficient.
    // We need full privilege escalation.
    setuid(0);
    setgid(0);
    seteuid(0);
    setegid(0);

    // Verify we got root
    if (geteuid() != 0) {
        fprintf(stderr, "[helper] Failed to acquire root privileges (euid=%d)\n", geteuid());
        return 1;
    }

    if (argc < 2) {
        fprintf(stderr, "[helper] Usage: %s <command> [args...]\n", argv[0]);
        return 1;
    }

    pid_t pid;
    int status = posix_spawn(&pid, argv[1], NULL, NULL, &argv[1], environ);
    if (status != 0) {
        perror("[helper] posix_spawn failed");
        return status;
    }

    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
