#import "CrashReporter.h"
#import "JailbreakEnvironment.h"
#import <UIKit/UIKit.h>

static NSString * const kCrashLogsKey = @"IPAInstallerPro_CrashLogs_v2";

@interface CrashReporter ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *logs;
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
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kCrashLogsKey];
    _logs = saved ? [saved mutableCopy] : [NSMutableArray array];
}

- (void)saveLogs {
    [[NSUserDefaults standardUserDefaults] setObject:[self.logs copy] forKey:kCrashLogsKey];
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
        NSDictionary *crash = @{
            @"bundleID": bundleID ?: @"unknown",
            @"appName": appName ?: @"Unknown",
            @"timestamp": [[NSDate date] description],
            @"crashType": crashType ?: @"Unknown",
            @"crashReason": crashReason ?: @"Unknown",
            @"signingMethod": signingMethod ?: @"Unknown",
            @"entitlements": entitlements ?: @{},
            @"teamID": teamID ?: @"None",
            @"executablePath": exePath ?: @"Unknown",
            @"wasEncrypted": @(encrypted),
            @"iosVersion": [[UIDevice currentDevice] systemVersion] ?: @"Unknown",
            @"jailbreakType": [JailbreakEnvironment sharedEnvironment].jailbreakType ?: @"Unknown",
            @"detailedLog": log ?: @""
        };

        [self.logs addObject:crash];

        // Keep only last 100
        if (self.logs.count > 100) {
            [self.logs removeObjectsInRange:NSMakeRange(0, self.logs.count - 100)];
        }

        [self saveLogs];
        NSLog(@"[CrashReporter] Logged: %@ — %@", bundleID, crashReason);
    });
}

- (NSArray<NSDictionary *> *)allCrashLogs {
    __block NSArray<NSDictionary *> *result;
    dispatch_sync(self.queue, ^{ result = [self.logs copy]; });
    return result;
}

- (NSArray<NSDictionary *> *)crashLogsForBundleID:(NSString *)bundleID {
    return [[self allCrashLogs] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"bundleID == %@", bundleID]];
}

- (NSDictionary *)lastCrashForBundleID:(NSString *)bundleID {
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
    [report appendFormat:@"Total Logs: %lu\n\n", (unsigned long)self.logs.count];

    for (NSDictionary *log in [self allCrashLogs]) {
        [report appendString:[self formatCrashLog:log]];
        [report appendString:@"\n---\n\n"];
    }
    return report;
}

- (NSString *)generateReportForBundleID:(NSString *)bundleID {
    NSArray *logs = [self crashLogsForBundleID:bundleID];
    if (logs.count == 0) return @"No logs for this app.";

    NSMutableString *report = [NSMutableString string];
    [report appendFormat:@"📊 Report for %@\n", bundleID];
    [report appendString:@"=====================================\n\n"];
    [report appendFormat:@"Total: %lu\n\n", (unsigned long)logs.count];

    for (NSDictionary *log in logs) {
        [report appendString:[self formatCrashLog:log]];
        [report appendString:@"\n---\n\n"];
    }
    return report;
}

- (NSString *)formatCrashLog:(NSDictionary *)log {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"📱 %@ (%@)\n", log[@"appName"], log[@"bundleID"]];
    [s appendFormat:@"🕐 %@\n", log[@"timestamp"]];
    [s appendFormat:@"💥 %@\n", log[@"crashType"]];
    [s appendFormat:@"📋 %@\n", log[@"crashReason"]];
    [s appendFormat:@"🔏 Signing: %@\n", log[@"signingMethod"]];
    [s appendFormat:@"🏷️ Team ID: %@\n", log[@"teamID"]];
    [s appendFormat:@"📁 %@\n", log[@"executablePath"]];
    [s appendFormat:@"🔒 FairPlay: %@\n", [log[@"wasEncrypted"] boolValue] ? @"YES" : @"NO"];
    [s appendFormat:@"📄 Entitlements: %lu keys\n", (unsigned long)[log[@"entitlements"] count]];
    for (NSString *key in [log[@"entitlements"] allKeys]) {
        [s appendFormat:@"   • %@ = %@\n", key, log[@"entitlements"][key]];
    }
    [s appendFormat:@"\n📝 Log:\n%@", log[@"detailedLog"]];
    return s;
}

@end
