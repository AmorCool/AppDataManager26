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

static NSString *_currentTxnID = nil;

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
    OperationLog *opLog = [OperationLog sharedLog];
    NSString *txnID = [opLog beginTransactionForIPA:ipaPath];
    _currentTxnID = txnID;
    NSLog(@"[IPAInstallerPro] Install: %@ | Txn: %@", ipaPath, txnID);

    // ───────────────────────────────────────────────
    // PHASE 1: Verify IPA file exists
    // ───────────────────────────────────────────────
    NSString *rec1 = [opLog beginPhase:OperationPhaseIPAOpen
                             operation:@"fileExistsAtPath"
                                target:ipaPath
                                 input:ipaPath
                         transactionID:txnID];
    NSDate *t0 = [NSDate date];
    BOOL ipaExists = [fm fileExistsAtPath:ipaPath];
    NSDictionary *ipaAttrs = ipaExists ? [fm attributesOfItemAtPath:ipaPath error:nil] : nil;
    BOOL ipaReadable = ipaExists ? [fm isReadableFileAtPath:ipaPath] : NO;
    NSTimeInterval dur1 = [[NSDate date] timeIntervalSinceDate:t0];

    [opLog endPhase:rec1
            exitCode:ipaExists ? 0 : ENOENT
           rawOutput:@""
            rawError:ipaExists ? @"" : @"IPA file not found"
        verification:[NSString stringWithFormat:@"exists=%@ readable=%@ size=%lld",
                      ipaExists ? @"YES" : @"NO",
                      ipaReadable ? @"YES" : @"NO",
                      ipaAttrs ? ipaAttrs.fileSize : 0]
            verified:(ipaExists && ipaReadable)
            duration:dur1];

    if (!ipaExists || !ipaReadable) {
        [opLog endTransaction:txnID finalResult:OperationResultFailed];
        _currentTxnID = nil;
        if (completion) completion([InstallationResult failureResult:@"IPA not found or unreadable" error:nil]);
        return;
    }

    // ───────────────────────────────────────────────
    // PHASE 2: Create temp directory
    // ───────────────────────────────────────────────
    NSString *rec2 = [opLog beginPhase:OperationPhaseIPAExtract
                             operation:@"createDirectoryAtPath"
                                target:NSTemporaryDirectory()
                                 input:@""
                         transactionID:txnID];
    t0 = [NSDate date];
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    BOOL tmpCreated = [fm createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:nil];
    NSTimeInterval dur2 = [[NSDate date] timeIntervalSinceDate:t0];
    BOOL tmpVerified = tmpCreated && [fm fileExistsAtPath:tmp];

    [opLog endPhase:rec2
            exitCode:tmpCreated ? 0 : 1
           rawOutput:@""
            rawError:tmpCreated ? @"" : @"Failed to create temp directory"
        verification:[NSString stringWithFormat:@"created=%@ exists=%@", tmpCreated ? @"YES" : @"NO", tmpVerified ? @"YES" : @"NO"]
            verified:tmpVerified
            duration:dur2];

    if (!tmpVerified) {
        [opLog endTransaction:txnID finalResult:OperationResultFailed];
        _currentTxnID = nil;
        if (completion) completion([InstallationResult failureResult:@"Temp directory creation failed" error:nil]);
        return;
    }

    // ───────────────────────────────────────────────
    // PHASE 3: Unzip IPA
    // ───────────────────────────────────────────────
    NSString *rec3 = [opLog beginPhase:OperationPhaseIPAExtract
                             operation:@"unzip"
                                target:ipaPath
                                 input:[@[@"-o", ipaPath, @"-d", tmp] componentsJoinedByString:@" "]
                         transactionID:txnID];
    t0 = [NSDate date];
    BOOL unzipOk = [self runCmd:self.unzipPath args:@[@"-o", ipaPath, @"-d", tmp]];
    NSTimeInterval dur3 = [[NSDate date] timeIntervalSinceDate:t0];
    // Verify: Payload folder must exist
    NSString *payload = [tmp stringByAppendingPathComponent:@"Payload"];
    BOOL payloadExists = [fm fileExistsAtPath:payload];

    [opLog endPhase:rec3
            exitCode:unzipOk ? 0 : 1
           rawOutput:@""
            rawError:unzipOk ? @"" : @"unzip returned non-zero"
        verification:[NSString stringWithFormat:@"Payload exists=%@", payloadExists ? @"YES" : @"NO"]
            verified:(unzipOk && payloadExists)
            duration:dur3];

    if (!unzipOk || !payloadExists) {
        [fm removeItemAtPath:tmp error:nil];
        [opLog endTransaction:txnID finalResult:OperationResultFailed];
        _currentTxnID = nil;
        if (completion) completion([InstallationResult failureResult:@"Unzip failed" error:nil]);
        return;
    }

    // ───────────────────────────────────────────────
    // PHASE 4: Find .app in Payload
    // ───────────────────────────────────────────────
    NSString *rec4 = [opLog beginPhase:OperationPhaseAppIdentify
                             operation:@"find .app in Payload"
                                target:payload
                                 input:@""
                         transactionID:txnID];
    t0 = [NSDate date];
    NSArray *items = [fm contentsOfDirectoryAtPath:payload error:nil];
    NSString *appFolder = nil;
    for (NSString *i in items) { if ([i hasSuffix:@".app"]) { appFolder = i; break; } }
    NSTimeInterval dur4 = [[NSDate date] timeIntervalSinceDate:t0];
    BOOL appFound = (appFolder != nil);

    [opLog endPhase:rec4
            exitCode:appFound ? 0 : 1
           rawOutput:@""
            rawError:appFound ? @"" : @"No .app folder found in Payload"
        verification:[NSString stringWithFormat:@"found=%@ name=%@", appFound ? @"YES" : @"NO", appFolder ?: @"N/A"]
            verified:appFound
            duration:dur4];

    if (!appFound) {
        [fm removeItemAtPath:tmp error:nil];
        [opLog endTransaction:txnID finalResult:OperationResultFailed];
        _currentTxnID = nil;
        if (completion) completion([InstallationResult failureResult:@"No .app found" error:nil]);
        return;
    }

    // ───────────────────────────────────────────────
    // PHASE 5: Read Info.plist
    // ───────────────────────────────────────────────
    NSString *srcApp = [payload stringByAppendingPathComponent:appFolder];
    NSString *infoPath = [srcApp stringByAppendingPathComponent:@"Info.plist"];
    NSString *rec5 = [opLog beginPhase:OperationPhaseAppIdentify
                             operation:@"dictionaryWithContentsOfFile (Info.plist)"
                                target:infoPath
                                 input:@""
                         transactionID:txnID];
    t0 = [NSDate date];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    NSTimeInterval dur5 = [[NSDate date] timeIntervalSinceDate:t0];
    BOOL infoRead = (info != nil);
    BOOL infoHasKeys = infoRead && (info[@"CFBundleIdentifier"] != nil) && (info[@"CFBundleExecutable"] != nil);

    [opLog endPhase:rec5
            exitCode:infoRead ? 0 : 1
           rawOutput:@""
            rawError:infoRead ? @"" : @"Info.plist could not be parsed"
        verification:[NSString stringWithFormat:@"read=%@ hasBundleID=%@ hasExe=%@",
                      infoRead ? @"YES" : @"NO",
                      info[@"CFBundleIdentifier"] ? @"YES" : @"NO",
                      info[@"CFBundleExecutable"] ? @"YES" : @"NO"]
            verified:(infoRead && infoHasKeys)
            duration:dur5];

    if (!infoRead || !infoHasKeys) {
        [fm removeItemAtPath:tmp error:nil];
        [opLog endTransaction:txnID finalResult:OperationResultFailed];
        _currentTxnID = nil;
        if (completion) completion([InstallationResult failureResult:@"Invalid Info.plist" error:nil]);
        return;
    }

    // ───────────────────────────────────────────────
    // PHASE 6: Extract metadata
    // ───────────────────────────────────────────────
    NSString *bundleID = info[@"CFBundleIdentifier"];
    NSString *appName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: appFolder;
    NSString *exeName = info[@"CFBundleExecutable"];
    NSString *rec6 = [opLog beginPhase:OperationPhaseAppIdentify
                             operation:@"extract bundle metadata"
                                target:appFolder
                                 input:@""
                         transactionID:txnID];
    BOOL metaValid = (bundleID.length > 0 && exeName.length > 0);

    [opLog endPhase:rec6
            exitCode:metaValid ? 0 : 1
           rawOutput:@""
            rawError:metaValid ? @"" : @"Missing CFBundleIdentifier or CFBundleExecutable"
        verification:[NSString stringWithFormat:@"bundleID=%@ exeName=%@ appName=%@",
                      bundleID ?: @"N/A", exeName ?: @"N/A", appName]
            verified:metaValid
            duration:0];

    if (!metaValid) {
        [fm removeItemAtPath:tmp error:nil];
        [opLog endTransaction:txnID finalResult:OperationResultFailed];
        _currentTxnID = nil;
        if (completion) completion([InstallationResult failureResult:@"Missing bundleID/exe" error:nil]);
        return;
    }

    // ───────────────────────────────────────────────
    // PHASE 7: Resolve destination path
    // ───────────────────────────────────────────────
    NSString *logicalDest = [@"/Applications" stringByAppendingPathComponent:appFolder];
    NSString *rec7 = [opLog beginPhase:OperationPhaseFileCopy
                             operation:@"resolvePath"
                                target:logicalDest
                                 input:logicalDest
                         transactionID:txnID];
    NSString *destApp = [[RootlessManager sharedManager] resolvePath:logicalDest];
    BOOL destResolved = (destApp != nil && destApp.length > 0);

    [opLog endPhase:rec7
            exitCode:destResolved ? 0 : 1
           rawOutput:destApp ?: @""
            rawError:destResolved ? @"" : @"RootlessManager could not resolve path"
        verification:[NSString stringWithFormat:@"resolved=%@ path=%@", destResolved ? @"YES" : @"NO", destApp ?: @"N/A"]
            verified:destResolved
            duration:0];

    if (!destResolved) {
        [fm removeItemAtPath:tmp error:nil];
        [opLog endTransaction:txnID finalResult:OperationResultFailed];
        _currentTxnID = nil;
        if (completion) completion([InstallationResult failureResult:@"Could not resolve destination path" error:nil]);
        return;
    }

    // ───────────────────────────────────────────────
    // PHASE 8: Delete existing app if present
    // ───────────────────────────────────────────────
    if ([fm fileExistsAtPath:destApp]) {
        NSString *rec8 = [opLog beginPhase:OperationPhaseFileCopy
                                 operation:hasH ? @"rm -rf (root)" : @"removeItemAtPath"
                                    target:destApp
                                     input:@""
                             transactionID:txnID];
        t0 = [NSDate date];
        BOOL deleted;
        if (hasH) {
            deleted = [self runRoot:self.rmPath args:@[@"-rf", destApp]];
        } else {
            deleted = [fm removeItemAtPath:destApp error:nil];
        }
        NSTimeInterval dur8 = [[NSDate date] timeIntervalSinceDate:t0];
        BOOL verifyDeleted = ![fm fileExistsAtPath:destApp];

        [opLog endPhase:rec8
                exitCode:deleted ? 0 : 1
               rawOutput:@""
                rawError:deleted ? @"" : @"Delete command failed"
            verification:[NSString stringWithFormat:@"command=%@ stillExists=%@", deleted ? @"YES" : @"NO", verifyDeleted ? @"NO" : @"YES"]
                verified:verifyDeleted
                duration:dur8];
    } else {
        NSString *rec8 = [opLog beginPhase:OperationPhaseFileCopy
                                 operation:@"check existing"
                                    target:destApp
                                     input:@""
                             transactionID:txnID];
        [opLog endPhase:rec8
                exitCode:0
               rawOutput:@"No existing app at destination"
                rawError:@""
            verification:@"No existing app — nothing to delete"
                verified:YES
                duration:0];
    }

    // ───────────────────────────────────────────────
    // PHASE 9: Copy app bundle
    // ───────────────────────────────────────────────
    NSString *rec9 = [opLog beginPhase:OperationPhaseFileCopy
                             operation:@"copy app bundle"
                                target:[NSString stringWithFormat:@"%@ -> %@", srcApp, destApp]
                                 input:@""
                         transactionID:txnID];
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
        }
    }
    NSTimeInterval dur9 = [[NSDate date] timeIntervalSinceDate:t0];

    // Verification: dest must exist, must contain Info.plist and executable
    BOOL destExists = [fm fileExistsAtPath:destApp];
    NSString *destInfoPath = [destApp stringByAppendingPathComponent:@"Info.plist"];
    BOOL destInfoExists = [fm fileExistsAtPath:destInfoPath];
    NSString *destExePath = [destApp stringByAppendingPathComponent:exeName];
    BOOL destExeExists = [fm fileExistsAtPath:destExePath];

    [opLog endPhase:rec9
            exitCode:copied ? 0 : copyErrno
           rawOutput:@""
            rawError:copied ? @"" : [NSString stringWithFormat:@"%@ failed, errno=%d", copyMethod, copyErrno]
        verification:[NSString stringWithFormat:@"destExists=%@ infoExists=%@ exeExists=%@ method=%@",
                      destExists ? @"YES" : @"NO",
                      destInfoExists ? @"YES" : @"NO",
                      destExeExists ? @"YES" : @"NO",
                      copyMethod]
            verified:(copied && destExists && destInfoExists && destExeExists)
            duration:dur9];

    if (!copied || !destExists || !destInfoExists || !destExeExists) {
        [fm removeItemAtPath:tmp error:nil];
        [opLog endTransaction:txnID finalResult:OperationResultFailed];
        _currentTxnID = nil;
        if (completion) completion([InstallationResult failureResult:@"Copy failed or verification failed" error:nil]);
        return;
    }

    // ───────────────────────────────────────────────
    // PHASE 10: Set permissions (chmod)
    // ───────────────────────────────────────────────
    NSString *rec10a = [opLog beginPhase:OperationPhasePermission
                               operation:@"chmod -R 755"
                                  target:destApp
                                   input:@""
                           transactionID:txnID];
    t0 = [NSDate date];
    BOOL chmodOk = hasH ? [self runRoot:self.chmodPath args:@[@"-R", @"755", destApp]]
                        : [self runCmd:self.chmodPath args:@[@"-R", @"755", destApp]];
    NSTimeInterval dur10a = [[NSDate date] timeIntervalSinceDate:t0];
    // Verify: check executable is readable
    BOOL exeReadableAfterChmod = [fm isReadableFileAtPath:destExePath];

    [opLog endPhase:rec10a
            exitCode:chmodOk ? 0 : 1
           rawOutput:@""
            rawError:chmodOk ? @"" : @"chmod command failed"
        verification:[NSString stringWithFormat:@"command=%@ exeReadable=%@", chmodOk ? @"YES" : @"NO", exeReadableAfterChmod ? @"YES" : @"NO"]
            verified:(chmodOk && exeReadableAfterChmod)
            duration:dur10a];

    // ───────────────────────────────────────────────
    // PHASE 10b: Set ownership (chown)
    // ───────────────────────────────────────────────
    NSString *rec10b = [opLog beginPhase:OperationPhasePermission
                               operation:@"chown -R root:wheel"
                                  target:destApp
                                   input:@""
                           transactionID:txnID];
    t0 = [NSDate date];
    BOOL chownOk = hasH ? [self runRoot:self.chownPath args:@[@"-R", @"root:wheel", destApp]]
                        : [self runCmd:self.chownPath args:@[@"-R", @"root:wheel", destApp]];
    NSTimeInterval dur10b = [[NSDate date] timeIntervalSinceDate:t0];
    // Verify: check we can still read
    BOOL exeReadableAfterChown = [fm isReadableFileAtPath:destExePath];

    [opLog endPhase:rec10b
            exitCode:chownOk ? 0 : 1
           rawOutput:@""
            rawError:chownOk ? @"" : @"chown command failed"
        verification:[NSString stringWithFormat:@"command=%@ exeReadable=%@", chownOk ? @"YES" : @"NO", exeReadableAfterChown ? @"YES" : @"NO"]
            verified:(chownOk && exeReadableAfterChown)
            duration:dur10b];

    // ───────────────────────────────────────────────
    // PHASE 11: Sign all binaries recursively
    // ───────────────────────────────────────────────
    NSString *rec11 = [opLog beginPhase:OperationPhaseSign
                              operation:@"signAllAt (recursive)"
                                 target:destApp
                                  input:@""
                          transactionID:txnID];
    t0 = [NSDate date];
    [self signAllAt:destApp hasHelper:hasH];
    NSTimeInterval dur11 = [[NSDate date] timeIntervalSinceDate:t0];
    // Verify: check main executable is still readable after signing
    BOOL exeReadableAfterSignAll = [fm isReadableFileAtPath:destExePath];

    [opLog endPhase:rec11
            exitCode:0
           rawOutput:@""
            rawError:@""
        verification:[NSString stringWithFormat:@"exeReadable=%@", exeReadableAfterSignAll ? @"YES" : @"NO"]
            verified:exeReadableAfterSignAll
            duration:dur11];

    // ───────────────────────────────────────────────
    // PHASE 12: Sign main executable
    // ───────────────────────────────────────────────
    NSString *exePath = [destApp stringByAppendingPathComponent:exeName];
    NSString *rec12 = [opLog beginPhase:OperationPhaseSign
                              operation:@"signExe (main executable)"
                                 target:exePath
                                  input:@""
                          transactionID:txnID];
    t0 = [NSDate date];
    [self signExe:exePath hasHelper:hasH];
    NSTimeInterval dur12 = [[NSDate date] timeIntervalSinceDate:t0];
    // Verify: executable must exist and be readable
    BOOL exeExistsAfterSign = [fm fileExistsAtPath:exePath];
    BOOL exeReadableAfterSign = [fm isReadableFileAtPath:exePath];

    [opLog endPhase:rec12
            exitCode:0
           rawOutput:@""
            rawError:@""
        verification:[NSString stringWithFormat:@"exeExists=%@ exeReadable=%@", exeExistsAfterSign ? @"YES" : @"NO", exeReadableAfterSign ? @"YES" : @"NO"]
            verified:(exeExistsAfterSign && exeReadableAfterSign)
            duration:dur12];

    // ───────────────────────────────────────────────
    // PHASE 13: Fix frameworks
    // ───────────────────────────────────────────────
    NSString *rec13 = [opLog beginPhase:OperationPhaseFramework
                              operation:@"fixFrameworks"
                                 target:destApp
                                  input:@""
                          transactionID:txnID];
    t0 = [NSDate date];
    [self fixFrameworks:destApp hasHelper:hasH];
    NSTimeInterval dur13 = [[NSDate date] timeIntervalSinceDate:t0];
    // Verify: if Frameworks folder exists, check dylibs are readable
    NSString *fwPath = [destApp stringByAppendingPathComponent:@"Frameworks"];
    BOOL fwVerified = YES;
    NSString *fwVerifyDetail = @"No Frameworks folder";
    if ([fm fileExistsAtPath:fwPath]) {
        NSMutableString *detail = [NSMutableString string];
        for (NSString *item in [fm contentsOfDirectoryAtPath:fwPath error:nil]) {
            if ([item hasSuffix:@".dylib"]) {
                NSString *dp = [fwPath stringByAppendingPathComponent:item];
                BOOL readable = [fm isReadableFileAtPath:dp];
                [detail appendFormat:@"%@=%@ ", item, readable ? @"OK" : @"FAIL"];
                if (!readable) fwVerified = NO;
            }
        }
        fwVerifyDetail = detail.length > 0 ? detail : @"Frameworks folder empty";
    }

    [opLog endPhase:rec13
            exitCode:0
           rawOutput:@""
            rawError:@""
        verification:fwVerifyDetail
            verified:fwVerified
            duration:dur13];

    // ───────────────────────────────────────────────
    // PHASE 14: Run uicache
    // ───────────────────────────────────────────────
    NSString *rec14a = [opLog beginPhase:OperationPhaseUICache
                               operation:@"uicache -p logicalDest"
                                  target:logicalDest
                                   input:@""
                           transactionID:txnID];
    t0 = [NSDate date];
    BOOL uc1 = hasH ? [self runRoot:self.uicachePath args:@[@"-p", logicalDest]]
                    : [self runCmd:self.uicachePath args:@[@"-p", logicalDest]];
    NSTimeInterval dur14a = [[NSDate date] timeIntervalSinceDate:t0];

    [opLog endPhase:rec14a
            exitCode:uc1 ? 0 : 1
           rawOutput:@""
            rawError:uc1 ? @"" : @"uicache -p logicalDest failed"
        verification:[NSString stringWithFormat:@"command=%@", uc1 ? @"YES" : @"NO"]
            verified:uc1
            duration:dur14a];

    NSString *rec14b = [opLog beginPhase:OperationPhaseUICache
                               operation:@"uicache -p destApp"
                                  target:destApp
                                   input:@""
                           transactionID:txnID];
    t0 = [NSDate date];
    BOOL uc2 = hasH ? [self runRoot:self.uicachePath args:@[@"-p", destApp]]
                    : [self runCmd:self.uicachePath args:@[@"-p", destApp]];
    NSTimeInterval dur14b = [[NSDate date] timeIntervalSinceDate:t0];

    [opLog endPhase:rec14b
            exitCode:uc2 ? 0 : 1
           rawOutput:@""
            rawError:uc2 ? @"" : @"uicache -p destApp failed"
        verification:[NSString stringWithFormat:@"command=%@", uc2 ? @"YES" : @"NO"]
            verified:uc2
            duration:dur14b];

    NSString *rec14c = [opLog beginPhase:OperationPhaseUICache
                               operation:@"uicache -a"
                                  target:@""
                                   input:@""
                           transactionID:txnID];
    t0 = [NSDate date];
    BOOL uc3 = hasH ? [self runRoot:self.uicachePath args:@[@"-a"]]
                    : [self runCmd:self.uicachePath args:@[@"-a"]];
    NSTimeInterval dur14c = [[NSDate date] timeIntervalSinceDate:t0];

    [opLog endPhase:rec14c
            exitCode:uc3 ? 0 : 1
           rawOutput:@""
            rawError:uc3 ? @"" : @"uicache -a failed"
        verification:[NSString stringWithFormat:@"command=%@", uc3 ? @"YES" : @"NO"]
            verified:uc3
            duration:dur14c];

    // ───────────────────────────────────────────────
    // PHASE 15: Post-install verification
    // ───────────────────────────────────────────────
    NSString *rec15 = [opLog beginPhase:OperationPhaseVerify
                              operation:@"verify"
                                 target:destApp
                                  input:bundleID
                          transactionID:txnID];
    t0 = [NSDate date];
    BOOL ok = [self verify:destApp bundleID:bundleID exeName:exeName];
    NSTimeInterval dur15 = [[NSDate date] timeIntervalSinceDate:t0];

    [opLog endPhase:rec15
            exitCode:ok ? 0 : 1
           rawOutput:@""
            rawError:ok ? @"" : @"Verification reported failures"
        verification:[NSString stringWithFormat:@"verify returned %@", ok ? @"YES" : @"NO"]
            verified:ok
            duration:dur15];

    // ───────────────────────────────────────────────
    // PHASE 16: Cleanup temp
    // ───────────────────────────────────────────────
    NSString *rec16 = [opLog beginPhase:OperationPhaseCleanup
                              operation:@"removeItemAtPath (temp)"
                                 target:tmp
                                  input:@""
                          transactionID:txnID];
    [fm removeItemAtPath:tmp error:nil];
    BOOL tmpRemoved = ![fm fileExistsAtPath:tmp];

    [opLog endPhase:rec16
            exitCode:tmpRemoved ? 0 : 1
           rawOutput:@""
            rawError:tmpRemoved ? @"" : @"Temp directory still exists"
        verification:[NSString stringWithFormat:@"removed=%@", tmpRemoved ? @"YES" : @"NO"]
            verified:tmpRemoved
            duration:0];

    // ───────────────────────────────────────────────
    // FINAL: Determine overall result
    // ───────────────────────────────────────────────
    BOOL hasFailures = [opLog transactionHasFailures:txnID];
    OperationResult finalResult = hasFailures ? OperationResultPartial : OperationResultSuccess;

    InstallationResult *res = [InstallationResult successResult:[NSString stringWithFormat:@"Installed %@", appName]];
    res.bundleID = bundleID;
    res.detailedOutput = hasFailures ? @"Installation completed with warnings — review audit trail" : @"Verification passed";

    [opLog endTransaction:txnID finalResult:finalResult];
    _currentTxnID = nil;
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
        if (_currentTxnID) {
            NSString *rec = [[OperationLog sharedLog] beginPhase:OperationPhaseSign
                                                        operation:[NSString stringWithFormat:@"ldid SKIP (%@)", label]
                                                           target:path
                                                            input:@""
                                                    transactionID:_currentTxnID];
            [[OperationLog sharedLog] endPhase:rec
                                        exitCode:0
                                       rawOutput:@""
                                        rawError:@"File does not exist"
                                    verification:@"File missing — skipped"
                                        verified:YES
                                        duration:0];
        }
        return;
    }

    NSString *rec = nil;
    if (_currentTxnID) {
        rec = [[OperationLog sharedLog] beginPhase:OperationPhaseSign
                                          operation:[NSString stringWithFormat:@"ldid -S (%@)", label]
                                             target:path
                                              input:@""
                                      transactionID:_currentTxnID];
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
    // Verify: file must still exist and be readable after signing
    BOOL stillExists = [[NSFileManager defaultManager] fileExistsAtPath:path];
    BOOL stillReadable = [[NSFileManager defaultManager] isReadableFileAtPath:path];

    NSLog(@"[IPAInstallerPro] %@: %@", ok ? @"✅" : @"⚠️", label);

    if (rec) {
        [[OperationLog sharedLog] endPhase:rec
                                    exitCode:ok ? 0 : 1
                                   rawOutput:@""
                                    rawError:ok ? @"" : [NSString stringWithFormat:@"%@ failed for %@", signMethod, label]
                                verification:[NSString stringWithFormat:@"exists=%@ readable=%@", stillExists ? @"YES" : @"NO", stillReadable ? @"YES" : @"NO"]
                                    verified:(ok && stillExists && stillReadable)
                                    duration:dur];
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
        if (_currentTxnID) {
            NSString *rec = [[OperationLog sharedLog] beginPhase:OperationPhaseSign
                                                        operation:@"ldid SKIP (main exe)"
                                                           target:path
                                                            input:@""
                                                    transactionID:_currentTxnID];
            [[OperationLog sharedLog] endPhase:rec
                                        exitCode:0
                                       rawOutput:@""
                                        rawError:@"Main executable does not exist"
                                    verification:@"File missing — skipped"
                                        verified:YES
                                        duration:0];
        }
        return;
    }

    NSString *rec = nil;
    if (_currentTxnID) {
        rec = [[OperationLog sharedLog] beginPhase:OperationPhaseSign
                                          operation:@"signExe (main executable)"
                                             target:path
                                              input:@""
                                      transactionID:_currentTxnID];
    }

    NSDate *t0 = [NSDate date];
    NSString *ep = [NSTemporaryDirectory() stringByAppendingPathComponent:@"orig.ent"];
    BOOL ok = NO;
    NSString *signMethod = @"";

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
    // Verify: file must exist and be readable
    BOOL stillExists = [[NSFileManager defaultManager] fileExistsAtPath:path];
    BOOL stillReadable = [[NSFileManager defaultManager] isReadableFileAtPath:path];

    NSLog(@"[IPAInstallerPro] Main exe sign: %@", ok ? @"OK" : @"⚠️");

    if (rec) {
        [[OperationLog sharedLog] endPhase:rec
                                    exitCode:ok ? 0 : 1
                                   rawOutput:entOutput ?: @""
                                    rawError:ok ? @"" : @"All ldid attempts failed"
                                verification:[NSString stringWithFormat:@"exists=%@ readable=%@ method=%@", stillExists ? @"YES" : @"NO", stillReadable ? @"YES" : @"NO", signMethod]
                                    verified:(ok && stillExists && stillReadable)
                                    duration:dur];
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
        if (_currentTxnID) {
            NSString *rec = [[OperationLog sharedLog] beginPhase:OperationPhaseFramework
                                                        operation:@"Frameworks check"
                                                           target:fw
                                                            input:@""
                                                    transactionID:_currentTxnID];
            [[OperationLog sharedLog] endPhase:rec
                                        exitCode:0
                                       rawOutput:@"No Frameworks folder"
                                        rawError:@""
                                    verification:@"No Frameworks folder — nothing to process"
                                        verified:YES
                                        duration:0];
        }
        return;
    }

    if (_currentTxnID) {
        NSString *rec = [[OperationLog sharedLog] beginPhase:OperationPhaseFramework
                                                    operation:@"Frameworks found"
                                                       target:fw
                                                        input:@""
                                                transactionID:_currentTxnID];
        [[OperationLog sharedLog] endPhase:rec
                                    exitCode:0
                                   rawOutput:@""
                                    rawError:@""
                                verification:@"Frameworks folder exists"
                                    verified:YES
                                    duration:0];
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

    NSString *ip = [appPath stringByAppendingPathComponent:@"Info.plist"];
    BOOL infoExists = [fm fileExistsAtPath:ip];
    if (!infoExists) { NSLog(@"❌ Info.plist missing"); ok = NO; }
    else NSLog(@"✅ Info.plist OK");

    NSString *fwp = [appPath stringByAppendingPathComponent:@"Frameworks"];
    if ([fm fileExistsAtPath:fwp]) {
        for (NSString *item in [fm contentsOfDirectoryAtPath:fwp error:nil]) {
            NSString *p = [fwp stringByAppendingPathComponent:item];
            if ([item hasSuffix:@".dylib"] || [item hasSuffix:@".so"]) {
                BOOL dylibReadable = [fm isReadableFileAtPath:p];
                if (!dylibReadable) { NSLog(@"❌ %@ unreadable", item); ok = NO; }
                else NSLog(@"✅ %@ OK", item);
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
        }
    }
    return ok;
}

@end
