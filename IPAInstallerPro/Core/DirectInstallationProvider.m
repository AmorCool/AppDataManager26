//
//  DirectInstallationProvider.m
//  IPAInstallerPro
//

#import "DirectInstallationProvider.h"
#import "RootlessManager.h"
#import "InstallationLogger.h"
#import "OperationLog.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "DiagnosticEngine.h"
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
@property (nonatomic, strong) NSString *helperPath;
@property (nonatomic, strong) NSString *whoamiPath;
@end

@implementation DirectInstallationProvider

// Current operation log transaction ID
static NSString *_currentOpID = nil;

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

    // ─── BEGIN OPERATION LOG ───
    OperationLog *opLog = [OperationLog sharedLog];
    _currentOpID = [opLog beginTransactionForIPA:ipaPath];
    NSString *opID = _currentOpID;
    NSLog(@"[IPAInstallerPro] Install: %@ | OpID: %@", ipaPath, opID);

    // [STEP 0] Check IPA exists
    BOOL ipaExists = [fm fileExistsAtPath:ipaPath];
    NSDictionary *ipaAttrs = ipaExists ? [fm attributesOfItemAtPath:ipaPath error:nil] : nil;
    [opLog logOperation:@"fileExistsAtPath"
                  phase:OperationPhaseIPAOpen
                 target:ipaPath
                 result:ipaExists ? OperationResultSuccess : OperationResultFailed
               exitCode:ipaExists ? 0 : ENOENT
              rawOutput:@""
               rawError:ipaExists ? @"" : @"IPA file not found on filesystem"
               duration:0
                context:@{@"size": ipaAttrs ? @(ipaAttrs.fileSize) : @0}
          operationID:opID];

    if (!ipaExists) {
        [opLog endTransaction:opID];
        _currentOpID = nil;
        if (completion) completion([InstallationResult failureResult:@"IPA not found" error:nil]);
        return;
    }

    // [STEP 1] Create temp directory
    NSDate *t0 = [NSDate date];
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    BOOL tmpCreated = [fm createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:nil];
    [opLog logOperation:@"createDirectoryAtPath"
                  phase:OperationPhaseIPAExtract
                 target:tmp
                 result:tmpCreated ? OperationResultSuccess : OperationResultFailed
               exitCode:tmpCreated ? 0 : 1
              rawOutput:@""
               rawError:tmpCreated ? @"" : @"Failed to create temp directory"
               duration:[[NSDate date] timeIntervalSinceDate:t0]
                context:@{}
          operationID:opID];

    // [STEP 2] Unzip IPA
    t0 = [NSDate date];
    NSArray *unzipArgs = @[@"-o", ipaPath, @"-d", tmp];
    BOOL unzipOk = [self runCmd:self.unzipPath args:unzipArgs];
    NSTimeInterval unzipDur = [[NSDate date] timeIntervalSinceDate:t0];
    [opLog logOperation:@"unzip"
                  phase:OperationPhaseIPAExtract
                 target:ipaPath
                 result:unzipOk ? OperationResultSuccess : OperationResultFailed
               exitCode:unzipOk ? 0 : 1
              rawOutput:@""
               rawError:unzipOk ? @"" : @"unzip command returned non-zero exit code"
               duration:unzipDur
                context:@{@"args": [unzipArgs componentsJoinedByString:@" "], @"tmp": tmp}
          operationID:opID];

    if (!unzipOk) {
        [fm removeItemAtPath:tmp error:nil];
        [opLog endTransaction:opID];
        _currentOpID = nil;
        if (completion) completion([InstallationResult failureResult:@"Unzip failed" error:nil]);
        return;
    }

    // [STEP 3] Find Payload/*.app
    t0 = [NSDate date];
    NSString *payload = [tmp stringByAppendingPathComponent:@"Payload"];
    NSArray *items = [fm contentsOfDirectoryAtPath:payload error:nil];
    NSString *appFolder = nil;
    for (NSString *i in items) { if ([i hasSuffix:@".app"]) { appFolder = i; break; } }
    BOOL appFound = (appFolder != nil);
    [opLog logOperation:@"find .app in Payload"
                  phase:OperationPhaseAppIdentify
                 target:payload
                 result:appFound ? OperationResultSuccess : OperationResultFailed
               exitCode:appFound ? 0 : 1
              rawOutput:@""
               rawError:appFound ? @"" : @"No .app folder found in extracted Payload"
               duration:[[NSDate date] timeIntervalSinceDate:t0]
                context:@{@"payloadContents": items ?: @[]}
          operationID:opID];

    if (!appFound) {
        [fm removeItemAtPath:tmp error:nil];
        [opLog endTransaction:opID];
        _currentOpID = nil;
        if (completion) completion([InstallationResult failureResult:@"No .app found" error:nil]);
        return;
    }

    // [STEP 4] Read Info.plist
    t0 = [NSDate date];
    NSString *srcApp = [payload stringByAppendingPathComponent:appFolder];
    NSString *infoPath = [srcApp stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    BOOL infoRead = (info != nil);
    [opLog logOperation:@"dictionaryWithContentsOfFile (Info.plist)"
                  phase:OperationPhaseAppIdentify
                 target:infoPath
                 result:infoRead ? OperationResultSuccess : OperationResultFailed
               exitCode:infoRead ? 0 : 1
              rawOutput:@""
               rawError:infoRead ? @"" : @"Info.plist could not be read"
               duration:[[NSDate date] timeIntervalSinceDate:t0]
                context:@{}
          operationID:opID];

    if (!infoRead) {
        [fm removeItemAtPath:tmp error:nil];
        [opLog endTransaction:opID];
        _currentOpID = nil;
        if (completion) completion([InstallationResult failureResult:@"No Info.plist" error:nil]);
        return;
    }

    // [STEP 5] Extract metadata
    NSString *bundleID = info[@"CFBundleIdentifier"];
    NSString *appName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: appFolder;
    NSString *exeName = info[@"CFBundleExecutable"];
    BOOL metaValid = (bundleID != nil && exeName != nil);
    [opLog logOperation:@"extract bundle metadata"
                  phase:OperationPhaseAppIdentify
                 target:appFolder
                 result:metaValid ? OperationResultSuccess : OperationResultFailed
               exitCode:metaValid ? 0 : 1
              rawOutput:@""
               rawError:metaValid ? @"" : @"Missing CFBundleIdentifier or CFBundleExecutable"
               duration:0
                context:@{@"bundleID": bundleID ?: @"", @"appName": appName, @"exeName": exeName ?: @""}
          operationID:opID];

    if (!metaValid) {
        [fm removeItemAtPath:tmp error:nil];
        [opLog endTransaction:opID];
        _currentOpID = nil;
        if (completion) completion([InstallationResult failureResult:@"Missing bundleID/exe" error:nil]);
        return;
    }

    // [STEP 6] Resolve destination path
    NSString *logicalDest = [@"/Applications" stringByAppendingPathComponent:appFolder];
    NSString *destApp = [[RootlessManager sharedManager] resolvePath:logicalDest];
    [opLog logOperation:@"resolvePath"
                  phase:OperationPhaseFileCopy
                 target:logicalDest
                 result:OperationResultSuccess
               exitCode:0
              rawOutput:destApp
               rawError:@""
               duration:0
                context:@{@"resolvedPath": destApp}
          operationID:opID];

    // [STEP 7] Delete existing app if present
    if ([fm fileExistsAtPath:destApp]) {
        t0 = [NSDate date];
        BOOL deleted;
        if (hasH) {
            deleted = [self runRoot:self.rmPath args:@[@"-rf", destApp]];
        } else {
            deleted = [fm removeItemAtPath:destApp error:nil];
        }
        [opLog logOperation:hasH ? @"rm -rf (root)" : @"removeItemAtPath"
                      phase:OperationPhaseFileCopy
                     target:destApp
                     result:deleted ? OperationResultSuccess : OperationResultFailed
                   exitCode:deleted ? 0 : 1
                  rawOutput:@""
                   rawError:deleted ? @"" : @"Failed to delete existing app"
                   duration:[[NSDate date] timeIntervalSinceDate:t0]
                    context:@{}
              operationID:opID];
    } else {
        [opLog logOperation:@"check existing"
                      phase:OperationPhaseFileCopy
                     target:destApp
                     result:OperationResultSkipped
                   exitCode:0
                  rawOutput:@"No existing app at destination"
                   rawError:@""
                   duration:0
                    context:@{}
              operationID:opID];
    }

    // [STEP 8] Copy app bundle
    t0 = [NSDate date];
    BOOL copied = NO;
    int copyErrno = 0;
    NSString *copyMethod = @"";

    if (hasH) {
        copied = [self runRoot:self.cpPath args:@[@"-R", srcApp, destApp]];
        copyMethod = @"cp -R (root)";
        if (!copied) {
            int rv = copyfile([srcApp UTF8String], [destApp UTF8String], NULL, COPYFILE_ALL | COPYFILE_RECURSIVE);
            copied = (rv == 0);
            copyMethod = @"copyfile (root fallback)";
            if (!copied) copyErrno = errno;
        }
    } else {
        int rv = copyfile([srcApp UTF8String], [destApp UTF8String], NULL, COPYFILE_ALL | COPYFILE_RECURSIVE);
        if (rv == 0) {
            copied = YES;
            copyMethod = @"copyfile";
        } else {
            copyErrno = errno;
            NSError *e;
            [fm copyItemAtPath:srcApp toPath:destApp error:&e];
            copied = (e == nil);
            copyMethod = copied ? @"copyItemAtPath" : @"copyItemAtPath (failed)";
            if (!copied) {
                [opLog logOperation:copyMethod
                              phase:OperationPhaseFileCopy
                             target:[NSString stringWithFormat:@"%@ -> %@", srcApp, destApp]
                             result:OperationResultFailed
                           exitCode:(int)e.code
                          rawOutput:@""
                           rawError:e.localizedDescription
                           duration:[[NSDate date] timeIntervalSinceDate:t0]
                            context:@{}
                      operationID:opID];
            }
        }
    }
    NSTimeInterval copyDur = [[NSDate date] timeIntervalSinceDate:t0];

    if (copied) {
        NSDictionary *destAttrs = [fm attributesOfItemAtPath:destApp error:nil];
        [opLog logOperation:copyMethod
                      phase:OperationPhaseFileCopy
                     target:[NSString stringWithFormat:@"%@ -> %@", srcApp, destApp]
                     result:OperationResultSuccess
                   exitCode:0
                  rawOutput:@""
                   rawError:@""
                   duration:copyDur
                    context:@{@"destSize": destAttrs ? @(destAttrs.fileSize) : @0}
              operationID:opID];
    } else {
        [opLog logOperation:copyMethod
                      phase:OperationPhaseFileCopy
                     target:[NSString stringWithFormat:@"%@ -> %@", srcApp, destApp]
                     result:OperationResultFailed
                   exitCode:copyErrno
                  rawOutput:@""
                   rawError:[NSString stringWithFormat:@"Copy failed, errno=%d", copyErrno]
                   duration:copyDur
                    context:@{}
              operationID:opID];
        [fm removeItemAtPath:tmp error:nil];
        [opLog endTransaction:opID];
        _currentOpID = nil;
        if (completion) completion([InstallationResult failureResult:@"Copy failed" error:nil]);
        return;
    }

    // [STEP 9] Set permissions
    t0 = [NSDate date];
    BOOL chmodOk, chownOk;
    if (hasH) {
        chmodOk = [self runRoot:self.chmodPath args:@[@"-R", @"755", destApp]];
        chownOk = [self runRoot:self.chownPath args:@[@"-R", @"root:wheel", destApp]];
    } else {
        chmodOk = [self runCmd:self.chmodPath args:@[@"-R", @"755", destApp]];
        chownOk = [self runCmd:self.chownPath args:@[@"-R", @"root:wheel", destApp]];
    }
    [opLog logOperation:@"chmod -R 755"
                  phase:OperationPhasePermission
                 target:destApp
                 result:chmodOk ? OperationResultSuccess : OperationResultFailed
               exitCode:chmodOk ? 0 : 1
              rawOutput:@""
               rawError:chmodOk ? @"" : @"chmod failed"
               duration:[[NSDate date] timeIntervalSinceDate:t0]
                context:@{}
          operationID:opID];
    [opLog logOperation:@"chown -R root:wheel"
                  phase:OperationPhasePermission
                 target:destApp
                 result:chownOk ? OperationResultSuccess : OperationResultFailed
               exitCode:chownOk ? 0 : 1
              rawOutput:@""
               rawError:chownOk ? @"" : @"chown failed"
               duration:0
                context:@{}
          operationID:opID];

    // [STEP 10] Sign all binaries recursively
    t0 = [NSDate date];
    [self signAllAt:destApp hasHelper:hasH];
    [opLog logOperation:@"signAllAt (recursive)"
                  phase:OperationPhaseSign
                 target:destApp
                 result:OperationResultSuccess
               exitCode:0
              rawOutput:@""
               rawError:@""
               duration:[[NSDate date] timeIntervalSinceDate:t0]
                context:@{}
          operationID:opID];

    // [STEP 11] Sign main executable
    t0 = [NSDate date];
    NSString *exePath = [destApp stringByAppendingPathComponent:exeName];
    [self signExe:exePath hasHelper:hasH];
    [opLog logOperation:@"signExe (main executable)"
                  phase:OperationPhaseSign
                 target:exePath
                 result:OperationResultSuccess
               exitCode:0
              rawOutput:@""
               rawError:@""
               duration:[[NSDate date] timeIntervalSinceDate:t0]
                context:@{}
          operationID:opID];

    // [STEP 12] Fix frameworks
    t0 = [NSDate date];
    [self fixFrameworks:destApp hasHelper:hasH];
    [opLog logOperation:@"fixFrameworks"
                  phase:OperationPhaseFramework
                 target:destApp
                 result:OperationResultSuccess
               exitCode:0
              rawOutput:@""
               rawError:@""
               duration:[[NSDate date] timeIntervalSinceDate:t0]
                context:@{}
          operationID:opID];

    // [STEP 13] Run uicache
    t0 = [NSDate date];
    BOOL uc1, uc2, uc3;
    if (hasH) {
        uc1 = [self runRoot:self.uicachePath args:@[@"-p", logicalDest]];
        uc2 = [self runRoot:self.uicachePath args:@[@"-p", destApp]];
        uc3 = [self runRoot:self.uicachePath args:@[@"-a"]];
    } else {
        uc1 = [self runCmd:self.uicachePath args:@[@"-p", logicalDest]];
        uc2 = [self runCmd:self.uicachePath args:@[@"-p", destApp]];
        uc3 = [self runCmd:self.uicachePath args:@[@"-a"]];
    }
    NSTimeInterval ucDur = [[NSDate date] timeIntervalSinceDate:t0];
    [opLog logOperation:@"uicache -p logicalDest"
                  phase:OperationPhaseUICache
                 target:logicalDest
                 result:uc1 ? OperationResultSuccess : OperationResultFailed
               exitCode:uc1 ? 0 : 1
              rawOutput:@""
               rawError:uc1 ? @"" : @"uicache -p logicalDest failed"
               duration:ucDur
                context:@{}
          operationID:opID];
    [opLog logOperation:@"uicache -p destApp"
                  phase:OperationPhaseUICache
                 target:destApp
                 result:uc2 ? OperationResultSuccess : OperationResultFailed
               exitCode:uc2 ? 0 : 1
              rawOutput:@""
               rawError:uc2 ? @"" : @"uicache -p destApp failed"
               duration:0
                context:@{}
          operationID:opID];
    [opLog logOperation:@"uicache -a"
                  phase:OperationPhaseUICache
                 target:@""
                 result:uc3 ? OperationResultSuccess : OperationResultFailed
               exitCode:uc3 ? 0 : 1
              rawOutput:@""
               rawError:uc3 ? @"" : @"uicache -a failed"
               duration:0
                context:@{}
          operationID:opID];

    // [STEP 14] Verify installation
    t0 = [NSDate date];
    BOOL ok = [self verify:destApp bundleID:bundleID exeName:exeName];
    [opLog logOperation:@"verify"
                  phase:OperationPhaseVerify
                 target:destApp
                 result:ok ? OperationResultSuccess : OperationResultFailed
               exitCode:ok ? 0 : 1
              rawOutput:@""
               rawError:ok ? @"" : @"Verification failed"
               duration:[[NSDate date] timeIntervalSinceDate:t0]
                context:@{@"bundleID": bundleID}
          operationID:opID];

    // [STEP 15] Cleanup temp
    [fm removeItemAtPath:tmp error:nil];
    [opLog logOperation:@"removeItemAtPath (temp)"
                  phase:OperationPhaseCleanup
                 target:tmp
                 result:OperationResultSuccess
               exitCode:0
              rawOutput:@""
               rawError:@""
               duration:0
                context:@{}
          operationID:opID];

    // [COMPLETE]
    InstallationResult *res = [InstallationResult successResult:[NSString stringWithFormat:@"Installed %@", appName]];
    res.bundleID = bundleID;
    res.detailedOutput = ok ? @"Verification passed" : @"Verification incomplete - may need reboot";
    [opLog logOperation:@"INSTALL_COMPLETE"
                  phase:OperationPhaseComplete
                 target:bundleID
                 result:OperationResultSuccess
               exitCode:0
              rawOutput:res.detailedOutput
               rawError:@""
               duration:0
                context:@{@"appName": appName, @"destApp": destApp, @"hasHelper": @(hasH)}
          operationID:opID];
    [opLog endTransaction:opID];
    _currentOpID = nil;
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
        if ([self hasRootHelper]) { [self runRoot:self.uicachePath args:@[@"-a"]]; }
        else { [self runCmd:self.uicachePath args:@[@"-a"]]; }
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
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (_currentOpID) {
            [[OperationLog sharedLog] logOperation:[NSString stringWithFormat:@"ldid SKIP (%@)", label]
                                             phase:OperationPhaseSign
                                            target:path
                                            result:OperationResultSkipped
                                          exitCode:0
                                         rawOutput:@""
                                          rawError:@"File does not exist"
                                          duration:0
                                           context:@{@"label": label}
                                     operationID:_currentOpID];
        }
        return;
    }

    NSDate *t0 = [NSDate date];
    if (hasH) [self runRoot:self.chmodPath args:@[@"755", path]];
    else [self runCmd:self.chmodPath args:@[@"755", path]];

    BOOL ok = hasH ? [self runRoot:self.ldidPath args:@[@"-S", path]] : [self runCmd:self.ldidPath args:@[@"-S", path]];
    NSString *signMethod = @"ldid -S";

    if (!ok) {
        NSString *ep = [NSTemporaryDirectory() stringByAppendingPathComponent:@"min.ent"];
        [@{@"get-task-allow":@YES, @"platform-application":@YES} writeToFile:ep atomically:YES];
        NSString *sf = [NSString stringWithFormat:@"-S%@", ep];
        ok = hasH ? [self runRoot:self.ldidPath args:@[sf, path]] : [self runCmd:self.ldidPath args:@[sf, path]];
        signMethod = @"ldid -S<min.ent>";
    }

    NSTimeInterval dur = [[NSDate date] timeIntervalSinceDate:t0];
    NSLog(@"[IPAInstallerPro] %@: %@", ok ? @"✅" : @"⚠️", label);

    if (_currentOpID) {
        [[OperationLog sharedLog] logOperation:[NSString stringWithFormat:@"%@ (%@)", signMethod, label]
                                         phase:OperationPhaseSign
                                        target:path
                                        result:ok ? OperationResultSuccess : OperationResultFailed
                                      exitCode:ok ? 0 : 1
                                     rawOutput:@""
                                      rawError:ok ? @"" : [NSString stringWithFormat:@"ldid failed for %@", label]
                                      duration:dur
                                       context:@{@"label": label}
                                 operationID:_currentOpID];
    }
}

