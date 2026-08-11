#import "InstallationEngine.h"
#import "Logger.h"
#import "JailbreakEnvironment.h"
#import "RootlessManager.h"
#import "CapabilityManager.h"
#import "DirectInstallationProvider.h"
#import "SystemInstallationProvider.h"
#import "AppInstInstallationProvider.h"

@interface InstallationEngine ()
@property (nonatomic, strong) NSArray<id<InstallationProvider>> *providers;
@property (nonatomic, strong) id<InstallationProvider> currentProvider;
@property (nonatomic, strong) InstallationResult *lastResult;
@property (nonatomic, strong) NSString *lastLog;
@end

@implementation InstallationEngine

+ (instancetype)sharedEngine {
    static InstallationEngine *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self scanProviders];
    }
    return self;
}

- (void)scanProviders {
    NSMutableArray *available = [NSMutableArray array];

    DirectInstallationProvider *direct = [[DirectInstallationProvider alloc] init];
    if ([direct isAvailable]) [available addObject:direct];

    AppInstInstallationProvider *appinst = [[AppInstInstallationProvider alloc] init];
    if ([appinst isAvailable]) [available addObject:appinst];

    SystemInstallationProvider *system = [[SystemInstallationProvider alloc] init];
    if ([system isAvailable]) [available addObject:system];

    self.providers = available;
    [[Logger sharedLogger] info:[NSString stringWithFormat:@"InstallationEngine: %lu providers available", (unsigned long)available.count]];
}

- (NSArray<id<InstallationProvider>> *)availableProviders {
    return self.providers;
}

- (id<InstallationProvider>)bestProvider {
    NSArray *available = [self availableProviders];
    if (available.count == 0) return nil;

    // Direct Install is preferred: it extracts, signs with entitlements, copies to /Applications
    for (id<InstallationProvider> provider in available) {
        if ([provider.providerName isEqualToString:@"Direct Install"]) return provider;
    }
    for (id<InstallationProvider> provider in available) {
        if ([provider.providerName isEqualToString:@"appinst"]) return provider;
    }
    for (id<InstallationProvider> provider in available) {
        if ([provider.providerName isEqualToString:@"System"]) return provider;
    }
    for (id<InstallationProvider> provider in available) {
        if ([provider.providerName isEqualToString:@"appinst"]) return provider;
    }
    return available.firstObject;
}

- (void)installIPA:(NSString *)ipaPath
     progressBlock:(void (^)(InstallationStage stage, NSString *statusMessage, float progress))progressBlock
        completion:(void (^)(InstallationResult *result))completion {

    // FIX: Check AppSync before installation (warn if missing)
    CapabilityManager *capMgr = [CapabilityManager sharedManager];
    [capMgr scanCapabilities];
    if (!capMgr.canInstallIPA) {
        [[Logger sharedLogger] warning:@"AppSync not detected — installed apps may crash on iOS 15+"];
    }

    id<InstallationProvider> provider = [self bestProvider];
    if (!provider) {
        InstallationResult *result = [InstallationResult failureResult:@"لا يوجد محرك تثبيت متاح" error:nil];
        if (completion) completion(result);
        return;
    }

    self.currentProvider = provider;
    [[Logger sharedLogger] info:[NSString stringWithFormat:@"Using provider: %@", [provider providerName]]];

    if (progressBlock) progressBlock(InstallationStagePreparing, @"جاري التجهيز...", 0.1);
    if (progressBlock) progressBlock(InstallationStageValidating, @"جاري التحقق...", 0.2);
    if (progressBlock) progressBlock(InstallationStageInstalling, [NSString stringWithFormat:@"جاري التثبيت عبر %@...", [provider providerName]], 0.5);

    [provider installIPA:ipaPath completion:^(InstallationResult *result) {
        self.lastResult = result;
        self.lastLog = result.detailedOutput;
        if (result.success) {
            if (progressBlock) progressBlock(InstallationStageRegistering, @"جاري تسجيل التطبيق...", 0.8);
            if (progressBlock) progressBlock(InstallationStageCompleted, @"تم التثبيت بنجاح", 1.0);
        } else {
            if (progressBlock) progressBlock(InstallationStageFailed, result.message, 1.0);
        }
        if (completion) completion(result);
    }];
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    id<InstallationProvider> provider = [self bestProvider];
    if (!provider) {
        if (completion) completion(NO, @"لا يوجد محرك إلغاء تثبيت متاح");
        return;
    }
    [provider uninstallAppWithBundleID:bundleID completion:completion];
}

- (NSString *)currentProviderName {
    return [self.currentProvider providerName];
}

- (NSString *)lastInstallationLog {
    return self.lastLog;
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

@end
