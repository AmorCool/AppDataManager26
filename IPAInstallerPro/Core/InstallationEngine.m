#import "InstallationEngine.h"
#include <spawn.h>
#include <sys/wait.h>
#import "Logger.h"
#import "IPAValidator.h"
#import "AppInstInstallationProvider.h"
#import "SystemInstallationProvider.h"

@interface InstallationEngine ()
@property (nonatomic, strong) NSMutableArray<id<InstallationProvider>> *providers;
@property (nonatomic, strong) id<InstallationProvider> currentProvider;
@end

@implementation InstallationEngine

+ (instancetype)sharedEngine {
    static InstallationEngine *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _providers = [NSMutableArray array];
        [_providers addObject:[[AppInstInstallationProvider alloc] init]];
        [_providers addObject:[[SystemInstallationProvider alloc] init]];

        // Sort by priority (highest first)
        [_providers sortUsingComparator:^NSComparisonResult(id<InstallationProvider> a, id<InstallationProvider> b) {
            return [@(b.priority) compare:@(a.priority)];
        }];
    }
    return self;
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
    for (id<InstallationProvider> provider in self.providers) {
        if ([provider isAvailable]) {
            [[Logger sharedLogger] info:[NSString stringWithFormat:@"Selected provider: %@", provider.providerName]];
            return provider;
        }
    }
    return nil;
}

- (void)installIPA:(NSString *)ipaPath
     progressBlock:(void (^)(InstallationStage, NSString *, float))progressBlock
        completion:(void (^)(InstallationResult *))completion {

    if (!completion) return;
    if (!ipaPath || ipaPath.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion([InstallationResult failureResult:@"مسار IPA غير صالح" error:nil]);
        });
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Stage 1: Preparing
        [self reportProgress:InstallationStagePreparing message:@"جاري تجهيز التطبيق..." progress:0.1 block:progressBlock];
        [NSThread sleepForTimeInterval:0.3];

        // Stage 2: Validating
        [self reportProgress:InstallationStageValidating message:@"جاري التحقق من الملف..." progress:0.2 block:progressBlock];

        IPAValidationResult *validation = [[IPAValidator sharedValidator] validateIPAAtPath:ipaPath];
        if (!validation.isReadyForInstall) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *msg = validation.issues.count > 0 ? validation.issues[0] : validation.statusMessage;
                completion([InstallationResult failureResult:msg error:nil]);
            });
            return;
        }

        // Stage 3: Installing
        [self reportProgress:InstallationStageInstalling message:@"جاري التثبيت..." progress:0.4 block:progressBlock];

        id<InstallationProvider> provider = [self bestProvider];
        if (!provider) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([InstallationResult failureResult:@"لا يوجد محرك تثبيت متاح. يرجى تثبيت appinst." error:nil]);
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self reportProgress:InstallationStageInstalling message:[NSString stringWithFormat:@"جاري التثبيت عبر %@...", provider.providerName] progress:0.5 block:progressBlock];
        });

        [provider installIPA:ipaPath completion:^(InstallationResult *result) {
            if (result.success) {
                // Stage 4: Registering
                [self reportProgress:InstallationStageRegistering message:@"جاري تسجيل التطبيق..." progress:0.8 block:progressBlock];

                // Run uicache
                [self runUICache];

                [NSThread sleepForTimeInterval:0.5];

                [self reportProgress:InstallationStageCompleted message:@"تم التثبيت بنجاح ✓" progress:1.0 block:progressBlock];
            } else {
                [self reportProgress:InstallationStageFailed message:result.message progress:1.0 block:progressBlock];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                completion(result);
            });
        }];
    });
}

- (void)reportProgress:(InstallationStage)stage message:(NSString *)message progress:(float)progress block:(void (^)(InstallationStage, NSString *, float))block {
    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(stage, message, progress);
        });
    }
    [[Logger sharedLogger] info:[NSString stringWithFormat:@"Install stage %ld: %@", (long)stage, message]];
}

- (void)runUICache {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        const char *path = "/usr/bin/uicache";
        const char *args[] = { path, "-a", NULL };
        pid_t pid;
        int status;
        posix_spawn(&pid, path, NULL, NULL, (char **)args, NULL);
        waitpid(pid, &status, 0);
        [[Logger sharedLogger] info:@"uicache executed"];
    });
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    if (!completion) return;

    // Try system provider first for uninstall
    SystemInstallationProvider *sysProvider = [[SystemInstallationProvider alloc] init];
    if ([sysProvider isAvailable]) {
        [sysProvider uninstallAppWithBundleID:bundleID completion:completion];
        return;
    }

    completion(NO, @"لا توجد طريقة متاحة لحذف التطبيق");
}

- (NSString *)stageDescription:(InstallationStage)stage {
    switch (stage) {
        case InstallationStageIdle: return @"في الانتظار";
        case InstallationStagePreparing: return @"تجهيز";
        case InstallationStageValidating: return @"تحقق";
        case InstallationStageInstalling: return @"تثبيت";
        case InstallationStageRegistering: return @"تسجيل";
        case InstallationStageCompleted: return @"تم";
        case InstallationStageFailed: return @"فشل";
        default: return @"غير معروف";
    }
}

@end
