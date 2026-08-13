//
// helper.c
// IPA Installer Pro Helper
//
// v2.2 — Robust root execution with fallback verification for Dopamine 3.0
//

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <errno.h>
#include <string.h>

int main(int argc, char *argv[], char *envp[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <command> [args...]\n", argv[0]);
        return 1;
    }

    // Attempt to gain root privileges
    uid_t original_uid = getuid();

    if (setuid(0) != 0) {
        // setuid failed — try seteuid for Dopamine 3.0
        if (seteuid(0) != 0) {
            fprintf(stderr, "Warning: Could not acquire root (errno=%d). Running as uid=%d\n", errno, original_uid);
            // In Dopamine 3.0, some operations work without full root
            // Continue with current privileges
        } else {
            // seteuid succeeded — also try setegid
            setegid(0);
        }
    } else {
        // setuid succeeded — also set gid
        setgid(0);
        seteuid(0);
        setegid(0);
    }

    // Verify elevation (best effort)
    uid_t current_uid = getuid();
    uid_t current_euid = geteuid();
    if (current_uid != 0 && current_euid != 0) {
        fprintf(stderr, "Warning: Not running as root (uid=%d, euid=%d)\n", current_uid, current_euid);
    }

    // Execute target command with original environment
    execve(argv[1], &argv[1], envp);

    // If execve fails, report error
    fprintf(stderr, "execve failed for %s: errno=%d\n", argv[1], errno);

    // Fallback: try system() as last resort
    char cmd[4096] = {0};
    for (int i = 1; i < argc; i++) {
        if (i > 1) strncat(cmd, " ", sizeof(cmd) - strlen(cmd) - 1);
        strncat(cmd, argv[i], sizeof(cmd) - strlen(cmd) - 1);
    }
    int ret = system(cmd);
    return WEXITSTATUS(ret);
}
