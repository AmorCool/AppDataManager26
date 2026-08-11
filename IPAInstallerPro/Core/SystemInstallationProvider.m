#import "SystemInstallationProvider.h"
#import "Logger.h"
#import "RootlessManager.h"
#import "CapabilityManager.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface SystemInstallationProvider ()
@property (nonatomic, strong) id lsApplicationWorkspace;
@end

@implementation SystemInstallationProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        Class LSApplicationWorkspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        if (LSApplicationWorkspaceClass) {
            self.lsApplicationWorkspace = [LSApplicationWorkspaceClass performSelector:@selector(defaultWorkspace)];
        }
    }
    return self;
}

- (NSString *)providerName { return @"System"; }
- (NSString *)providerDescription { return @"تثبيت عبر نظام iOS (يتطلب AppSync)"; }
- (NSInteger)priority { return 10; }

- (BOOL)isAvailable {
    // LSApplicationWorkspace installApplication requires AppSync Unified on iOS 15+ Rootless
    // Without AppSync, it will fail with "Operation not permitted" for unsigned IPAs
    if (self.lsApplicationWorkspace == nil) return NO;

    CapabilityManager *capMgr = [CapabilityManager sharedManager];
    if (!capMgr.isAppSyncAvailable) {
        [[Logger sharedLogger] info:@"SystemInstallationProvider: AppSync not available, disabling System provider"];
        return NO;
    }
    return YES;
}

- (void)installIPA:(NSString *)ipaPath completion:(void (^)(InstallationResult *))completion {
    if (!completion) return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableString *log = [NSMutableString string];
        void (^logStep)(NSString *) = ^(NSString *msg) {
            NSString *entry = [NSString stringWithFormat:@"[System] %@", msg];
            [[Logger sharedLogger] info:entry];
            [log appendFormat:@"%@\n", entry];
        };

        logStep([NSString stringWithFormat:@"START: Installing %@", [ipaPath lastPathComponent]]);

        if (!self.lsApplicationWorkspace) {
            logStep(@"ERROR: LSApplicationWorkspace not available");
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *result = [InstallationResult failureResult:@"LSApplicationWorkspace غير متاح" error:nil];
                result.detailedOutput = log;
                completion(result);
            });
            return;
        }

        NSString *bundleID = [self extractBundleIDFromIPA:ipaPath];
        logStep([NSString stringWithFormat:@"BUNDLE_ID: %@", bundleID ?: @"unknown"]);

        NSURL *ipaURL = [NSURL fileURLWithPath:ipaPath];
        NSMutableDictionary *options = [NSMutableDictionary dictionary];
        if (bundleID) options[@"CFBundleIdentifier"] = bundleID;
        options[@"SkipUninstall"] = @YES;
        logStep([NSString stringWithFormat:@"OPTIONS: BundleID=%@, SkipUninstall=YES", bundleID ?: @"nil"]);

        logStep(@"INSTALL: Calling LSApplicationWorkspace...");

        @try {
            SEL installSelector = NSSelectorFromString(@"installApplication:withOptions:error:");
            NSMethodSignature *sig = [self.lsApplicationWorkspace methodSignatureForSelector:installSelector];
            if (!sig) {
                logStep(@"ERROR: installApplication:withOptions:error: not found");
                dispatch_async(dispatch_get_main_queue(), ^{
                    InstallationResult *result = [InstallationResult failureResult:@"LSApplicationWorkspace method not found" error:nil];
                    result.detailedOutput = log;
                    completion(result);
                });
                return;
            }

            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
            [invocation setTarget:self.lsApplicationWorkspace];
            [invocation setSelector:installSelector];
            [invocation setArgument:&ipaURL atIndex:2];
            [invocation setArgument:&options atIndex:3];
            NSError *installError = nil;
            [invocation setArgument:&installError atIndex:4];
            [invocation invoke];

            BOOL success = NO;
            [invocation getReturnValue:&success];

            if (success && !installError) {
                logStep(@"SUCCESS: App installed via System");
                dispatch_async(dispatch_get_main_queue(), ^{
                    InstallationResult *result = [InstallationResult successResult:@"تم التثبيت بنجاح عبر النظام"];
                    result.bundleID = bundleID;
                    result.detailedOutput = log;
                    completion(result);
                });
            } else {
                NSString *errorMsg = installError ? installError.localizedDescription : @"فشل التثبيت عبر النظام";
                logStep([NSString stringWithFormat:@"ERROR: %@", errorMsg]);
                dispatch_async(dispatch_get_main_queue(), ^{
                    InstallationResult *result = [InstallationResult failureResult:errorMsg error:installError];
                    result.detailedOutput = log;
                    completion(result);
                });
            }
        }
        @catch (NSException *exception) {
            NSString *errorMsg = [NSString stringWithFormat:@"Exception: %@", exception.reason];
            logStep([NSString stringWithFormat:@"ERROR: %@", errorMsg]);
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *result = [InstallationResult failureResult:errorMsg error:nil];
                result.detailedOutput = log;
                completion(result);
            });
        }
    });
}

- (NSString *)extractBundleIDFromIPA:(NSString *)ipaPath {
    @try {
        NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

        NSString *unzipPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/unzip"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:unzipPath]) unzipPath = @"/usr/bin/unzip";

        const char *cmd = [unzipPath UTF8String];
        char *args[] = {(char*)cmd, (char*)"-q", (char*)"-o", (char*)[ipaPath UTF8String], (char*)"-d", (char*)[tempDir UTF8String], NULL};
        pid_t pid;
        posix_spawn(&pid, cmd, NULL, NULL, (char **)args, NULL);
        int status;
        waitpid(pid, &status, 0);

        NSString *payloadPath = [tempDir stringByAppendingPathComponent:@"Payload"];
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadPath error:nil];
        NSString *bundleID = nil;
        for (NSString *item in contents) {
            if ([item hasSuffix:@".app"]) {
                NSString *infoPath = [payloadPath stringByAppendingPathComponent:[item stringByAppendingPathComponent:@"Info.plist"]];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
                bundleID = info[@"CFBundleIdentifier"];
                break;
            }
        }
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        return bundleID;
    }
    @catch (NSException *exception) {
        return nil;
    }
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    if (!self.lsApplicationWorkspace) {
        if (completion) completion(NO, @"LSApplicationWorkspace غير متاح");
        return;
    }
    @try {
        SEL uninstallSelector = NSSelectorFromString(@"uninstallApplication:withOptions:");
        if ([self.lsApplicationWorkspace respondsToSelector:uninstallSelector]) {
            NSMethodSignature *sig = [self.lsApplicationWorkspace methodSignatureForSelector:uninstallSelector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
            [invocation setTarget:self.lsApplicationWorkspace];
            [invocation setSelector:uninstallSelector];
            [invocation setArgument:&bundleID atIndex:2];
            NSMutableDictionary *opts = [NSMutableDictionary dictionary];
            [invocation setArgument:&opts atIndex:3];
            [invocation invoke];
            if (completion) completion(YES, nil);
        } else {
            if (completion) completion(NO, @"uninstallApplication not available");
        }
    }
    @catch (NSException *exception) {
        if (completion) completion(NO, exception.reason);
    }
}

@end
