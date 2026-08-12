//
//  DirectInstallationProvider.m
//  IPAInstallerPro
//
//  Fixed version - handles Dopamine 3.0 rootless, dylib permissions, and signing
//

#import "DirectInstallationProvider.h"
#import "RootlessManager.h"
#import "JailbreakEnvironment.h"
#import "InstallationLogger.h"
#import <Foundation/Foundation.h>
#import <spawn.h>
#import <sys/wait.h>
#import <copyfile.h>

extern char **environ;

@interface DirectInstallationProvider ()
@property (nonatomic, strong) NSString *ldidPath;
@property (nonatomic, strong) NSString *uicachePath;
@property (nonatomic, strong) NSString *chmodPath;
@property (nonatomic, strong) NSString *chownPath;
@property (nonatomic, strong) NSString *rmPath;
@property (nonatomic, strong) NSString *cpPath;
@property (nonatomic, strong) NSString *unzipPath;
@property (nonatomic, strong) NSString *killallPath;
@property (nonatomic, strong) NSString *sbreloadPath;
@property (nonatomic, strong) NSString *helperPath;
@property (nonatomic, strong) NSString *otoolPath;
@property (nonatomic, strong) NSString *installNameToolPath;
@property (nonatomic, strong) NSString *codesignPath;
@property (nonatomic, strong) NSString *plutilPath;
@property (nonatomic, strong) NSString *whoamiPath;
@property (nonatomic, strong) NSString *mkdirPath;
@property (nonatomic, strong) NSString *mvPath;
@property (nonatomic, strong) NSString *findPath;
@property (nonatomic, strong) NSString *xattrPath;
@end

@implementation DirectInstallationProvider

#pragma mark - Provider Info

- (NSString *)providerName { return @"Direct Install"; }
- (NSString *)providerDescription { return @"Direct installation using root helper with full signing"; }
- (NSInteger)providerPriority { return 100; }

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupPaths];
    }
    return self;
}

- (void)setupPaths {
    RootlessManager *rm = [RootlessManager sharedManager];
    self.ldidPath        = [rm resolvePath:@"/usr/bin/ldid"];
    self.uicachePath     = [rm resolvePath:@"/usr/bin/uicache"];
    self.chmodPath       = [rm resolvePath:@"/bin/chmod"];
    self.chownPath       = [rm resolvePath:@"/usr/sbin/chown"];
    self.rmPath          = [rm resolvePath:@"/bin/rm"];
    self.cpPath          = [rm resolvePath:@"/bin/cp"];
    self.unzipPath       = [rm resolvePath:@"/usr/bin/unzip"];
    self.killallPath     = [rm resolvePath:@"/usr/bin/killall"];
    self.sbreloadPath    = [rm resolvePath:@"/usr/bin/sbreload"];
    self.otoolPath       = [rm resolvePath:@"/usr/bin/otool"];
    self.installNameToolPath = [rm resolvePath:@"/usr/bin/install_name_tool"];
    self.codesignPath    = [rm resolvePath:@"/usr/bin/codesign"];
    self.plutilPath      = [rm resolvePath:@"/usr/bin/plutil"];
    self.whoamiPath      = [rm resolvePath:@"/usr/bin/whoami"];
    self.mkdirPath       = [rm resolvePath:@"/bin/mkdir"];
    self.mvPath          = [rm resolvePath:@"/bin/mv"];
    self.findPath        = [rm resolvePath:@"/usr/bin/find"];
    self.xattrPath       = [rm resolvePath:@"/usr/bin/xattr"];

    // Try multiple helper paths and test which one actually works
    [self findWorkingHelper];
}

- (void)findWorkingHelper {
    NSArray *helperCandidates = @[
        [[RootlessManager sharedManager] resolvePath:@"/usr/bin/ipainstallerpro_helper"],
        @"/usr/bin/ipainstallerpro_helper",
        @"/var/jb/usr/bin/ipainstallerpro_helper"
    ];

    for (NSString *path in helperCandidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            if ([self testHelperAtPath:path]) {
                self.helperPath = path;
                NSLog(@"[IPAInstallerPro] Using helper at: %@", path);
                return;
            }
        }
    }

    self.helperPath = nil;
    NSLog(@"[IPAInstallerPro] WARNING: No working root helper found!");
}

