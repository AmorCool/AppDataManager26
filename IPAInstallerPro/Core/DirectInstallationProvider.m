#import "DirectInstallationProvider.h"
#import "Logger.h"
#import "RootlessManager.h"
#import <spawn.h>
#import <sys/wait.h>
#include <copyfile.h>
#include <errno.h>
#include <unistd.h>

@interface DirectInstallationProvider ()
@property (nonatomic, strong) NSString *appsPath;
@property (nonatomic, strong) NSString *jbPrefix;
@property (nonatomic, strong) NSString *helperPath;
@property (nonatomic, strong) NSString *cpPath;
@property (nonatomic, strong) NSString *rmPath;
@property (nonatomic, strong) NSString *chmodPath;
@property (nonatomic, strong) NSString *chownPath;
@end

@implementation DirectInstallationProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *resolvedApps = [[RootlessManager sharedManager] resolvePath:@"/Applications"];
        _appsPath = resolvedApps;
        _jbPrefix = [resolvedApps hasPrefix:@"/var/jb"] ? @"/var/jb" : @"";
        _helperPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/ipainstallerpro_helper"];

        // Find correct binary paths for Rootless
        NSFileManager *fm = [NSFileManager defaultManager];
        _cpPath = @"/var/jb/bin/cp";
        if (![fm fileExistsAtPath:_cpPath]) _cpPath = @"/usr/bin/cp";
        if (![fm fileExistsAtPath:_cpPath]) _cpPath = @"/bin/cp";

        _rmPath = @"/var/jb/bin/rm";
        if (![fm fileExistsAtPath:_rmPath]) _rmPath = @"/usr/bin/rm";
        if (![fm fileExistsAtPath:_rmPath]) _rmPath = @"/bin/rm";

        _chmodPath = @"/var/jb/bin/chmod";
        if (![fm fileExistsAtPath:_chmodPath]) _chmodPath = @"/usr/bin/chmod";
        if (![fm fileExistsAtPath:_chmodPath]) _chmodPath = @"/bin/chmod";

        _chownPath = @"/var/jb/usr/sbin/chown";
        if (![fm fileExistsAtPath:_chownPath]) _chownPath = @"/usr/sbin/chown";
    }
    return self;
}

- (NSString *)providerName { return @"Direct Install"; }
- (NSString *)providerDescription { return @"تثبيت مباشر (Dopamine/Jailbreak)"; }
- (NSInteger)priority { return 100; }

