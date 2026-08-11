#import "CrashReporter.h"
#import "Logger.h"
#import "CrashLogParser.h"
#import "ProcessMonitor.h"
#import "LaunchDetector.h"
#import "InstallationLogger.h"
#import "JailbreakEnvironment.h"
#import <UIKit/UIKit.h>

static NSString * const kCrashEventsKey = @"IPAInstallerPro_CrashEvents_v3";

@implementation CrashEvent
@end

@interface CrashReporter ()
@property (nonatomic, strong) NSMutableArray<CrashEvent *> *events;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSDateFormatter *formatter;
@property (nonatomic, strong) NSDate *lastScanTime;
@property (nonatomic, strong) InstallationLogger *installationLogger;
@end

@implementation CrashReporter

+ (instancetype)sharedReporter {
    static CrashReporter *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.aosaid.crashreporter", DISPATCH_QUEUE_SERIAL);
        _formatter = [[NSDateFormatter alloc] init];
        [_formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        _installationLogger = [InstallationLogger sharedLogger];
        [self loadEvents];
        [self registerForNotifications];
    }
    return self;
}

- (void)registerForNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAppDidLaunch:) name:@"AppDidLaunch" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAppLaunchFailed:) name:@"AppLaunchFailed" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleProcessDidExit:) name:@"ProcessDidExit" object:nil];
}

- (void)loadEvents {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kCrashEventsKey];
    _events = [NSMutableArray array];
    for (NSDictionary *dict in saved) {
        CrashEvent *event = [self eventFromDictionary:dict];
        if (event) [self.events addObject:event];
    }
}

