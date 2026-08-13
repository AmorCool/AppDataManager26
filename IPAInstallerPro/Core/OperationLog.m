//
// OperationLog.m
// IPA Installer Pro
//
// v2.1 — Complete implementation matching header with OperationRecord objects
//

#import "OperationLog.h"
#import "Logger.h"

static NSString * const kLogFileName = @"IPAInstallerPro_OperationLog.plist";

@interface OperationLog ()
@property (nonatomic, strong) NSMutableArray<OperationRecord *> *records;
@property (nonatomic, strong) dispatch_queue_t logQueue;
@property (nonatomic, strong) NSString *logFilePath;
@property (nonatomic, strong) NSString *activeTxnID;
@end

@implementation OperationLog

+ (instancetype)sharedLog {
    static OperationLog *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

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

#pragma mark - Transaction Lifecycle

- (NSString *)beginTransactionForIPA:(NSString *)ipaPath {
    NSString *txnID = [[NSUUID UUID] UUIDString];
    self.activeTxnID = txnID;

    OperationRecord *rec = [[OperationRecord alloc] init];
    rec->_recordID = [[NSUUID UUID] UUIDString];
    rec->_transactionID = txnID;
    rec->_timestamp = [NSDate date];
    rec->_phase = OperationPhaseStart;
    rec->_operation = @"beginTransaction";
    rec->_target = [ipaPath lastPathComponent];
    rec->_input = ipaPath ?: @"";
    rec->_exitCode = 0;
    rec->_rawOutput = @"";
    rec->_rawError = @"";
    rec->_verification = @"Transaction started";
    rec->_verified = YES;
    rec->_result = OperationResultPending;
    rec->_duration = 0;
    rec->_context = @{};

    [self addRecord:rec];
    return txnID;
}

- (void)endTransaction:(NSString *)transactionID finalResult:(OperationResult)result {
    self.activeTxnID = nil;

    OperationRecord *rec = [[OperationRecord alloc] init];
    rec->_recordID = [[NSUUID UUID] UUIDString];
    rec->_transactionID = transactionID;
    rec->_timestamp = [NSDate date];
    rec->_phase = OperationPhaseComplete;
    rec->_operation = @"endTransaction";
    rec->_target = @"";
    rec->_input = @"";
    rec->_exitCode = (result == OperationResultSuccess) ? 0 : 1;
    rec->_rawOutput = @"";
    rec->_rawError = @"";
    rec->_verification = [NSString stringWithFormat:@"Transaction ended with result: %@", [self resultName:result]];
    rec->_verified = (result == OperationResultSuccess);
    rec->_result = result;
    rec->_duration = 0;
    rec->_context = @{};

    [self addRecord:rec];
}

#pragma mark - Phase Lifecycle

- (NSString *)beginPhase:(OperationPhase)phase operation:(NSString *)operation target:(NSString *)target input:(NSString *)input transactionID:(NSString *)transactionID {
    NSString *recID = [[NSUUID UUID] UUIDString];

    OperationRecord *rec = [[OperationRecord alloc] init];
    rec->_recordID = recID;
    rec->_transactionID = transactionID ?: @"";
    rec->_timestamp = [NSDate date];
    rec->_phase = phase;
    rec->_operation = operation ?: @"";
    rec->_target = target ?: @"";
    rec->_input = input ?: @"";
    rec->_exitCode = -1;
    rec->_rawOutput = @"";
    rec->_rawError = @"";
    rec->_verification = @"Phase started";
    rec->_verified = NO;
    rec->_result = OperationResultPending;
    rec->_duration = 0;
    rec->_context = @{};

    [self addRecord:rec];
    return recID;
}

- (void)endPhase:(NSString *)recordID exitCode:(int)exitCode rawOutput:(NSString *)rawOutput rawError:(NSString *)rawError verification:(NSString *)verification verified:(BOOL)verified duration:(NSTimeInterval)duration {
    [self endPhase:recordID exitCode:exitCode rawOutput:rawOutput rawError:rawError verification:verification verified:verified duration:duration context:@{}];
}

- (void)endPhase:(NSString *)recordID exitCode:(int)exitCode rawOutput:(NSString *)rawOutput rawError:(NSString *)rawError verification:(NSString *)verification verified:(BOOL)verified duration:(NSTimeInterval)duration context:(NSDictionary *)context {
    dispatch_async(self.logQueue, ^{
        for (NSUInteger i = 0; i < self.records.count; i++) {
            OperationRecord *rec = self.records[i];
            if ([rec.recordID isEqualToString:recordID]) {
                // Recreate with updated values (since properties are readonly)
                OperationRecord *updated = [[OperationRecord alloc] init];
                updated->_recordID = rec.recordID;
                updated->_transactionID = rec.transactionID;
                updated->_timestamp = rec.timestamp;
                updated->_phase = rec.phase;
                updated->_operation = rec.operation;
                updated->_target = rec.target;
                updated->_input = rec.input;
                updated->_exitCode = exitCode;
                updated->_rawOutput = rawOutput ?: @"";
                updated->_rawError = rawError ?: @"";
                updated->_verification = verification ?: @"";
                updated->_verified = verified;
                updated->_result = verified ? (exitCode == 0 ? OperationResultSuccess : OperationResultPartial) : OperationResultFailed;
                updated->_duration = duration;
                updated->_context = context ?: @{};
                self.records[i] = updated;
                [self saveLog];
                [self broadcastRecordUpdated:updated];
                break;
            }
        }
    });
}

#pragma mark - Record Management

- (void)addRecord:(OperationRecord *)record {
    dispatch_async(self.logQueue, ^{
        [self.records addObject:record];
        [self saveLog];
        [self broadcastRecordAdded:record];
    });
}

- (OperationRecord *)recordByID:(NSString *)recordID {
    __block OperationRecord *result = nil;
    dispatch_sync(self.logQueue, ^{
        for (OperationRecord *rec in self.records) {
            if ([rec.recordID isEqualToString:recordID]) {
                result = rec;
                break;
            }
        }
    });
    return result;
}

- (NSArray<OperationRecord *> *)recordsForTransaction:(NSString *)transactionID {
    __block NSArray *result = nil;
    dispatch_sync(self.logQueue, ^{
        NSMutableArray *filtered = [NSMutableArray array];
        for (OperationRecord *rec in self.records) {
            if ([rec.transactionID isEqualToString:transactionID]) [filtered addObject:rec];
        }
        result = [filtered copy];
    });
    return result;
}

- (NSArray<OperationRecord *> *)failedRecordsInTransaction:(NSString *)transactionID {
    NSMutableArray *failed = [NSMutableArray array];
    for (OperationRecord *rec in [self recordsForTransaction:transactionID]) {
        if (rec.result == OperationResultFailed) [failed addObject:rec];
    }
    return failed;
}

- (OperationRecord *)firstFailureInTransaction:(NSString *)transactionID {
    for (OperationRecord *rec in [self recordsForTransaction:transactionID]) {
        if (rec.result == OperationResultFailed) return rec;
    }
    return nil;
}

- (BOOL)transactionHasFailures:(NSString *)transactionID {
    return [self firstFailureInTransaction:transactionID] != nil;
}

- (NSArray<OperationRecord *> *)allRecords {
    __block NSArray *result = nil;
    dispatch_sync(self.logQueue, ^{ result = [self.records copy]; });
    return result;
}

- (NSArray<NSString *> *)allTransactionIDs {
    NSMutableSet *txns = [NSMutableSet set];
    for (OperationRecord *rec in self.records) {
        if (rec.transactionID.length > 0) [txns addObject:rec.transactionID];
    }
    return [txns allObjects];
}

- (void)clearTransaction:(NSString *)transactionID {
    dispatch_async(self.logQueue, ^{
        NSMutableIndexSet *toRemove = [NSMutableIndexSet indexSet];
        for (NSUInteger i = 0; i < self.records.count; i++) {
            if ([self.records[i].transactionID isEqualToString:transactionID]) {
                [toRemove addIndex:i];
            }
        }
        [self.records removeObjectsAtIndexes:toRemove];
        [self saveLog];
    });
}

- (void)clearAll {
    dispatch_async(self.logQueue, ^{
        [self.records removeAllObjects];
        [self saveLog];
    });
}

#pragma mark - Reports

- (NSString *)transactionReport:(NSString *)txnID {
    if (!txnID) return @"";
    NSArray *records = [self recordsForTransaction:txnID];
    NSMutableString *report = [NSMutableString string];
    [report appendFormat:@"Transaction Report: %@\n", txnID];
    [report appendFormat:@"Total records: %lu\n\n", (unsigned long)records.count];
    for (OperationRecord *rec in records) {
        [report appendFormat:@"%@ [%@] %@ — %@ (exit=%d)\n",
         [rec resultSymbol], [rec phaseName], rec.operation, rec.target, rec.exitCode];
        if (rec.rawError.length > 0) [report appendFormat:@"   ⚠️ %@\n", rec.rawError];
    }
    return report;
}

- (NSString *)transactionSummary:(NSString *)txnID {
    NSArray *records = [self recordsForTransaction:txnID];
    NSUInteger total = records.count;
    NSUInteger failed = 0;
    for (OperationRecord *rec in records) {
        if (rec.result == OperationResultFailed) failed++;
    }
    return [NSString stringWithFormat:@"%lu phases, %lu failed", (unsigned long)total, (unsigned long)failed];
}

- (NSDictionary *)transactionStats:(NSString *)txnID {
    NSArray *records = [self recordsForTransaction:txnID];
    NSUInteger total = records.count;
    NSUInteger failed = 0;
    NSTimeInterval totalDuration = 0;
    for (OperationRecord *rec in records) {
        if (rec.result == OperationResultFailed) failed++;
        totalDuration += rec.duration;
    }
    return @{
        @"totalRecords": @(total),
        @"failedRecords": @(failed),
        @"successRate": @(total > 0 ? (total - failed) / (double)total : 0),
        @"totalDuration": @(totalDuration)
    };
}

- (NSString *)exportTransactionAsJSON:(NSString *)txnID {
    NSArray *records = [self recordsForTransaction:txnID];
    NSMutableArray *dicts = [NSMutableArray array];
    for (OperationRecord *rec in records) {
        [dicts addObject:[rec dictionaryRepresentation]];
    }
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dicts options:NSJSONWritingPrettyPrinted error:&error];
    return jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";
}