- (BOOL)isAvailable {
    @try {
        RootlessManager *rl = [RootlessManager sharedManager];
        BOOL hasLdid = [rl fileExistsAtLogicalPath:@"/usr/bin/ldid"];
        BOOL hasUICache = [rl fileExistsAtLogicalPath:@"/usr/bin/uicache"];
        BOOL hasUnzip = [rl fileExistsAtLogicalPath:@"/usr/bin/unzip"];
        return hasLdid && hasUICache && hasUnzip;
    }
    @catch (NSException *exception) {
        return NO;
    }
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
        if (hasHelper) {
            logStep(@"HELPER", @"Root helper available — using privileged execution");
        } else {
            logStep(@"HELPER", @"Root helper NOT found — falling back to standard execution");
        }

        // 1. Create temp extraction dir
        NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
        logStep(@"TEMP", tempDir);

        // 2. Unzip IPA
        logStep(@"UNZIP", @"Extracting IPA...");
        NSString *unzipPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/unzip"];
        if (![fm fileExistsAtPath:unzipPath]) unzipPath = @"/usr/bin/unzip";

        BOOL unzipSuccess = [self runCommand:unzipPath args:@[@"-q", @"-o", ipaPath, @"-d", tempDir]];
        if (!unzipSuccess) {
            [fm removeItemAtPath:tempDir error:nil];
            logStep(@"ERROR", @"Failed to extract IPA");
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *result = [InstallationResult failureResult:@"فشل فك ضغط IPA" error:nil];
                result.detailedOutput = log;
                completion(result);
            });
            return;
        }
        logStep(@"UNZIP", @"Success");

        // 3. Find .app bundle
        NSString *payloadPath = [tempDir stringByAppendingPathComponent:@"Payload"];
        NSArray *payloadContents = [fm contentsOfDirectoryAtPath:payloadPath error:nil];
        NSString *appBundleName = nil;
        for (NSString *item in payloadContents) {
            if ([item hasSuffix:@".app"]) {
                appBundleName = item;
                break;
            }
        }

        if (!appBundleName) {
            [fm removeItemAtPath:tempDir error:nil];
            logStep(@"ERROR", @"No .app bundle found in Payload");
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *result = [InstallationResult failureResult:@"لم يتم العثور على .app داخل IPA" error:nil];
                result.detailedOutput = log;
                completion(result);
            });
            return;
        }
        logStep(@"BUNDLE", appBundleName);

        NSString *sourceAppPath = [payloadPath stringByAppendingPathComponent:appBundleName];
        NSString *destAppPath = [self.appsPath stringByAppendingPathComponent:appBundleName];
        NSString *exeName = [self executableNameFromApp:sourceAppPath];
        NSString *destExePath = exeName ? [destAppPath stringByAppendingPathComponent:exeName] : nil;

        // 4. Remove existing app if present
        if ([fm fileExistsAtPath:destAppPath]) {
            logStep(@"CLEAN", @"Removing existing app...");
            if (hasHelper) {
                [self runCommandAsRoot:self.rmPath args:@[@"-rf", destAppPath]];
            } else {
                [self runCommand:self.rmPath args:@[@"-rf", destAppPath]];
            }
        }

        // 5. Copy app to /Applications
        logStep(@"INSTALL", [NSString stringWithFormat:@"Copying to %@...", destAppPath]);
        BOOL copySuccess = NO;

        if (hasHelper) {
            // Try helper first
            copySuccess = [self runCommandAsRoot:self.cpPath args:@[@"-R", sourceAppPath, destAppPath]];
            if (!copySuccess) {
                // Fallback: use tar via helper
                logStep(@"FALLBACK", @"cp failed, trying tar...");
                NSString *tarPath = @"/var/jb/bin/tar";
                if (![fm fileExistsAtPath:tarPath]) tarPath = @"/usr/bin/tar";
                if ([fm fileExistsAtPath:tarPath]) {
                    NSString *parentDir = [destAppPath stringByDeletingLastPathComponent];
                    copySuccess = [self runCommandAsRoot:tarPath args:@[@"-cf", @"-", @"-C", [sourceAppPath stringByDeletingLastPathComponent], appBundleName, @"|", tarPath, @"-xf", @"-", @"-C", parentDir]];
                }
            }
        }

        // If helper failed or not available, try direct copyfile with setuid fallback
        if (!copySuccess) {
            logStep(@"FALLBACK", @"Trying copyfile() API...");
            if (copyfile([sourceAppPath UTF8String], [destAppPath UTF8String], NULL, COPYFILE_ALL | COPYFILE_RECURSIVE) == 0) {
                copySuccess = YES;
                logStep(@"COPY", @"copyfile() succeeded");
            } else {
                logStep(@"FALLBACK", [NSString stringWithFormat:@"copyfile() failed: %s", strerror(errno)]);
            }
        }

        // Last resort: NSFileManager
        if (!copySuccess) {
            NSError *copyErr = nil;
            copySuccess = [fm copyItemAtPath:sourceAppPath toPath:destAppPath error:&copyErr];
            if (copySuccess) {
                logStep(@"COPY", @"NSFileManager copy succeeded");
            } else {
                logStep(@"FALLBACK", [NSString stringWithFormat:@"NSFileManager failed: %@", copyErr.localizedDescription]);
            }
        }

        if (!copySuccess) {
            [fm removeItemAtPath:tempDir error:nil];
            logStep(@"ERROR", @"Failed to copy app to destination");
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *result = [InstallationResult failureResult:@"فشل نسخ التطبيق — تأكد من تشغيل الأداة بصلاحيات root أو تثبيت Root Helper" error:nil];
                result.detailedOutput = log;
                completion(result);
            });
            return;
        }
        logStep(@"COPY", @"App copied successfully");

        // 6. Sign with ldid
        logStep(@"SIGN", @"Signing app with ldid...");
        NSString *ldidPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/ldid"];
        if (![fm fileExistsAtPath:ldidPath]) ldidPath = @"/usr/bin/ldid";

        if (destExePath && [fm fileExistsAtPath:destExePath]) {
            if (hasHelper) {
                [self runCommandAsRoot:ldidPath args:@[@"-S", destExePath]];
            } else {
                [self runCommand:ldidPath args:@[@"-S", destExePath]];
            }
            logStep(@"SIGN", [NSString stringWithFormat:@"Signed executable: %@", exeName]);
        }

        // Sign dylibs and frameworks
        [self signDylibsAndFrameworksAtPath:destAppPath ldidPath:ldidPath hasHelper:hasHelper log:logStep];

        // 7. Set permissions
        logStep(@"PERM", @"Setting permissions...");
        if (hasHelper) {
            [self runCommandAsRoot:self.chmodPath args:@[@"-R", @"755", destAppPath]];
            if (destExePath) {
                [self runCommandAsRoot:self.chmodPath args:@[@"+x", destExePath]];
            }
            [self runCommandAsRoot:self.chownPath args:@[@"-R", @"root:wheel", destAppPath]];
        } else {
            [self runCommand:self.chmodPath args:@[@"-R", @"755", destAppPath]];
            if (destExePath) {
                [self runCommand:self.chmodPath args:@[@"+x", destExePath]];
            }
            [self runCommand:self.chownPath args:@[@"-R", @"root:wheel", destAppPath]];
        }
        logStep(@"PERM", @"Ownership set to root:wheel");

        // 8. Run uicache
        logStep(@"UICACHE", @"Refreshing UI cache...");
        NSString *uicachePath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/uicache"];
        if (![fm fileExistsAtPath:uicachePath]) uicachePath = @"/usr/bin/uicache";
        if (hasHelper) {
            [self runCommandAsRoot:uicachePath args:@[@"-p", destAppPath]];
        } else {
            [self runCommand:uicachePath args:@[@"-p", destAppPath]];
        }
        logStep(@"UICACHE", @"UI cache refreshed");

        // 9. Cleanup temp dir
        [fm removeItemAtPath:tempDir error:nil];
        logStep(@"CLEAN", @"Temp files removed");

        // 10. Verify
        logStep(@"VERIFY", @"Verifying installation...");
        BOOL exists = [fm fileExistsAtPath:destAppPath];
        logStep(@"VERIFY", exists ? @"App exists at destination" : @"App NOT found at destination!");

        dispatch_async(dispatch_get_main_queue(), ^{
            if (exists) {
                InstallationResult *result = [InstallationResult successResult:@"تم التثبيت بنجاح"];
                result.bundleID = [self bundleIDFromApp:destAppPath];
                result.detailedOutput = log;
                completion(result);
            } else {
                InstallationResult *result = [InstallationResult failureResult:@"التطبيق غير موجود بعد التثبيت" error:nil];
                result.detailedOutput = log;
                completion(result);
            }
        });
    });
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
    int status = posix_spawn(&pid, cmdPath, NULL, NULL, argv, NULL);
    free(argv);
    if (status != 0) return NO;
    int waitStatus;
    waitpid(pid, &waitStatus, 0);
    return WIFEXITED(waitStatus) && WEXITSTATUS(waitStatus) == 0;
}

