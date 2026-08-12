//
//  IPAValidator.m
//  IPAInstallerPro
//

#import "IPAValidator.h"
#import "RootlessManager.h"
#import <Foundation/Foundation.h>
#import <spawn.h>
#import <sys/wait.h>

extern char **environ;

@interface IPAValidator ()
@property (nonatomic, strong) NSString *ldidPath;
@property (nonatomic, strong) NSString *otoolPath;
@property (nonatomic, strong) NSString *lipoPath;
@property (nonatomic, strong) NSString *unzipPath;
@end

@implementation IPAValidator

+ (instancetype)sharedValidator {
    static IPAValidator *s = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        RootlessManager *rm = [RootlessManager sharedManager];
        self.ldidPath = [rm resolvePath:@"/usr/bin/ldid"];
        self.otoolPath = [rm resolvePath:@"/usr/bin/otool"];
        self.lipoPath = [rm resolvePath:@"/usr/bin/lipo"];
        self.unzipPath = [rm resolvePath:@"/usr/bin/unzip"];
    }
    return self;
}

- (IPAValidationResult *)validateIPAAtPath:(NSString *)ipaPath {
    NSMutableArray *issues = [NSMutableArray array];
    NSMutableArray *missing = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:ipaPath]) {
        [issues addObject:@"IPA not found"];
        return [self result:IPAValidationStatusInvalidZip issues:issues missing:missing ready:NO];
    }
    if (![fm isReadableFileAtPath:ipaPath]) {
        [issues addObject:@"IPA not readable"];
        return [self result:IPAValidationStatusInvalidZip issues:issues missing:missing ready:NO];
    }

    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:ipaPath];
    if (!fh) {
        [issues addObject:@"Cannot open IPA"];
        return [self result:IPAValidationStatusInvalidZip issues:issues missing:missing ready:NO];
    }
    NSData *header = [fh readDataOfLength:4];
    [fh closeFile];
    if (header.length < 4) {
        [issues addObject:@"IPA empty/corrupt"];
        return [self result:IPAValidationStatusInvalidZip issues:issues missing:missing ready:NO];
    }
    const unsigned char *b = (const unsigned char *)header.bytes;
    if (b[0] != 0x50 || b[1] != 0x4B || b[2] != 0x03 || b[3] != 0x04) {
        [issues addObject:@"Not a valid ZIP"];
        return [self result:IPAValidationStatusInvalidZip issues:issues missing:missing ready:NO];
    }

    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [fm createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *cmd = [NSString stringWithFormat:@"\"%@\" -o \"%@\" -d \"%@\" 2>/dev/null", self.unzipPath, ipaPath, tmp];
    if (system([cmd UTF8String]) != 0) {
        [issues addObject:@"Unzip failed"];
        [fm removeItemAtPath:tmp error:nil];
        return [self result:IPAValidationStatusInvalidZip issues:issues missing:missing ready:NO];
    }

    NSString *payload = [tmp stringByAppendingPathComponent:@"Payload"];
    if (![fm fileExistsAtPath:payload]) {
        [issues addObject:@"Payload missing"];
        [fm removeItemAtPath:tmp error:nil];
        return [self result:IPAValidationStatusMissingPayload issues:issues missing:missing ready:NO];
    }

    NSString *appFolder = nil;
    for (NSString *i in [fm contentsOfDirectoryAtPath:payload error:nil]) {
        if ([i hasSuffix:@".app"]) { appFolder = i; break; }
    }
    if (!appFolder) {
        [issues addObject:@"No .app in Payload"];
        [fm removeItemAtPath:tmp error:nil];
        return [self result:IPAValidationStatusMissingAppBundle issues:issues missing:missing ready:NO];
    }

    NSString *appPath = [payload stringByAppendingPathComponent:appFolder];
    IPAValidationResult *res = [self validateExtractedAppAtPath:appPath];
    [fm removeItemAtPath:tmp error:nil];
    return res;
}

