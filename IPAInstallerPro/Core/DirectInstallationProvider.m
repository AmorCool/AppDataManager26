//
//  DirectInstallationProvider.m
//  IPAInstallerPro
//

#import "DirectInstallationProvider.h"
#import "RootlessManager.h"
#import "InstallationLogger.h"
#import <Foundation/Foundation.h>
#import <spawn.h>
#import <sys/wait.h>
#import <copyfile.h>

extern char **environ;

@interface DirectInstallationProvider ()
@property (nonatomic, strong) NSString *ldidPath;
@property (nonatomic, strong) NSString *uicachePath;
@property (nonatomic, strong) NSString *chmodPath;
@property (nonatomic, strong) NSString *chownPath;
@property (nonatomic, strong) NSString *rmPath;
@property (nonatomic, strong) NSString *cpPath;
@property (nonatomic, strong) NSString *unzipPath;
@property (nonatomic, strong) NSString *sbreloadPath;
@property (nonatomic, strong) NSString *helperPath;
@property (nonatomic, strong) NSString *whoamiPath;
@end

@implementation DirectInstallationProvider

- (NSString *)providerName { return @"Direct Install"; }
- (NSString *)providerDescription { return @"Direct installation using root helper with full signing"; }
- (NSInteger)priority { return 100; }

- (instancetype)init {
    self = [super init];
    if (self) {
        RootlessManager *rm = [RootlessManager sharedManager];
        self.ldidPath  = [rm resolvePath:@"/usr/bin/ldid"];
        self.uicachePath = [rm resolvePath:@"/usr/bin/uicache"];
        self.chmodPath = [rm resolvePath:@"/bin/chmod"];
        self.chownPath = [rm resolvePath:@"/usr/sbin/chown"];
        self.rmPath = [rm resolvePath:@"/bin/rm"];
        self.cpPath = [rm resolvePath:@"/bin/cp"];
        self.unzipPath = [rm resolvePath:@"/usr/bin/unzip"];
        self.sbreloadPath = [rm resolvePath:@"/usr/bin/sbreload"];
        self.whoamiPath = [rm resolvePath:@"/usr/bin/whoami"];
        [self findWorkingHelper];
    }
    return self;
}

- (void)findWorkingHelper {
    NSArray *candidates = @[
        [[RootlessManager sharedManager] resolvePath:@"/usr/bin/ipainstallerpro_helper"],
        @"/usr/bin/ipainstallerpro_helper",
        @"/var/jb/usr/bin/ipainstallerpro_helper"
    ];
    for (NSString *path in candidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            if ([self testHelperAtPath:path]) {
                self.helperPath = path;
                NSLog(@"[IPAInstallerPro] Helper: %@", path);
                return;
            }
        }
    }
    self.helperPath = nil;
    NSLog(@"[IPAInstallerPro] WARNING: No working helper!");
}

- (BOOL)testHelperAtPath:(NSString *)path {
    pid_t pid;
    const char *h = [path UTF8String];
    const char *w = [self.whoamiPath UTF8String];
    char *argv[] = {(char*)h, (char*)w, NULL};
    if (posix_spawn(&pid, h, NULL, NULL, argv, environ) != 0) return NO;
    int ws;
    waitpid(pid, &ws, 0);
    return (WIFEXITED(ws) && WEXITSTATUS(ws) == 0);
}

- (BOOL)isAvailable {
    return ([self hasRootHelper] || ([[NSFileManager defaultManager] fileExistsAtPath:self.ldidPath] &&
             [[NSFileManager defaultManager] fileExistsAtPath:self.uicachePath]));
}
- (BOOL)hasRootHelper { return (self.helperPath != nil && self.helperPath.length > 0); }

- (BOOL)runCmd:(NSString *)cmd args:(NSArray *)args {
    pid_t pid;
    const char *c = [cmd UTF8String];
    char **argv = malloc((args.count + 2) * sizeof(char*));
    argv[0] = (char*)c;
    for (NSUInteger i = 0; i < args.count; i++) argv[i+1] = (char*)[args[i] UTF8String];
    argv[args.count + 1] = NULL;
    int st = posix_spawn(&pid, c, NULL, NULL, argv, environ);
    free(argv);
    if (st != 0) return NO;
    int ws; waitpid(pid, &ws, 0);
    return (WIFEXITED(ws) && WEXITSTATUS(ws) == 0);
}

