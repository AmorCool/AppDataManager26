#ifndef ROOTLESS_H
#define ROOTLESS_H

#include <sys/stat.h>
#include <unistd.h>
#include <string.h>

static inline NSString *ROOT_PATH_NS(NSString *path) {
    if (!path || path.length == 0) return path;
    if ([path hasPrefix:@"/var/jb"]) return path;

    struct stat st;
    if (stat("/var/jb", &st) == 0 && S_ISDIR(st.st_mode)) {
        return [@"/var/jb" stringByAppendingPathComponent:path];
    }
    return path;
}

static inline const char *ROOT_PATH_C(const char *path) {
    if (!path) return path;
    if (strncmp(path, "/var/jb", 7) == 0) return path;

    struct stat st;
    if (stat("/var/jb", &st) == 0 && S_ISDIR(st.st_mode)) {
        static char buffer[PATH_MAX];
        snprintf(buffer, sizeof(buffer), "/var/jb%s", path);
        return buffer;
    }
    return path;
}

#endif
