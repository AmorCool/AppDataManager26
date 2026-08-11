#import <Foundation/Foundation.h>

@interface CrashLog : NSObject
@property (nonatomic, strong) NSString *bundleID;
@property (nonatomic, strong) NSString *appName;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, strong) NSString *crashType;        // EXC_BAD_ACCESS, SIGKILL, etc.
@property (nonatomic, strong) NSString *crashReason;      // Code Signing, Memory, etc.
@property (nonatomic, strong) NSString *signingMethod;    // ldid -S, ldid -S/path, etc.
@property (nonatomic, strong) NSDictionary *entitlementsUsed;
@property (nonatomic, strong) NSString *teamID;         // Apple Team ID if present
@property (nonatomic, strong) NSString *executablePath;
@property (nonatomic, strong) NSString *detailedLog;
@property (nonatomic, assign) BOOL wasFairPlayEncrypted;
@property (nonatomic, strong) NSString *iosVersion;
@property (nonatomic, strong) NSString *jailbreakType;
@end

@interface CrashReporter : NSObject
+ (instancetype)sharedReporter;

// Log a crash with full details
- (void)logCrash:(NSString *)bundleID
         appName:(NSString *)appName
      crashType:(NSString *)crashType
     crashReason:(NSString *)crashReason
   signingMethod:(NSString *)signingMethod
  entitlements:(NSDictionary *)entitlements
        teamID:(NSString *)teamID
 executablePath:(NSString *)exePath
    wasEncrypted:(BOOL)encrypted
     detailedLog:(NSString *)log;

// Query
- (NSArray<CrashLog *> *)allCrashLogs;
- (NSArray<CrashLog *> *)crashLogsForBundleID:(NSString *)bundleID;
- (CrashLog *)lastCrashForBundleID:(NSString *)bundleID;
- (NSUInteger)totalCrashCount;
- (NSUInteger)crashCountForBundleID:(NSString *)bundleID;
- (void)clearAllLogs;
- (void)clearLogsForBundleID:(NSString *)bundleID;

// Export
- (NSString *)generateFullReport;
- (NSString *)generateReportForBundleID:(NSString *)bundleID;
@end
