#import <Foundation/Foundation.h>

@interface ProcessMonitor : NSObject
+ (instancetype)sharedMonitor;
- (void)startMonitoring;
- (void)stopMonitoring;
- (BOOL)isMonitoring;
- (NSArray<NSDictionary *> *)runningProcesses;
- (NSDictionary *)processInfoForPID:(int)pid;
- (BOOL)isProcessRunning:(int)pid;
- (BOOL)isProcessRunningForBundleID:(NSString *)bundleID;
- (NSString *)bundleIDForPID:(int)pid;
- (NSString *)processNameForPID:(int)pid;
- (NSString *)executablePathForPID:(int)pid;
- (void)trackProcess:(int)pid bundleID:(NSString *)bundleID name:(NSString *)name;
@end
