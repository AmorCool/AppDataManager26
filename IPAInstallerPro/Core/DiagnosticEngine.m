//
//  DiagnosticEngine.m
//  IPAInstallerPro
//
//  Evidence-based diagnostic system — no assumptions, only data
//

#import "DiagnosticEngine.h"
#import "RootlessManager.h"
#import <spawn.h>
#import <sys/wait.h>
#import <sys/stat.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>

extern char **environ;

@implementation DiagnosticReport
@end

@implementation DiagnosticEngine

+ (instancetype)sharedEngine {
    static DiagnosticEngine *s = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; });
    return s;
}

#pragma mark - Command Execution (direct posix_spawn, no /bin/sh)

- (NSString *)runOutput:(NSString *)cmd args:(NSArray *)args {
    int pipefd[2];
    if (pipe(pipefd) != 0) return nil;

    pid_t pid;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);

    const char *path = [cmd UTF8String];
    int argc = (int)args.count + 2;
    char **argv = malloc(argc * sizeof(char *));
    argv[0] = (char *)path;
    for (NSUInteger i = 0; i < args.count; i++) argv[i + 1] = (char *)[args[i] UTF8String];
    argv[args.count + 1] = NULL;

    int st = posix_spawn(&pid, path, &actions, NULL, argv, environ);
    free(argv);
    posix_spawn_file_actions_destroy(&actions);
    close(pipefd[1]);

    if (st != 0) { close(pipefd[0]); return nil; }

    NSMutableString *output = [NSMutableString string];
    char buf[4096];
    ssize_t n;
    while ((n = read(pipefd[0], buf, sizeof(buf) - 1)) > 0) {
        buf[n] = '\0';
        [output appendString:[NSString stringWithUTF8String:buf]];
    }
    close(pipefd[0]);
    waitpid(pid, NULL, 0);
    return output;
}

#pragma mark - Main Diagnostic Entry

