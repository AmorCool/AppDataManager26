//
//  InstallationEngine.m
//  IPAInstallerPro
//

#import "InstallationEngine.h"
#import "IPAValidator.h"
#import "DirectInstallationProvider.h"
#import "SystemInstallationProvider.h"
#import "AppInstInstallationProvider.h"
#import "CapabilityManager.h"
#import <Foundation/Foundation.h>

@interface InstallationEngine ()
@property (nonatomic, strong) NSMutableArray *providers;
@property (nonatomic, strong) id<InstallationProvider> lastUsedProvider;
@end

@implementation InstallationEngine

+ (instancetype)sharedEngine {
    static InstallationEngine *s = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.providers = [NSMutableArray array];
        [self registerDefaultProviders];
    }
    return self;
}

- (void)registerDefaultProviders {
    [self registerProvider:[[DirectInstallationProvider alloc] init]];
    [self registerProvider:[[AppInstInstallationProvider alloc] init]];
    [self registerProvider:[[SystemInstallationProvider alloc] init]];
}

- (void)registerProvider:(id<InstallationProvider>)provider {
    if (provider && ![self.providers containsObject:provider]) [self.providers addObject:provider];
}

- (NSArray<id<InstallationProvider>> *)availableProviders {
    NSMutableArray *a = [NSMutableArray array];
    for (id<InstallationProvider> p in self.providers) if ([p isAvailable]) [a addObject:p];
    return a;
}

- (id<InstallationProvider>)bestProvider {
    NSArray *a = [self availableProviders];
    if (a.count == 0) return nil;
    NSArray *s = [a sortedArrayUsingComparator:^NSComparisonResult(id<InstallationProvider> x, id<InstallationProvider> y) {
        return [@([y priority]) compare:@([x priority])];
    }];
    for (id<InstallationProvider> p in s) if ([[p providerName] isEqualToString:@"Direct Install"]) return p;
    return s.firstObject;
}

- (NSString *)currentProviderName {
    id<InstallationProvider> p = [self bestProvider];
    return p ? [p providerName] : @"No provider available";
}

- (NSString *)stageDescription:(InstallationStage)stage {
    switch (stage) {
        case InstallationStageIdle: return @"Idle";
        case InstallationStagePreparing: return @"Preparing";
        case InstallationStageValidating: return @"Validating";
        case InstallationStageInstalling: return @"Installing";
        case InstallationStageRegistering: return @"Registering";
        case InstallationStageCompleted: return @"Completed";
        case InstallationStageFailed: return @"Failed";
        default: return @"Unknown";
    }
}

- (void)installIPA:(NSString *)ipaPath progressBlock:(void (^)(InstallationStage, NSString *, float))progressBlock completion:(void (^)(InstallationResult *))completion {
    if (progressBlock) progressBlock(InstallationStageValidating, @"Validating IPA...", 0.05f);

    IPAValidator *v = [IPAValidator sharedValidator];
    IPAValidationResult *vr = [v validateIPAAtPath:ipaPath];

    if (vr.status != IPAValidationStatusValid) {
        NSString *msg = [NSString stringWithFormat:@"Validation failed: %@", [vr.issues componentsJoinedByString:@", "]];
        if (completion) completion([InstallationResult failureResult:msg error:nil]);
        return;
    }

    for (NSString *w in vr.issues) NSLog(@"[IPAInstallerPro] Warning: %@", w);

    NSArray *providers = [self availableProviders];
    if (providers.count == 0) {
        if (completion) completion([InstallationResult failureResult:@"No installation provider available" error:nil]);
        return;
    }

    [self tryProviders:providers forIPA:ipaPath attempt:0 progressBlock:progressBlock completion:completion];
}

- (void)tryProviders:(NSArray *)providers forIPA:(NSString *)ipaPath attempt:(NSInteger)attempt progressBlock:(void (^)(InstallationStage, NSString *, float))progressBlock completion:(void (^)(InstallationResult *))completion {
    if (attempt >= providers.count) {
        if (completion) completion([InstallationResult failureResult:@"All providers failed" error:nil]);
        return;
    }
    id<InstallationProvider> p = providers[attempt];
    self.lastUsedProvider = p;
    if (progressBlock) progressBlock(InstallationStageInstalling, [NSString stringWithFormat:@"Installing via %@...", [p providerName]], 0.1f + (attempt * 0.1f));

    [p installIPA:ipaPath completion:^(InstallationResult *result) {
        if (result.success) {
            if (progressBlock) progressBlock(InstallationStageCompleted, @"Installation complete!", 1.0f);
            if (completion) completion(result);
        } else {
            NSLog(@"[IPAInstallerPro] %@ failed: %@", [p providerName], result.message);
            if (progressBlock) progressBlock(InstallationStageInstalling, [NSString stringWithFormat:@"%@ failed, trying next...", [p providerName]], 0.1f + (attempt * 0.1f));
            [self tryProviders:providers forIPA:ipaPath attempt:attempt + 1 progressBlock:progressBlock completion:completion];
        }
    }];
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    id<InstallationProvider> p = [self bestProvider];
    if (!p) { if (completion) completion(NO, @"No provider available"); return; }
    [p uninstallAppWithBundleID:bundleID completion:completion];
}

@end
