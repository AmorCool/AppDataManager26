#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, CrashEventType) {
    CrashEventTypeUnknown = 0,
    CrashEventTypeInstallation = 1,
    CrashEventTypeSigning = 2,
    CrashEventTypeLaunch = 3,
    CrashEventTypeNormalExit = 4,
    CrashEventTypeCrash = 5,
    CrashEventTypeWatchdog = 6,
    CrashEventTypeJetsam = 7,
    CrashEventTypeSignal = 8,
    CrashEventTypeException = 9,
    CrashEventTypeForcedTermination = 10,
    CrashEventTypeLaunchFailure = 11,
    CrashEventTypeUnexpectedExit = 12,
    CrashEventTypeDiagnostics = 13
};

@interface CrashEvent : NSObject
@property (nonatomic, strong) NSString *eventID;
@property (nonatomic, assign) CrashEventType eventType;
@property (nonatomic, strong) NSString *bundleID;
@property (nonatomic, strong) NSString *appName;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, strong) NSString *eventDescription;
@property (nonatomic, strong) NSDictionary *rawData;
@property (nonatomic, strong) NSString *detailedLog;
@end

@interface CrashReporter : NSObject
+ (instancetype)sharedReporter;
- (void)startMonitoring;
- (void)stopMonitoring;
- (BOOL)isMonitoring;
- (void)logInstallationEvent:(NSString *)eventType bundleID:(NSString *)bundleID appName:(NSString *)appName details:(NSDictionary *)details;
- (void)scanSystemCrashLogs;
- (void)scanSystemCrashLogsForBundleID:(NSString *)bundleID;
- (void)appWillLaunch:(NSString *)bundleID;
- (void)appDidLaunch:(NSString *)bundleID pid:(int)pid;
- (void)appLaunchFailed:(NSString *)bundleID reason:(NSString *)reason;
- (void)appDidExit:(NSString *)bundleID pid:(int)pid exitStatus:(int)status;
- (void)processDidExit:(NSDictionary *)info;
- (void)processCrashed:(NSDictionary *)crashInfo;
- (NSArray<CrashEvent *> *)allEvents;
- (NSArray<CrashEvent *> *)crashEventsOnly;
- (NSArray<CrashEvent *> *)installationEventsOnly;
- (NSArray<CrashEvent *> *)launchEventsOnly;
- (NSArray<CrashEvent *> *)eventsForBundleID:(NSString *)bundleID;
- (NSArray<CrashEvent *> *)crashEventsForBundleID:(NSString *)bundleID;
- (CrashEvent *)lastCrashForBundleID:(NSString *)bundleID;
- (CrashEvent *)lastEventForBundleID:(NSString *)bundleID;
- (NSUInteger)totalEventCount;
- (NSUInteger)totalCrashCount;
- (NSUInteger)crashCountForBundleID:(NSString *)bundleID;
- (NSUInteger)launchFailureCount;
- (void)clearAllEvents;
- (void)clearEventsForBundleID:(NSString *)bundleID;
- (void)clearCrashEventsOnly;
- (NSString *)generateFullReport;
- (NSString *)generateCrashReportForBundleID:(NSString *)bundleID;
- (NSString *)generateInstallationReport;
- (NSString *)formatEvent:(CrashEvent *)event;
- (NSString *)stringForEventType:(CrashEventType)type;
- (NSString *)iconForEventType:(CrashEventType)type;
// Legacy
- (void)logCrash:(NSString *)bundleID appName:(NSString *)appName crashType:(NSString *)crashType crashReason:(NSString *)crashReason signingMethod:(NSString *)signingMethod entitlements:(NSDictionary *)entitlements teamID:(NSString *)teamID executablePath:(NSString *)exePath wasEncrypted:(BOOL)encrypted detailedLog:(NSString *)log;
- (NSArray<NSDictionary *> *)allCrashLogs;
- (NSArray<NSDictionary *> *)crashLogsForBundleID:(NSString *)bundleID;
- (NSDictionary *)lastCrashLogForBundleID:(NSString *)bundleID;
- (NSUInteger)totalCrashLogCount;
- (void)clearAllLogs;
- (void)clearLogsForBundleID:(NSString *)bundleID;
@end
