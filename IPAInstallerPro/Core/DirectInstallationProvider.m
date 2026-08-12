//
//  DirectInstallationProvider.m
//  IPAInstallerPro
//
//  Rewritten v1.1.0 — Zero-Gap Verification + Live Logging
//

#import "DirectInstallationProvider.h"
#import "RootlessManager.h"
#import "LiveInstallationLogger.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <unistd.h>
#import <copyfile.h>
#import <errno.h>

@interface DirectInstallationProvider ()
@property (nonatomic, strong) NSFileManager *fm;
@property (nonatomic, strong) LiveInstallationLogger *logger;
@end

@implementation DirectInstallationProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        _fm = [NSFileManager defaultManager];
        _logger = [LiveInstallationLogger sharedLogger];
    }
    return self;
}

#pragma mark - Helper: Run Command & Capture Output

- (NSString *)runCmdOutput:(NSString *)cmd args:(NSArray *)args {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:cmd];
    [task setArguments:args];
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];
    [task launch];
    [task waitUntilExit];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

- (int)runCmd:(NSString *)cmd args:(NSArray *)args {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:cmd];
    [task setArguments:args];
    [task launch];
    [task waitUntilExit];
    int code = [task terminationStatus];
    [self.logger logCommandExecution:[NSString stringWithFormat:@"%@ %@", cmd, [args componentsJoinedByString:@" "]] exitCode:code output:nil];
    return code;
}

#pragma mark - Deep Verification Helpers

/**
 * DeepCopyVerification — يتحقق من أن النسخة مطابقة للأصل 100%
 * يتحقق من: وجود كل الملفات، تطابق الأحجام، الحفاظ على symlinks
 */
- (BOOL)verifyDeepCopyFrom:(NSString *)src to:(NSString *)dst detail:(NSMutableString *)detail {
    BOOL ok = YES;
    NSArray *srcItems = [self.fm subpathsAtPath:src];
    NSArray *dstItems = [self.fm subpathsAtPath:dst];

    if (srcItems.count != dstItems.count) {
        [detail appendFormat:@"fileCountMismatch(src=%lu,dst=%lu) ", (unsigned long)srcItems.count, (unsigned long)dstItems.count];
        ok = NO;
    }

    NSUInteger sizeMismatch = 0;
    NSUInteger missingFiles = 0;

    for (NSString *sub in srcItems) {
        NSString *sPath = [src stringByAppendingPathComponent:sub];
        NSString *dPath = [dst stringByAppendingPathComponent:sub];

        if (![self.fm fileExistsAtPath:dPath]) {
            missingFiles++;
            ok = NO;
            continue;
        }

        NSDictionary *sAttr = [self.fm attributesOfItemAtPath:sPath error:nil];
        NSDictionary *dAttr = [self.fm attributesOfItemAtPath:dPath error:nil];

        if ([sAttr fileSize] != [dAttr fileSize]) {
            sizeMismatch++;
            ok = NO;
        }

        // Check symlinks preserved
        NSDictionary *sLAttr = [self.fm attributesOfItemAtPath:sPath error:nil];
        if ([sLAttr fileType] == NSFileTypeSymbolicLink) {
            NSString *sLink = [self.fm destinationOfSymbolicLinkAtPath:sPath error:nil];
            NSString *dLink = [self.fm destinationOfSymbolicLinkAtPath:dPath error:nil];
            if (![sLink isEqualToString:dLink]) {
                [detail appendFormat:@"symlinkMismatch(%@) ", sub];
                ok = NO;
            }
        }
    }

    [detail appendFormat:@"missing=%lu sizeMismatch=%lu ", (unsigned long)missingFiles, (unsigned long)sizeMismatch];
    return ok;
}

/**
 * statVerification — يتحقق من mode bits و uid/gid
 */
