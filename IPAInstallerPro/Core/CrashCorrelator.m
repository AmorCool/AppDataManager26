//
// CrashCorrelator.m
// IPAInstallerPro
//

#import "CrashCorrelator.h"

@implementation CrashCorrelation
@end

@interface CrashCorrelator ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *installations;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *launches;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation CrashCorrelator

+ (instancetype)sharedCorrelator {
    static CrashCorrelator *s = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.aosaid.crashcorrelator", DISPATCH_QUEUE_SERIAL);
        _installations = [NSMutableDictionary dictionary];
        _launches = [NSMutableDictionary dictionary];
        _correlationWindow = 300.0; // 5 minutes
    }
    return self;
}

- (void)registerInstallation:(NSString *)bundleID installationID:(NSString *)installID timestamp:(NSDate *)date {
    if (!bundleID || !installID) return;
    dispatch_async(self.queue, ^{
        if (!self.installations[bundleID]) {
            self.installations[bundleID] = [NSMutableDictionary dictionary];
        }
        self.installations[bundleID][@"id"] = installID;
        self.installations[bundleID][@"time"] = date ?: [NSDate date];
    });
}

- (void)registerLaunch:(NSString *)bundleID launchID:(NSString *)launchID timestamp:(NSDate *)date {
    if (!bundleID || !launchID) return;
    dispatch_async(self.queue, ^{
        if (!self.launches[bundleID]) {
            self.launches[bundleID] = [NSMutableDictionary dictionary];
        }
        self.launches[bundleID][@"id"] = launchID;
        self.launches[bundleID][@"time"] = date ?: [NSDate date];
    });
}

- (CrashCorrelation *)correlateIncident:(CrashIncident *)incident {
    CrashCorrelation *corr = [[CrashCorrelation alloc] init];
    corr.incident = incident;

    NSString *bundleID = incident.bundleID;
    NSDate *crashTime = incident.timestamp;

    __block NSString *installID = nil;
    __block NSDate *installTime = nil;
    __block NSString *launchID = nil;
    __block NSDate *launchTime = nil;

    dispatch_sync(self.queue, ^{
        installID = self.installations[bundleID][@"id"];
        installTime = self.installations[bundleID][@"time"];
        launchID = self.launches[bundleID][@"id"];
        launchTime = self.launches[bundleID][@"time"];
    });

    corr.correlatedInstallationID = installID;
    corr.correlatedLaunchID = launchID;
    corr.installationTime = installTime;
    corr.launchTime = launchTime;

    if (installTime && crashTime) {
        corr.timeSinceInstall = [crashTime timeIntervalSinceDate:installTime];
        if (corr.timeSinceInstall >= 0 && corr.timeSinceInstall <= self.correlationWindow) {
            corr.isInstallRelated = YES;
        }
    }

    if (launchTime && crashTime) {
        corr.timeSinceLaunch = [crashTime timeIntervalSinceDate:launchTime];
        if (corr.timeSinceLaunch >= 0 && corr.timeSinceLaunch <= self.correlationWindow) {
            corr.isInstallRelated = YES;
        }
    }

    // Update incident with correlation data
    incident.correlatedInstallationID = installID;
    incident.correlatedLaunchID = launchID;

    return corr;
}

- (NSString *)lastInstallationIDForBundleID:(NSString *)bundleID {
    __block NSString *result;
    dispatch_sync(self.queue, ^{ result = self.installations[bundleID][@"id"]; });
    return result;
}

- (NSString *)lastLaunchIDForBundleID:(NSString *)bundleID {
    __block NSString *result;
    dispatch_sync(self.queue, ^{ result = self.launches[bundleID][@"id"]; });
    return result;
}

- (NSDate *)lastInstallationTimeForBundleID:(NSString *)bundleID {
    __block NSDate *result;
    dispatch_sync(self.queue, ^{ result = self.installations[bundleID][@"time"]; });
    return result;
}

- (NSDate *)lastLaunchTimeForBundleID:(NSString *)bundleID {
    __block NSDate *result;
    dispatch_sync(self.queue, ^{ result = self.launches[bundleID][@"time"]; });
    return result;
}

@end