- (DiagnosticReport *)diagnoseInstalledApp:(NSString *)appPath bundleID:(NSString *)bundleID {
    DiagnosticReport *report = [[DiagnosticReport alloc] init];
    report.bundleID = bundleID;
    NSMutableArray *issues = [NSMutableArray array];
    NSMutableDictionary *fsAudit = [NSMutableDictionary dictionary];

    NSFileManager *fm = [NSFileManager defaultManager];
    RootlessManager *rm = [RootlessManager sharedManager];

    // === 1. PROCESS IDENTITY ===
    fsAudit[@"installerUID"] = @(getuid());
    fsAudit[@"installerEUID"] = @(geteuid());
    fsAudit[@"installerGID"] = @(getgid());
    fsAudit[@"installerEGID"] = @(getegid());

    // === 2. FULL FILESYSTEM AUDIT ===
    NSMutableArray *entries = [NSMutableArray array];
    [self auditPath:appPath entries:entries issues:issues];
    fsAudit[@"entries"] = entries;

    // === 3. EXECUTABLE ANALYSIS ===
    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    NSString *exeName = info[@"CFBundleExecutable"];
    NSString *exePath = [appPath stringByAppendingPathComponent:exeName];

    NSString *otool = [rm resolvePath:@"/usr/bin/otool"];
    NSString *ldid = [rm resolvePath:@"/usr/bin/ldid"];

    fsAudit[@"executableDylibs"] = [self runOutput:otool args:@[@"-L", exePath]] ?: @"N/A";
    fsAudit[@"executableEntitlements"] = [self runOutput:ldid args:@[@"-e", exePath]] ?: @"N/A";

    // === 4. FRAMEWORKS/DYLIBS DEEP AUDIT ===
    NSString *fwPath = [appPath stringByAppendingPathComponent:@"Frameworks"];
    NSMutableDictionary *fwAudit = [NSMutableDictionary dictionary];
    if ([fm fileExistsAtPath:fwPath]) {
        for (NSString *item in [fm contentsOfDirectoryAtPath:fwPath error:nil]) {
            NSString *itemPath = [fwPath stringByAppendingPathComponent:item];

            if ([item hasSuffix:@".dylib"]) {
                struct stat st;
                int r_ok = access([itemPath UTF8String], R_OK);
                int x_ok = access([itemPath UTF8String], X_OK);
                int stat_ok = lstat([itemPath UTF8String], &st);

                fwAudit[item] = @{
                    @"stat": (stat_ok == 0) ? @{
                        @"mode_octal": [NSString stringWithFormat:@"%o", st.st_mode & 07777],
                        @"mode_human": [self modeString:st.st_mode],
                        @"uid": @(st.st_uid),
                        @"gid": @(st.st_gid),
                        @"size": @(st.st_size)
                    } : @{@"error": @(errno)},
                    @"access_R_OK": @(r_ok == 0),
                    @"access_X_OK": @(x_ok == 0),
                    @"access_errno": @(errno),
                    @"euid_at_check": @(geteuid()),
                    @"otool_D": [self runOutput:otool args:@[@"-D", itemPath]] ?: @"N/A",
                    @"ldid_e": [self runOutput:ldid args:@[@"-e", itemPath]] ?: @"N/A"
                };

                if (r_ok != 0) {
                    [issues addObject:[NSString stringWithFormat:@"[F1] DYLIB '%@': read denied (errno=%d, euid=%d, path=%@)", item, errno, geteuid(), itemPath]];
                }
                if (x_ok != 0) {
                    [issues addObject:[NSString stringWithFormat:@"[F2] DYLIB '%@': execute denied (errno=%d, euid=%d)", item, errno, geteuid()]];
                }
            }
            else if ([item hasSuffix:@".framework"]) {
                NSString *fn = [item stringByDeletingPathExtension];
                NSString *fwExe = [itemPath stringByAppendingPathComponent:fn];
                if ([fm fileExistsAtPath:fwExe]) {
                    struct stat st;
                    lstat([fwExe UTF8String], &st);
                    int r_ok = access([fwExe UTF8String], R_OK);
                    fwAudit[[item stringByAppendingString:@"/"]] = @{
                        @"exe_stat": @{
                            @"mode": [NSString stringWithFormat:@"%o", st.st_mode & 07777],
                            @"uid": @(st.st_uid),
                            @"gid": @(st.st_gid)
                        },
                        @"access_R_OK": @(r_ok == 0),
                        @"access_errno": @(errno)
                    };
                    if (r_ok != 0) {
                        [issues addObject:[NSString stringWithFormat:@"[F1] FRAMEWORK '%@/%@': read denied (errno=%d)", item, fn, errno]];
                    }
                }
            }
        }
    }
    fsAudit[@"frameworks"] = fwAudit;

    // === 5. DIRECTORY TRAVERSAL AUDIT ===
    NSMutableArray *traverse = [NSMutableArray array];
    NSString *current = appPath;
    while (current && ![current isEqualToString:@"/"]) {
        struct stat st;
        int stat_ok = lstat([current UTF8String], &st);
        int dir_x = access([current UTF8String], X_OK);
        [traverse addObject:@{
            @"path": current,
            @"stat_ok": @(stat_ok == 0),
            @"mode": (stat_ok == 0) ? [NSString stringWithFormat:@"%o", st.st_mode & 07777] : @"N/A",
            @"uid": (stat_ok == 0) ? @(st.st_uid) : @(-1),
            @"gid": (stat_ok == 0) ? @(st.st_gid) : @(-1),
            @"traverse_X_OK": @(dir_x == 0),
            @"traverse_errno": @(errno)
        }];
        if (dir_x != 0) {
            [issues addObject:[NSString stringWithFormat:@"[F3] TRAVERSE '%@': denied (errno=%d, euid=%d, mode=%o)", current, errno, geteuid(), (stat_ok == 0) ? (st.st_mode & 07777) : 0]];
        }
        current = [current stringByDeletingLastPathComponent];
    }
    fsAudit[@"directoryTraversal"] = traverse;

    report.filesystemAudit = fsAudit;
    report.postInstallIssues = issues;
    report.rootCause = [self determineRootCause:report];
    report.canLaunch = (issues.count == 0);

    return report;
}

#pragma mark - Filesystem Walker

- (void)auditPath:(NSString *)path entries:(NSMutableArray *)entries issues:(NSMutableArray *)issues {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    NSArray *items = [fm contentsOfDirectoryAtPath:path error:&err];
    if (err) {
        [issues addObject:[NSString stringWithFormat:@"[F4] LIST '%@': %@ (errno=%d)", path, err.localizedDescription, errno]];
        return;
    }

    for (NSString *item in items) {
        NSString *itemPath = [path stringByAppendingPathComponent:item];
        struct stat st;
        if (lstat([itemPath UTF8String], &st) == 0) {
            [entries addObject:@{
                @"path": itemPath,
                @"type": S_ISDIR(st.st_mode) ? @"dir" : (S_ISLNK(st.st_mode) ? @"link" : @"file"),
                @"mode_octal": [NSString stringWithFormat:@"%o", st.st_mode & 07777],
                @"uid": @(st.st_uid),
                @"gid": @(st.st_gid),
                @"size": @(st.st_size)
            }];
            if (S_ISDIR(st.st_mode)) {
                [self auditPath:itemPath entries:entries issues:issues];
            }
        } else {
            [issues addObject:[NSString stringWithFormat:@"[F4] STAT '%@': errno=%d", itemPath, errno]];
        }
    }
}

#pragma mark - Root Cause Determination

