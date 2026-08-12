//
//  InstallationEngine.m
//  IPAInstallerPro
//
//  Enhanced version - retry logic and better error handling
//

#import "InstallationEngine.h"
#import "DirectInstallationProvider.h"
#import "SystemInstallationProvider.h"
#import "AppInstInstallationProvider.h"
#import "CapabilityManager.h"
#import "InstallationLogger.h"
#import "RootlessManager.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface InstallationEngine ()
@property (nonatomic, strong) NSMutableArray *providers;
@property (nonatomic, strong) CapabilityManager *capabilityManager;
@property (nonatomic, strong) id<InstallationProvider> lastUsedProvider;
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
        self.providers = [NSMutableArray array];
        self.capabilityManager = [CapabilityManager sharedManager];
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
    if (provider && ![self.providers containsObject:provider]) {
        [self.providers addObject:provider];
    }
}

- (NSArray<id<InstallationProvider>> *)availableProviders {
    NSMutableArray *available = [NSMutableArray array];
    for (id<InstallationProvider> provider in self.providers) {
        if ([provider isAvailable]) {
            [available addObject:provider];
        }
    }
    return available;
}

- (id<InstallationProvider>)bestProvider {
    NSArray *available = [self availableProviders];
    if (available.count == 0) return nil;

    // Sort by priority (highest first)
    NSArray *sorted = [available sortedArrayUsingComparator:^NSComparisonResult(id<InstallationProvider> a, id<InstallationProvider> b) {
        return [@([b providerPriority]) compare:@([a providerPriority])];
    }];

    // Prefer Direct Install if available and working
    for (id<InstallationProvider> provider in sorted) {
        if ([[provider providerName] isEqualToString:@"Direct Install"]) {
            return provider;
        }
    }

    return sorted.firstObject;
}

- (void)installIPA:(NSString *)ipaPath
     progressBlock:(void (^)(InstallationStage stage, NSString *statusMessage, float progress))progressBlock
        completion:(void (^)(InstallationResult *result))completion {

    // Validate IPA first
    if (progressBlock) {
        progressBlock(InstallationStageValidating, @"جاري التحقق من صحة IPA...", 0.05f);
    }

    IPAValidator *validator = [[IPAValidator alloc] init];
    ValidationResult *validation = [validator validateIPA:ipaPath];

    if (!validation.isValid) {
        NSString *errorMsg = [NSString stringWithFormat:@"فشل التحقق: %@", [validation.errors componentsJoinedByString:@", "]];
        InstallationResult *result = [InstallationResult failureResult:errorMsg error:nil];
        if (completion) completion(result);
        return;
    }

    // Log warnings
    for (NSString *warning in validation.warnings) {
        NSLog(@"[IPAInstallerPro] Warning: %@", warning);
    }

    // Get available providers
    NSArray *providers = [self availableProviders];
    if (providers.count == 0) {
        InstallationResult *result = [InstallationResult failureResult:@"لا يوجد محرك تثبيت متاح" error:nil];
        if (completion) completion(result);
        return;
    }

    // Try providers in order with retry
    [self tryProviders:providers
               forIPA:ipaPath
              attempt:0
        progressBlock:progressBlock
           completion:completion];
}

- (void)tryProviders:(NSArray *)providers
             forIPA:(NSString *)ipaPath
            attempt:(NSInteger)attempt
      progressBlock:(void (^)(InstallationStage stage, NSString *statusMessage, float progress))progressBlock
         completion:(void (^)(InstallationResult *result))completion {

    if (attempt >= providers.count) {
        // All providers failed
        InstallationResult *result = [InstallationResult failureResult:@"فشل التثبيت بجميع المحركات المتاحة" error:nil];
        if (completion) completion(result);
        return;
    }

    id<InstallationProvider> provider = providers[attempt];
    self.lastUsedProvider = provider;

    if (progressBlock) {
        progressBlock(InstallationStageInstalling, 
                     [NSString stringWithFormat:@"جاري التثبيت عبر %@...", [provider providerName]], 
                     0.1f + (attempt * 0.1f));
    }

    [provider installIPA:ipaPath completion:^(InstallationResult *result) {
        if (result.success) {
            // Success!
            if (progressBlock) {
                progressBlock(InstallationStageCompleted, @"اكتمل التثبيت بنجاح!", 1.0f);
            }
            if (completion) completion(result);
        } else {
            // Log the failure
            NSLog(@"[IPAInstallerPro] Provider %@ failed: %@", [provider providerName], result.errorMessage);

            // Try next provider
            if (progressBlock) {
                progressBlock(InstallationStageInstalling, 
                             [NSString stringWithFormat:@"فشل %@، جرب المحرك التالي...", [provider providerName]], 
                             0.1f + (attempt * 0.1f));
            }

            [self tryProviders:providers
                        forIPA:ipaPath
                       attempt:attempt + 1
                 progressBlock:progressBlock
                    completion:completion];
        }
    }];
}

- (id<InstallationProvider>)lastProvider {
    return self.lastUsedProvider;
}

- (NSString *)installationMethodDescription {
    id<InstallationProvider> provider = [self bestProvider];
    if (provider) {
        return [NSString stringWithFormat:@"%@ - %@", [provider providerName], [provider providerDescription]];
    }
    return @"لا يوجد محرك متاح";
}

- (BOOL)canInstallIPA:(NSString *)ipaPath {
    IPAValidator *validator = [[IPAValidator alloc] init];
    ValidationResult *result = [validator validateIPA:ipaPath];
    return result.isValid;
}

@end
