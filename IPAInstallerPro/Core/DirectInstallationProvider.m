#import "DirectInstallationProvider.h"
#import "Logger.h"
#import "RootlessManager.h"
#import <spawn.h>
#import <sys/wait.h>
#include <copyfile.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>

@interface DirectInstallationProvider ()
@property (nonatomic, strong) NSString *appsPath;
@property (nonatomic, strong) NSString *helperPath;
@property (nonatomic, strong) NSString *cpPath;
@property (nonatomic, strong) NSString *rmPath;
@property (nonatomic, strong) NSString *chmodPath;
@property (nonatomic, strong) NSString *chownPath;
@property (nonatomic, strong) NSString *ldidPath;
@property (nonatomic, strong) NSString *uicachePath;
@end

@implementation DirectInstallationProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *resolvedApps = [[RootlessManager sharedManager] resolvePath:@"/Applications"];
        _appsPath = resolvedApps;
        _helperPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/ipainstallerpro_helper"];

        NSFileManager *fm = [NSFileManager defaultManager];
        _cpPath = @"/var/jb/bin/cp"; if (![fm fileExistsAtPath:_cpPath]) _cpPath = @"/bin/cp";
        _rmPath = @"/var/jb/bin/rm"; if (![fm fileExistsAtPath:_rmPath]) _rmPath = @"/bin/rm";
        _chmodPath = @"/var/jb/bin/chmod"; if (![fm fileExistsAtPath:_chmodPath]) _chmodPath = @"/bin/chmod";
        _chownPath = @"/var/jb/usr/sbin/chown"; if (![fm fileExistsAtPath:_chownPath]) _chownPath = @"/usr/sbin/chown";
        _ldidPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/ldid"];
        if (![fm fileExistsAtPath:_ldidPath]) _ldidPath = @"/usr/bin/ldid";
        _uicachePath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/uicache"];
        if (![fm fileExistsAtPath:_uicachePath]) _uicachePath = @"/usr/bin/uicache";
    }
    return self;
}

- (NSString *)providerName { return @"Direct Install"; }
- (NSString *)providerDescription { return @"تثبيت مباشر (Dopamine/Jailbreak)"; }
- (NSInteger)priority { return 100; }

- (BOOL)isAvailable {
    @try {
        RootlessManager *rl = [RootlessManager sharedManager];
        return [rl fileExistsAtLogicalPath:@"/usr/bin/ldid"] &&
               [rl fileExistsAtLogicalPath:@"/usr/bin/uicache"] &&
               [rl fileExistsAtLogicalPath:@"/usr/bin/unzip"];
    } @catch (NSException *exception) { return NO; }
}

- (BOOL)hasRootHelper {
    return [[NSFileManager defaultManager] fileExistsAtPath:self.helperPath];
}

