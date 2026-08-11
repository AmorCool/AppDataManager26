#import <Foundation/Foundation.h>

@interface CrashReporter : NSObject
+ (instancetype)sharedReporter;

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

- (NSArray<NSDictionary *> *)allCrashLogs;
- (NSArray<NSDictionary *> *)crashLogsForBundleID:(NSString *)bundleID;
- (NSDictionary *)lastCrashForBundleID:(NSString *)bundleID;
- (NSUInteger)totalCrashCount;
- (NSUInteger)crashCountForBundleID:(NSString *)bundleID;
- (void)clearAllLogs;
- (void)clearLogsForBundleID:(NSString *)bundleID;
- (NSString *)generateFullReport;
- (NSString *)generateReportForBundleID:(NSString *)bundleID;
@end
