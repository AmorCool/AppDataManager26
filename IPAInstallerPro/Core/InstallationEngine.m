//
// InstallationEngine.m
// IPA Installer Pro
//
// v2.2 — STANDALONE with concurrent install protection and NSLock
//

#import "InstallationEngine.h"
#import "DirectInstallationProvider.h"
#import "OperationLog.h"
#import "Logger.h"
#import <Foundation/Foundation.h>

@interface InstallationEngine ()
@property (nonatomic, strong) NSMutableArray<id<InstallationProvider>> *providers;
@property (nonatomic, strong) OperationLog *operationLog;
@property (nonatomic, strong) NSString *activeTxnID;
@property (nonatomic, assign) InstallationStage currentStage;
@property (nonatomic, strong) NSLock *installLock;
@property (nonatomic, assign) BOOL isInstalling;
@end

@implementation InstallationEngine

+ (instancetype)sharedEngine {
    static InstallationEngine *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _operationLog = [[OperationLog alloc] init];
        _providers = [NSMutableArray array];
        _currentStage = InstallationStageIdle;
        _installLock = [[NSLock alloc] init];
        _isInstalling = NO;
        // Only Direct Install — our standalone signature
        [self registerProvider:[[DirectInstallationProvider alloc] init]];
    }
    return self;
}

- (void)registerProvider:(id<InstallationProvider>)provider {
    if (!provider) return;
    [_providers addObject:provider];
    [_providers sortUsingComparator:^NSComparisonResult(id<InstallationProvider> a, id<InstallationProvider> b) {
        return [@(b.priority) compare:@(a.priority)];
    }];
    NSLog(@"[IPAInstallerPro] Registered provider: %@ (priority=%ld)", [provider providerName], (long)provider.priority);
}

- (NSArray<id<InstallationProvider>> *)availableProviders {
    NSMutableArray *available = [NSMutableArray array];
    for (id<InstallationProvider> p in self.providers) {
        if ([p isAvailable]) [available addObject:p];
    }
    return available;
}

- (id<InstallationProvider>)bestProvider {
    NSArray *available = [self availableProviders];
    return available.firstObject;
}

- (NSString *)currentProviderName {
    id<InstallationProvider> p = [self bestProvider];
    return p ? [p providerName] : @"None";
}

- (NSString *)stageDescription:(InstallationStage)stage {
    switch (stage) {
        case InstallationStageIdle: return @"Idle";
        case InstallationStagePreparing: return @"Preparing";
        case InstallationStageValidating: return @"Validating IPA";
        case InstallationStageInstalling: return @"Installing files";
        case InstallationStageRegistering: return @"Registering with system";
        case InstallationStageCompleted: return @"Completed";
        case InstallationStageFailed: return @"Failed";
        default: return @"Unknown";
    }
}

- (NSString *)activeTransactionID {
    return self.activeTxnID;
}

- (NSString *)transactionReport:(NSString *)txnID {
    if (!txnID) return @"";
    NSArray *records = [self.operationLog recordsForTransaction:txnID];
    NSMutableString *report = [NSMutableString string];
    [report appendFormat:@"Transaction Report: %@\n", txnID];
    [report appendFormat:@"Total records: %lu\n\n", (unsigned long)records.count];
    for (NSDictionary *rec in records) {
        NSString *phase = rec[@"phase"] ?: @"???";
        NSString *op = rec[@"operation"] ?: @"???";
        NSString *target = rec[@"target"] ?: @"???";
        NSNumber *exitCode = rec[@"exitCode"] ?: @(-1);
        NSNumber *verified = rec[@"verified"] ?: @NO;
        NSString *status = [verified boolValue] ? @"✅" : @"❌";
        [report appendFormat:@"%@ [%@] %@ — %@ (exit=%@)\n", status, phase, op, target, exitCode];
        NSString *err = rec[@"rawError"];
        if (err && err.length > 0) [report appendFormat:@"   ⚠️ %@\n", err];
    }
    return report;
}

- (OperationLog *)operationLog {
    return _operationLog;
}

