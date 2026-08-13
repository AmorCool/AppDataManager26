//
//  RuntimeDiagnostics.m
//  IPAInstallerPro
//
//  Post-Install Runtime Observability Layer — Implementation.
//  OBSERVE → MEASURE → RECORD. Never assume. Never fix without data.
//

#import "RuntimeDiagnostics.h"
#import "OperationLog.h"
#import "RootlessManager.h"
#import <objc/runtime.h>
#import <sys/types.h>
#import <signal.h>

@implementation ProcessInfo
@end

@implementation RuntimeDiagnosticsResult

- (NSString *)detailedReport {
    NSMutableString *r = [NSMutableString string];
    [r appendFormat:@"\n=== Runtime Diagnostics Report ===\n"];
    [r appendFormat:@"Bundle ID: %@\n", self.bundleID ?: @"N/A"];
    [r appendFormat:@"State: %@\n", self.state ?: @"N/A"];
    [r appendFormat:@"\n--- Timing ---\n"];
    [r appendFormat:@"Launch requested: %@\n", self.launchRequestedAt ?: @"N/A"];
    [r appendFormat:@"Process detected: %@\n", self.processDetectedAt ?: @"N/A"];
    [r appendFormat:@"Process exit: %@\n", self.processExitAt ?: @"N/A"];
    [r appendFormat:@"Launch detection time: %.0f ms\n", self.launchDetectionTimeMs];
    [r appendFormat:@"Process lifetime: %.0f ms\n", self.processLifetimeMs];
    [r appendFormat:@"Monitoring window: %.0f ms\n", self.monitoringWindowMs];
    [r appendFormat:@"\n--- Process ---\n"];
    [r appendFormat:@"Detected: %@\n", self.processDetected ? @"YES" : @"NO"];
    [r appendFormat:@"PID: %d\n", self.pid];
    [r appendFormat:@"UID: %d\n", self.uid];
    [r appendFormat:@"GID: %d\n", self.gid];
    [r appendFormat:@"Remained alive: %@\n", self.processRemainedAlive ? @"YES" : @"NO"];
    [r appendFormat:@"\n--- Crash ---\n"];
    [r appendFormat:@"Crash detected: %@\n", self.crashDetected ? @"YES" : @"NO"];
    [r appendFormat:@"Termination reason: %@\n", self.terminationReason ?: @"N/A"];
    [r appendFormat:@"Crash report path: %@\n", self.crashReportPath ?: @"unavailable"];
    if (self.diagnosticOutput && self.diagnosticOutput.length > 0) {
        [r appendFormat:@"\n--- Diagnostic Output ---\n%@\n", self.diagnosticOutput];
    }
    [r appendFormat:@"\n=== End Report ===\n"];
    return r;
}

@end

@interface RuntimeDiagnostics ()
@end

@implementation RuntimeDiagnostics

+ (instancetype)sharedDiagnostics {
    static RuntimeDiagnostics *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _processDetectionTimeout = 5.0;
        _monitoringWindow = 10.0;
        _pollInterval = 0.5;
    }
    return self;
}

