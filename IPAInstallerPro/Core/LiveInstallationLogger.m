//
//  LiveInstallationLogger.m
//  IPAInstallerPro
//

#import "LiveInstallationLogger.h"
#import <sys/stat.h>
#import <unistd.h>

@interface LiveInstallationLogger ()
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableEntries;
@property (nonatomic, readwrite) LiveLogPhase currentPhase;
@property (nonatomic, readwrite) NSString *currentPhaseName;
@property (nonatomic, readwrite) NSString *targetBundleID;
@property (nonatomic, readwrite) NSString *sourceIPAPath;
@property (nonatomic, readwrite) NSString *destinationAppPath;
@property (nonatomic, readwrite) NSDate *startTime;
@property (nonatomic, readwrite) BOOL hasErrors;
@property (nonatomic, readwrite) NSUInteger errorCount;
@property (nonatomic, readwrite) NSUInteger warningCount;
@property (nonatomic, strong) NSDateFormatter *formatter;
@property (nonatomic, strong) dispatch_queue_t logQueue;
@end

@implementation LiveInstallationLogger

+ (instancetype)sharedLogger {
    static LiveInstallationLogger *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableEntries = [NSMutableArray array];
        _currentPhase = LiveLogPhaseNone;
        _formatter = [[NSDateFormatter alloc] init];
        [_formatter setDateFormat:@"HH:mm:ss.SSS"];
        _logQueue = dispatch_queue_create("com.appdatamanager.livelogger", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Session Lifecycle

- (void)beginSessionWithBundleID:(NSString *)bundleID sourcePath:(NSString *)sourcePath {
    dispatch_async(self.logQueue, ^{
        self.startTime = [NSDate date];
        self.targetBundleID = bundleID;
        self.sourceIPAPath = sourcePath;
        self.hasErrors = NO;
        self.errorCount = 0;
        self.warningCount = 0;
        [self.mutableEntries removeAllObjects];

        NSString *header = [NSString stringWithFormat:
            @"═══════════════════════════════════════════════════════\n"
            @"  IPA Installer Pro — Live Installation Log\n"
            @"  Bundle ID: %@\n"
            @"  Source: %@\n"
            @"  Start: %@\n"
            @"═══════════════════════════════════════════════════════",
            bundleID, sourcePath, [self.formatter stringFromDate:self.startTime]];

        [self appendRaw:header];
    });
}

- (void)endSession {
    dispatch_async(self.logQueue, ^{
        NSTimeInterval elapsed = self.elapsedTime;
        NSString *status = self.hasErrors ? @"FAILED" : @"SUCCESS";
        NSString *footer = [NSString stringWithFormat:
            @"═══════════════════════════════════════════════════════\n"
            @"  Session End — Status: %@\n"
            @"  Duration: %.3fs | Errors: %lu | Warnings: %lu\n"
            @"═══════════════════════════════════════════════════════",
            status, elapsed, (unsigned long)self.errorCount, (unsigned long)self.warningCount];
        [self appendRaw:footer];
    });
}

- (void)resetSession {
    dispatch_async(self.logQueue, ^{
        [self.mutableEntries removeAllObjects];
        self.currentPhase = LiveLogPhaseNone;
        self.hasErrors = NO;
        self.errorCount = 0;
        self.warningCount = 0;
    });
}

#pragma mark - Phase Management

- (void)enterPhase:(LiveLogPhase)phase {
    [self enterPhase:phase withDetail:nil];
}

- (void)enterPhase:(LiveLogPhase)phase withDetail:(NSString *)detail {
    dispatch_async(self.logQueue, ^{
        self.currentPhase = phase;
        self.currentPhaseName = [self phaseNameForPhase:phase];
        NSString *timestamp = [self.formatter stringFromDate:[NSDate date]];
        NSString *entry = [NSString stringWithFormat:@"[%@] ▶️ ENTER PHASE: %@", timestamp, self.currentPhaseName];
        if (detail) {
            entry = [entry stringByAppendingFormat:@" | %@", detail];
        }
        [self appendRaw:entry];

        if ([self.delegate respondsToSelector:@selector(logger:didUpdatePhase:status:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate logger:self didUpdatePhase:self.currentPhaseName status:@"RUNNING"];
            });
        }
    });
}

- (NSString *)phaseNameForPhase:(LiveLogPhase)phase {
    switch (phase) {
        case LiveLogPhaseIPAOpen: return @"IPA_OPEN";
        case LiveLogPhaseIPAExtract: return @"IPA_EXTRACT";
        case LiveLogPhaseAppIdentify: return @"APP_IDENTIFY";
        case LiveLogPhaseFileCopy: return @"FILE_COPY";
        case LiveLogPhasePermissionChmod: return @"PERMISSION_chmod";
        case LiveLogPhasePermissionChown: return @"PERMISSION_chown";
        case LiveLogPhaseSignAll: return @"SIGN_signAllAt";
        case LiveLogPhaseSignExe: return @"SIGN_signExe";
        case LiveLogPhaseFramework: return @"FRAMEWORK";
        case LiveLogPhaseUICache: return @"UICACHE";
        case LiveLogPhaseVerify: return @"VERIFY";
        case LiveLogPhaseCleanup: return @"CLEANUP";
        case LiveLogPhaseComplete: return @"COMPLETE";
        case LiveLogPhaseFailed: return @"FAILED";
        default: return @"UNKNOWN";
    }
}

#pragma mark - Core Logging

- (void)appendRaw:(NSString *)text {
    [self.mutableEntries addObject:text];
    NSUInteger idx = self.mutableEntries.count - 1;
    if ([self.delegate respondsToSelector:@selector(logger:didAppendEntry:atIndex:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate logger:self didAppendEntry:text atIndex:idx];
        });
    }
}