- (void)saveEvents {
    NSMutableArray *serialized = [NSMutableArray array];
    for (CrashEvent *event in self.events) {
        [serialized addObject:[self dictionaryFromEvent:event]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:serialized forKey:kCrashEventsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (CrashEvent *)eventFromDictionary:(NSDictionary *)dict {
    if (!dict) return nil;
    CrashEvent *event = [[CrashEvent alloc] init];
    event.eventID = dict[@"eventID"] ?: [[NSUUID UUID] UUIDString];
    event.eventType = [dict[@"eventType"] integerValue];
    event.bundleID = dict[@"bundleID"];
    event.appName = dict[@"appName"];
    event.timestamp = dict[@"timestamp"] ? [self.formatter dateFromString:dict[@"timestamp"]] : [NSDate date];
    event.eventDescription = dict[@"eventDescription"];
    event.rawData = dict[@"rawData"];
    event.detailedLog = dict[@"detailedLog"];
    return event;
}

- (NSDictionary *)dictionaryFromEvent:(CrashEvent *)event {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"eventID"] = event.eventID ?: [[NSUUID UUID] UUIDString];
    dict[@"eventType"] = @(event.eventType);
    dict[@"bundleID"] = event.bundleID ?: @"unknown";
    dict[@"appName"] = event.appName ?: @"Unknown";
    dict[@"timestamp"] = event.timestamp ? [self.formatter stringFromDate:event.timestamp] : [self.formatter stringFromDate:[NSDate date]];
    dict[@"eventDescription"] = event.eventDescription ?: @"";
    dict[@"rawData"] = event.rawData ?: @{};
    dict[@"detailedLog"] = event.detailedLog ?: @"";
    return dict;
}

- (void)startMonitoring {
    [[ProcessMonitor sharedMonitor] startMonitoring];
    [[LaunchDetector sharedDetector] startDetection];
    [self scanSystemCrashLogs];
    [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(periodicScan) userInfo:nil repeats:YES];
    [[Logger sharedLogger] info:@"CrashReporter: Started monitoring"];
}

- (void)stopMonitoring {
    [[ProcessMonitor sharedMonitor] stopMonitoring];
    [[LaunchDetector sharedDetector] stopDetection];
    [[Logger sharedLogger] info:@"CrashReporter: Stopped monitoring"];
}

- (BOOL)isMonitoring {
    return [[ProcessMonitor sharedMonitor] isMonitoring];
}

- (void)periodicScan {
    [self scanSystemCrashLogs];
}

- (CrashEvent *)createEvent:(CrashEventType)type bundleID:(NSString *)bundleID appName:(NSString *)appName description:(NSString *)description rawData:(NSDictionary *)rawData detailedLog:(NSString *)log {
    CrashEvent *event = [[CrashEvent alloc] init];
    event.eventID = [[NSUUID UUID] UUIDString];
    event.eventType = type;
    event.bundleID = bundleID ?: @"unknown";
    event.appName = appName ?: @"Unknown";
    event.timestamp = [NSDate date];
    event.eventDescription = description ?: @"";
    event.rawData = rawData ?: @{};
    event.detailedLog = log ?: @"";
    return event;
}

- (void)addEvent:(CrashEvent *)event {
    if (!event) return;
    dispatch_async(self.queue, ^{
        [self.events addObject:event];
        if (self.events.count > 200) {
            [self.events removeObjectsInRange:NSMakeRange(0, self.events.count - 200)];
        }
        [self saveEvents];
        NSLog(@"[CrashReporter] Event: %@ — %@ — %@", [self stringForEventType:event.eventType], event.bundleID, event.eventDescription);
    });
}

- (void)logInstallationEvent:(NSString *)eventType bundleID:(NSString *)bundleID appName:(NSString *)appName details:(NSDictionary *)details {
    [[InstallationLogger sharedLogger] logEvent:eventType bundleID:bundleID appName:appName details:details];
    CrashEventType type = CrashEventTypeInstallation;
    if ([eventType containsString:@"SIGN"]) type = CrashEventTypeSigning;
    NSString *desc = [NSString stringWithFormat:@"Installation: %@", eventType];
    CrashEvent *event = [self createEvent:type bundleID:bundleID appName:appName description:desc rawData:details detailedLog:details[@"log"] ?: @""];
    [self addEvent:event];
}

- (void)scanSystemCrashLogs {
    CrashLogParser *parser = [CrashLogParser sharedParser];
    NSArray *newLogs = [parser newCrashLogsSince:self.lastScanTime];
    self.lastScanTime = [NSDate date];
    for (NSDictionary *crashLog in newLogs) {
        NSString *bundleID = crashLog[@"bundle_identifier"] ?: @"unknown";
        NSString *appName = crashLog[@"process_name"] ?: @"Unknown";
        NSString *eventTypeStr = crashLog[@"event_type"] ?: @"UNKNOWN_EXIT";
        CrashEventType type = [self eventTypeFromString:eventTypeStr];
        NSString *desc = crashLog[@"event_description"] ?: @"System detected crash";
        CrashEvent *event = [self createEvent:type bundleID:bundleID appName:appName description:desc rawData:crashLog detailedLog:crashLog[@"backtrace_text"] ?: @""];
        [self addEvent:event];
    }
    if (newLogs.count > 0) {
        [[Logger sharedLogger] info:[NSString stringWithFormat:@"CrashReporter: Found %lu new crash logs", (unsigned long)newLogs.count]];
    }
}

- (void)scanSystemCrashLogsForBundleID:(NSString *)bundleID {
    if (!bundleID) return;
    CrashLogParser *parser = [CrashLogParser sharedParser];
    NSArray *logs = [parser crashLogsForBundleID:bundleID];
    for (NSDictionary *crashLog in logs) {
        NSString *eventTypeStr = crashLog[@"event_type"] ?: @"UNKNOWN_EXIT";
        CrashEventType type = [self eventTypeFromString:eventTypeStr];
        BOOL alreadyLogged = NO;
        NSString *logPath = crashLog[@"source_path"];
        for (CrashEvent *event in self.events) {
            if ([event.bundleID isEqualToString:bundleID] && event.eventType == type && [event.rawData[@"source_path"] isEqualToString:logPath]) {
                alreadyLogged = YES;
                break;
            }
        }
        if (!alreadyLogged) {
            NSString *desc = crashLog[@"event_description"] ?: @"System detected crash";
            CrashEvent *event = [self createEvent:type bundleID:bundleID appName:crashLog[@"process_name"] ?: @"Unknown" description:desc rawData:crashLog detailedLog:crashLog[@"backtrace_text"] ?: @""];
            [self addEvent:event];
        }
    }
}

- (void)appWillLaunch:(NSString *)bundleID {
    [[LaunchDetector sharedDetector] willLaunchApp:bundleID];
}

- (void)appDidLaunch:(NSString *)bundleID pid:(int)pid {
    [[LaunchDetector sharedDetector] didLaunchApp:bundleID pid:pid];
    CrashEvent *event = [self createEvent:CrashEventTypeLaunch bundleID:bundleID appName:bundleID description:[NSString stringWithFormat:@"App launched (pid: %d)", pid] rawData:@{@"pid": @(pid)} detailedLog:@""];
    [self addEvent:event];
}

- (void)appLaunchFailed:(NSString *)bundleID reason:(NSString *)reason {
    [[LaunchDetector sharedDetector] launchFailedForApp:bundleID reason:reason];
    CrashEvent *event = [self createEvent:CrashEventTypeLaunchFailure bundleID:bundleID appName:bundleID description:[NSString stringWithFormat:@"Launch failed: %@", reason] rawData:@{@"reason": reason ?: @"Unknown"} detailedLog:@""];
    [self addEvent:event];
}

- (void)appDidExit:(NSString *)bundleID pid:(int)pid exitStatus:(int)status {
    CrashEventType type = CrashEventTypeNormalExit;
    NSString *desc = [NSString stringWithFormat:@"Process exited normally (status: %d)", status];
    if (status != 0) {
        type = CrashEventTypeUnexpectedExit;
        desc = [NSString stringWithFormat:@"Unexpected exit (status: %d)", status];
    }
    CrashEvent *event = [self createEvent:type bundleID:bundleID appName:bundleID description:desc rawData:@{@"pid": @(pid), @"status": @(status)} detailedLog:@""];
    [self addEvent:event];
}

- (void)handleAppDidLaunch:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    NSString *bundleID = info[@"bundleID"];
    int pid = [info[@"pid"] intValue];
    if (bundleID) [self appDidLaunch:bundleID pid:pid];
}

- (void)handleAppLaunchFailed:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    NSString *bundleID = info[@"bundleID"];
    NSString *reason = info[@"reason"];
    if (bundleID) [self appLaunchFailed:bundleID reason:reason];
}