- (NSString *)runCmdOutput:(NSString *)cmd args:(NSArray *)args {
    int pipefd[2];
    if (pipe(pipefd) != 0) return nil;
    pid_t pid;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);
    const char *c = [cmd UTF8String];
    char **argv = malloc((args.count + 2) * sizeof(char*));
    argv[0] = (char*)c;
    for (NSUInteger i = 0; i < args.count; i++) argv[i+1] = (char*)[args[i] UTF8String];
    argv[args.count + 1] = NULL;
    int st = posix_spawn(&pid, c, &actions, NULL, argv, environ);
    free(argv);
    posix_spawn_file_actions_destroy(&actions);
    close(pipefd[1]);
    if (st != 0) { close(pipefd[0]); return nil; }
    NSMutableString *output = [NSMutableString string];
    char buf[4096];
    ssize_t n;
    while ((n = read(pipefd[0], buf, sizeof(buf) - 1)) > 0) { buf[n] = '\0'; [output appendString:[NSString stringWithUTF8String:buf]]; }
    close(pipefd[0]);
    waitpid(pid, NULL, 0);
    return output;
}

- (void)signExe:(NSString *)path hasHelper:(BOOL)hasH {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (_currentOpID) {
            [[OperationLog sharedLog] logOperation:@"ldid SKIP (main exe)"
                                             phase:OperationPhaseSign
                                            target:path
                                            result:OperationResultSkipped
                                          exitCode:0
                                         rawOutput:@""
                                          rawError:@"Main executable does not exist"
                                          duration:0
                                           context:@{}
                                     operationID:_currentOpID];
        }
        return;
    }

    NSDate *t0 = [NSDate date];
    NSString *ep = [NSTemporaryDirectory() stringByAppendingPathComponent:@"orig.ent"];
    BOOL ok = NO;
    NSString *signMethod = @"";

    // Try to extract original entitlements via pipe
    NSString *entOutput = hasH ? [self runRootCmdOutput:self.ldidPath args:@[@"-e", path]] : [self runCmdOutput:self.ldidPath args:@[@"-e", path]];
    if (entOutput && entOutput.length > 10) {
        [entOutput writeToFile:ep atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *sf = [NSString stringWithFormat:@"-S%@", ep];
        ok = hasH ? [self runRoot:self.ldidPath args:@[sf, path]] : [self runCmd:self.ldidPath args:@[sf, path]];
        signMethod = @"ldid -S<orig.ent>";
    }

    if (!ok) {
        ok = hasH ? [self runRoot:self.ldidPath args:@[@"-S", path]] : [self runCmd:self.ldidPath args:@[@"-S", path]];
        signMethod = @"ldid -S";
    }
    if (!ok) {
        NSString *ep2 = [NSTemporaryDirectory() stringByAppendingPathComponent:@"min.ent"];
        [@{@"get-task-allow":@YES, @"platform-application":@YES} writeToFile:ep2 atomically:YES];
        NSString *sf = [NSString stringWithFormat:@"-S%@", ep2];
        ok = hasH ? [self runRoot:self.ldidPath args:@[sf, path]] : [self runCmd:self.ldidPath args:@[sf, path]];
        signMethod = @"ldid -S<min.ent>";
    }

    NSTimeInterval dur = [[NSDate date] timeIntervalSinceDate:t0];
    NSLog(@"[IPAInstallerPro] Main exe sign: %@", ok ? @"OK" : @"⚠️");

    if (_currentOpID) {
        [[OperationLog sharedLog] logOperation:[NSString stringWithFormat:@"%@ (main exe)", signMethod]
                                         phase:OperationPhaseSign
                                        target:path
                                        result:ok ? OperationResultSuccess : OperationResultFailed
                                      exitCode:ok ? 0 : 1
                                     rawOutput:entOutput ?: @""
                                      rawError:ok ? @"" : @"All ldid attempts failed"
                                      duration:dur
                                       context:@{@"hadEntitlements": @(entOutput.length > 10)}
                                 operationID:_currentOpID];
    }
}

