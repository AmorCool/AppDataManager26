#import "LaunchDetector.h"
#import "Logger.h"
#import "ProcessMonitor.h"

static NSString * const kLaunchHistoryKey = @"IPAInstallerPro_LaunchHistory_v1";

@interface LaunchDetector ()
@property (nonatomic, strong) NSMutableDictionary *pendingLaunches;
@property (nonatomic, strong) NSMutableArray *launchHistory;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSTimer *checkTimer;
@end

@implementation LaunchDetector

+ (instancetype)sharedDetector {
    static LaunchDetector *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.aosaid.launchdetector", DISPATCH_QUEUE_SERIAL);
        _pendingLaunches = [NSMutableDictionary dictionary];
        [self loadHistory];
    }
    return self;
}

- (void)loadHistory {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kLaunchHistoryKey];
    _launchHistory = saved ? [saved mutableCopy] : [NSMutableArray array];
}

- (void)saveHistory {
    if (self.launchHistory.count > 200) {
        [self.launchHistory removeObjectsInRange:NSMakeRange(0, self.launchHistory.count - 200)];
    }
    [[NSUserDefaults standardUserDefaults] setObject:[self.launchHistory copy] forKey:kLaunchHistoryKey];
}

- (void)startDetection {
    self.checkTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(checkPendingLaunches) userInfo:nil repeats:YES];
    [[Logger sharedLogger] info:@"LaunchDetector: Started"];
}

- (void)stopDetection {
    [self.checkTimer invalidate];
    self.checkTimer = nil;
}

- (void)willLaunchApp:(NSString *)bundleID {
    if (!bundleID) return;
    dispatch_async(self.queue, ^{
        self.pendingLaunches[bundleID] = @{ @"bundleID": bundleID, @"attemptTime": [NSDate date], @"status": @"pending" };
        [[Logger sharedLogger] info:[NSString stringWithFormat:@"LaunchDetector: Will launch %@", bundleID]];
    });
}

- (void)didLaunchApp:(NSString *)bundleID pid:(int)pid {
    if (!bundleID) return;
    dispatch_async(self.queue, ^{
        NSDictionary *pending = self.pendingLaunches[bundleID];
        NSDate *attemptTime = pending[@"attemptTime"] ?: [NSDate date];
        NSDictionary *record = @{ @"bundleID": bundleID, @"pid": @(pid), @"attemptTime": attemptTime, @"launchTime": [NSDate date], @"status": @"launched", @"eventType": @"LAUNCH" };
        [self.launchHistory addObject:record];
        [self saveHistory];
        [self.pendingLaunches removeObjectForKey:bundleID];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"AppDidLaunch" object:nil userInfo:record];
    });
}

- (void)launchFailedForApp:(NSString *)bundleID reason:(NSString *)reason {
    if (!bundleID) return;
    dispatch_async(self.queue, ^{
        NSDictionary *pending = self.pendingLaunches[bundleID];
        NSDate *attemptTime = pending[@"attemptTime"] ?: [NSDate date];
        NSDictionary *record = @{ @"bundleID": bundleID, @"attemptTime": attemptTime, @"status": @"failed", @"failureTime": [NSDate date], @"reason": reason ?: @"Unknown", @"eventType": @"LAUNCH_FAILURE" };
        [self.launchHistory addObject:record];
        [self saveHistory];
        [self.pendingLaunches removeObjectForKey:bundleID];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"AppLaunchFailed" object:nil userInfo:record];
    });
}

- (void)checkPendingLaunches {
    dispatch_async(self.queue, ^{
        NSDate *now = [NSDate date];
        NSMutableArray *toRemove = [NSMutableArray array];
        for (NSString *bundleID in self.pendingLaunches) {
            NSDictionary *pending = self.pendingLaunches[bundleID];
            NSDate *attemptTime = pending[@"attemptTime"];
            if (attemptTime && [now timeIntervalSinceDate:attemptTime] > 10.0) {
                BOOL isRunning = [[ProcessMonitor sharedMonitor] isProcessRunningForBundleID:bundleID];
                if (!isRunning) {
                    [self launchFailedForApp:bundleID reason:@"Process did not start within timeout"];
                }
                [toRemove addObject:bundleID];
            }
        }
        for (NSString *bundleID in toRemove) {
            [self.pendingLaunches removeObjectForKey:bundleID];
        }
    });
}

- (NSArray<NSDictionary *> *)launchHistoryForBundleID:(NSString *)bundleID {
    if (!bundleID) return @[];
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *record in self.launchHistory) {
        if ([record[@"bundleID"] isEqualToString:bundleID]) [filtered addObject:record];
    }
    return filtered;
}

- (NSArray<NSDictionary *> *)allLaunchAttempts { return [self.launchHistory copy]; }

- (NSArray<NSDictionary *> *)failedLaunches {
    NSMutableArray *failed = [NSMutableArray array];
    for (NSDictionary *record in self.launchHistory) {
        if ([record[@"status"] isEqualToString:@"failed"]) [failed addObject:record];
    }
    return failed;
}

@end
