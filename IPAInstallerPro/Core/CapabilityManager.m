//
// CapabilityManager.m
// IPA Installer Pro
//
// v2.1 — STANDALONE: Only system tools (ldid, uicache, unzip, helper)
//

#import "CapabilityManager.h"
#import "RootlessManager.h"
#import <Foundation/Foundation.h>

@interface CapabilityManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *capabilities;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *paths;
@end

@implementation CapabilityManager

+ (instancetype)sharedManager {
    static CapabilityManager *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _capabilities = [NSMutableDictionary dictionary];
        _paths = [NSMutableDictionary dictionary];
        [self refreshCapabilities];
    }
    return self;
}

- (void)refreshCapabilities {
    RootlessManager *rm = [RootlessManager sharedManager];
    NSFileManager *fm = [NSFileManager defaultManager];

    // System tools only — no external dependencies
    [self checkTool:@"ldid" path:[rm resolvePath:@"/usr/bin/ldid"]];
    [self checkTool:@"uicache" path:[rm resolvePath:@"/usr/bin/uicache"]];
    [self checkTool:@"unzip" path:[rm resolvePath:@"/usr/bin/unzip"]];
    [self checkTool:@"chmod" path:[rm resolvePath:@"/bin/chmod"]];
    [self checkTool:@"chown" path:[rm resolvePath:@"/usr/sbin/chown"]];
    [self checkTool:@"cp" path:[rm resolvePath:@"/bin/cp"]];
    [self checkTool:@"rm" path:[rm resolvePath:@"/bin/rm"]];
    [self checkTool:@"mkdir" path:[rm resolvePath:@"/bin/mkdir"]];

    // Root helper
    NSString *h1 = [rm resolvePath:@"/usr/bin/ipainstallerpro_helper"];
    NSString *h2 = @"/usr/bin/ipainstallerpro_helper";
    NSString *h3 = @"/var/jb/usr/bin/ipainstallerpro_helper";
    BOOL hasHelper = [fm fileExistsAtPath:h1] || [fm fileExistsAtPath:h2] || [fm fileExistsAtPath:h3];
    self.capabilities[@"root_helper"] = @(hasHelper);
    if (hasHelper) {
        if ([fm fileExistsAtPath:h1]) self.paths[@"root_helper"] = h1;
        else if ([fm fileExistsAtPath:h2]) self.paths[@"root_helper"] = h2;
        else self.paths[@"root_helper"] = h3;
    }

    // LSApplicationWorkspace (for verification only, not installation)
    Class LS = objc_getClass("LSApplicationWorkspace");
    self.capabilities[@"ls_workspace"] = @(LS != nil);

    NSLog(@"[IPAInstallerPro] Capabilities refreshed: %@", self.capabilities);
}

- (void)checkTool:(NSString *)name path:(NSString *)path {
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path];
    self.capabilities[name] = @(exists);
    if (exists) self.paths[name] = path;
}

- (BOOL)hasCapability:(NSString *)capability {
    return [self.capabilities[capability] boolValue];
}

- (NSString *)pathForTool:(NSString *)tool {
    return self.paths[tool];
}

- (NSDictionary<NSString *, NSNumber *> *)allCapabilities {
    return [self.capabilities copy];
}

- (NSString *)capabilityDescription:(NSString *)capability {
    static NSDictionary *desc = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        desc = @{
            @"ldid": @"Code signing tool (required)",
            @"uicache": @"App registration tool (required)",
            @"unzip": @"Archive extraction tool (required)",
            @"chmod": @"Permission modification tool (required)",
            @"chown": @"Ownership modification tool (required)",
            @"cp": @"File copy tool (required)",
            @"rm": @"File removal tool (required)",
            @"mkdir": @"Directory creation tool (required)",
            @"root_helper": @"Root privilege helper (recommended)",
            @"ls_workspace": @"System app registry (verification only)"
        };
    });
    return desc[capability] ?: capability;
}

@end