- (NSString *)runRootCmdOutput:(NSString *)cmd args:(NSArray *)args {
    if (![self hasRootHelper]) return [self runCmdOutput:cmd args:args];
    int pipefd[2];
    if (pipe(pipefd) != 0) return nil;
    pid_t pid;
    const char *h = [self.helperPath UTF8String];
    const char *c = [cmd UTF8String];
    char **argv = malloc((args.count + 3) * sizeof(char*));
    argv[0] = (char*)h; argv[1] = (char*)c;
    for (NSUInteger i = 0; i < args.count; i++) argv[i+2] = (char*)[args[i] UTF8String];
    argv[args.count + 2] = NULL;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);
    int st = posix_spawn(&pid, h, &actions, NULL, argv, environ);
    free(argv);
    posix_spawn_file_actions_destroy(&actions);
    close(pipefd[1]);
    if (st != 0) { close(pipefd[0]); return nil; }
    NSMutableString *output = [NSMutableString string];
    char buf[4096];
    ssize_t n;
    while ((n = read(pipefd[0], buf, sizeof(buf) - 1)) > 0) { buf[n] = '\0'; [output appendString:[NSString stringWithUTF8String:buf]]; }
    close(pipefd[0]);
    waitpid(pid, NULL, 0);
    return output;
}