- (IPAValidationResult *)validateExtractedAppAtPath:(NSString *)appPath {
    NSMutableArray *issues = [NSMutableArray array];
    NSMutableArray *missing = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    if (![fm fileExistsAtPath:infoPath]) {
        [issues addObject:@"Info.plist missing"];
        return [self result:IPAValidationStatusMissingInfoPlist issues:issues missing:missing ready:NO];
    }
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    if (!info) {
        [issues addObject:@"Info.plist corrupt"];
        return [self result:IPAValidationStatusMissingInfoPlist issues:issues missing:missing ready:NO];
    }

    NSString *bundleID = info[@"CFBundleIdentifier"];
    NSString *exeName = info[@"CFBundleExecutable"];
    id minOS = info[@"MinimumOSVersion"];
    NSArray *supportedDevices = info[@"UISupportedDevices"];

    if (!bundleID || bundleID.length == 0) {
        [issues addObject:@"BundleID missing"];
        return [self result:IPAValidationStatusInvalidBundleID issues:issues missing:missing ready:NO];
    }
    if (!exeName || exeName.length == 0) {
        [issues addObject:@"Executable missing"];
        return [self result:IPAValidationStatusMissingExecutable issues:issues missing:missing ready:NO];
    }

    NSString *exePath = [appPath stringByAppendingPathComponent:exeName];
    if (![fm fileExistsAtPath:exePath]) {
        [issues addObject:[NSString stringWithFormat:@"Executable %@ missing", exeName]];
        return [self result:IPAValidationStatusMissingExecutable issues:issues missing:missing ready:NO];
    }
    if (![fm isReadableFileAtPath:exePath]) {
        [issues addObject:[NSString stringWithFormat:@"Executable %@ not readable", exeName]];
    }

    NSArray *archs = [self archsFor:exePath];
    if (archs.count == 0) [issues addObject:@"Cannot determine architecture"];
    else {
        BOOL hasArm64 = NO;
        for (NSString *a in archs) if ([a containsString:@"arm64"]) hasArm64 = YES;
        if (!hasArm64) [issues addObject:@"No arm64 support"];
    }

    if (minOS) {
        NSString *mos = [minOS isKindOfClass:[NSString class]] ? (NSString*)minOS : [minOS stringValue];
        NSInteger maj = [[[mos componentsSeparatedByString:@"."] firstObject] integerValue];
        if (maj > 15) [issues addObject:[NSString stringWithFormat:@"Requires iOS %@+", mos]];
    }

    if ([fm fileExistsAtPath:self.ldidPath]) {
        if (![self isSigned:exePath]) [issues addObject:@"Not signed - will re-sign"];
    }

    if ([fm fileExistsAtPath:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"]]) {
        [issues addObject:@"Has Apple provisioning - will remove and re-sign"];
    }

    if (supportedDevices && supportedDevices.count > 0) [issues addObject:@"Device restrictions"];

    if ([fm fileExistsAtPath:self.ldidPath]) {
        NSDictionary *ents = [self extractEnts:exePath];
        if (ents && ents[@"com.apple.private.security.container-required"] && [ents[@"com.apple.private.security.container-required"] boolValue]) {
            [issues addObject:@"Requires special security container"];
        }
    }

    NSString *fwPath = [appPath stringByAppendingPathComponent:@"Frameworks"];
    if ([fm fileExistsAtPath:fwPath]) {
        for (NSString *item in [fm contentsOfDirectoryAtPath:fwPath error:nil]) {
            NSString *ip = [fwPath stringByAppendingPathComponent:item];
            BOOL isDir = NO;
            [fm fileExistsAtPath:ip isDirectory:&isDir];
            if ([item hasSuffix:@".dylib"] || [item hasSuffix:@".so"]) {
                if (![fm isReadableFileAtPath:ip]) [issues addObject:[NSString stringWithFormat:@"Frameworks/%@ unreadable", item]];
                else if ([fm fileExistsAtPath:self.ldidPath] && ![self isSigned:ip]) [issues addObject:[NSString stringWithFormat:@"Frameworks/%@ unsigned", item]];
            } else if (isDir && [item hasSuffix:@".framework"]) {
                NSString *fn = [item stringByDeletingPathExtension];
                NSString *fep = [ip stringByAppendingPathComponent:fn];
                if ([fm fileExistsAtPath:fep] && ![fm isReadableFileAtPath:fep]) [issues addObject:[NSString stringWithFormat:@"Frameworks/%@/%@ unreadable", item, fn]];
            }
        }
    }

    NSArray *deps = [self checkDependenciesAtAppPath:appPath];
    for (NSString *dep in deps) {
        if (![dep hasPrefix:@"@rpath/"] && ![dep hasPrefix:@"@executable_path/"] && ![dep hasPrefix:@"/usr/lib/"] && ![dep hasPrefix:@"/System/Library/"]) {
            [issues addObject:[NSString stringWithFormat:@"External dependency: %@", dep]];
        }
    }

    if ([fm fileExistsAtPath:[appPath stringByAppendingPathComponent:@"PlugIns"]]) [issues addObject:@"Has PlugIns - may need extra signing"];

    BOOL ready = (issues.count == 0);
    return [self result:ready ? IPAValidationStatusValid : IPAValidationStatusIncompatibleArchitecture issues:issues missing:missing ready:ready];
}

- (IPAValidationResult *)result:(IPAValidationStatus)status issues:(NSArray *)issues missing:(NSArray *)missing ready:(BOOL)ready {
    IPAValidationResult *r = [[IPAValidationResult alloc] init];
    r.status = status;
    r.issues = issues;
    r.missingLibraries = missing;
    r.isReadyForInstall = ready;
    if (status == IPAValidationStatusValid) r.statusMessage = @"Valid for install";
    else if (status == IPAValidationStatusInvalidZip) r.statusMessage = @"Invalid ZIP";
    else if (status == IPAValidationStatusMissingPayload) r.statusMessage = @"Payload missing";
    else if (status == IPAValidationStatusMissingAppBundle) r.statusMessage = @".app missing";
    else if (status == IPAValidationStatusMissingInfoPlist) r.statusMessage = @"Info.plist missing";
    else if (status == IPAValidationStatusMissingExecutable) r.statusMessage = @"Executable missing";
    else if (status == IPAValidationStatusInvalidBundleID) r.statusMessage = @"Invalid BundleID";
    else r.statusMessage = @"Has warnings - may need fixes";
    return r;
}

- (NSArray *)archsFor:(NSString *)path {
    NSMutableArray *a = [NSMutableArray array];
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.lipoPath]) return a;
    NSString *cmd = [NSString stringWithFormat:@"\"%@\" -info \"%@\" 2>/dev/null", self.lipoPath, path];
    FILE *fp = popen([cmd UTF8String], "r");
    if (!fp) return a;
    char buf[1024]; NSMutableString *out = [NSMutableString string];
    while (fgets(buf, sizeof(buf), fp)) [out appendString:[NSString stringWithUTF8String:buf]];
    pclose(fp);
    if ([out containsString:@"arm64e"]) [a addObject:@"arm64e"];
    if ([out containsString:@"arm64"] && ![out containsString:@"arm64e"]) [a addObject:@"arm64"];
    if ([out containsString:@"armv7s"]) [a addObject:@"armv7s"];
    if ([out containsString:@"armv7"]) [a addObject:@"armv7"];
    return a;
}