- (void)handleProcessDidExit:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    NSString *bundleID = info[@"bundleID"];
    NSNumber *pid = info[@"pid"];
    if (bundleID && pid) [self scanSystemCrashLogsForBundleID:bundleID];
}

- (void)processDidExit:(NSDictionary *)info {
    [self handleProcessDidExit:[NSNotification notificationWithName:@"ProcessDidExit" object:nil userInfo:info]];
}

- (void)processCrashed:(NSDictionary *)crashInfo {
    NSString *bundleID = crashInfo[@"bundleID"] ?: @"unknown";
    NSString *appName = crashInfo[@"appName"] ?: @"Unknown";
    NSString *reason = crashInfo[@"reason"] ?: @"Unknown crash";
    CrashEvent *event = [self createEvent:CrashEventTypeCrash bundleID:bundleID appName:appName description:reason rawData:crashInfo detailedLog:crashInfo[@"log"] ?: @""];
    [self addEvent:event];
}

- (NSArray<CrashEvent *> *)allEvents {
    __block NSArray<CrashEvent *> *result;
    dispatch_sync(self.queue, ^{ result = [self.events copy]; });
    return result;
}

- (NSArray<CrashEvent *> *)crashEventsOnly {
    return [[self allEvents] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CrashEvent *event, NSDictionary *bindings) {
        return event.eventType == CrashEventTypeCrash || event.eventType == CrashEventTypeWatchdog || event.eventType == CrashEventTypeJetsam || event.eventType == CrashEventTypeSignal || event.eventType == CrashEventTypeException || event.eventType == CrashEventTypeForcedTermination || event.eventType == CrashEventTypeLaunchFailure || event.eventType == CrashEventTypeUnexpectedExit;
    }]];
}

- (NSArray<CrashEvent *> *)installationEventsOnly {
    return [[self allEvents] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CrashEvent *event, NSDictionary *bindings) {
        return event.eventType == CrashEventTypeInstallation || event.eventType == CrashEventTypeSigning;
    }]];
}

- (NSArray<CrashEvent *> *)launchEventsOnly {
    return [[self allEvents] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CrashEvent *event, NSDictionary *bindings) {
        return event.eventType == CrashEventTypeLaunch || event.eventType == CrashEventTypeLaunchFailure;
    }]];
}