- (void)fixFrameworks:(NSString *)appPath hasHelper:(BOOL)hasH {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *fw = [appPath stringByAppendingPathComponent:@"Frameworks"];
    if (![fm fileExistsAtPath:fw]) {
        if (_currentOpID) {
            [[OperationLog sharedLog] logOperation:@"Frameworks folder check"
                                             phase:OperationPhaseFramework
                                            target:fw
                                            result:OperationResultSkipped
                                          exitCode:0
                                         rawOutput:@"No Frameworks folder"
                                          rawError:@""
                                          duration:0
                                           context:@{}
                                     operationID:_currentOpID];
        }
        return;
    }

    if (_currentOpID) {
        [[OperationLog sharedLog] logOperation:@"Frameworks folder found"
                                         phase:OperationPhaseFramework
                                        target:fw
                                        result:OperationResultSuccess
                                      exitCode:0
                                     rawOutput:@""
                                      rawError:@""
                                      duration:0
                                       context:@{}
                                 operationID:_currentOpID];
    }

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
    BOOL exeExists = [fm fileExistsAtPath:ep];
    BOOL exeReadable = [fm isReadableFileAtPath:ep];
    if (!exeExists) { NSLog(@"❌ exe missing"); ok = NO; }
    else if (!exeReadable) { NSLog(@"❌ exe unreadable"); ok = NO; }
    else NSLog(@"✅ exe OK");

    if (_currentOpID) {
        [[OperationLog sharedLog] logOperation:@"verify executable"
                                         phase:OperationPhaseVerify
                                        target:ep
                                        result:(exeExists && exeReadable) ? OperationResultSuccess : OperationResultFailed
                                      exitCode:(exeExists && exeReadable) ? 0 : 1
                                     rawOutput:@""
                                      rawError:(exeExists && exeReadable) ? @"" : @"Executable missing or unreadable"
                                      duration:0
                                       context:@{@"exists": @(exeExists), @"readable": @(exeReadable)}
                                 operationID:_currentOpID];
    }

    NSString *ip = [appPath stringByAppendingPathComponent:@"Info.plist"];
    BOOL infoExists = [fm fileExistsAtPath:ip];
    if (!infoExists) { NSLog(@"❌ Info.plist missing"); ok = NO; }
    else NSLog(@"✅ Info.plist OK");

    if (_currentOpID) {
        [[OperationLog sharedLog] logOperation:@"verify Info.plist"
                                         phase:OperationPhaseVerify
                                        target:ip
                                        result:infoExists ? OperationResultSuccess : OperationResultFailed
                                      exitCode:infoExists ? 0 : 1
                                     rawOutput:@""
                                      rawError:infoExists ? @"" : @"Info.plist missing"
                                      duration:0
                                       context:@{}
                                 operationID:_currentOpID];
    }

    NSString *fwp = [appPath stringByAppendingPathComponent:@"Frameworks"];
    if ([fm fileExistsAtPath:fwp]) {
        for (NSString *item in [fm contentsOfDirectoryAtPath:fwp error:nil]) {
            NSString *p = [fwp stringByAppendingPathComponent:item];
            if ([item hasSuffix:@".dylib"] || [item hasSuffix:@".so"]) {
                BOOL dylibReadable = [fm isReadableFileAtPath:p];
                if (!dylibReadable) { NSLog(@"❌ %@ unreadable", item); ok = NO; }
                else NSLog(@"✅ %@ OK", item);

                if (_currentOpID) {
                    [[OperationLog sharedLog] logOperation:@"verify dylib"
                                                     phase:OperationPhaseVerify
                                                    target:p
                                                    result:dylibReadable ? OperationResultSuccess : OperationResultFailed
                                                  exitCode:dylibReadable ? 0 : 1
                                                 rawOutput:@""
                                                  rawError:dylibReadable ? @"" : @"Dylib unreadable"
                                                  duration:0
                                                   context:@{@"item": item}
                                             operationID:_currentOpID];
                }
            }
        }
    }

    Class LS = objc_getClass("LSApplicationWorkspace");
    if (LS) {
        id ws = [LS performSelector:@selector(defaultWorkspace)];
        if ([ws respondsToSelector:@selector(applicationForIdentifier:)]) {
            id a = [ws performSelector:@selector(applicationForIdentifier:) withObject:bid];
            BOOL registered = (a != nil);
            NSLog(@"%@", registered ? @"✅ Registered" : @"⚠️ Not registered yet");

            if (_currentOpID) {
                [[OperationLog sharedLog] logOperation:@"LSApplicationWorkspace registration check"
                                                 phase:OperationPhaseVerify
                                                target:bid
                                                result:registered ? OperationResultSuccess : OperationResultFailed
                                              exitCode:registered ? 0 : 1
                                             rawOutput:@""
                                              rawError:registered ? @"" : @"App not registered in LSApplicationWorkspace"
                                              duration:0
                                               context:@{}
                                         operationID:_currentOpID];
            }
        }
    }
    return ok;
}

@end
