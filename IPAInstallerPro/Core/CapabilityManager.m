#import "CapabilityManager.h"
#import <objc/runtime.h>
#import "Logger.h"
#import "RootlessManager.h"

@implementation Capability
@end

@interface CapabilityManager ()
@property (nonatomic, strong) NSMutableArray<Capability *> *capabilities;
@end

@implementation CapabilityManager

+ (instancetype)sharedManager {
    static CapabilityManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _capabilities = [NSMutableArray array];
        [self scanCapabilities];
    }
    return self;
}

- (void)scanCapabilities {
    [self.capabilities removeAllObjects];

    // AppSync Unified (kernel tweak — required for unsigned IPA installation)
    Capability *appSync = [[Capability alloc] init];
    appSync.name = @"AppSync Unified";
    appSync.identifier = @"appsync";
    appSync.isAvailable = [self checkAppSync];
    appSync.statusMessage = appSync.isAvailable ? @"جاهز ✓" : @"غير متوفر";
    appSync.path = @"/var/lib/dpkg/info/ai.akemi.appsyncunified.list";
    [self.capabilities addObject:appSync];

    // appinst (CLI backend — auto-provisioned by postinst if missing)
    Capability *appInst = [[Capability alloc] init];
    appInst.name = @"appinst Backend";
    appInst.identifier = @"appinst";
    appInst.isAvailable = [self checkAppInst];
    appInst.statusMessage = appInst.isAvailable ? @"جاهز ✓" : @"جاري التوفير...";
    appInst.path = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/appinst"];
    [self.capabilities addObject:appInst];

    // unzip (archive extraction)
    Capability *unzip = [[Capability alloc] init];
    unzip.name = @"Archive Extractor";
    unzip.identifier = @"unzip";
    unzip.isAvailable = [self checkUnzip];
    unzip.statusMessage = unzip.isAvailable ? @"جاهز ✓" : @"غير متوفر";
    unzip.path = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/unzip"];
    [self.capabilities addObject:unzip];

    // System installation (LSApplicationWorkspace)
    Capability *sysInstall = [[Capability alloc] init];
    sysInstall.name = @"System Installation";
    sysInstall.identifier = @"system_install";
    sysInstall.isAvailable = (objc_getClass("LSApplicationWorkspace") != nil);
    sysInstall.statusMessage = sysInstall.isAvailable ? @"متاح ✓" : @"محدود";
    [self.capabilities addObject:sysInstall];

    [[Logger sharedLogger] info:[NSString stringWithFormat:@"Capabilities scanned: %lu ready", 
        (unsigned long)[[self.capabilities filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isAvailable == YES"]] count]]];
}

- (BOOL)checkAppSync {
    RootlessManager *rl = [RootlessManager sharedManager];
    return [rl fileExistsAtLogicalPath:@"/var/lib/dpkg/info/ai.akemi.appsyncunified.list"] ||
           [rl fileExistsAtLogicalPath:@"/var/lib/dpkg/info/net.angelxwind.appsyncunified.list"];
}

- (BOOL)checkAppInst {
    RootlessManager *rl = [RootlessManager sharedManager];
    return [rl fileExistsAtLogicalPath:@"/usr/bin/appinst"];
}

- (BOOL)checkUnzip {
    RootlessManager *rl = [RootlessManager sharedManager];
    return [rl fileExistsAtLogicalPath:@"/usr/bin/unzip"];
}

- (NSArray<Capability *> *)allCapabilities {
    return [self.capabilities copy];
}

- (Capability *)capabilityForIdentifier:(NSString *)identifier {
    for (Capability *cap in self.capabilities) {
        if ([cap.identifier isEqualToString:identifier]) return cap;
    }
    return nil;
}

- (BOOL)isAppSyncAvailable { return [self capabilityForIdentifier:@"appsync"].isAvailable; }
- (BOOL)isAppInstAvailable { return [self capabilityForIdentifier:@"appinst"].isAvailable; }
- (BOOL)isUnzipAvailable { return [self capabilityForIdentifier:@"unzip"].isAvailable; }
- (BOOL)isSystemInstallationAvailable { return [self capabilityForIdentifier:@"system_install"].isAvailable; }

- (NSString *)installationReadinessStatus {
    if (!self.isAppSyncAvailable) return @"يتطلب AppSync Unified";
    if (!self.isUnzipAvailable) return @"يتطلب أداة فك الضغط";
    if (!self.isAppInstAvailable && !self.isSystemInstallationAvailable) return @"لا توجد طريقة تثبيت متاحة";
    return @"جاهز للتثبيت ✓";
}

- (BOOL)canInstallIPA {
    return self.isAppSyncAvailable && self.isUnzipAvailable && (self.isAppInstAvailable || self.isSystemInstallationAvailable);
}

@end