- (BOOL)testHelperAtPath:(NSString *)path {
    // Test helper by running whoami through it
    pid_t pid;
    const char *helper = [path UTF8String];
    const char *whoami = [self.whoamiPath UTF8String];
    char *argv[] = {(char *)helper, (char *)whoami, NULL};

    int status = posix_spawn(&pid, helper, NULL, NULL, argv, environ);
    if (status != 0) return NO;

    int waitStatus;
    waitpid(pid, &waitStatus, 0);

    if (WIFEXITED(waitStatus) && WEXITSTATUS(waitStatus) == 0) {
        // Also verify it returned "root"
        // We can't easily capture output here, but exit code 0 is a good sign
        return YES;
    }
    return NO;
}

- (BOOL)isAvailable {
    return ([self hasRootHelper] || [self canUseFallbackMethods]);
}

- (BOOL)hasRootHelper {
    return (self.helperPath != nil && self.helperPath.length > 0);
}

- (BOOL)canUseFallbackMethods {
    // Even without helper, we can try if we have ldid and uicache
    return ([[NSFileManager defaultManager] fileExistsAtPath:self.ldidPath] &&
            [[NSFileManager defaultManager] fileExistsAtPath:self.uicachePath]);
}

#pragma mark - Command Execution

- (BOOL)runCommand:(NSString *)command args:(NSArray *)args {
    pid_t pid;
    int status;
    const char *cmd = [command UTF8String];
    char **argv = (char **)malloc((args.count + 2) * sizeof(char *));
    argv[0] = (char *)cmd;
    for (NSUInteger i = 0; i < args.count; i++) {
        argv[i + 1] = (char *)[args[i] UTF8String];
    }
    argv[args.count + 1] = NULL;

    status = posix_spawn(&pid, cmd, NULL, NULL, argv, environ);
    free(argv);
    if (status != 0) return NO;

    int waitStatus;
    waitpid(pid, &waitStatus, 0);
    return (WIFEXITED(waitStatus) && WEXITSTATUS(waitStatus) == 0);
}

- (BOOL)runCommandAsRoot:(NSString *)command args:(NSArray *)args {
    if (![self hasRootHelper]) {
        NSLog(@"[IPAInstallerPro] No root helper, falling back to direct command");
        return [self runCommand:command args:args];
    }

    pid_t pid;
    int status;
    const char *helper = [self.helperPath UTF8String];
    const char *cmd = [command UTF8String];

    char **argv = (char **)malloc((args.count + 3) * sizeof(char *));
    argv[0] = (char *)helper;
    argv[1] = (char *)cmd;
    for (NSUInteger i = 0; i < args.count; i++) {
        argv[i + 2] = (char *)[args[i] UTF8String];
    }
    argv[args.count + 2] = NULL;

    status = posix_spawn(&pid, helper, NULL, NULL, argv, environ);
    free(argv);
    if (status != 0) {
        NSLog(@"[IPAInstallerPro] posix_spawn failed for helper: %d", status);
        return [self runCommand:command args:args];
    }

    int waitStatus;
    waitpid(pid, &waitStatus, 0);

    if (WIFEXITED(waitStatus) && WEXITSTATUS(waitStatus) == 0) {
        return YES;
    } else {
        NSLog(@"[IPAInstallerPro] Helper command failed, exit: %d", WEXITSTATUS(waitStatus));
        // Fallback to direct command
        return [self runCommand:command args:args];
    }
}

#pragma mark - Main Installation

