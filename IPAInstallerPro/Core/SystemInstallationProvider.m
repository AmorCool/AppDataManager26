//
//  SystemInstallationProvider.m
//  IPAInstallerPro
//

#import "SystemInstallationProvider.h"
#import "Logger.h"
#import "JailbreakEnvironment.h"
#import "OperationLog.h"
#import <objc/runtime.h>
#include <spawn.h>

@interface SystemInstallationProvider ()
@property (nonatomic, strong) id lsApplicationWorkspace;
@property (nonatomic, strong) NSString *appsPath;
@end

@implementation SystemInstallationProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        JailbreakEnvironment *env = [JailbreakEnvironment sharedEnvironment];
        self.lsApplicationWorkspace = env.lsApplicationWorkspace;
        self.appsPath = env.applicationsPath;
    }
    return self;
}

- (NSString *)providerName { return @"System"; }
- (NSString *)providerDescription { return @"تثبيت عبر النظام (LSApplicationWorkspace)"; }
- (NSInteger)priority { return 10; }

- (BOOL)isAvailable {
    return self.lsApplicationWorkspace != nil;
}

- (void)installIPA:(NSString *)ipaPath operationLog:(OperationLog *)opLog completion:(void (^)(InstallationResult *))completion {
    if (!completion) return;

    NSString *txnID = [opLog beginTransactionForIPA:ipaPath];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        if (!self.lsApplicationWorkspace) {
            NSString *rec = [opLog beginPhase:OperationPhaseStart operation:@"LSApplicationWorkspace check" target:@"" input:@"" transactionID:txnID];
            [opLog endPhase:rec exitCode:1 rawOutput:@"" rawError:@"LSApplicationWorkspace not available"
                verification:@"LSApplicationWorkspace is nil" verified:NO duration:0];
            [opLog endTransaction:txnID finalResult:OperationResultFailed];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([InstallationResult failureResult:@"LSApplicationWorkspace غير متاح" provider:[self providerName] transaction:txnID error:nil evidence:nil]);
            });
            return;
        }

        NSURL *ipaURL = [NSURL fileURLWithPath:ipaPath];
        NSString *bundleID = nil;

        // Extract bundle ID
        NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *unzipPath = @"/usr/bin/unzip";
        if (![fm fileExistsAtPath:unzipPath]) unzipPath = @"/var/jb/usr/bin/unzip";

        pid_t pid;
        char *argv[] = {(char *)[unzipPath UTF8String], (char *)"-q", (char *)"-o", (char *)[ipaPath UTF8String], (char *)"-d", (char *)[tempDir UTF8String], NULL};
        extern char **environ;
        int status = posix_spawn(&pid, [unzipPath UTF8String], NULL, NULL, argv, environ);
        if (status == 0) {
            int waitStatus;
            waitpid(pid, &waitStatus, 0);
        }

        NSString *payloadPath = [tempDir stringByAppendingPathComponent:@"Payload"];
        NSArray *items = [fm contentsOfDirectoryAtPath:payloadPath error:nil];
        for (NSString *item in items) {
            if ([item hasSuffix:@".app"]) {
                NSString *infoPath = [payloadPath stringByAppendingPathComponent:[item stringByAppendingPathComponent:@"Info.plist"]];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
                bundleID = info[@"CFBundleIdentifier"];
                break;
            }
        }
        [fm removeItemAtPath:tempDir error:nil];

        NSMutableDictionary *options = [NSMutableDictionary dictionary];
        options[@"PackageType"] = @"Developer";
        if (bundleID) options[@"CFBundleIdentifier"] = bundleID;

        NSError *installError = nil;
        SEL installSel = NSSelectorFromString(@"installApplication:withOptions:error:");
        typedef BOOL (*InstallMethod)(id, SEL, NSURL *, NSDictionary *, NSError **);
        InstallMethod method = (InstallMethod)objc_msgSend;
        BOOL installed = method(self.lsApplicationWorkspace, installSel, ipaURL, options, &installError);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (installed && !installError) {
                NSString *rec = [opLog beginPhase:OperationPhaseComplete operation:@"LSApplicationWorkspace install" target:ipaPath input:@"" transactionID:txnID];
                [opLog endPhase:rec exitCode:0 rawOutput:@"" rawError:@""
                    verification:[NSString stringWithFormat:@"bundleID=%@", bundleID ?: @"N/A"] verified:YES duration:0];
                [opLog endTransaction:txnID finalResult:OperationResultSuccess];
                InstallationResult *result = [InstallationResult successResult:@"تم التثبيت عبر النظام" provider:[self providerName] transaction:txnID evidence:nil];
                result.bundleID = bundleID;
                completion(result);
            } else {
                NSString *rec = [opLog beginPhase:OperationPhaseComplete operation:@"LSApplicationWorkspace install" target:ipaPath input:@"" transactionID:txnID];
                [opLog endPhase:rec exitCode:1 rawOutput:@"" rawError:installError ? installError.localizedDescription : @"Unknown error"
                    verification:@"Installation failed" verified:NO duration:0];
                [opLog endTransaction:txnID finalResult:OperationResultFailed];
                completion([InstallationResult failureResult:@"فشل التثبيت عبر النظام" provider:[self providerName] transaction:txnID error:installError evidence:nil]);
            }
        });
    });
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    if (!self.lsApplicationWorkspace) {
        if (completion) completion(NO, @"LSApplicationWorkspace غير متاح");
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SEL uninstallSel = NSSelectorFromString(@"uninstallApplication:withOptions:");

        if ([self.lsApplicationWorkspace respondsToSelector:uninstallSel]) {
            typedef void (*UninstallMethod)(id, SEL, NSString *, NSDictionary *);
            UninstallMethod method = (UninstallMethod)objc_msgSend;
            method(self.lsApplicationWorkspace, uninstallSel, bundleID, @{});
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(YES, nil);
            });
            return;
        }

        SEL uninstallBlockSel = NSSelectorFromString(@"uninstallApplication:withOptions:usingBlock:");
        if ([self.lsApplicationWorkspace respondsToSelector:uninstallBlockSel]) {
            typedef void (*UninstallBlockMethod)(id, SEL, NSString *, NSDictionary *, id);
            UninstallBlockMethod method = (UninstallBlockMethod)objc_msgSend;
            method(self.lsApplicationWorkspace, uninstallBlockSel, bundleID, @{}, nil);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(YES, nil);
            });
            return;
        }

        // Filesystem fallback
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *apps = [fm contentsOfDirectoryAtPath:self.appsPath error:nil];
        for (NSString *app in apps) {
            if (![app hasSuffix:@".app"]) continue;
            NSString *appPath = [self.appsPath stringByAppendingPathComponent:app];
            NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
            if ([info[@"CFBundleIdentifier"] isEqualToString:bundleID]) {
                NSString *rmPath = @"/bin/rm";
                if (![fm fileExistsAtPath:rmPath]) rmPath = @"/var/jb/bin/rm";

                pid_t pid;
                char *argv[] = {(char *)[rmPath UTF8String], (char *)"-rf", (char *)[appPath UTF8String], NULL};
                extern char **environ;
                posix_spawn(&pid, [rmPath UTF8String], NULL, NULL, argv, environ);
                int waitStatus;
                waitpid(pid, &waitStatus, 0);

                NSString *uicachePath = @"/usr/bin/uicache";
                if (![fm fileExistsAtPath:uicachePath]) uicachePath = @"/var/jb/usr/bin/uicache";
                char *uiargv[] = {(char *)[uicachePath UTF8String], (char *)"-p", (char *)[[@"/Applications" stringByAppendingPathComponent:app] UTF8String], NULL};
                posix_spawn(&pid, [uicachePath UTF8String], NULL, NULL, uiargv, environ);
                waitpid(pid, &waitStatus, 0);

                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(YES, nil);
                });
                return;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO, @"التطبيق غير موجود");
        });
    });
}

@end
