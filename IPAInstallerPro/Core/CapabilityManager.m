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

    // Direct installation (ldid + root access)
    Capability *directInstall = [[Capability alloc] init];
    directInstall.name = @"Direct Installation";
    directInstall.identifier = @"direct_install";
    directInstall.isAvailable = [self checkDirectInstall];
    directInstall.statusMessage = directInstall.isAvailable ? @"جاهز ✓" : @"غير متوفر";
    directInstall.path = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/ldid"];
    [self.capabilities addObject:directInstall];

    [[Logger sharedLogger] info:[NSString stringWithFormat:@"Capabilities scanned: %lu ready", 
        (unsigned long)[[self.capabilities filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isAvailable == YES"]] count]]];
}

- (BOOL)checkAppSync {
    RootlessManager *rl = [RootlessManager sharedManager];
    return [rl fileExistsAtLogicalPath:@"/var/lib/dpkg/info/ai.akemi.appsyncunified.list"] ||
           [rl fileExistsAtLogicalPath:@"/var/lib/dpkg/info/net.angelxwind.appsyncunified.list"];
}

- (BOOL)checkAppInst {
    return [[RootlessManager sharedManager] fileExistsAtLogicalPath:@"/usr/bin/appinst"];
}

- (BOOL)checkUnzip {
    return [[RootlessManager sharedManager] fileExistsAtLogicalPath:@"/usr/bin/unzip"];
}

- (BOOL)checkDirectInstall {
    // Check for ldid (signing tool) and root access
    RootlessManager *rl = [RootlessManager sharedManager];
    BOOL hasLdid = [rl fileExistsAtLogicalPath:@"/usr/bin/ldid"];
    BOOL hasRoot = (getuid() == 0);
    return hasLdid && hasRoot;
}

- (NSArray<Capability *> *)allCapabilities {
    return [self.capabilities copy];
}

- (Capability *)capabilityForIdentifier:(NSString *)identifier {
    for (Capability *cap in self.capabilities) {
        if ([cap.identifier isEqualToString:identifier]) {
            return cap;
        }
    }
    return nil;
}

- (BOOL)isAppSyncAvailable {
    return [self capabilityForIdentifier:@"appsync"].isAvailable;
}

- (BOOL)isAppInstAvailable {
    return [self capabilityForIdentifier:@"appinst"].isAvailable;
}

- (BOOL)isUnzipAvailable {
    return [self capabilityForIdentifier:@"unzip"].isAvailable;
}

- (BOOL)isSystemInstallationAvailable {
    return [self capabilityForIdentifier:@"system_install"].isAvailable;
}

- (BOOL)isDirectInstallationAvailable {
    return [self capabilityForIdentifier:@"direct_install"].isAvailable;
}

- (NSString *)installationReadinessStatus {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:@"═══ جاهزية التثبيت ═══"];
    [lines addObject:@""];

    for (Capability *cap in self.capabilities) {
        NSString *status = cap.isAvailable ? @"✓" : @"✗";
        [lines addObject:[NSString stringWithFormat:@"%@ %@: %@", status, cap.name, cap.statusMessage]];
    }

    [lines addObject:@""];

    if (self.canInstallIPA) {
        [lines addObject:@"✅ يمكن تثبيت IPA"];
    } else {
        [lines addObject:@"❌ لا يمكن تثبيت IPA"];
        [lines addObject:@""];
        [lines addObject:@"للتثبيت المباشر (بدون AppSync):"];
        [lines addObject:@"• تأكد من تثبيت ldid"];
        [lines addObject:@"• تأكد من تشغيل الأداة بصلاحيات root"];
        [lines addObject:@""];
        [lines addObject:@"للتثبيت عبر appinst:"];
        [lines addObject:@"• تأكد من تثبيت appinst"];
    }

    return [lines componentsJoinedByString:@"\n"];
}

- (BOOL)canInstallIPA {
    // Can install if ANY of these is available:
    // 1. appinst backend
    // 2. System installation (LSApplicationWorkspace)
    // 3. Direct installation (ldid + root)
    // 4. Unzip (for extraction, but needs a provider too)
    return self.isAppInstAvailable || self.isSystemInstallationAvailable || self.isDirectInstallationAvailable;
}

@end
