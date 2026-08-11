#import "CapabilityManager.h"
#import "Logger.h"
#import "RootlessManager.h"

@interface CapabilityManager ()
@property (nonatomic, strong) NSMutableDictionary *capabilities;
@property (nonatomic, assign) BOOL hasScanned;
@end

@implementation CapabilityManager

+ (instancetype)sharedManager {
    static CapabilityManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _capabilities = [NSMutableDictionary dictionary];
        _hasScanned = NO;
    }
    return self;
}

- (void)scanCapabilities {
    @try {
        RootlessManager *rl = [RootlessManager sharedManager];
        NSFileManager *fm = [NSFileManager defaultManager];

        // Check AppSync Unified (multiple possible package IDs)
        BOOL appSync = NO;
        NSArray *appSyncPaths = @[
            @"/var/lib/dpkg/info/ai.akemi.appsyncunified.list",
            @"/var/lib/dpkg/info/net.angelxwind.appsyncunified.list",
            @"/var/lib/dpkg/info/com.angelxwind.appsyncunified.list"
        ];
        for (NSString *path in appSyncPaths) {
            if ([rl fileExistsAtLogicalPath:path]) {
                appSync = YES;
                break;
            }
        }
        // Also check for the dynamic library (proves it's actually loaded)
        NSArray *appSyncDylibPaths = @[
            @"/usr/lib/TweakInject/AppSyncUnified.dylib",
            @"/var/jb/usr/lib/TweakInject/AppSyncUnified.dylib",
            @"/usr/lib/Cephei/AppSyncUnified.dylib",
            @"/var/jb/usr/lib/Cephei/AppSyncUnified.dylib"
        ];
        for (NSString *path in appSyncDylibPaths) {
            if ([rl fileExistsAtLogicalPath:path]) {
                appSync = YES;
                break;
            }
        }
        self.capabilities[@"AppSync"] = @(appSync);

        // Check appinst
        NSString *appinstPath = [rl resolvePath:@"/usr/bin/appinst"];
        self.capabilities[@"appinst"] = @([fm fileExistsAtPath:appinstPath]);

        // Check ldid
        NSString *ldidPath = [rl resolvePath:@"/usr/bin/ldid"];
        self.capabilities[@"ldid"] = @([fm fileExistsAtPath:ldidPath]);

        // Check uicache
        NSString *uicachePath = [rl resolvePath:@"/usr/bin/uicache"];
        self.capabilities[@"uicache"] = @([fm fileExistsAtPath:uicachePath]);

        // Check unzip
        NSString *unzipPath = [rl resolvePath:@"/usr/bin/unzip"];
        self.capabilities[@"unzip"] = @([fm fileExistsAtPath:unzipPath]);

        // Check root helper
        NSString *helperPath = [rl resolvePath:@"/usr/bin/ipainstallerpro_helper"];
        self.capabilities[@"root_helper"] = @([fm fileExistsAtPath:helperPath]);

        // Check LSApplicationWorkspace
        Class LSApplicationWorkspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        self.capabilities[@"LSApplicationWorkspace"] = @(LSApplicationWorkspaceClass != nil);

        self.hasScanned = YES;

        [[Logger sharedLogger] info:[NSString stringWithFormat:@"Capabilities: AppSync=%@, appinst=%@, ldid=%@, uicache=%@, unzip=%@, root_helper=%@, LSAppWS=%@",
            self.capabilities[@"AppSync"],
            self.capabilities[@"appinst"],
            self.capabilities[@"ldid"],
            self.capabilities[@"uicache"],
            self.capabilities[@"unzip"],
            self.capabilities[@"root_helper"],
            self.capabilities[@"LSApplicationWorkspace"]]];
    }
    @catch (NSException *exception) {
        [[Logger sharedLogger] error:[NSString stringWithFormat:@"Capability scan failed: %@", exception.reason]];
    }
}

- (BOOL)isAppSyncAvailable {
    if (!self.hasScanned) [self scanCapabilities];
    return [self.capabilities[@"AppSync"] boolValue];
}

- (BOOL)isAppInstAvailable {
    if (!self.hasScanned) [self scanCapabilities];
    return [self.capabilities[@"appinst"] boolValue];
}

- (BOOL)isLDIDAvailable {
    if (!self.hasScanned) [self scanCapabilities];
    return [self.capabilities[@"ldid"] boolValue];
}

- (BOOL)isUICacheAvailable {
    if (!self.hasScanned) [self scanCapabilities];
    return [self.capabilities[@"uicache"] boolValue];
}

- (BOOL)isUnzipAvailable {
    if (!self.hasScanned) [self scanCapabilities];
    return [self.capabilities[@"unzip"] boolValue];
}

- (BOOL)isRootHelperAvailable {
    if (!self.hasScanned) [self scanCapabilities];
    return [self.capabilities[@"root_helper"] boolValue];
}

- (BOOL)isLSApplicationWorkspaceAvailable {
    if (!self.hasScanned) [self scanCapabilities];
    return [self.capabilities[@"LSApplicationWorkspace"] boolValue];
}

- (NSDictionary *)allCapabilities {
    if (!self.hasScanned) [self scanCapabilities];
    return [self.capabilities copy];
}

- (NSString *)capabilityStatusString {
    if (!self.hasScanned) [self scanCapabilities];
    NSMutableString *status = [NSMutableString string];
    [status appendFormat:@"AppSync: %@\n", self.isAppSyncAvailable ? @"✅" : @"❌"];
    [status appendFormat:@"appinst: %@\n", self.isAppInstAvailable ? @"✅" : @"❌"];
    [status appendFormat:@"ldid: %@\n", self.isLDIDAvailable ? @"✅" : @"❌"];
    [status appendFormat:@"uicache: %@\n", self.isUICacheAvailable ? @"✅" : @"❌"];
    [status appendFormat:@"unzip: %@\n", self.isUnzipAvailable ? @"✅" : @"❌"];
    [status appendFormat:@"Root Helper: %@\n", self.isRootHelperAvailable ? @"✅" : @"❌"];
    [status appendFormat:@"LSApplicationWorkspace: %@", self.isLSApplicationWorkspaceAvailable ? @"✅" : @"❌"];
    return status;
}

@end