- (BOOL)runRoot:(NSString *)cmd args:(NSArray *)args {
    if (![self hasRootHelper]) return [self runCmd:cmd args:args];
    pid_t pid;
    const char *h = [self.helperPath UTF8String];
    const char *c = [cmd UTF8String];
    char **argv = malloc((args.count + 3) * sizeof(char*));
    argv[0] = (char*)h; argv[1] = (char*)c;
    for (NSUInteger i = 0; i < args.count; i++) argv[i+2] = (char*)[args[i] UTF8String];
    argv[args.count + 2] = NULL;
    int st = posix_spawn(&pid, h, NULL, NULL, argv, environ);
    free(argv);
    if (st != 0) return [self runCmd:cmd args:args];
    int ws; waitpid(pid, &ws, 0);
    if (WIFEXITED(ws) && WEXITSTATUS(ws) == 0) return YES;
    return [self runCmd:cmd args:args];
}

- (void)installIPA:(NSString *)ipaPath completion:(void (^)(InstallationResult *))completion {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL hasH = [self hasRootHelper];
    NSLog(@"[IPAInstallerPro] Install: %@", ipaPath);

    if (![fm fileExistsAtPath:ipaPath]) {
        if (completion) completion([InstallationResult failureResult:@"IPA not found" error:nil]);
        return;
    }

    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [fm createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:nil];

    if (![self runCmd:self.unzipPath args:@[@"-o", ipaPath, @"-d", tmp]]) {
        [fm removeItemAtPath:tmp error:nil];
        if (completion) completion([InstallationResult failureResult:@"Unzip failed" error:nil]);
        return;
    }

    NSString *payload = [tmp stringByAppendingPathComponent:@"Payload"];
    NSArray *items = [fm contentsOfDirectoryAtPath:payload error:nil];
    NSString *appFolder = nil;
    for (NSString *i in items) { if ([i hasSuffix:@".app"]) { appFolder = i; break; } }
    if (!appFolder) {
        [fm removeItemAtPath:tmp error:nil];
        if (completion) completion([InstallationResult failureResult:@"No .app found" error:nil]);
        return;
    }

    NSString *srcApp = [payload stringByAppendingPathComponent:appFolder];
    NSString *infoPath = [srcApp stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    if (!info) {
        [fm removeItemAtPath:tmp error:nil];
        if (completion) completion([InstallationResult failureResult:@"No Info.plist" error:nil]);
        return;
    }

    NSString *bundleID = info[@"CFBundleIdentifier"];
    NSString *appName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: appFolder;
    NSString *exeName = info[@"CFBundleExecutable"];
    if (!bundleID || !exeName) {
        [fm removeItemAtPath:tmp error:nil];
        if (completion) completion([InstallationResult failureResult:@"Missing bundleID/exe" error:nil]);
        return;
    }

    NSString *logicalDest = [@"/Applications" stringByAppendingPathComponent:appFolder];
    NSString *destApp = [[RootlessManager sharedManager] resolvePath:logicalDest];

    if ([fm fileExistsAtPath:destApp]) {
        if (hasH) [self runRoot:self.rmPath args:@[@"-rf", destApp]];
        else [fm removeItemAtPath:destApp error:nil];
    }

    BOOL copied = NO;
    if (hasH) {
        copied = [self runRoot:self.cpPath args:@[@"-R", srcApp, destApp]];
        if (!copied) copied = (copyfile([srcApp UTF8String], [destApp UTF8String], NULL, COPYFILE_ALL | COPYFILE_RECURSIVE) == 0);
    } else {
        if (copyfile([srcApp UTF8String], [destApp UTF8String], NULL, COPYFILE_ALL | COPYFILE_RECURSIVE) == 0) copied = YES;
        else { NSError *e; [fm copyItemAtPath:srcApp toPath:destApp error:&e]; copied = (e == nil); }
    }

    if (!copied) {
        [fm removeItemAtPath:tmp error:nil];
        if (completion) completion([InstallationResult failureResult:@"Copy failed" error:nil]);
        return;
    }

    if (hasH) {
        [self runRoot:self.chmodPath args:@[@"-R", @"755", destApp]];
        [self runRoot:self.chownPath args:@[@"-R", @"root:wheel", destApp]];
    } else {
        [self runCmd:self.chmodPath args:@[@"-R", @"755", destApp]];
        [self runCmd:self.chownPath args:@[@"-R", @"root:wheel", destApp]];
    }

    [self signAllAt:destApp hasHelper:hasH];

    NSString *exePath = [destApp stringByAppendingPathComponent:exeName];
    [self signExe:exePath hasHelper:hasH];
    [self fixFrameworks:destApp hasHelper:hasH];

    if (hasH) {
        [self runRoot:self.uicachePath args:@[@"-p", logicalDest]];
        [self runRoot:self.uicachePath args:@[@"-p", destApp]];
        [self runRoot:self.uicachePath args:@[@"-a"]];
        [self runRoot:self.sbreloadPath args:@[]];
    } else {
        [self runCmd:self.uicachePath args:@[@"-p", logicalDest]];
        [self runCmd:self.uicachePath args:@[@"-p", destApp]];
        [self runCmd:self.uicachePath args:@[@"-a"]];
        [self runCmd:self.sbreloadPath args:@[]];
    }

    BOOL ok = [self verify:destApp bundleID:bundleID exeName:exeName];
    [fm removeItemAtPath:tmp error:nil];

    InstallationResult *res = [InstallationResult successResult:[NSString stringWithFormat:@"Installed %@", appName]];
    res.bundleID = bundleID;
    res.detailedOutput = ok ? @"Verification passed" : @"Verification incomplete - may need reboot";
    if (completion) completion(res);
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    Class LS = objc_getClass("LSApplicationWorkspace");
    if (!LS) { if (completion) completion(NO, @"LSApplicationWorkspace unavailable"); return; }
    id ws = [LS performSelector:@selector(defaultWorkspace)];
    if (![ws respondsToSelector:@selector(applicationForIdentifier:)]) {
        if (completion) completion(NO, @"applicationForIdentifier unavailable"); return;
    }
    id app = [ws performSelector:@selector(applicationForIdentifier:) withObject:bundleID];
    if (!app) { if (completion) completion(NO, @"App not found"); return; }
    NSString *path = nil;
    if ([app respondsToSelector:@selector(bundleURL)]) path = [[app performSelector:@selector(bundleURL)] path];
    if (!path) { if (completion) completion(NO, @"Cannot determine app path"); return; }
    BOOL removed = [self hasRootHelper] ? [self runRoot:self.rmPath args:@[@"-rf", path]] : [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    if (removed) {
        if ([self hasRootHelper]) { [self runRoot:self.uicachePath args:@[@"-a"]]; [self runRoot:self.sbreloadPath args:@[]]; }
        else { [self runCmd:self.uicachePath args:@[@"-a"]]; [self runCmd:self.sbreloadPath args:@[]]; }
        if (completion) completion(YES, nil);
    } else { if (completion) completion(NO, @"Remove failed"); }
}

- (void)signAllAt:(NSString *)path hasHelper:(BOOL)hasH {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *item in [fm contentsOfDirectoryAtPath:path error:nil]) {
        NSString *ip = [path stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        [fm fileExistsAtPath:ip isDirectory:&isDir];
        if (isDir) {
            [self signAllAt:ip hasHelper:hasH];
            if ([item hasSuffix:@".app"]) {
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[ip stringByAppendingPathComponent:@"Info.plist"]];
                NSString *en = info[@"CFBundleExecutable"];
                if (en) [self signBin:[ip stringByAppendingPathComponent:en] hasHelper:hasH label:[@"app:" stringByAppendingString:en]];
            } else if ([item hasSuffix:@".framework"]) {
                NSString *fn = [item stringByDeletingPathExtension];
                [self signBin:[ip stringByAppendingPathComponent:fn] hasHelper:hasH label:[@"fw:" stringByAppendingString:fn]];
            }
        } else if ([item hasSuffix:@".dylib"] || [item hasSuffix:@".so"]) {
            [self signBin:ip hasHelper:hasH label:[@"dylib:" stringByAppendingString:item]];
        }
    }
}

- (void)signBin:(NSString *)path hasHelper:(BOOL)hasH label:(NSString *)label {
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    if (hasH) [self runRoot:self.chmodPath args:@[@"755", path]];
    else [self runCmd:self.chmodPath args:@[@"755", path]];
    BOOL ok = hasH ? [self runRoot:self.ldidPath args:@[@"-S", path]] : [self runCmd:self.ldidPath args:@[@"-S", path]];
    if (!ok) {
        NSString *ep = [NSTemporaryDirectory() stringByAppendingPathComponent:@"min.ent"];
        [@{@"get-task-allow":@YES, @"platform-application":@YES} writeToFile:ep atomically:YES];
        NSString *sf = [NSString stringWithFormat:@"-S%@", ep];
        ok = hasH ? [self runRoot:self.ldidPath args:@[sf, path]] : [self runCmd:self.ldidPath args:@[sf, path]];
    }
    NSLog(@"[IPAInstallerPro] %@: %@", ok ? @"✅" : @"⚠️", label);
}

- (void)signExe:(NSString *)path hasHelper:(BOOL)hasH {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    NSString *ep = [NSTemporaryDirectory() stringByAppendingPathComponent:@"orig.ent"];
    BOOL extracted = hasH ? [self runRoot:self.ldidPath args:@[@"-e", @">", ep, path]] : [self runCmd:self.ldidPath args:@[@"-e", @">", ep, path]];
    BOOL ok = NO;
    if (extracted && [[NSFileManager defaultManager] fileExistsAtPath:ep]) {
        NSData *d = [NSData dataWithContentsOfFile:ep];
        if (d && d.length > 10) {
            NSString *sf = [NSString stringWithFormat:@"-S%@", ep];
            ok = hasH ? [self runRoot:self.ldidPath args:@[sf, path]] : [self runCmd:self.ldidPath args:@[sf, path]];
        }
    }
    if (!ok) ok = hasH ? [self runRoot:self.ldidPath args:@[@"-S", path]] : [self runCmd:self.ldidPath args:@[@"-S", path]];
    if (!ok) {
        NSString *ep2 = [NSTemporaryDirectory() stringByAppendingPathComponent:@"min.ent"];
        [@{@"get-task-allow":@YES, @"platform-application":@YES} writeToFile:ep2 atomically:YES];
        NSString *sf = [NSString stringWithFormat:@"-S%@", ep2];
        ok = hasH ? [self runRoot:self.ldidPath args:@[sf, path]] : [self runCmd:self.ldidPath args:@[sf, path]];
    }
    NSLog(@"[IPAInstallerPro] Main exe sign: %@", ok ? @"OK" : @"⚠️");
}

- (void)fixFrameworks:(NSString *)appPath hasHelper:(BOOL)hasH {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *fw = [appPath stringByAppendingPathComponent:@"Frameworks"];
    if (![fm fileExistsAtPath:fw]) return;
    for (NSString *item in [fm contentsOfDirectoryAtPath:fw error:nil]) {
        NSString *ip = [fw stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        [fm fileExistsAtPath:ip isDirectory:&isDir];
        if (isDir && [item hasSuffix:@".framework"]) {
            NSString *fn = [item stringByDeletingPathExtension];
            [self signBin:[ip stringByAppendingPathComponent:fn] hasHelper:hasH label:[@"fw:" stringByAppendingString:fn]];
            [self signAllAt:ip hasHelper:hasH];
        } else if ([item hasSuffix:@".dylib"] || [item hasSuffix:@".so"]) {
            [self signBin:ip hasHelper:hasH label:[@"dylib:" stringByAppendingString:item]];
            if (hasH) { [self runRoot:self.chmodPath args:@[@"755", ip]]; [self runRoot:self.chownPath args:@[@"root:wheel", ip]]; }
        }
    }
}

- (BOOL)verify:(NSString *)appPath bundleID:(NSString *)bid exeName:(NSString *)en {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL ok = YES;
    NSString *ep = [appPath stringByAppendingPathComponent:en];
    if (![fm fileExistsAtPath:ep]) { NSLog(@"❌ exe missing"); ok = NO; }
    else if (![fm isReadableFileAtPath:ep]) { NSLog(@"❌ exe unreadable"); ok = NO; }
    else NSLog(@"✅ exe OK");
    NSString *ip = [appPath stringByAppendingPathComponent:@"Info.plist"];
    if (![fm fileExistsAtPath:ip]) { NSLog(@"❌ Info.plist missing"); ok = NO; }
    else NSLog(@"✅ Info.plist OK");
    NSString *fwp = [appPath stringByAppendingPathComponent:@"Frameworks"];
    if ([fm fileExistsAtPath:fwp]) {
        for (NSString *item in [fm contentsOfDirectoryAtPath:fwp error:nil]) {
            NSString *p = [fwp stringByAppendingPathComponent:item];
            if ([item hasSuffix:@".dylib"] || [item hasSuffix:@".so"]) {
                if (![fm isReadableFileAtPath:p]) { NSLog(@"❌ %@ unreadable", item); ok = NO; }
                else NSLog(@"✅ %@ OK", item);
            }
        }
    }
    Class LS = objc_getClass("LSApplicationWorkspace");
    if (LS) {
        id ws = [LS performSelector:@selector(defaultWorkspace)];
        if ([ws respondsToSelector:@selector(applicationForIdentifier:)]) {
            id a = [ws performSelector:@selector(applicationForIdentifier:) withObject:bid];
            NSLog(@"%@", a ? @"✅ Registered" : @"⚠️ Not registered yet");
        }
    }
    return ok;
}

@end