- (void)signDylibsAndFrameworksAtPath:(NSString *)appPath ldidPath:(NSString *)ldidPath hasHelper:(BOOL)hasHelper log:(void (^)(NSString *, NSString *))logStep {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm contentsOfDirectoryAtPath:appPath error:nil];
    for (NSString *item in contents) {
        NSString *itemPath = [appPath stringByAppendingPathComponent:item];
        if ([item hasSuffix:@".dylib"]) {
            if (hasHelper) {
                [self runCommandAsRoot:ldidPath args:@[@"-S", itemPath]];
            } else {
                [self runCommand:ldidPath args:@[@"-S", itemPath]];
            }
            logStep(@"SIGN", [NSString stringWithFormat:@"Signed dylib: %@", item]);
        }
        if ([item hasSuffix:@".framework"]) {
            NSString *fwName = [item stringByDeletingPathExtension];
            NSString *fwExe = [itemPath stringByAppendingPathComponent:fwName];
            if ([fm fileExistsAtPath:fwExe]) {
                if (hasHelper) {
                    [self runCommandAsRoot:ldidPath args:@[@"-S", fwExe]];
                } else {
                    [self runCommand:ldidPath args:@[@"-S", fwExe]];
                }
                logStep(@"SIGN", [NSString stringWithFormat:@"Signed framework: %@", fwName]);
            }
        }
    }
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
            if ([self hasRootHelper]) {
                [self runCommandAsRoot:self.rmPath args:@[@"-rf", appPath]];
            } else {
                [self runCommand:self.rmPath args:@[@"-rf", appPath]];
            }
            NSString *uicachePath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/uicache"];
            if (![fm fileExistsAtPath:uicachePath]) uicachePath = @"/usr/bin/uicache";
            if ([self hasRootHelper]) {
                [self runCommandAsRoot:uicachePath args:@[@"-p", appPath]];
            } else {
                [self runCommand:uicachePath args:@[@"-p", appPath]];
            }
            if (completion) completion(YES, nil);
            return;
        }
    }
    if (completion) completion(NO, @"التطبيق غير موجود");
}

@end
