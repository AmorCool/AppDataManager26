#import "InstallationEngine.h"
#include <spawn.h>
#include <sys/wait.h>
#import "Logger.h"
#import "CapabilityManager.h"
#import "VerificationEngine.h"
#import "RootlessManager.h"
#import "IPAValidator.h"
#import "IPAExtractor.h"
#import "AppInstInstallationProvider.h"
#import "SystemInstallationProvider.h"
#import "DirectInstallationProvider.h"

@interface InstallationEngine ()
@property (nonatomic, strong) NSMutableArray<id<InstallationProvider>> *providers;
@property (nonatomic, strong) id<InstallationProvider> currentProvider;
@property (nonatomic, strong) NSMutableString *installLog;
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
        _installLog = [NSMutableString string];
        [_providers addObject:[[AppInstInstallationProvider alloc] init]];
        [_providers addObject:[[SystemInstallationProvider alloc] init]];
        [_providers addObject:[[DirectInstallationProvider alloc] init]];
    }
    return self;
}

- (NSArray<id<InstallationProvider>> *)availableProviders {
    NSMutableArray *available = [NSMutableArray array];
    for (id<InstallationProvider> provider in self.providers) {
        if ([provider isAvailable]) [available addObject:provider];
    }
    return available;
}

- (id<InstallationProvider>)bestProvider {
    NSArray *available = [self availableProviders];
    if (available.count == 0) return nil;
    for (id<InstallationProvider> provider in available) {
        if ([provider.providerName isEqualToString:@"appinst"]) return provider;
    }
    for (id<InstallationProvider> provider in available) {
        if ([provider.providerName isEqualToString:@"System"]) return provider;
    }
    return available.firstObject;
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

    [self.installLog setString:@""];
    [self log:@"=== بدء عملية التثبيت ==="];
    [self log:[NSString stringWithFormat:@"IPA: %@", [ipaPath lastPathComponent]]];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self reportProgress:InstallationStagePreparing message:@"جاري تجهيز التطبيق..." progress:0.05 block:progressBlock];
        [self log:@"[1/5] تجهيز..."];
        [NSThread sleepForTimeInterval:0.2];

        [self reportProgress:InstallationStageValidating message:@"جاري التحقق من الملف..." progress:0.15 block:progressBlock];
        [self log:@"[2/5] التحقق من IPA..."];

        IPAValidationResult *validation = [[IPAValidator sharedValidator] validateIPAAtPath:ipaPath];
        if (!validation.isReadyForInstall) {
            NSString *msg = validation.issues.count > 0 ? validation.issues[0] : validation.statusMessage;
            [self log:[NSString stringWithFormat:@"❌ التحقق فشل: %@", msg]];
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *result = [InstallationResult failureResult:msg error:nil];
                result.detailedOutput = [self.installLog copy];
                completion(result);
            });
            return;
        }
        [self log:@"✅ التحقق نجح"];

        // Get info from IPAExtractor for bundleID/version
        IPAExtractedInfo *info = [[IPAExtractor sharedExtractor] extractInfoFromIPA:ipaPath];
        if (info) {
            [self log:[NSString stringWithFormat:@"   Bundle ID: %@", info.bundleID ?: @"غير معروف"]];
            [self log:[NSString stringWithFormat:@"   الإصدار: %@", info.version ?: @"غير معروف"]];
            [self log:[NSString stringWithFormat:@"   الاسم: %@", info.displayName ?: info.name ?: @"غير معروف"]];
        }

        [self reportProgress:InstallationStageInstalling message:@"جاري التثبيت..." progress:0.30 block:progressBlock];
        [self log:@"[3/5] اختيار محرك التثبيت..."];

        id<InstallationProvider> provider = [self bestProvider];
        if (!provider) {
            [self log:@"❌ لا يوجد محرك تثبيت متاح"];
            [self log:@"   المتاحون:"];
            for (id<InstallationProvider> p in self.providers) {
                [self log:[NSString stringWithFormat:@"   - %@: %@", p.providerName, [p isAvailable] ? @"✅" : @"❌"]];
            }
            [self log:@"   الحل: تأكد من تثبيت appinst أو تشغيل الأداة بصلاحيات root"];
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallationResult *result = [InstallationResult failureResult:@"لا يوجد محرك تثبيت متاح. يرجى تثبيت appinst أو تشغيل الأداة بصلاحيات root." error:nil];
                result.detailedOutput = [self.installLog copy];
                completion(result);
            });
            return;
        }

        [self log:[NSString stringWithFormat:@"✅ محرك مختار: %@", provider.providerName]];
        [self log:[NSString stringWithFormat:@"   الوصف: %@", provider.providerDescription]];
        [self reportProgress:InstallationStageInstalling message:[NSString stringWithFormat:@"جاري التثبيت عبر %@...", provider.providerName] progress:0.40 block:progressBlock];

        [provider installIPA:ipaPath completion:^(InstallationResult *result) {
            if (result.success) {
                [self log:@"[4/5] تسجيل التطبيق..."];
                [self reportProgress:InstallationStageRegistering message:@"جاري تسجيل التطبيق..." progress:0.80 block:progressBlock];
                [self runUICache];
                [self log:@"✅ uicache تم التنفيذ"];
                [NSThread sleepForTimeInterval:0.3];
                [self log:@"[5/5] اكتمال!"];
                [self reportProgress:InstallationStageCompleted message:@"تم التثبيت بنجاح ✓" progress:1.0 block:progressBlock];
            } else {
                [self log:[NSString stringWithFormat:@"❌ فشل التثبيت: %@", result.message]];
                if (result.detailedOutput && result.detailedOutput.length > 0) {
                    [self log:@"--- تفاصيل ---"];
                    [self log:result.detailedOutput];
                }
                [self reportProgress:InstallationStageFailed message:result.message progress:1.0 block:progressBlock];
            }

            result.detailedOutput = [self.installLog copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(result);
            });
        }];
    });
}

- (void)log:(NSString *)msg {
    if (!msg) return;
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss";
    NSString *time = [df stringFromDate:[NSDate date]];
    [self.installLog appendFormat:@"[%@] %@\n", time, msg];
    [[Logger sharedLogger] info:msg];
}

- (void)reportProgress:(InstallationStage)stage message:(NSString *)message progress:(float)progress block:(void (^)(InstallationStage, NSString *, float))block {
    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(stage, message, progress);
        });
    }
}

- (void)runUICache {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *uicachePath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/uicache"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:uicachePath]) uicachePath = @"/usr/bin/uicache";
        const char *path = [uicachePath UTF8String];
        const char *args[] = { path, "-a", NULL };
        pid_t pid; int status;
        posix_spawn(&pid, path, NULL, NULL, (char **)args, NULL);
        waitpid(pid, &status, 0);
        [[Logger sharedLogger] info:@"uicache executed"];
    });
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    if (!completion) return;
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