- (void)installIPA:(NSString *)ipaPath completion:(void (^)(InstallationResult *))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableString *log = [NSMutableString string];
        void (^logStep)(NSString *, NSString *) = ^(NSString *step, NSString *detail) {
            NSString *entry = [NSString stringWithFormat:@"[DirectInstall] %@: %@", step, detail];
            [[Logger sharedLogger] info:entry];
            [log appendFormat:@"%@\n", entry];
        };

        logStep(@"START", [NSString stringWithFormat:@"Installing %@", [ipaPath lastPathComponent]]);
        logStep(@"INFO", [NSString stringWithFormat:@"Apps path: %@", self.appsPath]);

        BOOL hasHelper = [self hasRootHelper];
        if (hasHelper) logStep(@"HELPER", @"Root helper available");
        else logStep(@"HELPER", @"Root helper NOT found — using fallback");

        // 1. Create temp dir
        NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

        // 2. Unzip
        logStep(@"UNZIP", @"Extracting IPA...");
        NSString *unzipPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/unzip"];
        if (![fm fileExistsAtPath:unzipPath]) unzipPath = @"/usr/bin/unzip";
        if (![self runCommand:unzipPath args:@[@"-q", @"-o", ipaPath, @"-d", tempDir]]) {
            [fm removeItemAtPath:tempDir error:nil];
            logStep(@"ERROR", @"Failed to extract IPA");
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *r = [InstallationResult failureResult:@"فشل فك ضغط IPA" error:nil];
                r.detailedOutput = log; completion(r);
            });
            return;
        }
        logStep(@"UNZIP", @"Success");

        // 3. Find .app
        NSString *payloadPath = [tempDir stringByAppendingPathComponent:@"Payload"];
        NSArray *payloadContents = [fm contentsOfDirectoryAtPath:payloadPath error:nil];
        NSString *appBundleName = nil;
        for (NSString *item in payloadContents) {
            if ([item hasSuffix:@".app"]) { appBundleName = item; break; }
        }
        if (!appBundleName) {
            [fm removeItemAtPath:tempDir error:nil];
            logStep(@"ERROR", @"No .app bundle found");
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *r = [InstallationResult failureResult:@"لم يتم العثور على .app" error:nil];
                r.detailedOutput = log; completion(r);
            });
            return;
        }
        logStep(@"BUNDLE", appBundleName);

        NSString *sourceAppPath = [payloadPath stringByAppendingPathComponent:appBundleName];
        NSString *destAppPath = [self.appsPath stringByAppendingPathComponent:appBundleName];
        NSString *exeName = [self executableNameFromApp:sourceAppPath];
        NSString *sourceExePath = exeName ? [sourceAppPath stringByAppendingPathComponent:exeName] : nil;
        NSString *destExePath = exeName ? [destAppPath stringByAppendingPathComponent:exeName] : nil;

        // 4. Remove existing
        if ([fm fileExistsAtPath:destAppPath]) {
            logStep(@"CLEAN", @"Removing existing app...");
            if (hasHelper) [self runCommandAsRoot:self.rmPath args:@[@"-rf", destAppPath]];
            else [self runCommand:self.rmPath args:@[@"-rf", destAppPath]];
        }

        // 5. Copy app
        logStep(@"INSTALL", [NSString stringWithFormat:@"Copying to %@...", destAppPath]);
        BOOL copySuccess = NO;

        // Try helper first (root cp)
        if (hasHelper) {
            copySuccess = [self runCommandAsRoot:self.cpPath args:@[@"-R", @"-f", sourceAppPath, destAppPath]];
            if (copySuccess) logStep(@"COPY", @"Root cp succeeded");
        }

        // Fallback: copyfile()
        if (!copySuccess) {
            if (copyfile([sourceAppPath UTF8String], [destAppPath UTF8String], NULL, COPYFILE_ALL | COPYFILE_RECURSIVE) == 0) {
                copySuccess = YES; logStep(@"COPY", @"copyfile() succeeded");
            }
        }

        // Last fallback: NSFileManager
        if (!copySuccess) {
            NSError *err = nil;
            copySuccess = [fm copyItemAtPath:sourceAppPath toPath:destAppPath error:&err];
            if (copySuccess) logStep(@"COPY", @"NSFileManager copy succeeded");
            else logStep(@"FALLBACK", [NSString stringWithFormat:@"NSFileManager failed: %@", err.localizedDescription]);
        }

        if (!copySuccess) {
            [fm removeItemAtPath:tempDir error:nil];
            logStep(@"ERROR", @"Failed to copy app");
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *r = [InstallationResult failureResult:@"فشل نسخ التطبيق" error:nil];
                r.detailedOutput = log; completion(r);
            });
            return;
        }
        logStep(@"COPY", @"App copied successfully");

        // 6. EXTRACT entitlements from original executable using system() with redirect
        NSString *entitlementsPath = [tempDir stringByAppendingPathComponent:@"extracted_entitlements.plist"];
        BOOL hasEntitlements = NO;
        if (sourceExePath && [fm fileExistsAtPath:sourceExePath]) {
            logStep(@"ENTITLEMENTS", @"Extracting from original executable...");
            // Use posix_spawn with stdout redirect to file
            int extractStatus = -1;
            {
                int out_fd = open([entitlementsPath UTF8String], O_WRONLY | O_CREAT | O_TRUNC, 0644);
                if (out_fd >= 0) {
                    pid_t extractPid;
                    char *extractArgv[] = {
                        (char *)[self.ldidPath UTF8String],
                        (char *)"-e",
                        (char *)[sourceExePath UTF8String],
                        NULL
                    };
                    posix_spawn_file_actions_t actions;
                    posix_spawn_file_actions_init(&actions);
                    posix_spawn_file_actions_adddup2(&actions, out_fd, STDOUT_FILENO);
                    posix_spawn_file_actions_addclose(&actions, out_fd);
                    extern char **environ;
                    int spawnStatus = posix_spawn(&extractPid, [self.ldidPath UTF8String], &actions, NULL, extractArgv, environ);
                    posix_spawn_file_actions_destroy(&actions);
                    close(out_fd);
                    if (spawnStatus == 0) {
                        int waitStatus;
                        waitpid(extractPid, &waitStatus, 0);
                        extractStatus = WIFEXITED(waitStatus) ? WEXITSTATUS(waitStatus) : -1;
                    }
                }
            }
            if (extractStatus == 0) {
                NSDictionary *entitlements = [NSDictionary dictionaryWithContentsOfFile:entitlementsPath];
                if (entitlements && entitlements.count > 0) {
                    hasEntitlements = YES;
                    logStep(@"ENTITLEMENTS", [NSString stringWithFormat:@"Extracted %lu entitlements", (unsigned long)entitlements.count]);
                } else {
                    logStep(@"ENTITLEMENTS", @"Extraction returned empty, using default");
                }
            } else {
                logStep(@"ENTITLEMENTS", @"Extraction failed, using default entitlements");
            }
        }

        // 7. Sign executable WITH extracted entitlements (CRITICAL FIX)
        logStep(@"SIGN", @"Signing executable...");
        if (destExePath && [fm fileExistsAtPath:destExePath]) {
            // CRITICAL FIX: Create CLEAN jailbreak entitlements
            // Extracted entitlements contain Apple's Team ID which causes crash on iOS 15+
            NSString *cleanEntitlementsPath = [tempDir stringByAppendingPathComponent:@"clean_entitlements.plist"];
            NSMutableDictionary *cleanEntitlements = [NSMutableDictionary dictionary];

            // Start with extracted entitlements if available
            if (hasEntitlements) {
                NSDictionary *extracted = [NSDictionary dictionaryWithContentsOfFile:entitlementsPath];
                if (extracted) [cleanEntitlements addEntriesFromDictionary:extracted];
            }

            // REMOVE Apple-specific keys that cause crash on jailbreak
            [cleanEntitlements removeObjectForKey:@"application-identifier"];
            [cleanEntitlements removeObjectForKey:@"com.apple.developer.team-identifier"];
            [cleanEntitlements removeObjectForKey:@"team-identifier"];
            [cleanEntitlements removeObjectForKey:@"keychain-access-groups"];
            [cleanEntitlements removeObjectForKey:@"aps-environment"];

            // ADD required jailbreak entitlements
            cleanEntitlements[@"get-task-allow"] = @YES;
            cleanEntitlements[@"platform-application"] = @YES;
            cleanEntitlements[@"com.apple.private.security.container-required"] = @NO;
            cleanEntitlements[@"com.apple.private.security.no-container"] = @YES;

            [cleanEntitlements writeToFile:cleanEntitlementsPath atomically:YES];

            NSString *sFlag = [NSString stringWithFormat:@"-S%@", cleanEntitlementsPath];
            if (hasHelper) {
                [self runCommandAsRoot:self.ldidPath args:@[sFlag, destExePath]];
            } else {
                [self runCommand:self.ldidPath args:@[sFlag, destExePath]];
            }
            logStep(@"SIGN", [NSString stringWithFormat:@"Signed with clean jailbreak entitlements (%lu keys): %@", (unsigned long)cleanEntitlements.count, exeName]);
            // Make sure it\'s executable
            if (hasHelper) [self runCommandAsRoot:self.chmodPath args:@[@"+x", destExePath]];
            else [self runCommand:self.chmodPath args:@[@"+x", destExePath]];
        }

        // 8. Sign ALL frameworks and dylibs recursively (without entitlements — they don\'t need them)
        logStep(@"SIGN", @"Signing frameworks and dylibs...");
        [self signAllBinariesAtPath:destAppPath hasHelper:hasHelper log:logStep];

        // 9. Set permissions on entire app
        logStep(@"PERM", @"Setting permissions...");
        if (hasHelper) {
            [self runCommandAsRoot:self.chmodPath args:@[@"-R", @"755", destAppPath]];
            [self runCommandAsRoot:self.chownPath args:@[@"-R", @"root:wheel", destAppPath]];
        } else {
            [self runCommand:self.chmodPath args:@[@"-R", @"755", destAppPath]];
            [self runCommand:self.chownPath args:@[@"-R", @"root:wheel", destAppPath]];
        }
        logStep(@"PERM", @"Set to root:wheel, 755");

        // 10. uicache — use LOGICAL path + refresh all + sbreload
        logStep(@"UICACHE", @"Refreshing UI cache...");
        NSString *logicalAppPath = [@"/Applications" stringByAppendingPathComponent:appBundleName];
        NSString *physicalAppPath = [self.appsPath stringByAppendingPathComponent:appBundleName];

        // Try both logical and physical paths, then refresh all
        if (hasHelper) {
            [self runCommandAsRoot:self.uicachePath args:@[@"-p", logicalAppPath]];
            [self runCommandAsRoot:self.uicachePath args:@[@"-p", physicalAppPath]];
            [self runCommandAsRoot:self.uicachePath args:@[@"-a"]];
        } else {
            [self runCommand:self.uicachePath args:@[@"-p", logicalAppPath]];
            [self runCommand:self.uicachePath args:@[@"-p", physicalAppPath]];
            [self runCommand:self.uicachePath args:@[@"-a"]];
        }
        logStep(@"UICACHE", @"Done");

        // 10b. SpringBoard reload (CRITICAL for Dopamine 3.0)
        logStep(@"SPRINGBOARD", @"Reloading SpringBoard...");
        NSString *sbreloadPath = @"/var/jb/usr/bin/sbreload";
        if (![[NSFileManager defaultManager] fileExistsAtPath:sbreloadPath]) sbreloadPath = @"/usr/bin/sbreload";
        if ([[NSFileManager defaultManager] fileExistsAtPath:sbreloadPath]) {
            if (hasHelper) [self runCommandAsRoot:sbreloadPath args:@[]];
            else [self runCommand:sbreloadPath args:@[]];
            logStep(@"SPRINGBOARD", @"Reloaded");
        } else {
            // Fallback: killall SpringBoard
            NSString *killallPath = @"/var/jb/usr/bin/killall";
            if (![[NSFileManager defaultManager] fileExistsAtPath:killallPath]) killallPath = @"/usr/bin/killall";
            if (hasHelper) [self runCommandAsRoot:killallPath args:@[@"SpringBoard"]];
            else [self runCommand:killallPath args:@[@"SpringBoard"]];
            logStep(@"SPRINGBOARD", @"Killed SpringBoard");
        }

        // 11. Cleanup
        [fm removeItemAtPath:tempDir error:nil];
        logStep(@"CLEAN", @"Temp removed");

        // 12. Verify
        BOOL exists = [fm fileExistsAtPath:destAppPath];
        logStep(@"VERIFY", exists ? @"App exists ✓" : @"App NOT found ✗");

        dispatch_async(dispatch_get_main_queue(), ^{
            if (exists) {
                InstallationResult *r = [InstallationResult successResult:@"تم التثبيت بنجاح"];
                r.bundleID = [self bundleIDFromApp:destAppPath];
                r.detailedOutput = log;
                completion(r);
            } else {
                InstallationResult *r = [InstallationResult failureResult:@"التطبيق غير موجود بعد التثبيت" error:nil];
                r.detailedOutput = log; completion(r);
            }
        });
    });
}