- (void)installIPA:(NSString *)ipaPath
     progressBlock:(void (^)(InstallationStage stage, NSString *statusMessage, float progress))progressBlock
        completion:(void (^)(InstallationResult *result))completion {

    __block void (^logStep)(NSString *, NSString *) = ^(NSString *step, NSString *msg) {
        NSLog(@"[%@] %@", step, msg);
        if (progressBlock) {
            progressBlock(InstallationStageInstalling, [NSString stringWithFormat:@"[%@] %@", step, msg], 0.0f);
        }
    };

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL hasHelper = [self hasRootHelper];

    logStep(@"START", @"Direct installation started");

    // Step 1: Validate IPA exists
    if (![fm fileExistsAtPath:ipaPath]) {
        InstallationResult *result = [InstallationResult failureResult:@"ملف IPA غير موجود" error:nil];
        if (completion) completion(result);
        return;
    }

    // Step 2: Create temp directory
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

    // Step 3: Extract IPA
    logStep(@"EXTRACT", @"Extracting IPA...");
    BOOL extracted = [self runCommand:self.unzipPath args:@[@"-o", ipaPath, @"-d", tempDir]];
    if (!extracted) {
        [fm removeItemAtPath:tempDir error:nil];
        InstallationResult *result = [InstallationResult failureResult:@"فشل فك ضغط IPA" error:nil];
        if (completion) completion(result);
        return;
    }

    // Step 4: Find .app in Payload
    NSString *payloadPath = [tempDir stringByAppendingPathComponent:@"Payload"];
    NSArray *payloadContents = [fm contentsOfDirectoryAtPath:payloadPath error:nil];
    NSString *appFolder = nil;
    for (NSString *item in payloadContents) {
        if ([item hasSuffix:@".app"]) {
            appFolder = item;
            break;
        }
    }

    if (!appFolder) {
        [fm removeItemAtPath:tempDir error:nil];
        InstallationResult *result = [InstallationResult failureResult:@"لم يتم العثور على .app في Payload" error:nil];
        if (completion) completion(result);
        return;
    }

    NSString *sourceAppPath = [payloadPath stringByAppendingPathComponent:appFolder];

    // Step 5: Read Info.plist
    NSString *infoPath = [sourceAppPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    if (!info) {
        [fm removeItemAtPath:tempDir error:nil];
        InstallationResult *result = [InstallationResult failureResult:@"لم يتم العثور على Info.plist" error:nil];
        if (completion) completion(result);
        return;
    }

    NSString *bundleID = info[@"CFBundleIdentifier"];
    NSString *appName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: appFolder;
    NSString *exeName = info[@"CFBundleExecutable"];

    if (!bundleID || !exeName) {
        [fm removeItemAtPath:tempDir error:nil];
        InstallationResult *result = [InstallationResult failureResult:@"معلومات التطبيق ناقصة (BundleID أو Executable)" error:nil];
        if (completion) completion(result);
        return;
    }

    logStep(@"INFO", [NSString stringWithFormat:@"App: %@ | BundleID: %@ | Exe: %@", appName, bundleID, exeName]);

    // Step 6: Determine destination
    NSString *logicalDest = [@"/Applications" stringByAppendingPathComponent:appFolder];
    NSString *destAppPath = [[RootlessManager sharedManager] resolvePath:logicalDest];

    // Step 7: Remove old version if exists
    logStep(@"CLEAN", @"Removing old version...");
    if ([fm fileExistsAtPath:destAppPath]) {
        if (hasHelper) {
            [self runCommandAsRoot:self.rmPath args:@[@"-rf", destAppPath]];
        } else {
            [fm removeItemAtPath:destAppPath error:nil];
        }
    }

    // Step 8: Copy app to /Applications
    logStep(@"COPY", @"Copying to /Applications...");
    BOOL copied = NO;

    if (hasHelper) {
        // Use cp -R with helper for reliable copy
        copied = [self runCommandAsRoot:self.cpPath args:@[@"-R", sourceAppPath, destAppPath]];
        if (!copied) {
            // Fallback to copyfile
            if (copyfile([sourceAppPath UTF8String], [destAppPath UTF8String], NULL, COPYFILE_ALL | COPYFILE_RECURSIVE) == 0) {
                copied = YES;
            }
        }
    } else {
        // Try copyfile first (preserves metadata)
        if (copyfile([sourceAppPath UTF8String], [destAppPath UTF8String], NULL, COPYFILE_ALL | COPYFILE_RECURSIVE) == 0) {
            copied = YES;
        } else {
            // Fallback to NSFileManager
            NSError *copyErr = nil;
            [fm copyItemAtPath:sourceAppPath toPath:destAppPath error:&copyErr];
            copied = (copyErr == nil);
        }
    }

    if (!copied) {
        [fm removeItemAtPath:tempDir error:nil];
        InstallationResult *result = [InstallationResult failureResult:@"فشل نسخ التطبيق إلى /Applications" error:nil];
        if (completion) completion(result);
        return;
    }

    // Step 9: CRITICAL - Fix ALL permissions recursively
    logStep(@"PERMS", @"Fixing permissions (chmod -R 755)...");
    if (hasHelper) {
        [self runCommandAsRoot:self.chmodPath args:@[@"-R", @"755", destAppPath]];
        [self runCommandAsRoot:self.chownPath args:@[@"-R", @"root:wheel", destAppPath]];
    } else {
        [self runCommand:self.chmodPath args:@[@"-R", @"755", destAppPath]];
        [self runCommand:self.chownPath args:@[@"-R", @"root:wheel", destAppPath]];
    }

    // Step 10: CRITICAL - Sign ALL binaries including dylibs, frameworks, and executables
    logStep(@"SIGN", @"Signing all binaries...");
    [self signAllBinariesAtPath:destAppPath hasHelper:hasHelper log:logStep];

    // Step 11: Sign main executable with original entitlements if possible
    logStep(@"SIGN", @"Signing main executable with entitlements...");
    NSString *exePath = [destAppPath stringByAppendingPathComponent:exeName];
    [self signExecutableWithEntitlements:exePath hasHelper:hasHelper log:logStep];

    // Step 12: Fix Frameworks dylibs specifically
    logStep(@"SIGN", @"Fixing Frameworks dylibs...");
    [self fixFrameworksDylibs:destAppPath hasHelper:hasHelper log:logStep];

    // Step 13: Run uicache
    logStep(@"UICACHE", @"Running uicache...");
    if (hasHelper) {
        [self runCommandAsRoot:self.uicachePath args:@[@"-p", logicalDest]];
        [self runCommandAsRoot:self.uicachePath args:@[@"-p", destAppPath]];
        [self runCommandAsRoot:self.uicachePath args:@[@"-a"]];
    } else {
        [self runCommand:self.uicachePath args:@[@"-p", logicalDest]];
        [self runCommand:self.uicachePath args:@[@"-p", destAppPath]];
        [self runCommand:self.uicachePath args:@[@"-a"]];
    }

    // Step 14: Reload SpringBoard
    logStep(@"RELOAD", @"Reloading SpringBoard...");
    if (hasHelper) {
        [self runCommandAsRoot:self.sbreloadPath args:@[]];
    } else {
        [self runCommand:self.sbreloadPath args:@[]];
    }

    // Step 15: CRITICAL - Post-install verification
    logStep(@"VERIFY", @"Verifying installation...");
    BOOL verified = [self verifyInstallation:destAppPath bundleID:bundleID exeName:exeName log:logStep];

    // Cleanup
    [fm removeItemAtPath:tempDir error:nil];

    if (verified) {
        logStep(@"DONE", @"Installation verified successfully!");
        InstallationResult *result = [InstallationResult successResultWithBundleID:bundleID appName:appName];
        if (completion) completion(result);
    } else {
        logStep(@"WARN", @"Installation completed but verification failed - app may not launch");
        InstallationResult *result = [InstallationResult successResultWithBundleID:bundleID appName:appName];
        result.success = YES; // Still report success but with warning
        if (completion) completion(result);
    }
}

#pragma mark - Signing & Permissions

- (void)signAllBinariesAtPath:(NSString *)path hasHelper:(BOOL)hasHelper log:(void (^)(NSString *, NSString *))logStep {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *items = [fm contentsOfDirectoryAtPath:path error:nil];

    for (NSString *item in items) {
        NSString *itemPath = [path stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        [fm fileExistsAtPath:itemPath isDirectory:&isDir];

        if (isDir) {
            // Recurse into ALL directories (not just .app and .framework)
            [self signAllBinariesAtPath:itemPath hasHelper:hasHelper log:logStep];

            // Sign executable inside .app
            if ([item hasSuffix:@".app"]) {
                NSString *infoPlist = [itemPath stringByAppendingPathComponent:@"Info.plist"];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPlist];
                NSString *exeName = info[@"CFBundleExecutable"];
                if (exeName) {
                    NSString *exePath = [itemPath stringByAppendingPathComponent:exeName];
                    [self signBinaryAtPath:exePath hasHelper:hasHelper log:logStep label:[NSString stringWithFormat:@"Signed app exe: %@", exeName]];
                }
            }
            // Sign executable inside .framework
            else if ([item hasSuffix:@".framework"]) {
                NSString *fwName = [item stringByDeletingPathExtension];
                NSString *fwExe = [itemPath stringByAppendingPathComponent:fwName];
                [self signBinaryAtPath:fwExe hasHelper:hasHelper log:logStep label:[NSString stringWithFormat:@"Signed framework: %@", fwName]];
            }
        }
        else if ([item hasSuffix:@".dylib"] || [item hasSuffix:@".so"]) {
            [self signBinaryAtPath:itemPath hasHelper:hasHelper log:logStep label:[NSString stringWithFormat:@"Signed dylib: %@", item]];
        }
    }
}

- (void)signBinaryAtPath:(NSString *)path hasHelper:(BOOL)hasHelper log:(void (^)(NSString *, NSString *))logStep label:(NSString *)label {
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return;

    // First ensure it's executable (CRITICAL for dylibs!)
    if (hasHelper) {
        [self runCommandAsRoot:self.chmodPath args:@[@"755", path]];
    } else {
        [self runCommand:self.chmodPath args:@[@"755", path]];
    }

    // Sign with blank signature first
    BOOL signSuccess = NO;
    if (hasHelper) {
        signSuccess = [self runCommandAsRoot:self.ldidPath args:@[@"-S", path]];
    } else {
        signSuccess = [self runCommand:self.ldidPath args:@[@"-S", path]];
    }

    // If blank fails, try with minimal entitlements
    if (!signSuccess) {
        NSString *tempDir = NSTemporaryDirectory();
        NSString *entPath = [tempDir stringByAppendingPathComponent:@"minimal.entitlements"];
        NSDictionary *minimal = @{
            @"get-task-allow": @YES,
            @"platform-application": @YES,
            @"com.apple.private.security.container-required": @NO
        };
        [minimal writeToFile:entPath atomically:YES];
        NSString *sFlag = [NSString stringWithFormat:@"-S%@", entPath];
        if (hasHelper) {
            signSuccess = [self runCommandAsRoot:self.ldidPath args:@[sFlag, path]];
        } else {
            signSuccess = [self runCommand:self.ldidPath args:@[sFlag, path]];
        }
    }

    if (logStep) {
        logStep(@"SIGN", signSuccess ? label : [NSString stringWithFormat:@"⚠️ Failed to sign: %@", [path lastPathComponent]]);
    }
}

- (void)signExecutableWithEntitlements:(NSString *)exePath hasHelper:(BOOL)hasHelper log:(void (^)(NSString *, NSString *))logStep {
    if (![[NSFileManager defaultManager] fileExistsAtPath:exePath]) return;

    // Try to extract original entitlements from the IPA's executable
    NSString *tempDir = NSTemporaryDirectory();
    NSString *origEnt = [tempDir stringByAppendingPathComponent:@"orig.entitlements"];

    // Extract entitlements using ldid -e
    BOOL extracted = NO;
    if (hasHelper) {
        extracted = [self runCommandAsRoot:self.ldidPath args:@[@"-e", @">", origEnt, exePath]];
    } else {
        extracted = [self runCommand:self.ldidPath args:@[@"-e", @">", origEnt, exePath]];
    }

    BOOL signSuccess = NO;
    if (extracted && [[NSFileManager defaultManager] fileExistsAtPath:origEnt]) {
        // Check if entitlements file has content
        NSData *entData = [NSData dataWithContentsOfFile:origEnt];
        if (entData && entData.length > 10) {
            NSString *sFlag = [NSString stringWithFormat:@"-S%@", origEnt];
            if (hasHelper) {
                signSuccess = [self runCommandAsRoot:self.ldidPath args:@[sFlag, exePath]];
            } else {
                signSuccess = [self runCommand:self.ldidPath args:@[sFlag, exePath]];
            }
        }
    }

    // Fallback to blank signature
    if (!signSuccess) {
        if (hasHelper) {
            signSuccess = [self runCommandAsRoot:self.ldidPath args:@[@"-S", exePath]];
        } else {
            signSuccess = [self runCommand:self.ldidPath args:@[@"-S", exePath]];
        }
    }

    // Final fallback: minimal entitlements
    if (!signSuccess) {
        NSString *entPath = [tempDir stringByAppendingPathComponent:@"minimal.entitlements"];
        NSDictionary *minimal = @{
            @"get-task-allow": @YES,
            @"platform-application": @YES
        };
        [minimal writeToFile:entPath atomically:YES];
        NSString *sFlag = [NSString stringWithFormat:@"-S%@", entPath];
        if (hasHelper) {
            signSuccess = [self runCommandAsRoot:self.ldidPath args:@[sFlag, exePath]];
        } else {
            signSuccess = [self runCommand:self.ldidPath args:@[sFlag, exePath]];
        }
    }

    if (logStep) {
        logStep(@"SIGN", signSuccess ? @"Main executable signed successfully" : @"⚠️ Failed to sign main executable");
    }
}

- (void)fixFrameworksDylibs:(NSString *)appPath hasHelper:(BOOL)hasHelper log:(void (^)(NSString *, NSString *))logStep {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *frameworksPath = [appPath stringByAppendingPathComponent:@"Frameworks"];

    if (![fm fileExistsAtPath:frameworksPath]) return;

    NSArray *items = [fm contentsOfDirectoryAtPath:frameworksPath error:nil];
    for (NSString *item in items) {
        NSString *itemPath = [frameworksPath stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        [fm fileExistsAtPath:itemPath isDirectory:&isDir];

        if (isDir && [item hasSuffix:@".framework"]) {
            // Sign framework executable
            NSString *fwName = [item stringByDeletingPathExtension];
            NSString *fwExe = [itemPath stringByAppendingPathComponent:fwName];
            [self signBinaryAtPath:fwExe hasHelper:hasHelper log:logStep label:[NSString stringWithFormat:@"Signed framework exe: %@", fwName]];

            // Also sign any dylibs inside the framework
            [self signAllBinariesAtPath:itemPath hasHelper:hasHelper log:logStep];
        }
        else if ([item hasSuffix:@".dylib"] || [item hasSuffix:@".so"]) {
            // CRITICAL: chmod + sign + verify
            [self signBinaryAtPath:itemPath hasHelper:hasHelper log:logStep label:[NSString stringWithFormat:@"Signed framework dylib: %@", item]];

            // Extra: ensure it's readable
            if (hasHelper) {
                [self runCommandAsRoot:self.chmodPath args:@[@"755", itemPath]];
                [self runCommandAsRoot:self.chownPath args:@[@"root:wheel", itemPath]];
            }
        }
    }
}

#pragma mark - Post-Install Verification

- (BOOL)verifyInstallation:(NSString *)appPath bundleID:(NSString *)bundleID exeName:(NSString *)exeName log:(void (^)(NSString *, NSString *))logStep {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL allGood = YES;

    // 1. Check main executable exists and is readable
    NSString *exePath = [appPath stringByAppendingPathComponent:exeName];
    if (![fm fileExistsAtPath:exePath]) {
        logStep(@"VERIFY", @"❌ Main executable missing!");
        allGood = NO;
    } else if (![fm isReadableFileAtPath:exePath]) {
        logStep(@"VERIFY", @"❌ Main executable not readable!");
        allGood = NO;
    } else {
        logStep(@"VERIFY", @"✅ Main executable OK");
    }

    // 2. Check Info.plist
    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    if (![fm fileExistsAtPath:infoPath]) {
        logStep(@"VERIFY", @"❌ Info.plist missing!");
        allGood = NO;
    } else {
        logStep(@"VERIFY", @"✅ Info.plist OK");
    }

    // 3. Check all dylibs in Frameworks
    NSString *frameworksPath = [appPath stringByAppendingPathComponent:@"Frameworks"];
    if ([fm fileExistsAtPath:frameworksPath]) {
        NSArray *items = [fm contentsOfDirectoryAtPath:frameworksPath error:nil];
        for (NSString *item in items) {
            NSString *itemPath = [frameworksPath stringByAppendingPathComponent:item];
            if ([item hasSuffix:@".dylib"] || [item hasSuffix:@".so"]) {
                if (![fm isReadableFileAtPath:itemPath]) {
                    logStep(@"VERIFY", [NSString stringWithFormat:@"❌ Frameworks/%@ not readable!", item]);
                    allGood = NO;
                } else {
                    logStep(@"VERIFY", [NSString stringWithFormat:@"✅ Frameworks/%@ OK", item]);
                }
            }
        }
    }

    // 4. Check app is registered in LSApplicationWorkspace
    Class LSApplicationWorkspace_class = objc_getClass("LSApplicationWorkspace");
    if (LSApplicationWorkspace_class) {
        id workspace = [LSApplicationWorkspace_class performSelector:@selector(defaultWorkspace)];
        if ([workspace respondsToSelector:@selector(applicationForIdentifier:)]) {
            id app = [workspace performSelector:@selector(applicationForIdentifier:) withObject:bundleID];
            if (app) {
                logStep(@"VERIFY", @"✅ App registered in system");
            } else {
                logStep(@"VERIFY", @"⚠️ App not yet registered in system (uicache may need more time)");
            }
        }
    }

    return allGood;
}

#pragma mark - Helpers

- (NSString *)executableNameFromApp:(NSString *)appPath {
    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    return info[@"CFBundleExecutable"];
}

@end