- (NSArray<CrashEvent *> *)eventsForBundleID:(NSString *)bundleID {
    if (!bundleID) return @[];
    return [[self allEvents] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CrashEvent *event, NSDictionary *bindings) {
        return [event.bundleID isEqualToString:bundleID];
    }]];
}

- (NSArray<CrashEvent *> *)crashEventsForBundleID:(NSString *)bundleID {
    return [[self crashEventsOnly] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CrashEvent *event, NSDictionary *bindings) {
        return [event.bundleID isEqualToString:bundleID];
    }]];
}

- (CrashEvent *)lastCrashForBundleID:(NSString *)bundleID {
    NSArray *crashes = [self crashEventsForBundleID:bundleID];
    return crashes.lastObject;
}

- (CrashEvent *)lastEventForBundleID:(NSString *)bundleID {
    NSArray *events = [self eventsForBundleID:bundleID];
    return events.lastObject;
}

- (NSUInteger)totalEventCount {
    return self.events.count;
}

- (NSUInteger)totalCrashCount {
    return [self crashEventsOnly].count;
}

- (NSUInteger)crashCountForBundleID:(NSString *)bundleID {
    return [self crashEventsForBundleID:bundleID].count;
}

- (NSUInteger)launchFailureCount {
    return [[self allEvents] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CrashEvent *event, NSDictionary *bindings) {
        return event.eventType == CrashEventTypeLaunchFailure;
    }]].count;
}

- (void)clearAllEvents {
    dispatch_async(self.queue, ^{ [self.events removeAllObjects]; [self saveEvents]; });
    [[InstallationLogger sharedLogger] clearAllLogs];
}

- (void)clearEventsForBundleID:(NSString *)bundleID {
    dispatch_async(self.queue, ^{
        NSMutableArray *toRemove = [NSMutableArray array];
        for (CrashEvent *event in self.events) {
            if ([event.bundleID isEqualToString:bundleID]) [toRemove addObject:event];
        }
        [self.events removeObjectsInArray:toRemove];
        [self saveEvents];
    });
    [[InstallationLogger sharedLogger] clearLogsForBundleID:bundleID];
}

- (void)clearCrashEventsOnly {
    dispatch_async(self.queue, ^{
        NSMutableArray *toRemove = [NSMutableArray array];
        for (CrashEvent *event in self.events) {
            if (event.eventType == CrashEventTypeCrash || event.eventType == CrashEventTypeWatchdog || event.eventType == CrashEventTypeJetsam || event.eventType == CrashEventTypeSignal || event.eventType == CrashEventTypeException || event.eventType == CrashEventTypeForcedTermination || event.eventType == CrashEventTypeLaunchFailure || event.eventType == CrashEventTypeUnexpectedExit) {
                [toRemove addObject:event];
            }
        }
        [self.events removeObjectsInArray:toRemove];
        [self saveEvents];
    });
}

- (NSString *)generateFullReport {
    NSMutableString *report = [NSMutableString string];
    [report appendString:@"📊 IPA Installer Pro — Full Diagnostic Report\n"];
    [report appendString:@"==============================================\n\n"];
    [report appendFormat:@"iOS Version: %@\n", [[UIDevice currentDevice] systemVersion]];
    [report appendFormat:@"Jailbreak: %@\n", [JailbreakEnvironment sharedEnvironment].jailbreakType];
    [report appendFormat:@"Total Events: %lu\n", (unsigned long)self.events.count];
    [report appendFormat:@"Crash Events: %lu\n", (unsigned long)[self crashEventsOnly].count];
    [report appendFormat:@"Launch Failures: %lu\n\n", (unsigned long)self.launchFailureCount];
    [report appendString:@"=== Event Summary ===\n"];
    NSArray *allEvents = [self allEvents];
    NSMutableDictionary *typeCounts = [NSMutableDictionary dictionary];
    for (CrashEvent *event in allEvents) {
        NSString *typeStr = [self stringForEventType:event.eventType];
        NSNumber *current = typeCounts[typeStr] ?: @0;
        typeCounts[typeStr] = @(current.integerValue + 1);
    }
    for (NSString *type in typeCounts) {
        [report appendFormat:@"  %@: %@\n", type, typeCounts[type]];
    }
    [report appendString:@"\n"];
    for (CrashEvent *event in allEvents) {
        [report appendString:[self formatEvent:event]];
        [report appendString:@"\n---\n\n"];
    }
    return report;
}