- (void)diagnoseAppLaunch:(NSString *)bundleID
           transactionID:(NSString *)txnID
            operationLog:(OperationLog *)opLog
              completion:(void (^)(RuntimeDiagnosticsResult *result))completion {

    NSDate *overallStart = [NSDate date];
    RuntimeDiagnosticsResult *result = [[RuntimeDiagnosticsResult alloc] init];
    result.bundleID = bundleID;
    result.state = @"NOT_STARTED";
    result.launchRequestedAt = [NSDate date];
    result.monitoringWindowMs = self.monitoringWindow * 1000.0;

    NSLog(@"[RuntimeDiagnostics] Starting diagnosis for %@", bundleID);

    // PHASE 1: LAUNCH
    NSString *recLaunch = [opLog beginPhase:OperationPhaseLaunch
                                  operation:@"launchApp"
                                     target:bundleID
                                      input:@""
                              transactionID:txnID];

    result.state = @"LAUNCH_REQUESTED";
    BOOL launched = [self launchAppWithBundleID:bundleID];
    NSTimeInterval launchDuration = [[NSDate date] timeIntervalSinceDate:result.launchRequestedAt] * 1000.0;

    [opLog endPhase:recLaunch
           exitCode:launched ? 0 : 1
          rawOutput:@""
           rawError:launched ? @"" : @"LSApplicationWorkspace openApplicationWithBundleID failed"
       verification:launched ? @"Launch request dispatched" : @"Launch request failed"
           verified:launched
           duration:launchDuration / 1000.0];

    if (!launched) {
        result.success = NO;
        result.state = @"LAUNCH_FAILED";
        result.summary = @"Launch request failed";
        if (completion) completion(result);
        return;
    }

    // PHASE 2: PROCESS DETECTION
    NSString *recDetect = [opLog beginPhase:OperationPhaseLaunch
                                  operation:@"processDetection"
                                     target:bundleID
                                      input:[NSString stringWithFormat:@"timeout=%.1fs", self.processDetectionTimeout]
                              transactionID:txnID];

    NSDate *detectStart = [NSDate date];
    ProcessInfo *proc = [self detectProcessForBundleID:bundleID timeout:self.processDetectionTimeout];
    result.launchDetectionTimeMs = [[NSDate date] timeIntervalSinceDate:detectStart] * 1000.0;
    result.processDetectedAt = proc ? [NSDate date] : nil;

    if (proc) {
        result.processDetected = YES;
        result.pid = proc.pid;
        result.uid = proc.uid;
        result.gid = proc.gid;
        result.appName = proc.name;
        result.executablePath = proc.executablePath;
        result.state = @"PROCESS_DETECTED";

        NSString *procInfo = [NSString stringWithFormat:@"PID=%d name=%@ UID=%d GID=%d path=%@",
                              proc.pid, proc.name, proc.uid, proc.gid, proc.executablePath ?: @"N/A"];

        [opLog endPhase:recDetect
               exitCode:0
              rawOutput:procInfo
               rawError:@""
           verification:[NSString stringWithFormat:@"Process detected in %.0f ms", result.launchDetectionTimeMs]
               verified:YES
               duration:result.launchDetectionTimeMs / 1000.0];
    } else {
        result.processDetected = NO;
        result.state = @"PROCESS_NOT_DETECTED";
        result.success = NO;
        result.summary = [NSString stringWithFormat:@"Process not detected within %.1fs", self.processDetectionTimeout];

        [opLog endPhase:recDetect
               exitCode:1
              rawOutput:@""
               rawError:[NSString stringWithFormat:@"No process matching %@ found after %.1fs", bundleID, self.processDetectionTimeout]
           verification:@"Process detection timeout"
               verified:NO
               duration:result.launchDetectionTimeMs / 1000.0];

        if (completion) completion(result);
        return;
    }

    // PHASE 3: RUNTIME MONITORING
    NSString *recMonitor = [opLog beginPhase:OperationPhaseRuntimeMonitor
                                   operation:@"runtimeMonitor"
                                      target:bundleID
                                       input:[NSString stringWithFormat:@"PID=%d window=%.1fs poll=%.1fs",
                                              result.pid, self.monitoringWindow, self.pollInterval]
                               transactionID:txnID];

    NSDate *monitorStart = [NSDate date];
    BOOL stillAlive = [self monitorProcess:result.pid duration:self.monitoringWindow];
    NSTimeInterval monitorDuration = [[NSDate date] timeIntervalSinceDate:monitorStart] * 1000.0;

    if (!stillAlive) {
        result.processRemainedAlive = NO;
        result.processExitAt = [NSDate date];
        result.processLifetimeMs = monitorDuration;

        BOOL isCrash = [self checkIfCrashed:result.pid bundleID:bundleID];
        result.crashDetected = isCrash;
        result.state = isCrash ? @"CRASHED" : @"EXITED";
        result.terminationReason = isCrash ? @"Process terminated abnormally (crash suspected)"
                                            : @"Process exited normally";
        result.success = NO;
        result.summary = [NSString stringWithFormat:@"%@ after %.0f ms",
                          isCrash ? @"Crashed" : @"Exited", monitorDuration];

        [opLog endPhase:recMonitor
               exitCode:isCrash ? 2 : 1
              rawOutput:[NSString stringWithFormat:@"lifetime=%.0fms", monitorDuration]
               rawError:result.terminationReason
           verification:[NSString stringWithFormat:@"Process %@ after %.0f ms",
                          isCrash ? @"crashed" : @"exited", monitorDuration]
               verified:NO
               duration:monitorDuration / 1000.0];

        if (isCrash) {
            NSString *recCrash = [opLog beginPhase:OperationPhaseCrashDiagnostics
                                          operation:@"crashDiagnostics"
                                             target:bundleID
                                              input:[NSString stringWithFormat:@"PID=%d", result.pid]
                                      transactionID:txnID];

            NSString *crashPath = [self findCrashReportForBundleID:bundleID processName:proc.name];
            result.crashReportPath = crashPath;

            NSString *crashContent = nil;
            if (crashPath && [[NSFileManager defaultManager] fileExistsAtPath:crashPath]) {
                crashContent = [NSString stringWithContentsOfFile:crashPath encoding:NSUTF8StringEncoding error:nil];
                result.diagnosticOutput = crashContent;
            }

            BOOL crashReportFound = (crashPath != nil);
            [opLog endPhase:recCrash
                   exitCode:crashReportFound ? 0 : 1
                  rawOutput:crashContent ?: @""
                   rawError:crashReportFound ? @"" : @"No crash report located"
               verification:crashReportFound ? @"Crash report found and read" : @"Crash report unavailable"
                   verified:crashReportFound
                   duration:0];
        }

    } else {
        result.processRemainedAlive = YES;
        result.processLifetimeMs = monitorDuration;
        result.state = @"RUNNING";
        result.success = YES;
        result.terminationReason = @"";
        result.summary = [NSString stringWithFormat:@"Process remained alive for full %.0f ms window", monitorDuration];

        [opLog endPhase:recMonitor
               exitCode:0
              rawOutput:[NSString stringWithFormat:@"alive_after=%.0fms", monitorDuration]
               rawError:@""
           verification:[NSString stringWithFormat:@"Process remained alive for full %.0f ms monitoring window", monitorDuration]
               verified:YES
               duration:monitorDuration / 1000.0];
    }

    NSTimeInterval overallDuration = [[NSDate date] timeIntervalSinceDate:overallStart] * 1000.0;
    NSLog(@"[RuntimeDiagnostics] Complete for %@ in %.0f ms — State: %@", bundleID, overallDuration, result.state);

    if (completion) completion(result);
}