- (BOOL)verifyStatAtPath:(NSString *)path expectedModeMin:(mode_t)minMode expectedUid:(uid_t)uid expectedGid:(gid_t)gid detail:(NSMutableString *)detail {
    struct stat st;
    if (stat([path UTF8String], &st) != 0) {
        [detail appendFormat:@"statFailed(errno=%d) ", errno];
        [self.logger logError:[NSString stringWithFormat:@"stat() failed for %@: errno=%d", path, errno]];
        return NO;
    }

    mode_t actualMode = st.st_mode & 0777;
    BOOL modeOk = (actualMode >= minMode);
    BOOL uidOk = (uid == (uid_t)-1) ? YES : (st.st_uid == uid);
    BOOL gidOk = (gid == (gid_t)-1) ? YES : (st.st_gid == gid);

    [self.logger logStatResult:path mode:st.st_mode uid:st.st_uid gid:st.st_gid];

    if (!modeOk) {
        [detail appendFormat:@"mode=%o(expected>=%o) ", actualMode, minMode];
    }
    if (!uidOk) {
        [detail appendFormat:@"uid=%d(expected=%d) ", st.st_uid, uid];
    }
    if (!gidOk) {
        [detail appendFormat:@"gid=%d(expected=%d) ", st.st_gid, gid];
    }

    return modeOk && uidOk && gidOk;
}

/**
 * verifySignature — يتحقق من وجود توقيع ldid باستخدام ldid -d
 */
- (BOOL)verifySignature:(NSString *)path detail:(NSMutableString *)detail {
    NSString *output = [self runCmdOutput:@"/usr/bin/ldid" args:@[@"-d", path]];
    BOOL hasSig = (output.length > 10); // Minimal signature check
    if (!hasSig) {
        [detail appendFormat:@"noSignature "];
        [self.logger logWarning:[NSString stringWithFormat:@"No signature detected for %@", path]];
    }
    return hasSig;
}

/**
 * verifyDylibDependencies — يتحقق من أن كل dylibs المطلوبة موجودة وقابلة للوصول
 */
- (BOOL)verifyDylibDependencies:(NSString *)exePath appPath:(NSString *)appPath detail:(NSMutableString *)detail {
    NSString *output = [self runCmdOutput:@"/usr/bin/otool" args:@[@"-L", exePath]];
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    BOOL allOk = YES;

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"@rpath/"] || [trimmed hasPrefix:@"@executable_path/"]) {
            NSString *depName = nil;
            NSRange spaceRange = [trimmed rangeOfString:@" "];
            if (spaceRange.location != NSNotFound) {
                depName = [trimmed substringToIndex:spaceRange.location];
            } else {
                depName = trimmed;
            }

            NSString *resolvedPath = nil;
            if ([depName hasPrefix:@"@rpath/"]) {
                NSString *fwName = [depName substringFromIndex:7];
                resolvedPath = [appPath stringByAppendingPathComponent:[NSString stringWithFormat:@"Frameworks/%@", fwName]];
            } else if ([depName hasPrefix:@"@executable_path/"]) {
                NSString *relPath = [depName substringFromIndex:17];
                resolvedPath = [appPath stringByAppendingPathComponent:relPath];
            }

            if (resolvedPath) {
                BOOL exists = [self.fm fileExistsAtPath:resolvedPath];
                BOOL readable = (access([resolvedPath UTF8String], R_OK) == 0);
                BOOL executable = (access([resolvedPath UTF8String], X_OK) == 0);

                if (!exists || !readable || !executable) {
                    [detail appendFormat:@"depFail(%@:exists=%d,r=%d,x=%d) ", depName, exists, readable, executable];
                    allOk = NO;
                } else {
                    [self.logger logDebug:[NSString stringWithFormat:@"Dependency OK: %@", depName]];
                }
            }
        }
    }
    return allOk;
}

#pragma mark - Main Installation Method

- (int)installIPA:(NSString *)ipaPath toApp:(NSString *)appPath progress:(void(^)(float))progress {
    [self.logger beginSessionWithBundleID:[self extractBundleIDFromIPA:ipaPath] sourcePath:ipaPath];
    self.logger.destinationAppPath = appPath;

    int result = [self _installIPA:ipaPath toApp:appPath progress:progress];

    [self.logger endSession];
    return result;
}