- (NSString *)generateCrashReportForBundleID:(NSString *)bundleID {
    NSArray *crashes = [self crashEventsForBundleID:bundleID];
    if (crashes.count == 0) return @"No crash events found for this app.";
    NSMutableString *report = [NSMutableString string];
    [report appendFormat:@"📊 Crash Report for %@\n", bundleID];
    [report appendString:@"=====================================\n\n"];
    [report appendFormat:@"Total Crashes: %lu\n\n", (unsigned long)crashes.count];
    for (CrashEvent *event in crashes) {
        [report appendString:[self formatEvent:event]];
        [report appendString:@"\n---\n\n"];
    }
    return report;
}

- (NSString *)generateInstallationReport {
    return [[InstallationLogger sharedLogger] generateInstallationReport];
}

- (NSString *)formatEvent:(CrashEvent *)event {
    NSMutableString *s = [NSMutableString string];
    NSString *icon = [self iconForEventType:event.eventType];
    NSString *typeStr = [self stringForEventType:event.eventType];
    [s appendFormat:@"%@ [%@] %@ (%@)\n", icon, typeStr, event.appName, event.bundleID];
    [s appendFormat:@"🕐 %@\n", [self.formatter stringFromDate:event.timestamp]];
    [s appendFormat:@"📝 %@\n", event.eventDescription];
    if (event.rawData && event.rawData.count > 0) {
        [s appendString:@"\n📋 Details:\n"];
        for (NSString *key in event.rawData) {
            id value = event.rawData[key];
            if ([value isKindOfClass:[NSString class]]) [s appendFormat:@"  • %@: %@\n", key, value];
            else if ([value isKindOfClass:[NSNumber class]]) [s appendFormat:@"  • %@: %@\n", key, value];
            else if ([value isKindOfClass:[NSDictionary class]]) [s appendFormat:@"  • %@: (dictionary)\n", key];
        }
    }
    if (event.detailedLog && event.detailedLog.length > 0) [s appendFormat:@"\n📄 Log:\n%@", event.detailedLog];
    return s;
}

- (NSString *)stringForEventType:(CrashEventType)type {
    switch (type) {
        case CrashEventTypeInstallation: return @"INSTALLATION";
        case CrashEventTypeSigning: return @"SIGNING";
        case CrashEventTypeLaunch: return @"LAUNCH";
        case CrashEventTypeNormalExit: return @"NORMAL_EXIT";
        case CrashEventTypeCrash: return @"CRASH";
        case CrashEventTypeWatchdog: return @"WATCHDOG";
        case CrashEventTypeJetsam: return @"JETSAM";
        case CrashEventTypeSignal: return @"SIGNAL";
        case CrashEventTypeException: return @"EXCEPTION";
        case CrashEventTypeForcedTermination: return @"FORCED_TERMINATION";
        case CrashEventTypeLaunchFailure: return @"LAUNCH_FAILURE";
        case CrashEventTypeUnexpectedExit: return @"UNEXPECTED_EXIT";
        case CrashEventTypeDiagnostics: return @"DIAGNOSTICS";
        default: return @"UNKNOWN";
    }
}

- (NSString *)iconForEventType:(CrashEventType)type {
    switch (type) {
        case CrashEventTypeInstallation: return @"📦";
        case CrashEventTypeSigning: return @"🔏";
        case CrashEventTypeLaunch: return @"▶️";
        case CrashEventTypeNormalExit: return @"📤";
        case CrashEventTypeCrash: return @"💥";
        case CrashEventTypeWatchdog: return @"⏱️";
        case CrashEventTypeJetsam: return @"🧠";
        case CrashEventTypeSignal: return @"📡";
        case CrashEventTypeException: return @"⚠️";
        case CrashEventTypeForcedTermination: return @"🚫";
        case CrashEventTypeLaunchFailure: return @"❌";
        case CrashEventTypeUnexpectedExit: return @"🚪";
        case CrashEventTypeDiagnostics: return @"🔧";
        default: return @"❓";
    }
}