- (void)logAtLevel:(LiveLogLevel)level message:(NSString *)message {
    dispatch_async(self.logQueue, ^{
        NSString *timestamp = [self.formatter stringFromDate:[NSDate date]];
        NSString *levelStr = [self levelString:level];
        NSString *entry = [NSString stringWithFormat:@"[%@] %@ %@", timestamp, levelStr, message];
        [self appendRaw:entry];

        if (level == LiveLogLevelError || level == LiveLogLevelCritical) {
            self.hasErrors = YES;
            self.errorCount++;
        } else if (level == LiveLogLevelWarning) {
            self.warningCount++;
        }
    });
}

- (NSString *)levelString:(LiveLogLevel)level {
    switch (level) {
        case LiveLogLevelDebug: return @"🔍";
        case LiveLogLevelInfo: return @"ℹ️";
        case LiveLogLevelWarning: return @"⚠️";
        case LiveLogLevelError: return @"❌";
        case LiveLogLevelCritical: return @"🚨";
    }
}

- (void)logDebug:(NSString *)message { [self logAtLevel:LiveLogLevelDebug message:message]; }
- (void)logInfo:(NSString *)message { [self logAtLevel:LiveLogLevelInfo message:message]; }
- (void)logWarning:(NSString *)message { [self logAtLevel:LiveLogLevelWarning message:message]; }
- (void)logError:(NSString *)message { [self logAtLevel:LiveLogLevelError message:message]; }
- (void)logCritical:(NSString *)message { [self logAtLevel:LiveLogLevelCritical message:message]; }

#pragma mark - Structured Logging

- (void)logVerification:(NSString *)checkName result:(BOOL)passed detail:(NSString *)detail {
    NSString *icon = passed ? @"✅" : @"❌";
    NSString *status = passed ? @"PASS" : @"FAIL";
    [self logInfo:[NSString stringWithFormat:@"%@ VERIFICATION [%@] %@ | %@", icon, checkName, status, detail]];
}

- (void)logFileOperation:(NSString *)operation path:(NSString *)path result:(BOOL)success error:(NSString *)error {
    NSString *icon = success ? @"✅" : @"❌";
    NSString *msg = [NSString stringWithFormat:@"%@ FILE_OP [%@] path=%@", icon, operation, path];
    if (!success && error) {
        msg = [msg stringByAppendingFormat:@" | ERROR: %@", error];
        [self logError:msg];
    } else {
        [self logInfo:msg];
    }
}