#pragma mark - Helpers

- (NSString *)resultName:(OperationResult)result {
    switch (result) {
        case OperationResultSuccess: return @"SUCCESS";
        case OperationResultFailed: return @"FAILED";
        case OperationResultSkipped: return @"SKIPPED";
        case OperationResultPartial: return @"PARTIAL";
        default: return @"PENDING";
    }
}

#pragma mark - Persistence

- (void)saveLog {
    NSMutableArray *dicts = [NSMutableArray array];
    for (OperationRecord *rec in self.records) {
        [dicts addObject:[rec dictionaryRepresentation]];
    }
    [dicts writeToFile:self.logFilePath atomically:YES];
}

- (void)loadLog {
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.logFilePath]) {
        NSArray *loaded = [NSArray arrayWithContentsOfFile:self.logFilePath];
        if (loaded) {
            // Convert dictionaries back to OperationRecord objects
            for (NSDictionary *dict in loaded) {
                OperationRecord *rec = [[OperationRecord alloc] init];
                rec->_recordID = dict[@"recordID"] ?: @"";
                rec->_transactionID = dict[@"transactionID"] ?: @"";
                rec->_timestamp = dict[@"timestamp"] ?: [NSDate date];
                rec->_phase = [dict[@"phase"] integerValue];
                rec->_operation = dict[@"operation"] ?: @"";
                rec->_target = dict[@"target"] ?: @"";
                rec->_input = dict[@"input"] ?: @"";
                rec->_exitCode = [dict[@"exitCode"] intValue];
                rec->_rawOutput = dict[@"rawOutput"] ?: @"";
                rec->_rawError = dict[@"rawError"] ?: @"";
                rec->_verification = dict[@"verification"] ?: @"";
                rec->_verified = [dict[@"verified"] boolValue];
                rec->_result = [dict[@"result"] integerValue];
                rec->_duration = [dict[@"duration"] doubleValue];
                rec->_context = dict[@"context"] ?: @{};
                [self.records addObject:rec];
            }
        }
    }
}

#pragma mark - NSNotificationCenter

- (void)broadcastRecordAdded:(OperationRecord *)record {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"OperationRecordAdded"
                                                            object:self
                                                          userInfo:@{@"record": [record dictionaryRepresentation]}];
    });
}

- (void)broadcastRecordUpdated:(OperationRecord *)record {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"OperationRecordUpdated"
                                                            object:self
                                                          userInfo:@{@"record": [record dictionaryRepresentation]}];
    });
}

@end
