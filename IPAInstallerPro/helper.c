//
//  helper.c
//  ipainstallerpro_helper
//
//  Enhanced root helper with Dopamine 3.0 compatibility
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/wait.h>
#include <errno.h>

extern char **environ;

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <command> [args...]\n", argv[0]);
        return 1;
    }

    // Try setuid(0) - critical for root access
    if (setuid(0) != 0) {
        // Dopamine 3.0 rootless may require seteuid first
        if (seteuid(0) != 0) {
            fprintf(stderr, "ipainstallerpro_helper: setuid(0) failed: %s\n", strerror(errno));
            // Try setreuid as fallback
            if (setreuid(0, 0) != 0) {
                fprintf(stderr, "ipainstallerpro_helper: setreuid(0,0) also failed: %s\n", strerror(errno));
                // Last resort: try with current privileges
                fprintf(stderr, "ipainstallerpro_helper: WARNING - running without root privileges\n");
            }
        }
    }

    // Also ensure gid is root
    setgid(0);
    setegid(0);

    // Build argv for the target command
    char **new_argv = malloc((argc) * sizeof(char *));
    if (!new_argv) {
        fprintf(stderr, "ipainstallerpro_helper: malloc failed\n");
        return 1;
    }

    for (int i = 1; i < argc; i++) {
        new_argv[i - 1] = argv[i];
    }
    new_argv[argc - 1] = NULL;

    pid_t pid;
    int status = posix_spawn(&pid, argv[1], NULL, NULL, new_argv, environ);
    free(new_argv);

    if (status != 0) {
        fprintf(stderr, "ipainstallerpro_helper: posix_spawn failed: %s\n", strerror(status));
        return status;
    }

    int wait_status;
    waitpid(pid, &wait_status, 0);

    if (WIFEXITED(wait_status)) {
        return WEXITSTATUS(wait_status);
    }

    return 1;
}
