#import "CrashReporter.h"
#import "JailbreakEnvironment.h"
#import <UIKit/UIKit.h>

@implementation CrashLog
@end

static NSString * const kCrashLogsKey = @"IPAInstallerPro_CrashLogs";

@interface CrashReporter ()
@property (nonatomic, strong) NSMutableArray<CrashLog *> *logs;
@property (nonatomic, strong) NSDateFormatter *formatter;
@property (nonatomic, strong) dispatch_queue_t queue;
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
        [self loadLogs];
    }
    return self;
}

- (void)loadLogs {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:kCrashLogsKey];
    if (data) {
        _logs = [NSKeyedUnarchiver unarchiveObjectWithData:data] ?: [NSMutableArray array];
    } else {
        _logs = [NSMutableArray array];
    }
}

- (void)saveLogs {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.logs];
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:kCrashLogsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)logCrash:(NSString *)bundleID
         appName:(NSString *)appName
      crashType:(NSString *)crashType
     crashReason:(NSString *)crashReason
   signingMethod:(NSString *)signingMethod
    entitlements:(NSDictionary *)entitlements
        teamID:(NSString *)teamID
 executablePath:(NSString *)exePath
    wasEncrypted:(BOOL)encrypted
     detailedLog:(NSString *)log {

    dispatch_async(self.queue, ^{
        CrashLog *crash = [[CrashLog alloc] init];
        crash.bundleID = bundleID ?: @"unknown";
        crash.appName = appName ?: @"Unknown App";
        crash.timestamp = [NSDate date];
        crash.crashType = crashType ?: @"Unknown";
        crash.crashReason = crashReason ?: @"Unknown";
        crash.signingMethod = signingMethod ?: @"Unknown";
        crash.entitlementsUsed = entitlements ?: @{};
        crash.teamID = teamID ?: @"None";
        crash.executablePath = exePath ?: @"Unknown";
        crash.wasFairPlayEncrypted = encrypted;
        crash.iosVersion = [[UIDevice currentDevice] systemVersion];
        crash.jailbreakType = [JailbreakEnvironment sharedEnvironment].jailbreakType;
        crash.detailedLog = log ?: @"";

        [self.logs addObject:crash];

        // Keep only last 100 crashes
        if (self.logs.count > 100) {
            [self.logs removeObjectsInRange:NSMakeRange(0, self.logs.count - 100)];
        }

        [self saveLogs];

        NSLog(@"[CrashReporter] Crash logged for %@: %@ - %@", bundleID, crashType, crashReason);
    });
}

- (NSArray<CrashLog *> *)allCrashLogs {
    __block NSArray<CrashLog *> *result;
    dispatch_sync(self.queue, ^{ result = [self.logs copy]; });
    return result;
}

- (NSArray<CrashLog *> *)crashLogsForBundleID:(NSString *)bundleID {
    return [[self allCrashLogs] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"bundleID == %@", bundleID]];
}

- (CrashLog *)lastCrashForBundleID:(NSString *)bundleID {
    NSArray *logs = [self crashLogsForBundleID:bundleID];
    return logs.lastObject;
}

- (NSUInteger)totalCrashCount {
    return self.logs.count;
}

- (NSUInteger)crashCountForBundleID:(NSString *)bundleID {
    return [self crashLogsForBundleID:bundleID].count;
}

- (void)clearAllLogs {
    dispatch_async(self.queue, ^{
        [self.logs removeAllObjects];
        [self saveLogs];
    });
}

- (void)clearLogsForBundleID:(NSString *)bundleID {
    dispatch_async(self.queue, ^{
        [self.logs filterUsingPredicate:[NSPredicate predicateWithFormat:@"bundleID != %@", bundleID]];
        [self saveLogs];
    });
}

- (NSString *)generateFullReport {
    NSMutableString *report = [NSMutableString string];
    [report appendString:@"📊 IPA Installer Pro — Crash Report\n"];
    [report appendString:@"=====================================\n\n"];
    [report appendFormat:@"iOS Version: %@\n", [[UIDevice currentDevice] systemVersion]];
    [report appendFormat:@"Jailbreak: %@\n", [JailbreakEnvironment sharedEnvironment].jailbreakType];
    [report appendFormat:@"Total Crashes: %lu\n\n", (unsigned long)self.logs.count];

    for (CrashLog *log in [self allCrashLogs]) {
        [report appendString:[self formatCrashLog:log]];
        [report appendString:@"\n---\n\n"];
    }
    return report;
}

- (NSString *)generateReportForBundleID:(NSString *)bundleID {
    NSArray *logs = [self crashLogsForBundleID:bundleID];
    if (logs.count == 0) return @"No crashes recorded for this app.";

    NSMutableString *report = [NSMutableString string];
    [report appendFormat:@"📊 Crash Report for %@\n", bundleID];
    [report appendString:@"=====================================\n\n"];
    [report appendFormat:@"Total Crashes: %lu\n\n", (unsigned long)logs.count];

    for (CrashLog *log in logs) {
        [report appendString:[self formatCrashLog:log]];
        [report appendString:@"\n---\n\n"];
    }
    return report;
}

- (NSString *)formatCrashLog:(CrashLog *)log {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"📱 App: %@ (%@)\n", log.appName, log.bundleID];
    [s appendFormat:@"🕐 Time: %@\n", [self.formatter stringFromDate:log.timestamp]];
    [s appendFormat:@"💥 Type: %@\n", log.crashType];
    [s appendFormat:@"📋 Reason: %@\n", log.crashReason];
    [s appendFormat:@"🔏 Signing: %@\n", log.signingMethod];
    [s appendFormat:@"🏷️ Team ID: %@\n", log.teamID];
    [s appendFormat:@"📁 Executable: %@\n", log.executablePath];
    [s appendFormat:@"🔒 FairPlay Encrypted: %@\n", log.wasFairPlayEncrypted ? @"YES" : @"NO"];
    [s appendFormat:@"📄 Entitlements Used: %lu keys\n", (unsigned long)log.entitlementsUsed.count];
    for (NSString *key in log.entitlementsUsed.allKeys) {
        [s appendFormat:@"   • %@ = %@\n", key, log.entitlementsUsed[key]];
    }
    [s appendFormat:@"\n📝 Detailed Log:\n%@", log.detailedLog];
    return s;
}

@end