- (void)logCommandExecution:(NSString *)command exitCode:(int)exitCode output:(NSString *)output {
    NSString *icon = (exitCode == 0) ? @"✅" : @"❌";
    NSString *msg = [NSString stringWithFormat:@"%@ CMD [exit=%d] %@", icon, exitCode, command];
    [self logInfo:msg];
    if (output && output.length > 0) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            [self logDebug:[NSString stringWithFormat:@"   └─ Output: %@", trimmed]];
        }
    }
    if (exitCode != 0) {
        [self logError:[NSString stringWithFormat:@"Command failed with exit code %d: %@", exitCode, command]];
    }
}

- (void)logStatResult:(NSString *)path mode:(mode_t)mode uid:(uid_t)uid gid:(gid_t)gid {
    NSString *modeStr = [NSString stringWithFormat:@"%o", mode & 0777];
    NSString *owner = (uid == 0) ? @"root" : [NSString stringWithFormat:@"%d", uid];
    NSString *group = (gid == 0) ? @"wheel" : [NSString stringWithFormat:@"%d", gid];
    [self logDebug:[NSString stringWithFormat:@"📊 STAT path=%@ | mode=%@ | uid=%@ | gid=%@", path, modeStr, owner, group]];
}

- (void)logAccessCheck:(NSString *)path mode:(int)mode result:(BOOL)accessible {
    NSString *modeStr = (mode == X_OK) ? @"X_OK" : (mode == R_OK) ? @"R_OK" : (mode == W_OK) ? @"W_OK" : @"F_OK";
    NSString *icon = accessible ? @"✅" : @"❌";
    [self logDebug:[NSString stringWithFormat:@"%@ ACCESS(%@) path=%@", icon, modeStr, path]];
}

#pragma mark - Getters

- (NSArray<NSString *> *)entries {
    return [self.mutableEntries copy];
}

- (NSTimeInterval)elapsedTime {
    if (!self.startTime) return 0;
    return [[NSDate date] timeIntervalSinceDate:self.startTime];
}

- (NSString *)fullLogText {
    return [self.mutableEntries componentsJoinedByString:@"\n"];
}

- (NSString *)jsonExport {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"bundleID"] = self.targetBundleID ?: @"";
    dict[@"sourcePath"] = self.sourceIPAPath ?: @"";
    dict[@"destPath"] = self.destinationAppPath ?: @"";
    dict[@"startTime"] = [self.formatter stringFromDate:self.startTime] ?: @"";
    dict[@"elapsed"] = @(self.elapsedTime);
    dict[@"hasErrors"] = @(self.hasErrors);
    dict[@"errorCount"] = @(self.errorCount);
    dict[@"warningCount"] = @(self.warningCount);
    dict[@"entries"] = self.mutableEntries;

    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSString *)markdownReport {
    NSMutableString *md = [NSMutableString string];
    [md appendFormat:@"# Installation Report\n\n"];
    [md appendFormat:@"**Bundle ID:** `%@`\n\n", self.targetBundleID];
    [md appendFormat:@"**Source:** `%@`\n\n", self.sourceIPAPath];
    [md appendFormat:@"**Duration:** `%.3fs`\n\n", self.elapsedTime];
    [md appendFormat:@"**Status:** %@\n\n", self.hasErrors ? @"❌ FAILED" : @"✅ SUCCESS"];
    [md appendFormat:@"**Errors:** %lu | **Warnings:** %lu\n\n", (unsigned long)self.errorCount, (unsigned long)self.warningCount];
    [md appendString:@"---\n\n"];
    [md appendString:@"## Log\n\n"];
    [md appendString:@"```\n"];
    [md appendString:self.fullLogText];
    [md appendString:@"\n```\n"];
    return md;
}

- (void)saveToFile:(NSString *)path {
    [self.fullLogText writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

@end
