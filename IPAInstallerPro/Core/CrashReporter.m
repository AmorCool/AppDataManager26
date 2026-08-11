#import "CrashReporter.h"
#import "JailbreakEnvironment.h"
#import <UIKit/UIKit.h>

@implementation CrashLog

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.bundleID forKey:@"bundleID"];
    [coder encodeObject:self.appName forKey:@"appName"];
    [coder encodeObject:self.timestamp forKey:@"timestamp"];
    [coder encodeObject:self.crashType forKey:@"crashType"];
    [coder encodeObject:self.crashReason forKey:@"crashReason"];
    [coder encodeObject:self.signingMethod forKey:@"signingMethod"];
    [coder encodeObject:self.entitlementsUsed forKey:@"entitlementsUsed"];
    [coder encodeObject:self.teamID forKey:@"teamID"];
    [coder encodeObject:self.executablePath forKey:@"executablePath"];
    [coder encodeObject:self.detailedLog forKey:@"detailedLog"];
    [coder encodeBool:self.wasFairPlayEncrypted forKey:@"wasFairPlayEncrypted"];
    [coder encodeObject:self.iosVersion forKey:@"iosVersion"];
    [coder encodeObject:self.jailbreakType forKey:@"jailbreakType"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        self.bundleID = [coder decodeObjectForKey:@"bundleID"];
        self.appName = [coder decodeObjectForKey:@"appName"];
        self.timestamp = [coder decodeObjectForKey:@"timestamp"];
        self.crashType = [coder decodeObjectForKey:@"crashType"];
        self.crashReason = [coder decodeObjectForKey:@"crashReason"];
        self.signingMethod = [coder decodeObjectForKey:@"signingMethod"];
        self.entitlementsUsed = [coder decodeObjectForKey:@"entitlementsUsed"];
        self.teamID = [coder decodeObjectForKey:@"teamID"];
        self.executablePath = [coder decodeObjectForKey:@"executablePath"];
        self.detailedLog = [coder decodeObjectForKey:@"detailedLog"];
        self.wasFairPlayEncrypted = [coder decodeBoolForKey:@"wasFairPlayEncrypted"];
        self.iosVersion = [coder decodeObjectForKey:@"iosVersion"];
        self.jailbreakType = [coder decodeObjectForKey:@"jailbreakType"];
    }
    return self;
}

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
        @try {
            NSArray *loaded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
            _logs = loaded ? [NSMutableArray arrayWithArray:loaded] : [NSMutableArray array];
        } @catch (NSException *e) {
            _logs = [NSMutableArray array];
        }
    } else {
        _logs = [NSMutableArray array];
    }
}

- (void)saveLogs {
    @try {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.logs];
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:kCrashLogsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } @catch (NSException *e) {
        NSLog(@"[CrashReporter] Failed to save logs: %@", e.reason);
    }
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

        if (self.logs.count > 100) {
            [self.logs removeObjectsInRange:NSMakeRange(0, self.logs.count - 100)];
        }

        [self saveLogs];

        NSLog(@"[CrashReporter] Logged: %@ | %@ | %@", bundleID, crashType, crashReason);
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
