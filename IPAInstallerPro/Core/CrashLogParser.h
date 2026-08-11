#import <Foundation/Foundation.h>

@interface CrashLogParser : NSObject
+ (instancetype)sharedParser;
- (NSArray<NSString *> *)scanCrashLogDirectories;
- (NSArray<NSDictionary *> *)parseAllRecentCrashLogs;
- (NSArray<NSDictionary *> *)crashLogsForBundleID:(NSString *)bundleID;
- (NSDictionary *)parseCrashLogAtPath:(NSString *)path;
- (NSArray<NSDictionary *> *)newCrashLogsSince:(NSDate *)date;
- (NSArray<NSString *> *)crashLogPathsForBundleID:(NSString *)bundleID;
@end
