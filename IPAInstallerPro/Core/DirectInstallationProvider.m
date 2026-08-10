#import "DirectInstallationProvider.h"
#import "Logger.h"
#import "RootlessManager.h"
#import <Foundation/Foundation.h>
#include <spawn.h>
#include <sys/wait.h>

@interface DirectInstallationProvider ()
@property (nonatomic, strong) NSString *appsPath;
@property (nonatomic, strong) NSString *jbPrefix;
@end

@implementation DirectInstallationProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        // Detect rootless vs rootful using RootlessManager
        NSString *resolvedApps = [[RootlessManager sharedManager] resolvePath:@"/Applications"];
        _appsPath = resolvedApps;
        if ([resolvedApps hasPrefix:@"/var/jb"]) {
            _jbPrefix = @"/var/jb";
        } else {
            _jbPrefix = @"";
        }
    }
    return self;
}

- (NSString *)providerName { return @"Direct Install (No AppSync)"; }
- (NSString *)providerDescription { return @"Direct installation without AppSync using ldid + uicache"; }
- (NSInteger)priority { return 100; }

- (BOOL)isAvailable {
    // Check if we have root access and ldid (via RootlessManager)
    NSString *ldidPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/ldid"];
    return [[NSFileManager defaultManager] fileExistsAtPath:ldidPath];
}

- (void)installIPA:(NSString *)ipaPath completion:(void (^)(InstallationResult *))completion {
    if (!completion) return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        // 1. Create temp extraction dir
        NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

        // 2. Unzip IPA
        NSString *payloadPath = [tempDir stringByAppendingPathComponent:@"Payload"];
        if (![self unzipIPA:ipaPath toDirectory:tempDir]) {
            [fm removeItemAtPath:tempDir error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([InstallationResult failureResult:@"فشل فك ضغط IPA" error:nil]);
            });
            return;
        }

        // 3. Find .app bundle
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
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([InstallationResult failureResult:@"لم يتم العثور على .app داخل IPA" error:nil]);
            });
            return;
        }

        NSString *sourceAppPath = [payloadPath stringByAppendingPathComponent:appBundleName];
        NSString *destAppPath = [self.appsPath stringByAppendingPathComponent:appBundleName];

        // 4. Remove existing app if present
        if ([fm fileExistsAtPath:destAppPath]) {
            [fm removeItemAtPath:destAppPath error:nil];
        }

        // 5. Copy to Applications
        NSError *copyError = nil;
        BOOL copied = [fm copyItemAtPath:sourceAppPath toPath:destAppPath error:&copyError];
        if (!copied) {
            [fm removeItemAtPath:tempDir error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([InstallationResult failureResult:[NSString stringWithFormat:@"فشل النسخ: %@", copyError.localizedDescription] error:nil]);
            });
            return;
        }

        // 6. Sign with ldid
        [self signAppAtPath:destAppPath];

        // 7. Set permissions
        [self setPermissions:destAppPath];

        // 8. Run uicache
        [self runUICache:destAppPath];

        // 9. Cleanup
        [fm removeItemAtPath:tempDir error:nil];

        dispatch_async(dispatch_get_main_queue(), ^{
            InstallationResult *result = [InstallationResult successResult:@"تم التثبيت بنجاح بدون AppSync"];
            result.bundleID = [self bundleIDFromApp:destAppPath];
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

- (void)signAppAtPath:(NSString *)appPath {
    NSString *ldidPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/ldid"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:ldidPath]) {
        ldidPath = @"/usr/bin/ldid";
    }

    // Sign the main executable
    NSString *exeName = [self executableNameFromApp:appPath];
    if (exeName) {
        NSString *exePath = [appPath stringByAppendingPathComponent:exeName];
        [self runCommand:ldidPath args:@[@"-S", exePath]];
    }

    // Sign all dylibs
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appPath error:nil];
    for (NSString *item in contents) {
        if ([item hasSuffix:@".dylib"]) {
            NSString *dylibPath = [appPath stringByAppendingPathComponent:item];
            [self runCommand:ldidPath args:@[@"-S", dylibPath]];
        }
        // Sign frameworks
        if ([item hasSuffix:@".framework"]) {
            NSString *fwPath = [appPath stringByAppendingPathComponent:item];
            NSString *fwName = [item stringByDeletingPathExtension];
            NSString *fwExe = [fwPath stringByAppendingPathComponent:fwName];
            if ([[NSFileManager defaultManager] fileExistsAtPath:fwExe]) {
                [self runCommand:ldidPath args:@[@"-S", fwExe]];
            }
        }
    }
}

- (void)setPermissions:(NSString *)appPath {
    [self runCommand:@"/bin/chmod" args:@[@"-R", @"755", appPath]];
    NSString *exeName = [self executableNameFromApp:appPath];
    if (exeName) {
        NSString *exePath = [appPath stringByAppendingPathComponent:exeName];
        [self runCommand:@"/bin/chmod" args:@[@"+x", exePath]];
    }
}

- (void)runUICache:(NSString *)appPath {
    NSString *uicachePath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/uicache"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:uicachePath]) {
        uicachePath = @"/usr/bin/uicache";
    }
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
    // Find app by bundle ID and remove
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *apps = [fm contentsOfDirectoryAtPath:self.appsPath error:nil];
    for (NSString *app in apps) {
        if (![app hasSuffix:@".app"]) continue;
        NSString *appPath = [self.appsPath stringByAppendingPathComponent:app];
        NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        if ([info[@"CFBundleIdentifier"] isEqualToString:bundleID]) {
            NSError *err = nil;
            [fm removeItemAtPath:appPath error:&err];
            [self runUICache:appPath];
            if (completion) completion(err == nil, err ? err.localizedDescription : nil);
            return;
        }
    }
    if (completion) completion(NO, @"التطبيق غير موجود");
}

@end