- (BOOL)launchAppWithBundleID:(NSString *)bundleID {
    @try {
        Class LSClass = objc_getClass(@"LSApplicationWorkspace");
        if (!LSClass) return NO;
        id workspace = ((id (*)(Class, SEL))objc_msgSend)(LSClass, NSSelectorFromString(@"defaultWorkspace"));
        if (!workspace) return NO;
        SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
        if ([workspace respondsToSelector:openSel]) {
            BOOL opened = ((BOOL (*)(id, SEL, NSString *))objc_msgSend)(workspace, openSel, bundleID);
            return opened;
        }
        NSString *urlScheme = [NSString stringWithFormat:@"%@://", bundleID];
        NSURL *url = [NSURL URLWithString:urlScheme];
        if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            return YES;
        }
        return NO;
    } @catch (NSException *e) {
        return NO;
    }
}

- (ProcessInfo *)detectProcessForBundleID:(NSString *)bundleID timeout:(NSTimeInterval)timeout {
    NSDate *start = [NSDate date];
    NSString *exeName = [self extractExecutableNameFromBundleID:bundleID];
    while ([[NSDate date] timeIntervalSinceDate:start] < timeout) {
        ProcessInfo *proc = [self findProcessMatchingBundleID:bundleID exeName:exeName];
        if (proc) return proc;
        [NSThread sleepForTimeInterval:self.pollInterval];
    }
    return nil;
}

- (NSString *)extractExecutableNameFromBundleID:(NSString *)bundleID {
    NSString *appPath = [self findAppPathForBundleID:bundleID];
    if (appPath) {
        NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        NSString *exeName = info[@"CFBundleExecutable"];
        if (exeName) return exeName;
    }
    NSArray *parts = [bundleID componentsSeparatedByString:@"."];
    return parts.lastObject ?: bundleID;
}

- (NSString *)findAppPathForBundleID:(NSString *)bundleID {
    NSArray *searchPaths = @[@"/var/jb/Applications", @"/Applications"];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *base in searchPaths) {
        NSArray *items = [fm contentsOfDirectoryAtPath:base error:nil];
        for (NSString *item in items) {
            if ([item hasSuffix:@".app"]) {
                NSString *appPath = [base stringByAppendingPathComponent:item];
                NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
                if ([info[@"CFBundleIdentifier"] isEqualToString:bundleID]) {
                    return appPath;
                }
            }
        }
    }
    return nil;
}