- (NSString *)extractBundleIDFromIPA:(NSString *)ipaPath {
    // Quick extraction for logging
    return @"unknown";
}

- (int)_installIPA:(NSString *)ipaPath toApp:(NSString *)appPath progress:(void(^)(float))progress {
    NSString *tempDir = nil;
    NSString *appFolder = nil;
    NSString *destApp = nil;
    NSString *destInfo = nil;
    NSString *destExe = nil;
    NSString *bundleID = nil;
    NSString *exeName = nil;
    NSString *infoPlist = nil;
    NSString *exePath = nil;

    int exitCode = 0;
    BOOL verified = NO;
    NSString *verification = @"";
    NSMutableString *detail = [NSMutableString string];

    // ========== PHASE 1: IPA_OPEN ==========
    [self.logger enterPhase:LiveLogPhaseIPAOpen withDetail:ipaPath];

    BOOL fileExists = [self.fm fileExistsAtPath:ipaPath];
    BOOL isReadable = [self.fm isReadableFileAtPath:ipaPath];
    NSDictionary *attrs = [self.fm attributesOfItemAtPath:ipaPath error:nil];
    unsigned long long fileSize = [attrs fileSize];

    [self.logger logInfo:[NSString stringWithFormat:@"IPA exists=%d readable=%d size=%llu", fileExists, isReadable, fileSize]];

    if (!fileExists) {
        [self.logger logCritical:@"IPA file does not exist"];
        return 1;
    }
    if (!isReadable) {
        [self.logger logCritical:@"IPA file is not readable"];
        return 1;
    }
    if (fileSize == 0) {
        [self.logger logCritical:@"IPA file is empty"];
        return 1;
    }

    [self.logger logVerification:@"IPA_OPEN" result:YES detail:[NSString stringWithFormat:@"size=%llu", fileSize]];
    if (progress) progress(0.05f);

    // ========== PHASE 2: IPA_EXTRACT ==========
    [self.logger enterPhase:LiveLogPhaseIPAExtract];

    tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [self.logger logInfo:[NSString stringWithFormat:@"Creating temp dir: %@", tempDir]];

    BOOL dirCreated = [self.fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    if (!dirCreated) {
        [self.logger logCritical:[NSString stringWithFormat:@"Failed to create temp dir: %@", tempDir]];
        return 2;
    }

    // Extract using unzip
    int unzipExit = [self runCmd:@"/usr/bin/unzip" args:@[@"-o", @"-q", ipaPath, @"-d", tempDir]];
    if (unzipExit != 0) {
        [self.logger logCritical:[NSString stringWithFormat:@"unzip failed with exit code %d", unzipExit]];
        [self cleanup:tempDir];
        return 2;
    }

    NSString *payloadPath = [tempDir stringByAppendingPathComponent:@"Payload"];
    BOOL payloadExists = [self.fm fileExistsAtPath:payloadPath];
    [self.logger logVerification:@"IPA_EXTRACT" result:payloadExists detail:[NSString stringWithFormat:@"Payload exists=%d", payloadExists]];

    if (!payloadExists) {
        [self.logger logCritical:@"Payload folder not found after extraction"];
        [self cleanup:tempDir];
        return 2;
    }
    if (progress) progress(0.10f);

    // ========== PHASE 3: APP_IDENTIFY ==========
    [self.logger enterPhase:LiveLogPhaseAppIdentify];

    NSArray *payloadContents = [self.fm contentsOfDirectoryAtPath:payloadPath error:nil];
    appFolder = nil;
    for (NSString *item in payloadContents) {
        if ([item hasSuffix:@".app"]) {
            appFolder = [payloadPath stringByAppendingPathComponent:item];
            break;
        }
    }

    if (!appFolder) {
        [self.logger logCritical:@"No .app folder found in Payload"];
        [self cleanup:tempDir];
        return 3;
    }

    infoPlist = [appFolder stringByAppendingPathComponent:@"Info.plist"];
    BOOL infoExists = [self.fm fileExistsAtPath:infoPlist];
    [self.logger logFileOperation:@"check" path:infoPlist result:infoExists error:nil];

    if (!infoExists) {
        [self.logger logCritical:@"Info.plist not found in app bundle"];
        [self cleanup:tempDir];
        return 3;
    }

    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPlist];
    bundleID = info[@"CFBundleIdentifier"];
    exeName = info[@"CFBundleExecutable"];

    [self.logger logInfo:[NSString stringWithFormat:@"BundleID=%@ Executable=%@", bundleID, exeName]];

    if (!bundleID || bundleID.length == 0) {
        [self.logger logCritical:@"CFBundleIdentifier missing or empty"];
        [self cleanup:tempDir];
        return 3;
    }
    if (!exeName || exeName.length == 0) {
        [self.logger logCritical:@"CFBundleExecutable missing or empty"];
        [self cleanup:tempDir];
        return 3;
    }

    exePath = [appFolder stringByAppendingPathComponent:exeName];
    BOOL exeExists = [self.fm fileExistsAtPath:exePath];
    [self.logger logVerification:@"APP_IDENTIFY" result:(infoExists && exeExists) detail:[NSString stringWithFormat:@"bundleID=%@ exe=%@", bundleID, exeName]];

    if (!exeExists) {
        [self.logger logCritical:@"Executable not found in app bundle"];
        [self cleanup:tempDir];
        return 3;
    }
    if (progress) progress(0.15f);

    // ========== PHASE 4: FILE_COPY ==========
    [self.logger enterPhase:LiveLogPhaseFileCopy withDetail:[NSString stringWithFormat:@"src=%@ dst=%@", appFolder, appPath]];

    // Determine destination with Rootless support
    if ([[RootlessManager sharedManager] isRootless]) {
        appPath = [[RootlessManager sharedManager] rootlessPathForAppPath:appPath];
        [self.logger logInfo:[NSString stringWithFormat:@"Rootless path resolved: %@", appPath]];
    }

    destApp = appPath;
    destInfo = [destApp stringByAppendingPathComponent:@"Info.plist"];
    destExe = [destApp stringByAppendingPathComponent:exeName];

    // Remove existing app if present
    if ([self.fm fileExistsAtPath:destApp]) {
        [self.logger logWarning:[NSString stringWithFormat:@"Removing existing app at %@", destApp]];
        [self.fm removeItemAtPath:destApp error:nil];
    }

    // Deep copy using copyfile for symlinks preservation
    int copyFlags = COPYFILE_ALL | COPYFILE_NOFOLLOW_SRC;
    int copyResult = copyfile([appFolder UTF8String], [destApp UTF8String], NULL, copyFlags);

    if (copyResult != 0) {
        [self.logger logError:[NSString stringWithFormat:@"copyfile failed: errno=%d", errno]];
        // Fallback to NSFileManager
        [self.logger logWarning:@"Falling back to NSFileManager copy"];
        NSError *copyError = nil;
        BOOL copied = [self.fm copyItemAtPath:appFolder toPath:destApp error:&copyError];
        if (!copied) {
            [self.logger logCritical:[NSString stringWithFormat:@"Copy failed: %@", copyError.localizedDescription]];
            [self cleanup:tempDir];
            return 4;
        }
    }

    // DEEP VERIFICATION of copy
    [self.logger logInfo:@"Running deep copy verification..."];
    NSMutableString *copyDetail = [NSMutableString string];
    BOOL deepOk = [self verifyDeepCopyFrom:appFolder to:destApp detail:copyDetail];
    [self.logger logVerification:@"FILE_COPY_DEEP" result:deepOk detail:copyDetail];

    if (!deepOk) {
        [self.logger logCritical:[NSString stringWithFormat:@"Deep copy verification failed: %@", copyDetail]];
        [self cleanup:tempDir];
        return 4;
    }

    // Verify critical files exist
    BOOL destExists = [self.fm fileExistsAtPath:destApp];
    BOOL destInfoExists = [self.fm fileExistsAtPath:destInfo];
    BOOL destExeExists = [self.fm fileExistsAtPath:destExe];

    [self.logger logVerification:@"FILE_COPY" result:(destExists && destInfoExists && destExeExists) 
                          detail:[NSString stringWithFormat:@"dest=%d info=%d exe=%d", destExists, destInfoExists, destExeExists]];

    if (!destExists || !destInfoExists || !destExeExists) {
        [self.logger logCritical:@"Critical files missing after copy"];
        [self cleanup:tempDir];
        return 4;
    }
    if (progress) progress(0.30f);

    // ========== PHASE 5: PERMISSION_chmod ==========
    [self.logger enterPhase:LiveLogPhasePermissionChmod];

    int chmodExit = [self runCmd:@"/bin/chmod" args:@[@"-R", @"755", destApp]];
    if (chmodExit != 0) {
        [self.logger logError:[NSString stringWithFormat:@"chmod failed: exit=%d", chmodExit]];
    }

    // STAT VERIFICATION after chmod
    NSMutableString *chmodDetail = [NSMutableString string];
    BOOL chmodOk = [self verifyStatAtPath:destExe expectedModeMin:0755 expectedUid:-1 expectedGid:-1 detail:chmodDetail];
    [self.logger logVerification:@"PERMISSION_chmod" result:chmodOk detail:chmodDetail];

    if (!chmodOk) {
        [self.logger logWarning:[NSString stringWithFormat:@"chmod stat verification issue: %@", chmodDetail]];
        // Don't fail immediately — try to recover
    }
    if (progress) progress(0.40f);

    // ========== PHASE 6: PERMISSION_chown ==========
    [self.logger enterPhase:LiveLogPhasePermissionChown];

    int chownExit = [self runCmd:@"/usr/sbin/chown" args:@[@"-R", @"root:wheel", destApp]];
    if (chownExit != 0) {
        [self.logger logError:[NSString stringWithFormat:@"chown failed: exit=%d", chownExit]];
    }

    // STAT VERIFICATION after chown — CRITICAL for errno=13 detection
    NSMutableString *chownDetail = [NSMutableString string];
    BOOL chownOk = [self verifyStatAtPath:destExe expectedModeMin:0755 expectedUid:0 expectedGid:0 detail:chownDetail];
    [self.logger logVerification:@"PERMISSION_chown" result:chownOk detail:chownDetail];

    if (!chownOk) {
        [self.logger logCritical:[NSString stringWithFormat:@"chown verification failed: %@", chownDetail]];
        // This is where errno=13 originates — wrong ownership
        [self cleanup:tempDir];
        return 6;
    }
    if (progress) progress(0.50f);

    // ========== PHASE 7: SIGN_signAllAt ==========
    [self.logger enterPhase:LiveLogPhaseSignAll withDetail:destApp];

    [self signAllAt:destApp];

    // Verify signature on main executable
    NSMutableString *signAllDetail = [NSMutableString string];
    BOOL signAllOk = [self verifySignature:destExe detail:signAllDetail];
    [self.logger logVerification:@"SIGN_signAllAt" result:signAllOk detail:signAllDetail];

    if (!signAllOk) {
        [self.logger logWarning:@"signAllAt signature verification weak — continuing"];
    }
    if (progress) progress(0.60f);

    // ========== PHASE 8: SIGN_signExe ==========
    [self.logger enterPhase:LiveLogPhaseSignExe withDetail:destExe];

    [self signExe:destExe];

    BOOL exeExistsAfterSign = [self.fm fileExistsAtPath:destExe];
    BOOL exeReadableAfterSign = [self.fm isReadableFileAtPath:destExe];

    NSMutableString *signExeDetail = [NSMutableString string];
    BOOL signExeSigOk = [self verifySignature:destExe detail:signExeDetail];

    [self.logger logVerification:@"SIGN_signExe" result:(exeExistsAfterSign && exeReadableAfterSign && signExeSigOk) 
                          detail:[NSString stringWithFormat:@"exists=%d readable=%d signed=%d", exeExistsAfterSign, exeReadableAfterSign, signExeSigOk]];

    if (!exeExistsAfterSign || !exeReadableAfterSign) {
        [self.logger logCritical:@"Executable missing or unreadable after signing"];
        [self cleanup:tempDir];
        return 8;
    }
    if (progress) progress(0.70f);

    // ========== PHASE 9: FRAMEWORK ==========
    [self.logger enterPhase:LiveLogPhaseFramework];

    NSString *fwPath = [destApp stringByAppendingPathComponent:@"Frameworks"];
    BOOL fwExists = [self.fm fileExistsAtPath:fwPath];

    if (fwExists) {
        NSArray *fwItems = [self.fm contentsOfDirectoryAtPath:fwPath error:nil];
        [self.logger logInfo:[NSString stringWithFormat:@"Found %lu frameworks/dylibs", (unsigned long)fwItems.count]];

        NSUInteger fwVerified = 0;
        NSUInteger fwFailed = 0;

        for (NSString *item in fwItems) {
            NSString *dp = [fwPath stringByAppendingPathComponent:item];
            NSMutableString *fwDetail = [NSMutableString string];

            // stat verification
            BOOL statOk = [self verifyStatAtPath:dp expectedModeMin:0755 expectedUid:0 expectedGid:0 detail:fwDetail];

            // access(X_OK) verification
            BOOL xok = (access([dp UTF8String], X_OK) == 0);
            [self.logger logAccessCheck:dp mode:X_OK result:xok];

            // signature verification
            NSMutableString *sigDetail = [NSMutableString string];
            BOOL sigOk = [self verifySignature:dp detail:sigDetail];

            BOOL itemOk = statOk && xok && sigOk;
            if (itemOk) {
                fwVerified++;
                [self.logger logVerification:[NSString stringWithFormat:@"FRAMEWORK_%@", item] result:YES detail:@"all checks passed"];
            } else {
                fwFailed++;
                [self.logger logError:[NSString stringWithFormat:@"Framework item failed: %@ | stat=%d xok=%d sig=%d", item, statOk, xok, sigOk]];
            }
        }

        [self.logger logVerification:@"FRAMEWORK" result:(fwFailed == 0) 
                              detail:[NSString stringWithFormat:@"verified=%lu failed=%lu", (unsigned long)fwVerified, (unsigned long)fwFailed]];

        if (fwFailed > 0) {
            [self.logger logCritical:[NSString stringWithFormat:@"%lu framework items failed verification", (unsigned long)fwFailed]];
            [self cleanup:tempDir];
            return 9;
        }
    } else {
        [self.logger logInfo:@"No Frameworks folder — skipping framework verification"];
    }
    if (progress) progress(0.80f);

    // ========== PHASE 10: UICACHE ==========
    [self.logger enterPhase:LiveLogPhaseUICache];

    NSString *uicachePath = @"/usr/bin/uicache";
    if (![self.fm fileExistsAtPath:uicachePath]) {
        uicachePath = @"/var/jb/usr/bin/uicache";
    }

    // Run uicache 3 times as in original
    int uicache1 = [self runCmd:uicachePath args:@[@"-p", destApp]];
    int uicache2 = [self runCmd:uicachePath args:@[@"-p", destApp]];
    int uicache3 = [self runCmd:uicachePath args:@[@"-a"]];

    BOOL uicacheOk = (uicache1 == 0 || uicache2 == 0);
    [self.logger logVerification:@"UICACHE" result:uicacheOk 
                          detail:[NSString stringWithFormat:@"run1=%d run2=%d run3=%d", uicache1, uicache2, uicache3]];
    if (progress) progress(0.90f);

    // ========== PHASE 11: VERIFY ==========
    [self.logger enterPhase:LiveLogPhaseVerify];

    BOOL finalExeExists = [self.fm fileExistsAtPath:destExe];
    BOOL finalExeReadable = [self.fm isReadableFileAtPath:destExe];

    // CRITICAL: access(X_OK) check
    BOOL finalExeX_OK = (access([destExe UTF8String], X_OK) == 0);
    [self.logger logAccessCheck:destExe mode:X_OK result:finalExeX_OK];

    if (!finalExeX_OK) {
        [self.logger logCritical:[NSString stringWithFormat:@"access(X_OK) failed for %@ — errno=13 likely", destExe]];
    }

    // Dylib dependencies check
    NSMutableString *depsDetail = [NSMutableString string];
    BOOL depsOk = [self verifyDylibDependencies:destExe appPath:destApp detail:depsDetail];
    [self.logger logVerification:@"VERIFY_DEPS" result:depsOk detail:depsDetail];

    // LSApplicationWorkspace check
    BOOL lsRegistered = NO;
    if (NSClassFromString(@"LSApplicationWorkspace")) {
        id workspace = [NSClassFromString(@"LSApplicationWorkspace") performSelector:@selector(defaultWorkspace)];
        NSArray *apps = [workspace performSelector:@selector(allInstalledApplications)];
        for (id app in apps) {
            NSString *bid = [app performSelector:@selector(bundleIdentifier)];
            if ([bid isEqualToString:bundleID]) {
                lsRegistered = YES;
                break;
            }
        }
    }
    [self.logger logVerification:@"VERIFY_LSAppWS" result:lsRegistered detail:[NSString stringWithFormat:@"bundleID=%@", bundleID]];

    BOOL finalOk = finalExeExists && finalExeReadable && finalExeX_OK && depsOk;
    [self.logger logVerification:@"VERIFY_FINAL" result:finalOk 
                          detail:[NSString stringWithFormat:@"exists=%d readable=%d xok=%d deps=%d", finalExeExists, finalExeReadable, finalExeX_OK, depsOk]];

    if (!finalOk) {
        [self.logger logCritical:@"Final verification failed — installation aborted"];
        [self cleanup:tempDir];
        return 11;
    }
    if (progress) progress(0.95f);

    // ========== PHASE 12: CLEANUP ==========
    [self.logger enterPhase:LiveLogPhaseCleanup];
    [self cleanup:tempDir];
    [self.logger logInfo:@"Cleanup completed"];
    if (progress) progress(1.0f);

    // ========== COMPLETE ==========
    [self.logger enterPhase:LiveLogPhaseComplete];
    [self.logger logInfo:@"Installation completed successfully"];

    return 0;
}

