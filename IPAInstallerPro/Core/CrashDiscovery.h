//
// CrashDiscovery.h
// IPAInstallerPro
//
// Discovers crash logs ONLY for apps managed by IPA Installer Pro.
// Uses bundle ID whitelist + timestamp filtering.
//

#import <Foundation/Foundation.h>

@interface CrashDiscoveryResult : NSObject
@property (nonatomic, strong) NSArray<NSString *> *newPaths;
@property (nonatomic, strong) NSArray<NSString *> *allPaths;
@property (nonatomic, strong) NSDate *scanTime;
@end

@interface CrashDiscovery : NSObject
+ (instancetype)sharedDiscovery;

// Main: scan for crash logs belonging to specific bundle IDs
- (CrashDiscoveryResult *)discoverCrashLogsForBundleIDs:(NSArray<NSString *> *)bundleIDs
                                            sinceDate:(NSDate *)sinceDate;

// Scan all crash log directories
- (NSArray<NSString *> *)allCrashLogPaths;

// Check if a crash log belongs to a managed app
- (BOOL)isCrashLogManaged:(NSString *)path forBundleIDs:(NSArray<NSString *> *)bundleIDs;

// Get bundle ID from crash log path (quick peek, no full parse)
- (NSString *)peekBundleIDAtPath:(NSString *)path;

@property (nonatomic, strong, readonly) NSArray<NSString *> *crashLogDirectories;
@end