- (ProcessInfo *)findProcessMatchingBundleID:(NSString *)bundleID exeName:(NSString *)exeName {
    NSString *psOutput = [self runCmdOutput:@"/var/jb/usr/bin/ps" args:@[@"-eo", @"pid,uid,gid,comm"]];
    if (!psOutput) psOutput = [self runCmdOutput:@"/bin/ps" args:@[@"-eo", @"pid,uid,gid,comm"]];
    if (!psOutput) return nil;

    NSArray *lines = [psOutput componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) continue;
        NSArray *parts = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray *cleanParts = [NSMutableArray array];
        for (NSString *p in parts) {
            if (p.length > 0) [cleanParts addObject:p];
        }
        if (cleanParts.count >= 4) {
            NSString *pidStr = cleanParts[0];
            NSString *uidStr = cleanParts[1];
            NSString *gidStr = cleanParts[2];
            NSString *comm = cleanParts[3];
            if ([comm isEqualToString:exeName] || [comm isEqualToString:bundleID] || [comm containsString:exeName]) {
                pid_t pid = [pidStr intValue];
                if (pid > 0 && [self isProcessAlive:pid]) {
                    ProcessInfo *info = [[ProcessInfo alloc] init];
                    info.pid = pid;
                    info.uid = [uidStr intValue];
                    info.gid = [gidStr intValue];
                    info.name = comm;
                    info.startTime = [NSDate date];
                    return info;
                }
            }
        }
    }
    return nil;
}

- (BOOL)monitorProcess:(pid_t)pid duration:(NSTimeInterval)duration {
    NSDate *start = [NSDate date];
    while ([[NSDate date] timeIntervalSinceDate:start] < duration) {
        if (![self isProcessAlive:pid]) return NO;
        [NSThread sleepForTimeInterval:self.pollInterval];
    }
    return [self isProcessAlive:pid];
}

- (BOOL)isProcessAlive:(pid_t)pid {
    return (kill(pid, 0) == 0);
}

- (BOOL)checkIfCrashed:(pid_t)pid bundleID:(NSString *)bundleID {
    NSString *crashPath = [self findCrashReportForBundleID:bundleID processName:nil];
    if (crashPath) return YES;
    return YES;
}

- (NSString *)findCrashReportForBundleID:(NSString *)bundleID processName:(NSString *)processName {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *searchPaths = @[@"/var/mobile/Library/Logs/CrashReporter",
                             @"/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs"];
    NSDate *now = [NSDate date];
    NSString *latestPath = nil;
    NSDate *latestDate = nil;
    for (NSString *basePath in searchPaths) {
        if (![fm fileExistsAtPath:basePath]) continue;
        NSArray *items = [fm contentsOfDirectoryAtPath:basePath error:nil];
        for (NSString *item in items) {
            BOOL matches = NO;
            if (bundleID && [item containsString:bundleID]) matches = YES;
            if (processName && [item containsString:processName]) matches = YES;
            if (matches && [item hasSuffix:@".ips"]) {
                NSString *fullPath = [basePath stringByAppendingPathComponent:item];
                NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
                NSDate *modDate = attrs[NSFileModificationDate];
                if (modDate && [now timeIntervalSinceDate:modDate] < 300) {
                    if (!latestDate || [modDate compare:latestDate] == NSOrderedDescending) {
                        latestDate = modDate;
                        latestPath = fullPath;
                    }
                }
            }
        }
    }
    return latestPath;
}

- (NSString *)runCmdOutput:(NSString *)cmd args:(NSArray *)args {
    if (!cmd || cmd.length == 0) return nil;
    int outPipe[2];
    if (pipe(outPipe) != 0) return nil;
    pid_t pid;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, outPipe[0]);
    posix_spawn_file_actions_addclose(&actions, outPipe[1]);
    const char *c = [cmd UTF8String];
    char **argv = malloc((args.count + 2) * sizeof(char*));
    argv[0] = (char*)c;
    for (NSUInteger i = 0; i < args.count; i++) argv[i+1] = (char*)[args[i] UTF8String];
    argv[args.count + 1] = NULL;
    extern char **environ;
    int st = posix_spawn(&pid, c, &actions, NULL, argv, environ);
    free(argv);
    posix_spawn_file_actions_destroy(&actions);
    close(outPipe[1]);
    if (st != 0) { close(outPipe[0]); return nil; }
    NSMutableString *output = [NSMutableString string];
    char buf[4096];
    ssize_t n;
    while ((n = read(outPipe[0], buf, sizeof(buf) - 1)) > 0) {
        buf[n] = '\0';
        [output appendString:[NSString stringWithUTF8String:buf]];
    }
    close(outPipe[0]);
    int ws;
    waitpid(pid, &ws, 0);
    return output;
}

@end
