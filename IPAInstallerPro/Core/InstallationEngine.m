//
// InstallationEngine.m
// IPA Installer Pro
//
// v2.1 — STANDALONE: Only DirectInstallationProvider
//

#import "InstallationEngine.h"
#import "DirectInstallationProvider.h"
#import "OperationLog.h"
#import "Logger.h"
#import <Foundation/Foundation.h>

@interface InstallationEngine ()
@property (nonatomic, strong) NSMutableArray<id<InstallationProvider>> *providers;
@property (nonatomic, strong) OperationLog *operationLog;
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

- (void)installIPA:(NSString *)ipaPath completion:(void (^)(InstallationResult *))completion {
    if (!ipaPath || ipaPath.length == 0) {
        if (completion) completion([InstallationResult failureResult:@"IPA path is empty" provider:@"Engine" transaction:@"" error:nil evidence:nil]);
        return;
    }

    NSLog(@"[IPAInstallerPro] Starting installation for %@", [ipaPath lastPathComponent]);

    NSArray *available = [self availableProviders];
    if (available.count == 0) {
        NSString *err = @"No installation provider available. Ensure ldid, uicache, and unzip are installed.";
        if (completion) completion([InstallationResult failureResult:err provider:@"Engine" transaction:@"" error:nil evidence:nil]);
        return;
    }

    // Always use DirectInstallationProvider (the only one)
    id<InstallationProvider> provider = available.firstObject;
    NSLog(@"[IPAInstallerPro] Using provider: %@", [provider providerName]);

    [provider installIPA:ipaPath operationLog:self.operationLog completion:^(InstallationResult *result) {
        if (result && result.success) {
            NSLog(@"[IPAInstallerPro] Installation succeeded via %@", [provider providerName]);
        } else {
            NSLog(@"[IPAInstallerPro] Installation failed via %@: %@", [provider providerName], result ? result.message : @"Unknown error");
        }
        if (completion) completion(result);
    }];
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    if (!bundleID || bundleID.length == 0) {
        if (completion) completion(NO, @"Bundle ID is empty");
        return;
    }
    // Use DirectInstallationProvider for uninstall too
    for (id<InstallationProvider> p in self.providers) {
        if ([p isAvailable] && [p respondsToSelector:@selector(uninstallAppWithBundleID:completion:)]) {
            [p uninstallAppWithBundleID:bundleID completion:completion];
            return;
        }
    }
    if (completion) completion(NO, @"No provider available for uninstall");
}

- (OperationLog *)operationLog { return _operationLog; }

@end
