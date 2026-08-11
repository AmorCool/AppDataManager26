#import <Foundation/Foundation.h>

@interface LaunchDetector : NSObject
+ (instancetype)sharedDetector;
- (void)startDetection;
- (void)stopDetection;
- (void)willLaunchApp:(NSString *)bundleID;
- (void)didLaunchApp:(NSString *)bundleID pid:(int)pid;
- (void)launchFailedForApp:(NSString *)bundleID reason:(NSString *)reason;
- (NSArray<NSDictionary *> *)launchHistoryForBundleID:(NSString *)bundleID;
- (NSArray<NSDictionary *> *)allLaunchAttempts;
- (NSArray<NSDictionary *> *)failedLaunches;
@end
