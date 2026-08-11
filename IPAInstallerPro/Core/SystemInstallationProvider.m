#import "SystemInstallationProvider.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import "Logger.h"
#import "RootlessManager.h"

@interface SystemInstallationProvider ()
@property (nonatomic, strong) id lsApplicationWorkspace;
@end

@implementation SystemInstallationProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        Class lsClass = objc_getClass("LSApplicationWorkspace");
        if (lsClass) {
            SEL sharedSel = NSSelectorFromString(@"defaultWorkspace");
            if ([lsClass respondsToSelector:sharedSel]) {
                self.lsApplicationWorkspace = ((id (*)(Class, SEL))objc_msgSend)(lsClass, sharedSel);
            }
        }
    }
    return self;
}

- (NSString *)providerName { return @"System"; }
- (NSString *)providerDescription { return @"تثبيت عبر نظام iOS"; }
- (NSInteger)priority { return 50; }

- (BOOL)isAvailable {
    return (self.lsApplicationWorkspace != nil);
}

- (void)installIPA:(NSString *)ipaPath completion:(void (^)(InstallationResult *))completion {
    if (!completion) return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableString *log = [NSMutableString string];
        void (^logStep)(NSString *, NSString *) = ^(NSString *step, NSString *detail) {
            NSString *entry = [NSString stringWithFormat:@"[System] %@: %@", step, detail];
            [[Logger sharedLogger] info:entry];
            [log appendFormat:@"%@\n", entry];
        };

        logStep(@"START", [NSString stringWithFormat:@"Installing %@", [ipaPath lastPathComponent]]);

        // Extract bundle ID from IPA first
        NSString *bundleID = [self extractBundleIDFromIPA:ipaPath];
        if (!bundleID || bundleID.length == 0) {
            logStep(@"ERROR", @"Could not extract Bundle ID from IPA");
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *result = [InstallationResult failureResult:@"تعذر استخراج Bundle ID من IPA" error:nil];
                result.detailedOutput = log;
                completion(result);
            });
            return;
        }
        logStep(@"BUNDLE_ID", bundleID);

        NSURL *ipaURL = [NSURL fileURLWithPath:ipaPath];

        // Build options with Bundle ID (REQUIRED for iOS 15+)
        NSMutableDictionary *options = [NSMutableDictionary dictionary];
        options[@"ApplicationBundleIdentifier"] = bundleID;
        options[@"AllowInstallLocalProvisioned"] = @YES;
        options[@"IsUserInitiated"] = @YES;
        options[@"SkipUninstall"] = @YES;
        logStep(@"OPTIONS", [NSString stringWithFormat:@"BundleID=%@, SkipUninstall=YES", bundleID]);

        SEL installSel = NSSelectorFromString(@"installApplication:withOptions:error:");
        if (![self.lsApplicationWorkspace respondsToSelector:installSel]) {
            logStep(@"ERROR", @"LSApplicationWorkspace does not respond to installApplication:withOptions:error:");
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *result = [InstallationResult failureResult:@"محرك النظام غير متوفر" error:nil];
                result.detailedOutput = log;
                completion(result);
            });
            return;
        }

        logStep(@"INSTALL", @"Calling LSApplicationWorkspace...");
        NSError *error = nil;
        typedef BOOL (*InstallMethod)(id, SEL, NSURL *, NSDictionary *, NSError **);
        InstallMethod method = (InstallMethod)objc_msgSend;
        BOOL success = method(self.lsApplicationWorkspace, installSel, ipaURL, options, &error);

        if (success) {
            logStep(@"SUCCESS", @"System installation completed");
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *result = [InstallationResult successResult:@"تم التثبيت عبر النظام"];
                result.bundleID = bundleID;
                result.detailedOutput = log;
                completion(result);
            });
        } else {
            NSString *errMsg = error ? error.localizedDescription : @"فشل تثبيت عبر النظام";
            logStep(@"ERROR", errMsg);
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *result = [InstallationResult failureResult:errMsg error:error];
                result.detailedOutput = log;
                completion(result);
            });
        }
    });
}

- (NSString *)extractBundleIDFromIPA:(NSString *)ipaPath {
    // Quick extraction: unzip Info.plist and read Bundle ID
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *unzipPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/unzip"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:unzipPath]) unzipPath = @"/usr/bin/unzip";

    // Extract just Info.plist
    const char *cmd = [unzipPath UTF8String];
    const char *args[] = { cmd, "-q", "-o", [ipaPath UTF8String], @"Payload/*/Info.plist", @"-d", [tempDir UTF8String], NULL };
    pid_t pid; int status;
    posix_spawn(&pid, cmd, NULL, NULL, (char **)args, NULL);
    waitpid(pid, &status, 0);

    // Find Info.plist
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

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    if (!completion) return;

    SEL uninstallSel = NSSelectorFromString(@"uninstallApplication:withOptions:");
    if (![self.lsApplicationWorkspace respondsToSelector:uninstallSel]) {
        completion(NO, @"النظام لا يدعم إلغاء التثبيت");
        return;
    }

    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    options[@"ApplicationBundleIdentifier"] = bundleID;

    typedef void (*UninstallMethod)(id, SEL, NSString *, NSDictionary *);
    UninstallMethod method = (UninstallMethod)objc_msgSend;
    method(self.lsApplicationWorkspace, uninstallSel, bundleID, options);
    completion(YES, nil);
}

@end
