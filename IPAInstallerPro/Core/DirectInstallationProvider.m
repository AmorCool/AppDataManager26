#import "DirectInstallationProvider.h"
#import "Logger.h"
#import "RootlessManager.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <spawn.h>
#include <sys/wait.h>

@interface DirectInstallationProvider ()
@property (nonatomic, strong) NSString *appsPath;
@property (nonatomic, strong) NSString *jbPrefix;
@property (nonatomic, assign) BOOL hasRootAccess;
@end

@implementation DirectInstallationProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *resolvedApps = [[RootlessManager sharedManager] resolvePath:@"/Applications"];
        _appsPath = resolvedApps;
        if ([resolvedApps hasPrefix:@"/var/jb"]) {
            _jbPrefix = @"/var/jb";
        } else {
            _jbPrefix = @"";
        }
        _hasRootAccess = (getuid() == 0);
    }
    return self;
}

- (NSString *)providerName { return @"Direct Install"; }
- (NSString *)providerDescription { return @"تثبيت مباشر (يتطلب root)"; }
- (NSInteger)priority { return 100; }

- (BOOL)isAvailable {
    // Direct install requires root access + ldid
    if (!self.hasRootAccess) {
        [[Logger sharedLogger] warning:@"DirectInstall: No root access (getuid != 0)"];
        return NO;
    }
    NSString *ldidPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/ldid"];
    return [[NSFileManager defaultManager] fileExistsAtPath:ldidPath];
}

- (void)installIPA:(NSString *)ipaPath completion:(void (^)(InstallationResult *))completion {
    if (!completion) return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableString *log = [NSMutableString string];

        auto logStep = ^(NSString *step, NSString *detail) {
            NSString *entry = [NSString stringWithFormat:@"[DirectInstall] %@: %@", step, detail];
            [[Logger sharedLogger] info:entry];
            [log appendFormat:@"%@\n", entry];
        };

        logStep(@"START", [NSString stringWithFormat:@"Installing %@", [ipaPath lastPathComponent]]);
        logStep(@"INFO", [NSString stringWithFormat:@"Root access: %@, Apps path: %@", self.hasRootAccess ? @"YES" : @"NO", self.appsPath]);

        // 1. Create temp extraction dir
        NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
        logStep(@"TEMP", tempDir);

        // 2. Unzip IPA
        logStep(@"UNZIP", @"Extracting IPA...");
        if (![self unzipIPA:ipaPath toDirectory:tempDir]) {
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

        // 4. Remove existing app if present
        if ([fm fileExistsAtPath:destAppPath]) {
            logStep(@"CLEAN", @"Removing existing app...");
            [self runCommand:@"/bin/rm" args:@[@"-rf", destAppPath]];
        }

        // 5. Copy to Applications using cp -R (requires root)
        logStep(@"COPY", [NSString stringWithFormat:@"Copying to %@...", destAppPath]);
        BOOL copied = [self runCommand:@"/bin/cp" args:@[@"-R", sourceAppPath, destAppPath]];
        if (!copied) {
            // Fallback: try with NSFileManager (if permissions allow)
            NSError *copyError = nil;
            copied = [fm copyItemAtPath:sourceAppPath toPath:destAppPath error:&copyError];
            if (!copied) {
                [fm removeItemAtPath:tempDir error:nil];
                NSString *errMsg = [NSString stringWithFormat:@"فشل النسخ: %@", copyError.localizedDescription];
                logStep(@"ERROR", errMsg);
                dispatch_async(dispatch_get_main_queue(), ^{
                    InstallationResult *result = [InstallationResult failureResult:errMsg error:copyError];
                    result.detailedOutput = log;
                    completion(result);
                });
                return;
            }
        }
        logStep(@"COPY", @"Success");

        // 6. Sign with ldid
        logStep(@"SIGN", @"Signing app with ldid...");
        [self signAppAtPath:destAppPath log:logStep];

        // 7. Set permissions
        logStep(@"PERM", @"Setting permissions...");
        [self setPermissions:destAppPath log:logStep];

        // 8. Run uicache
        logStep(@"UICACHE", @"Refreshing UI cache...");
        [self runUICache:destAppPath log:logStep];

        // 9. Cleanup
        [fm removeItemAtPath:tempDir error:nil];
        logStep(@"CLEAN", @"Temp files removed");

        // 10. Verify
        logStep(@"VERIFY", @"Verifying installation...");
        BOOL exists = [fm fileExistsAtPath:destAppPath];
        logStep(@"VERIFY", exists ? @"App exists at destination" : @"App NOT found at destination!");

        dispatch_async(dispatch_get_main_queue(), ^{
            InstallationResult *result = [InstallationResult successResult:@"تم التثبيت بنجاح"];
            result.bundleID = [self bundleIDFromApp:destAppPath];
            result.detailedOutput = log;
            completion(result);
        });
    });
}