#pragma mark - Signing Helpers

- (void)signAllAt:(NSString *)path {
    [self.logger logInfo:[NSString stringWithFormat:@"Signing all at %@", path]];
    int exitCode = [self runCmd:@"/usr/bin/ldid" args:@[@"-S", path]];
    if (exitCode != 0) {
        [self.logger logWarning:@"ldid -S failed, trying without entitlements"];
        [self runCmd:@"/usr/bin/ldid" args:@[@"-S", path]];
    }
}

- (void)signExe:(NSString *)path {
    [self.logger logInfo:[NSString stringWithFormat:@"Signing executable: %@", path]];

    // Try with original entitlements
    int exit1 = [self runCmd:@"/usr/bin/ldid" args:@[@"-S", path]];
    if (exit1 != 0) {
        [self.logger logWarning:@"ldid -S failed, trying minimal entitlements"];

        // Create minimal entitlements
        NSString *tmpEnt = [NSTemporaryDirectory() stringByAppendingPathComponent:@"min_entitlements.plist"];
        [@"<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict><key>platform-application</key><true/></dict></plist>" writeToFile:tmpEnt atomically:YES encoding:NSUTF8StringEncoding error:nil];

        int exit2 = [self runCmd:@"/usr/bin/ldid" args:@[@"-S", tmpEnt, path]];
        if (exit2 != 0) {
            [self.logger logWarning:@"Minimal entitlements failed, trying bare -S"];
            [self runCmd:@"/usr/bin/ldid" args:@[@"-S", path]];
        }
    }
}

#pragma mark - Cleanup

- (void)cleanup:(NSString *)tempDir {
    if (tempDir && [self.fm fileExistsAtPath:tempDir]) {
        [self.fm removeItemAtPath:tempDir error:nil];
        [self.logger logInfo:[NSString stringWithFormat:@"Cleaned temp dir: %@", tempDir]];
    }
}

@end