// Recursively sign ALL binaries in the app bundle (dylibs/frameworks only — no entitlements needed)
- (void)signAllBinariesAtPath:(NSString *)path hasHelper:(BOOL)hasHelper log:(void (^)(NSString *, NSString *))logStep {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *items = [fm contentsOfDirectoryAtPath:path error:nil];
    for (NSString *item in items) {
        NSString *itemPath = [path stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        [fm fileExistsAtPath:itemPath isDirectory:&isDir];

        if (isDir && [item hasSuffix:@".app"]) {
            // Sign the executable inside .app
            NSString *exeName = [self executableNameFromApp:itemPath];
            if (exeName) {
                NSString *exePath = [itemPath stringByAppendingPathComponent:exeName];
                if ([fm fileExistsAtPath:exePath]) {
                    if (hasHelper) [self runCommandAsRoot:self.ldidPath args:@[@"-S", exePath]];
                    else [self runCommand:self.ldidPath args:@[@"-S", exePath]];
                    logStep(@"SIGN", [NSString stringWithFormat:@"Signed: %@/%@", item, exeName]);
                }
            }
            // Recurse into .app
            [self signAllBinariesAtPath:itemPath hasHelper:hasHelper log:logStep];
        }
        else if (isDir && [item hasSuffix:@".framework"]) {
            NSString *fwName = [item stringByDeletingPathExtension];
            NSString *fwExe = [itemPath stringByAppendingPathComponent:fwName];
            if ([fm fileExistsAtPath:fwExe]) {
                if (hasHelper) [self runCommandAsRoot:self.ldidPath args:@[@"-S", fwExe]];
                else [self runCommand:self.ldidPath args:@[@"-S", fwExe]];
                logStep(@"SIGN", [NSString stringWithFormat:@"Signed framework: %@", fwName]);
            }
            // Recurse into framework
            [self signAllBinariesAtPath:itemPath hasHelper:hasHelper log:logStep];
        }
        else if ([item hasSuffix:@".dylib"]) {
            if (hasHelper) [self runCommandAsRoot:self.ldidPath args:@[@"-S", itemPath]];
            else [self runCommand:self.ldidPath args:@[@"-S", itemPath]];
            logStep(@"SIGN", [NSString stringWithFormat:@"Signed dylib: %@", item]);
        }
    }
}

- (BOOL)runCommandAsRoot:(NSString *)cmd args:(NSArray *)args {
    if (!cmd || args.count == 0) return NO;
    if (!self.helperPath || ![[NSFileManager defaultManager] fileExistsAtPath:self.helperPath]) {
        return [self runCommand:cmd args:args];
    }
    NSMutableArray *allArgs = [NSMutableArray arrayWithObject:cmd];
    [allArgs addObjectsFromArray:args];
    return [self runCommand:self.helperPath args:allArgs];
}

- (BOOL)runCommand:(NSString *)cmd args:(NSArray *)args {
    if (!cmd || args.count == 0) return NO;
    const char *cmdPath = [cmd UTF8String];
    char **argv = (char **)malloc((args.count + 2) * sizeof(char *));
    argv[0] = (char *)cmdPath;
    for (int i = 0; i < args.count; i++) argv[i + 1] = (char *)[[args objectAtIndex:i] UTF8String];
    argv[args.count + 1] = NULL;
    pid_t pid;
    extern char **environ;  // FIX: pass environment variables
    int status = posix_spawn(&pid, cmdPath, NULL, NULL, argv, environ);
    free(argv);
    if (status != 0) return NO;
    int waitStatus;
    waitpid(pid, &waitStatus, 0);
    return WIFEXITED(waitStatus) && WEXITSTATUS(waitStatus) == 0;
}

- (NSString *)executableNameFromApp:(NSString *)appPath {
    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    return info[@"CFBundleExecutable"];
}

- (NSString *)bundleIDFromApp:(NSString *)appPath {
    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    return info[@"CFBundleIdentifier"];
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *apps = [fm contentsOfDirectoryAtPath:self.appsPath error:nil];
    for (NSString *app in apps) {
        if (![app hasSuffix:@".app"]) continue;
        NSString *appPath = [self.appsPath stringByAppendingPathComponent:app];
        NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        if ([info[@"CFBundleIdentifier"] isEqualToString:bundleID]) {
            // FIX: Use LOGICAL path for uicache (not physical /var/jb path)
            NSString *logicalAppPath = [@"/Applications" stringByAppendingPathComponent:app];

            if ([self hasRootHelper]) {
                [self runCommandAsRoot:self.rmPath args:@[@"-rf", appPath]];
                [self runCommandAsRoot:self.uicachePath args:@[@"-p", logicalAppPath]];
                [self runCommandAsRoot:self.uicachePath args:@[@"-a"]]; // Refresh all
            } else {
                [self runCommand:self.rmPath args:@[@"-rf", appPath]];
                [self runCommand:self.uicachePath args:@[@"-p", logicalAppPath]];
                [self runCommand:self.uicachePath args:@[@"-a"]]; // Refresh all
            }
            if (completion) completion(YES, nil);
            return;
        }
    }
    if (completion) completion(NO, @"التطبيق غير موجود");
}

@end
