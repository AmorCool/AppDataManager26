#ifndef ROOTLESS_H
#define ROOTLESS_H

#include <sys/syslimits.h>
#include <string.h>

static inline const char *ROOT_PATH(const char *path) {
    if (path[0] != '/') return path;
    static char newPath[PATH_MAX];
    strcpy(newPath, "/var/jb");
    strcat(newPath, path);
    return newPath;
}

#ifdef __OBJC__
#import <Foundation/Foundation.h>
static inline NSString *ROOT_PATH_NS(NSString *path) {
    if (![path isAbsolutePath]) return path;
    return [@"/var/jb" stringByAppendingPathComponent:path];
}
#endif

#endif