- (CrashEventType)eventTypeFromString:(NSString *)str {
    if ([str isEqualToString:@"CRASH"]) return CrashEventTypeCrash;
    if ([str isEqualToString:@"WATCHDOG"]) return CrashEventTypeWatchdog;
    if ([str isEqualToString:@"JETSAM"]) return CrashEventTypeJetsam;
    if ([str isEqualToString:@"SIGNAL"]) return CrashEventTypeSignal;
    if ([str isEqualToString:@"EXCEPTION"]) return CrashEventTypeException;
    if ([str isEqualToString:@"FORCED_TERMINATION"]) return CrashEventTypeForcedTermination;
    if ([str isEqualToString:@"LAUNCH_FAILURE"]) return CrashEventTypeLaunchFailure;
    if ([str isEqualToString:@"UNEXPECTED_EXIT"]) return CrashEventTypeUnexpectedExit;
    if ([str isEqualToString:@"NORMAL_EXIT"]) return CrashEventTypeNormalExit;
    return CrashEventTypeUnknown;
}

- (void)logCrash:(NSString *)bundleID appName:(NSString *)appName crashType:(NSString *)crashType crashReason:(NSString *)crashReason signingMethod:(NSString *)signingMethod entitlements:(NSDictionary *)entitlements teamID:(NSString *)teamID executablePath:(NSString *)exePath wasEncrypted:(BOOL)encrypted detailedLog:(NSString *)log {
    [self logInstallationEvent:@"INSTALL_SIGNING" bundleID:bundleID appName:appName details:@{
        @"crashType": crashType ?: @"Unknown",
        @"crashReason": crashReason ?: @"Unknown",
        @"signingMethod": signingMethod ?: @"Unknown",
        @"teamID": teamID ?: @"None",
        @"executablePath": exePath ?: @"Unknown",
        @"wasEncrypted": @(encrypted),
        @"log": log ?: @""
    }];
}

- (NSArray<NSDictionary *> *)allCrashLogs {
    NSMutableArray *logs = [NSMutableArray array];
    for (CrashEvent *event in [self crashEventsOnly]) {
        [logs addObject:[self legacyDictFromEvent:event]];
    }
    return logs;
}

- (NSArray<NSDictionary *> *)crashLogsForBundleID:(NSString *)bundleID {
    NSMutableArray *logs = [NSMutableArray array];
    for (CrashEvent *event in [self crashEventsForBundleID:bundleID]) {
        [logs addObject:[self legacyDictFromEvent:event]];
    }
    return logs;
}

- (NSDictionary *)lastCrashLogForBundleID:(NSString *)bundleID {
    CrashEvent *event = [self lastCrashForBundleID:bundleID];
    return event ? [self legacyDictFromEvent:event] : nil;
}

- (NSUInteger)totalCrashLogCount {
    return [self crashEventsOnly].count;
}

- (void)clearAllLogs {
    [self clearAllEvents];
}

- (void)clearLogsForBundleID:(NSString *)bundleID {
    [self clearEventsForBundleID:bundleID];
}

- (NSDictionary *)legacyDictFromEvent:(CrashEvent *)event {
    return @{
        @"bundleID": event.bundleID ?: @"unknown",
        @"appName": event.appName ?: @"Unknown",
        @"timestamp": event.timestamp ? [self.formatter stringFromDate:event.timestamp] : @"Unknown",
        @"crashType": [self stringForEventType:event.eventType],
        @"crashReason": event.eventDescription ?: @"Unknown",
        @"signingMethod": event.rawData[@"signingMethod"] ?: @"Unknown",
        @"entitlements": event.rawData[@"entitlements"] ?: @{},
        @"teamID": event.rawData[@"teamID"] ?: @"None",
        @"executablePath": event.rawData[@"executablePath"] ?: @"Unknown",
        @"wasEncrypted": event.rawData[@"wasEncrypted"] ?: @NO,
        @"iosVersion": event.rawData[@"iosVersion"] ?: @"Unknown",
        @"jailbreakType": event.rawData[@"jailbreakType"] ?: @"Unknown",
        @"detailedLog": event.detailedLog ?: @""
    };
}

@end