- (void)installIPA:(NSString *)ipaPath
     progressBlock:(void (^)(InstallationStage stage, NSString *statusMessage, float progress))progressBlock
        completion:(void (^)(InstallationResult *result))completion {

    // Concurrent install protection
    [self.installLock lock];
    if (self.isInstalling) {
        [self.installLock unlock];
        NSString *err = @"Another installation is already in progress. Please wait.";
        if (progressBlock) progressBlock(InstallationStageFailed, err, 1.0);
        if (completion) completion([InstallationResult failureResult:err provider:@"Engine" transaction:@"" error:nil evidence:nil]);
        return;
    }
    self.isInstalling = YES;
    [self.installLock unlock];

    self.currentStage = InstallationStagePreparing;
    if (progressBlock) progressBlock(self.currentStage, @"Preparing installation...", 0.05);

    if (!ipaPath || ipaPath.length == 0) {
        [self finishInstallation];
        self.currentStage = InstallationStageFailed;
        if (progressBlock) progressBlock(self.currentStage, @"IPA path is empty", 1.0);
        if (completion) completion([InstallationResult failureResult:@"IPA path is empty" provider:@"Engine" transaction:@"" error:nil evidence:nil]);
        return;
    }

    NSLog(@"[IPAInstallerPro] Starting installation for %@", [ipaPath lastPathComponent]);

    NSArray *available = [self availableProviders];
    if (available.count == 0) {
        [self finishInstallation];
        self.currentStage = InstallationStageFailed;
        NSString *err = @"No installation provider available. Ensure ldid, uicache, and unzip are installed.";
        if (progressBlock) progressBlock(self.currentStage, err, 1.0);
        if (completion) completion([InstallationResult failureResult:err provider:@"Engine" transaction:@"" error:nil evidence:nil]);
        return;
    }

    self.currentStage = InstallationStageValidating;
    if (progressBlock) progressBlock(self.currentStage, @"Validating IPA...", 0.15);

    // Always use DirectInstallationProvider (the only one)
    id<InstallationProvider> provider = available.firstObject;
    NSLog(@"[IPAInstallerPro] Using provider: %@", [provider providerName]);

    self.activeTxnID = [[NSUUID UUID] UUIDString];

    self.currentStage = InstallationStageInstalling;
    if (progressBlock) progressBlock(self.currentStage, @"Installing files...", 0.3);

    __weak typeof(self) weakSelf = self;
    [provider installIPA:ipaPath transactionID:self.activeTxnID operationLog:self.operationLog completion:^(InstallationResult *result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (result && result.success) {
            strongSelf.currentStage = InstallationStageRegistering;
            if (progressBlock) progressBlock(strongSelf.currentStage, @"Registering app...", 0.8);

            strongSelf.currentStage = InstallationStageCompleted;
            if (progressBlock) progressBlock(strongSelf.currentStage, @"Installation complete!", 1.0);
            NSLog(@"[IPAInstallerPro] Installation succeeded via %@", [provider providerName]);
        } else {
            strongSelf.currentStage = InstallationStageFailed;
            if (progressBlock) progressBlock(strongSelf.currentStage, result ? result.message : @"Unknown error", 1.0);
            NSLog(@"[IPAInstallerPro] Installation failed via %@: %@", [provider providerName], result ? result.message : @"Unknown error");
        }
        [strongSelf finishInstallation];
        if (completion) completion(result);
    }];
}

- (void)finishInstallation {
    [self.installLock lock];
    self.isInstalling = NO;
    [self.installLock unlock];
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    if (!bundleID || bundleID.length == 0) {
        if (completion) completion(NO, @"Bundle ID is empty");
        return;
    }
    for (id<InstallationProvider> p in self.providers) {
        if ([p isAvailable] && [p respondsToSelector:@selector(uninstallAppWithBundleID:completion:)]) {
            [p uninstallAppWithBundleID:bundleID completion:completion];
            return;
        }
    }
    if (completion) completion(NO, @"No provider available for uninstall");
}

@end
