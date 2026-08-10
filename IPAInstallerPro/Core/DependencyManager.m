#import "DependencyManager.h"
#import "Logger.h"
#import "RootlessManager.h"

@implementation Dependency
@end

@interface DependencyManager ()
@property (nonatomic, strong) NSMutableArray<Dependency *> *dependencies;
@end

@implementation DependencyManager

+ (instancetype)sharedManager {
    static DependencyManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupDependencies];
    }
    return self;
}

- (void)setupDependencies {
    self.dependencies = [NSMutableArray array];

    Dependency *appSync = [[Dependency alloc] init];
    appSync.name = @"AppSync Unified";
    appSync.packageID = @"ai.akemi.appsyncunified";
    appSync.descriptionText = @"يسمح بتثبيت تطبيقات IPA غير موقّعة";
    appSync.repoURL = @"https://cydia.akemi.ai/";
    [self.dependencies addObject:appSync];

    Dependency *appInst = [[Dependency alloc] init];
    appInst.name = @"appinst";
    appInst.packageID = @"ai.akemi.appinst";
    appInst.descriptionText = @"أداة سطر أوامر لتثبيت IPA";
    appInst.repoURL = @"https://cydia.akemi.ai/";
    [self.dependencies addObject:appInst];

    Dependency *unzip = [[Dependency alloc] init];
    unzip.name = @"unzip";
    unzip.packageID = @"unzip";
    unzip.descriptionText = @"مطلوب لفك ضغط ملفات IPA";
    unzip.repoURL = @"https://apt.bingner.com/";
    [self.dependencies addObject:unzip];

    [self refreshStatus];
}

- (void)refreshStatus {
    RootlessManager *rl = [RootlessManager sharedManager];
    for (Dependency *dep in self.dependencies) {
        dep.isInstalled = [self isPackageInstalled:dep.packageID];
        if (!dep.isInstalled && [dep.packageID isEqualToString:@"ai.akemi.appinst"]) {
            dep.isInstalled = [rl fileExistsAtLogicalPath:@"/usr/bin/appinst"];
        }
        if (!dep.isInstalled && [dep.packageID isEqualToString:@"unzip"]) {
            dep.isInstalled = [rl fileExistsAtLogicalPath:@"/usr/bin/unzip"];
        }
    }
    [[Logger sharedLogger] info:[NSString stringWithFormat:@"Dependencies refreshed: %lu installed", 
        (unsigned long)[[self.dependencies filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isInstalled == YES"]] count]]];
}

- (BOOL)isPackageInstalled:(NSString *)packageID {
    if (!packageID || packageID.length == 0) return NO;
    RootlessManager *rl = [RootlessManager sharedManager];
    NSString *listPath = [NSString stringWithFormat:@"/var/lib/dpkg/info/%@.list", packageID];
    return [rl fileExistsAtLogicalPath:listPath];
}

- (BOOL)isBinaryAvailable:(NSString *)binaryName {
    if (!binaryName || binaryName.length == 0) return NO;
    RootlessManager *rl = [RootlessManager sharedManager];
    return [rl fileExistsAtLogicalPath:[NSString stringWithFormat:@"/usr/bin/%@", binaryName]];
}

- (NSArray<Dependency *> *)allDependencies {
    return [self.dependencies copy];
}

- (Dependency *)dependencyForPackageID:(NSString *)packageID {
    for (Dependency *dep in self.dependencies) {
        if ([dep.packageID isEqualToString:packageID]) return dep;
    }
    return nil;
}

@end
