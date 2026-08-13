//
// OperationLog.m
// IPA Installer Pro
//
// v2.1 — Added NSNotificationCenter broadcasts for real-time UI updates
//

#import "OperationLog.h"
#import "Logger.h"

static NSString * const kLogFileName = @"IPAInstallerPro_OperationLog.plist";

@interface OperationLog ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *records;
@property (nonatomic, strong) dispatch_queue_t logQueue;
@property (nonatomic, strong) NSString *logFilePath;
@end

@implementation OperationLog

- (instancetype)init {
    self = [super init];
    if (self) {
        _logQueue = dispatch_queue_create("com.aosaid.ipainstallerpro.oplog", DISPATCH_QUEUE_SERIAL);
        _records = [NSMutableArray array];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docs = paths.firstObject;
        _logFilePath = [docs stringByAppendingPathComponent:kLogFileName];
        [self loadLog];
    }
    return self;
}

#pragma mark - Transaction Management

- (NSString *)beginTransactionForIPA:(NSString *)ipaPath {
    NSString *txnID = [[NSUUID UUID] UUIDString];
    NSDictionary *txn = @{
        @"recordID": [[NSUUID UUID] UUIDString],
        @"transactionID": txnID,
        @"timestamp": [NSDate date],
        @"phase": @"TRANSACTION_BEGIN",
        @"operation": @"beginTransaction",
        @"target": [ipaPath lastPathComponent],
        @"input": ipaPath ?: @"",
        @"exitCode": @0,
        @"rawOutput": @"",
        @"rawError": @"",
        @"verification": @"Transaction started",
        @"verified": @YES,
        @"duration": @0
    };
    [self addRecord:txn];
    return txnID;
}

- (void)endTransaction:(NSString *)transactionID finalResult:(NSString *)result {
    NSDictionary *rec = @{
        @"recordID": [[NSUUID UUID] UUIDString],
        @"transactionID": transactionID,
        @"timestamp": [NSDate date],
        @"phase": @"TRANSACTION_END",
        @"operation": @"endTransaction",
        @"target": result ?: @"UNKNOWN",
        @"input": @"",
        @"exitCode": [result isEqualToString:OperationResultSuccess] ? @0 : @1,
        @"rawOutput": @"",
        @"rawError": @"",
        @"verification": [NSString stringWithFormat:@"Transaction ended with result: %@", result ?: @"UNKNOWN"],
        @"verified": [result isEqualToString:OperationResultSuccess] ? @YES : @NO,
        @"duration": @0
    };
    [self addRecord:rec];
}

#pragma mark - Phase Recording

- (NSString *)beginPhase:(NSString *)phase operation:(NSString *)operation target:(NSString *)target input:(NSString *)input transactionID:(NSString *)transactionID {
    NSString *recID = [[NSUUID UUID] UUIDString];
    NSDictionary *rec = @{
        @"recordID": recID,
        @"transactionID": transactionID ?: @"",
        @"timestamp": [NSDate date],
        @"phase": phase ?: @"UNKNOWN",
        @"operation": operation ?: @"",
        @"target": target ?: @"",
        @"input": input ?: @"",
        @"exitCode": @(-1),
        @"rawOutput": @"",
        @"rawError": @"",
        @"verification": @"Phase started",
        @"verified": @NO,
        @"duration": @0
    };
    [self addRecord:rec];
    return recID;
}

- (void)endPhase:(NSString *)recordID exitCode:(int)exitCode rawOutput:(NSString *)rawOutput rawError:(NSString *)rawError verification:(NSString *)verification verified:(BOOL)verified duration:(NSTimeInterval)duration {
    dispatch_async(self.logQueue, ^{
        for (NSUInteger i = 0; i < self.records.count; i++) {
            NSMutableDictionary *rec = [self.records[i] mutableCopy];
            if ([rec[@"recordID"] isEqualToString:recordID]) {
                rec[@"exitCode"] = @(exitCode);
                rec[@"rawOutput"] = rawOutput ?: @"";
                rec[@"rawError"] = rawError ?: @"";
                rec[@"verification"] = verification ?: @"";
                rec[@"verified"] = @(verified);
                rec[@"duration"] = @(duration);
                self.records[i] = rec;
                [self saveLog];
                [self broadcastRecordUpdated:rec];
                break;
            }
        }
    });
}

#pragma mark - Record Management

- (void)addRecord:(NSDictionary *)record {
    dispatch_async(self.logQueue, ^{
        [self.records addObject:record];
        [self saveLog];
        [self broadcastRecordAdded:record];
    });
}

- (NSArray<NSDictionary *> *)recordsForTransaction:(NSString *)transactionID {
    __block NSArray *result = nil;
    dispatch_sync(self.logQueue, ^{
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSDictionary *rec in self.records) {
            if ([rec[@"transactionID"] isEqualToString:transactionID]) [filtered addObject:rec];
        }
        result = [filtered copy];
    });
    return result;
}

- (NSArray<NSDictionary *> *)allRecords {
    __block NSArray *result = nil;
    dispatch_sync(self.logQueue, ^{ result = [self.records copy]; });
    return result;
}

- (void)clearLog {
    dispatch_async(self.logQueue, ^{
        [self.records removeAllObjects];
        [self saveLog];
    });
}

#pragma mark - Persistence

- (void)saveLog {
    if (self.logFilePath) {
        [self.records writeToFile:self.logFilePath atomically:YES];
    }
}

- (void)loadLog {
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.logFilePath]) {
        NSArray *loaded = [NSArray arrayWithContentsOfFile:self.logFilePath];
        if (loaded) self.records = [loaded mutableCopy];
    }
}

#pragma mark - NSNotificationCenter Broadcasts

- (void)broadcastRecordAdded:(NSDictionary *)record {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"OperationRecordAdded" object:self userInfo:@{@"record": record ?: @{}}];
    });
}

- (void)broadcastRecordUpdated:(NSDictionary *)record {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"OperationRecordUpdated" object:self userInfo:@{@"record": record ?: @{}}];
    });
}

@end