- (NSString *)determineRootCause:(DiagnosticReport *)report {
    NSMutableArray *hypotheses = [NSMutableArray array];

    // H1: Filesystem permission failure
    BOOL hasF1 = NO, hasF2 = NO, hasF3 = NO;
    for (NSString *issue in report.postInstallIssues) {
        if ([issue hasPrefix:@"[F1]"]) hasF1 = YES;
        if ([issue hasPrefix:@"[F2]"]) hasF2 = YES;
        if ([issue hasPrefix:@"[F3]"]) hasF3 = YES;
    }
    if (hasF1) [hypotheses addObject:@"H1a: Filesystem read permission — dylib mode/ownership prevents read by current euid"];
    if (hasF2) [hypotheses addObject:@"H1b: Filesystem execute permission — dylib lacks +x bit required by dyld for mmap"];
    if (hasF3) [hypotheses addObject:@"H1c: Directory traversal — parent directory lacks +x, blocking path resolution"];

    // H2: Code-signing validation failure (only if filesystem passes)
    if (!hasF1 && !hasF2 && !hasF3) {
        NSDictionary *fw = report.filesystemAudit[@"frameworks"];
        for (NSString *name in fw) {
            NSDictionary *info = fw[name];
            NSString *ldidOut = info[@"ldid_e"];
            if (!ldidOut || [ldidOut isEqualToString:@"N/A"] || ldidOut.length < 10) {
                [hypotheses addObject:[NSString stringWithFormat:@"H2: Code-signing — %@ lacks valid signature/entitlements (dyld may reject)", name]];
            }
        }

        // H3: Install name / RPATH mismatch
        // This would require deeper Mach-O parsing — flagged for manual investigation
        [hypotheses addObject:@"H3: Mach-O load commands — possible @rpath resolution or install-name mismatch (requires manual otool -l inspection)"];
    }

    if (hypotheses.count == 0) return @"U1: Unknown — all automated checks passed. Root cause may require kernel-level dyld tracing or AMFI log analysis.";
    return [hypotheses componentsJoinedByString:@" | "];
}

#pragma mark - Helpers

- (NSString *)modeString:(mode_t)mode {
    char str[11];
    str[0] = S_ISDIR(mode) ? 'd' : (S_ISLNK(mode) ? 'l' : '-');
    str[1] = (mode & S_IRUSR) ? 'r' : '-';
    str[2] = (mode & S_IWUSR) ? 'w' : '-';
    str[3] = (mode & S_IXUSR) ? 'x' : '-';
    str[4] = (mode & S_IRGRP) ? 'r' : '-';
    str[5] = (mode & S_IWGRP) ? 'w' : '-';
    str[6] = (mode & S_IXGRP) ? 'x' : '-';
    str[7] = (mode & S_IROTH) ? 'r' : '-';
    str[8] = (mode & S_IWOTH) ? 'w' : '-';
    str[9] = (mode & S_IXOTH) ? 'x' : '-';
    str[10] = '\0';
    return [NSString stringWithUTF8String:str];
}

- (void)logReport:(DiagnosticReport *)report {
    NSLog(@"========================================");
    NSLog(@"IPA INSTALLER PRO — DIAGNOSTIC REPORT");
    NSLog(@"========================================");
    NSLog(@"BundleID: %@", report.bundleID);
    NSLog(@"CanLaunch: %@", report.canLaunch ? @"YES" : @"NO");
    NSLog(@"RootCause: %@", report.rootCause);
    NSLog(@"---");

    NSDictionary *fs = report.filesystemAudit;
    NSLog(@"Process Identity: uid=%@ euid=%@ gid=%@ egid=%@", fs[@"installerUID"], fs[@"installerEUID"], fs[@"installerGID"], fs[@"installerEGID"]);
    NSLog(@"---");

    if (report.postInstallIssues.count > 0) {
        NSLog(@"ISSUES (%lu):", (unsigned long)report.postInstallIssues.count);
        for (NSString *issue in report.postInstallIssues) {
            NSLog(@"  %@", issue);
        }
    } else {
        NSLog(@"ISSUES: None detected");
    }
    NSLog(@"---");

    NSDictionary *fw = fs[@"frameworks"];
    if (fw.count > 0) {
        NSLog(@"FRAMEWORKS/DYLIBS:");
        for (NSString *name in fw) {
            NSDictionary *info = fw[name];
            NSLog(@"  %@:", name);
            NSLog(@"    stat: %@", info[@"stat"]);
            NSLog(@"    access_R_OK: %@", info[@"access_R_OK"]);
            NSLog(@"    access_X_OK: %@", info[@"access_X_OK"]);
            NSLog(@"    access_errno: %@", info[@"access_errno"]);
            NSLog(@"    ldid_e length: %lu", (unsigned long)[info[@"ldid_e"] length]);
        }
    }
    NSLog(@"---");

    NSArray *traverse = fs[@"directoryTraversal"];
    if (traverse.count > 0) {
        NSLog(@"DIRECTORY TRAVERSAL:");
        for (NSDictionary *d in traverse) {
            NSLog(@"  %@: mode=%@ uid=%@ gid=%@ X_OK=%@ errno=%@", 
                  d[@"path"], d[@"mode"], d[@"uid"], d[@"gid"], d[@"traverse_X_OK"], d[@"traverse_errno"]);
        }
    }
    NSLog(@"========================================");
}

@end
