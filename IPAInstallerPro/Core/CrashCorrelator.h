//
// CrashCorrelator.h
// IPAInstallerPro
//
// Correlates crash incidents with installation and launch events.
// Answers: "Did this crash happen because of our installation?"
//

#import <Foundation/Foundation.h>
#import "CrashIncident.h"

@interface CrashCorrelation : NSObject
@property (nonatomic, strong) CrashIncident *incident;
@property (nonatomic, strong) NSString *correlatedInstallationID;
@property (nonatomic, strong) NSString *correlatedLaunchID;
@property (nonatomic, strong) NSDate *installationTime;
@property (nonatomic, strong) NSDate *launchTime;
@property (nonatomic, assign) NSTimeInterval timeSinceInstall;
@property (nonatomic, assign) NSTimeInterval timeSinceLaunch;
@property (nonatomic, assign) BOOL isInstallRelated;
@end

@interface CrashCorrelator : NSObject
+ (instancetype)sharedCorrelator;

// Register events
- (void)registerInstallation:(NSString *)bundleID installationID:(NSString *)installID timestamp:(NSDate *)date;
- (void)registerLaunch:(NSString *)bundleID launchID:(NSString *)launchID timestamp:(NSDate *)date;

// Correlate an incident
- (CrashCorrelation *)correlateIncident:(CrashIncident *)incident;

// Query
- (NSString *)lastInstallationIDForBundleID:(NSString *)bundleID;
- (NSString *)lastLaunchIDForBundleID:(NSString *)bundleID;
- (NSDate *)lastInstallationTimeForBundleID:(NSString *)bundleID;
- (NSDate *)lastLaunchTimeForBundleID:(NSString *)bundleID;

// Time window for correlation (default: 5 minutes)
@property (nonatomic, assign) NSTimeInterval correlationWindow;
@end
