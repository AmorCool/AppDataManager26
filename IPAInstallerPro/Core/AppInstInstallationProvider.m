#import "AppInstInstallationProvider.h"
#import "Logger.h"
#import "RootlessManager.h"
#import <objc/runtime.h>
#include <spawn.h>
#include <sys/wait.h>

@interface AppInstInstallationProvider ()
@property (nonatomic, strong) NSString *appInstPath;
@end

@implementation AppInstInstallationProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *resolvedPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/appinst"];
        _appInstPath = resolvedPath;
    }
    return self;
}

- (NSString *)providerName { return @"appinst"; }
- (NSString *)providerDescription { return @"تثبيت عبر appinst CLI"; }
- (NSInteger)priority { return 100; }

- (BOOL)isAvailable {
    return [[NSFileManager defaultManager] fileExistsAtPath:self.appInstPath];
}

- (void)installIPA:(NSString *)ipaPath completion:(void (^)(InstallationResult *))completion {
    if (!completion) return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableString *log = [NSMutableString string];
        void (^logStep)(NSString *, NSString *) = ^(NSString *step, NSString *detail) {
            NSString *entry = [NSString stringWithFormat:@"[AppInst] %@: %@", step, detail];
            [[Logger sharedLogger] info:entry];
            [log appendFormat:@"%@\n", entry];
        };

        logStep(@"START", [NSString stringWithFormat:@"Installing %@ via appinst", [ipaPath lastPathComponent]]);
        logStep(@"PATH", self.appInstPath);

        const char *cmd = [self.appInstPath UTF8String];
        const char *args[] = { cmd, "-i", [ipaPath UTF8String], NULL };

        logStep(@"EXEC", [NSString stringWithFormat:@"%@ -i %@", self.appInstPath, ipaPath]);

        pid_t pid;
        int status = posix_spawn(&pid, cmd, NULL, NULL, (char **)args, NULL);

        if (status != 0) {
            NSString *errMsg = [NSString stringWithFormat:@"posix_spawn failed: %d", status];
            logStep(@"ERROR", errMsg);
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *result = [InstallationResult failureResult:errMsg error:nil];
                result.detailedOutput = log;
                completion(result);
            });
            return;
        }

        int waitStatus;
        waitpid(pid, &waitStatus, 0);
        BOOL success = WIFEXITED(waitStatus) && WEXITSTATUS(waitStatus) == 0;

        if (success) {
            logStep(@"SUCCESS", @"appinst completed successfully");
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *result = [InstallationResult successResult:@"تم التثبيت عبر appinst"];
                result.detailedOutput = log;
                completion(result);
            });
        } else {
            NSString *errMsg = [NSString stringWithFormat:@"appinst exited with code %d", WEXITSTATUS(waitStatus)];
            logStep(@"ERROR", errMsg);
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *result = [InstallationResult failureResult:errMsg error:nil];
                result.detailedOutput = log;
                completion(result);
            });
        }
    });
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    if (completion) completion(NO, @"appinst لا يدعم إلغاء التثبيت");
}

@end