- (BOOL)unzipIPA:(NSString *)ipaPath toDirectory:(NSString *)destDir {
    NSString *unzipPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/unzip"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:unzipPath]) {
        unzipPath = @"/usr/bin/unzip";
    }
    return [self runCommand:unzipPath args:@[@"-q", @"-o", ipaPath, @"-d", destDir]];
}

- (void)signAppAtPath:(NSString *)appPath log:(void (^)(NSString *, NSString *))logStep {
    NSString *ldidPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/ldid"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:ldidPath]) {
        ldidPath = @"/usr/bin/ldid";
    }

    NSString *exeName = [self executableNameFromApp:appPath];
    if (exeName) {
        NSString *exePath = [appPath stringByAppendingPathComponent:exeName];
        logStep(@"SIGN", [NSString stringWithFormat:@"Signing executable: %@", exeName]);
        [self runCommand:ldidPath args:@[@"-S", exePath]];
    }

    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appPath error:nil];
    for (NSString *item in contents) {
        if ([item hasSuffix:@".dylib"]) {
            NSString *dylibPath = [appPath stringByAppendingPathComponent:item];
            logStep(@"SIGN", [NSString stringWithFormat:@"Signing dylib: %@", item]);
            [self runCommand:ldidPath args:@[@"-S", dylibPath]];
        }
        if ([item hasSuffix:@".framework"]) {
            NSString *fwPath = [appPath stringByAppendingPathComponent:item];
            NSString *fwName = [item stringByDeletingPathExtension];
            NSString *fwExe = [fwPath stringByAppendingPathComponent:fwName];
            if ([[NSFileManager defaultManager] fileExistsAtPath:fwExe]) {
                logStep(@"SIGN", [NSString stringWithFormat:@"Signing framework: %@", fwName]);
                [self runCommand:ldidPath args:@[@"-S", fwExe]];
            }
        }
    }
}

- (void)setPermissions:(NSString *)appPath log:(void (^)(NSString *, NSString *))logStep {
    [self runCommand:@"/bin/chmod" args:@[@"-R", @"755", appPath]];
    NSString *exeName = [self executableNameFromApp:appPath];
    if (exeName) {
        NSString *exePath = [appPath stringByAppendingPathComponent:exeName];
        logStep(@"PERM", [NSString stringWithFormat:@"chmod +x %@", exeName]);
        [self runCommand:@"/bin/chmod" args:@[@"+x", exePath]];
    }
    // Set ownership to root:wheel for system apps
    [self runCommand:@"/usr/sbin/chown" args:@[@"-R", @"root:wheel", appPath]];
    logStep(@"PERM", @"Ownership set to root:wheel");
}

- (void)runUICache:(NSString *)appPath log:(void (^)(NSString *, NSString *))logStep {
    NSString *uicachePath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/uicache"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:uicachePath]) {
        uicachePath = @"/usr/bin/uicache";
    }
    logStep(@"UICACHE", [NSString stringWithFormat:@"Running: %@ -p %@", uicachePath, appPath]);
    [self runCommand:uicachePath args:@[@"-p", appPath]];
}

- (BOOL)runCommand:(NSString *)cmd args:(NSArray *)args {
    if (!cmd || args.count == 0) return NO;

    const char *cmdPath = [cmd UTF8String];
    char **argv = (char **)malloc((args.count + 2) * sizeof(char *));
    argv[0] = (char *)cmdPath;
    for (int i = 0; i < args.count; i++) {
        argv[i + 1] = (char *)[[args objectAtIndex:i] UTF8String];
    }
    argv[args.count + 1] = NULL;

    pid_t pid;
    int status = posix_spawn(&pid, cmdPath, NULL, NULL, argv, NULL);
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
            [self runCommand:@"/bin/rm" args:@[@"-rf", appPath]];
            [self runUICache:appPath log:^(NSString *s, NSString *d){}];
            if (completion) completion(YES, nil);
            return;
        }
    }
    if (completion) completion(NO, @"التطبيق غير موجود");
}

@end
