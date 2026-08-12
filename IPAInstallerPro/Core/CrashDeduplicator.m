//
// CrashDeduplicator.m
// IPAInstallerPro
//

#import "CrashDeduplicator.h"

static NSString * const kDeduplicatorStateKey = @"IPAInstallerPro_DeduplicatorState_v1";

@interface CrashDeduplicator ()
@property (nonatomic, strong) NSMutableSet<NSString *> *fingerprints;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *fingerprintTimestamps;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, readwrite) NSUInteger totalDedupedCount;
@end

@implementation CrashDeduplicator

+ (instancetype)sharedDeduplicator {
    static CrashDeduplicator *s = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.aosaid.crashdeduplicator", DISPATCH_QUEUE_SERIAL);
        _fingerprints = [NSMutableSet set];
        _fingerprintTimestamps = [NSMutableDictionary dictionary];
        _totalDedupedCount = 0;
        [self loadState];
    }
    return self;
}

- (BOOL)isDuplicate:(CrashIncident *)incident {
    if (!incident || !incident.fingerprint) return NO;
    __block BOOL dup = NO;
    dispatch_sync(self.queue, ^{
        dup = [self.fingerprints containsObject:incident.fingerprint];
    });
    if (dup) {
        self.totalDedupedCount++;
        NSLog(@"[CrashDeduplicator] Duplicate suppressed: %@ (fp:%@)", incident.bundleID, incident.fingerprint);
    }
    return dup;
}

- (void)recordIncident:(CrashIncident *)incident {
    if (!incident || !incident.fingerprint) return;
    dispatch_async(self.queue, ^{
        [self.fingerprints addObject:incident.fingerprint];
        self.fingerprintTimestamps[incident.fingerprint] = [NSDate date];
        [self saveState];
    });
}

- (NSArray<NSString *> *)allFingerprints {
    __block NSArray<NSString *> *result;
    dispatch_sync(self.queue, ^{ result = [self.fingerprints allObjects]; });
    return result;
}

- (void)clearAll {
    dispatch_async(self.queue, ^{
        [self.fingerprints removeAllObjects];
        [self.fingerprintTimestamps removeAllObjects];
        self.totalDedupedCount = 0;
        [self saveState];
    });
}

- (void)saveState {
    NSArray *fps = [self.fingerprints allObjects];
    [[NSUserDefaults standardUserDefaults] setObject:fps forKey:kDeduplicatorStateKey];
}

- (void)loadState {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kDeduplicatorStateKey];
    if (saved) {
        [self.fingerprints addObjectsFromArray:saved];
    }
}

@end