- (BOOL)isSigned:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.ldidPath]) return YES;
    NSString *cmd = [NSString stringWithFormat:@"\"%@\" -e \"%@\" >/dev/null 2>&1", self.ldidPath, path];
    return (system([cmd UTF8String]) == 0);
}

- (NSDictionary *)extractEnts:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.ldidPath]) return nil;
    NSString *tp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ents.plist"];
    NSString *cmd = [NSString stringWithFormat:@"\"%@\" -e \"%@\" > \"%@\" 2>/dev/null", self.ldidPath, path, tp];
    system([cmd UTF8String]);
    NSData *d = [NSData dataWithContentsOfFile:tp];
    [[NSFileManager defaultManager] removeItemAtPath:tp error:nil];
    if (d.length > 10) {
        id obj = [NSPropertyListSerialization propertyListWithData:d options:0 format:NULL error:nil];
        if ([obj isKindOfClass:[NSDictionary class]]) return obj;
    }
    return nil;
}

- (NSArray *)checkDependenciesAtAppPath:(NSString *)appPath {
    NSMutableArray *d = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    NSString *en = info[@"CFBundleExecutable"];
    if (!en) return d;
    NSString *ep = [appPath stringByAppendingPathComponent:en];
    if (![fm fileExistsAtPath:ep] || ![fm fileExistsAtPath:self.otoolPath]) return d;
    NSString *cmd = [NSString stringWithFormat:@"\"%@\" -L \"%@\" 2>/dev/null", self.otoolPath, ep];
    FILE *fp = popen([cmd UTF8String], "r");
    if (!fp) return d;
    char buf[1024];
    while (fgets(buf, sizeof(buf), fp)) {
        NSString *line = [NSString stringWithUTF8String:buf];
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([t hasPrefix:@"\t"]) {
            NSRange r = [t rangeOfString:@" ("];
            if (r.location != NSNotFound) [d addObject:[t substringWithRange:NSMakeRange(1, r.location - 1)]];
        }
    }
    pclose(fp);
    return d;
}

@end
