//
// OperationLog.m
// IPAInstallerPro
//

#import "OperationLog.h"

// ============================================================
// OperationRecord
// ============================================================

@interface OperationRecord ()
@property (nonatomic, strong, readwrite) NSString *recordID;
@property (nonatomic, strong, readwrite) NSString *operationID;
@property (nonatomic, strong, readwrite) NSDate *timestamp;
@property (nonatomic, assign, readwrite) OperationPhase phase;
@property (nonatomic, strong, readwrite) NSString *operation;
@property (nonatomic, strong, readwrite) NSString *target;
@property (nonatomic, assign, readwrite) OperationResult result;
@property (nonatomic, assign, readwrite) int exitCode;
@property (nonatomic, strong, readwrite) NSString *rawOutput;
@property (nonatomic, strong, readwrite) NSString *rawError;
@property (nonatomic, assign, readwrite) NSTimeInterval duration;
@property (nonatomic, strong, readwrite) NSDictionary *context;
@end

@implementation OperationRecord

- (instancetype)initWithOperationID:(NSString *)opID
                              phase:(OperationPhase)phase
                          operation:(NSString *)operation
                             target:(NSString *)target
                             result:(OperationResult)result
                           exitCode:(int)exitCode
                          rawOutput:(NSString *)rawOutput
                           rawError:(NSString *)rawError
                           duration:(NSTimeInterval)duration
                            context:(NSDictionary *)context {
    self = [super init];
    if (self) {
        _recordID = [[NSUUID UUID] UUIDString];
        _operationID = opID ?: @"unknown";
        _timestamp = [NSDate date];
        _phase = phase;
        _operation = operation ?: @"unknown";
        _target = target ?: @"";
        _result = result;
        _exitCode = exitCode;
        _rawOutput = rawOutput ?: @"";
        _rawError = rawError ?: @"";
        _duration = duration;
        _context = context ?: @{};
    }
    return self;
}

- (NSString *)formattedTimestamp {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss.SSS";
    return [fmt stringFromDate:self.timestamp];
}

- (NSString *)phaseName {
    switch (self.phase) {
        case OperationPhaseStart: return @"START";
        case OperationPhaseIPAOpen: return @"IPA_OPEN";
        case OperationPhaseIPAValidate: return @"IPA_VALIDATE";
        case OperationPhaseIPAExtract: return @"IPA_EXTRACT";
        case OperationPhaseAppIdentify: return @"APP_IDENTIFY";
        case OperationPhaseFileCopy: return @"FILE_COPY";
        case OperationPhaseFramework: return @"FRAMEWORK";
        case OperationPhaseDylib: return @"DYLIB";
        case OperationPhaseSign: return @"SIGN";
        case OperationPhasePermission: return @"PERMISSION";
        case OperationPhaseUICache: return @"UICACHE";
        case OperationPhaseVerify: return @"VERIFY";
        case OperationPhaseLaunch: return @"LAUNCH";
        case OperationPhaseCleanup: return @"CLEANUP";
        case OperationPhaseComplete: return @"COMPLETE";
        default: return @"UNKNOWN";
    }
}

- (NSString *)resultSymbol {
    switch (self.result) {
        case OperationResultSuccess: return @"✅";
        case OperationResultFailed: return @"❌";
        case OperationResultSkipped: return @"⏭";
        case OperationResultPartial: return @"⚠️";
        case OperationResultPending: return @"⏳";
        default: return @"❓";
    }
}

- (NSString *)resultName {
    switch (self.result) {
        case OperationResultSuccess: return @"SUCCESS";
        case OperationResultFailed: return @"FAILED";
        case OperationResultSkipped: return @"SKIPPED";
        case OperationResultPartial: return @"PARTIAL";
        case OperationResultPending: return @"PENDING";
        default: return @"UNKNOWN";
    }
}

- (NSString *)logLine {
    return [NSString stringWithFormat:@"[%@] [%@] %@ %@ | %@ | exit=%d | %.3fs",
            [self formattedTimestamp],
            [self phaseName],
            [self resultSymbol],
            self.operation,
            self.target,
            self.exitCode,
            self.duration];
}

- (NSString *)detailDump {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"Record: %@\n", self.recordID];
    [s appendFormat:@"Transaction: %@\n", self.operationID];
    [s appendFormat:@"Time: %@\n", [self formattedTimestamp]];
    [s appendFormat:@"Phase: %@\n", [self phaseName]];
    [s appendFormat:@"Operation: %@\n", self.operation];
    [s appendFormat:@"Target: %@\n", self.target];
    [s appendFormat:@"Result: %@\n", [self resultName]];
    [s appendFormat:@"Exit Code: %d\n", self.exitCode];
    [s appendFormat:@"Duration: %.3f seconds\n", self.duration];
    if (self.rawOutput.length > 0) [s appendFormat:@"Raw Output:\n%@\n", self.rawOutput];
    if (self.rawError.length > 0) [s appendFormat:@"Raw Error:\n%@\n", self.rawError];
    if (self.context.count > 0) [s appendFormat:@"Context: %@\n", self.context];
    return s;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"recordID": self.recordID,
        @"operationID": self.operationID,
        @"timestamp": [self formattedTimestamp],
        @"phase": [self phaseName],
        @"operation": self.operation,
        @"target": self.target,
        @"result": [self resultName],
        @"exitCode": @(self.exitCode),
        @"duration": @(self.duration),
        @"rawOutput": self.rawOutput,
        @"rawError": self.rawError,
        @"context": self.context
    };
}

@end

// ============================================================
// OperationLog
// ============================================================

static NSString * const kOperationLogStorageKey = @"IPAInstallerPro_OperationLog_v2";

@interface OperationLog ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<OperationRecord *> *> *transactions;
@property (nonatomic, strong) NSMutableArray<NSString *> *transactionOrder;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong, readwrite) NSString *activeTransactionID;
@end

@implementation OperationLog

+ (instancetype)sharedLog {
    static OperationLog *s = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.aosaid.operationlog", DISPATCH_QUEUE_SERIAL);
        _transactions = [NSMutableDictionary dictionary];
        _transactionOrder = [NSMutableArray array];
        [self loadLogs];
    }
    return self;
}

#pragma mark - Transaction Management

- (NSString *)beginTransactionForIPA:(NSString *)ipaPath {
    NSString *opID = [NSString stringWithFormat:@"op_%@_%@",
                      [[ipaPath lastPathComponent] stringByDeletingPathExtension] ?: @"unknown",
                      @((NSUInteger)([[NSDate date] timeIntervalSince1970] * 1000))];

    dispatch_async(self.queue, ^{
        self.transactions[opID] = [NSMutableArray array];
        [self.transactionOrder addObject:opID];
        self.activeTransactionID = opID;
    });

    // Log transaction start
    [self logOperation:@"BEGIN"
                 phase:OperationPhaseStart
                target:ipaPath
                result:OperationResultSuccess
              exitCode:0
             rawOutput:@""
              rawError:@""
              duration:0
               context:@{@"device": [UIDevice currentDevice].name,
                        @"systemVersion": [UIDevice currentDevice].systemVersion}
         operationID:opID];

    NSLog(@"[OperationLog] Transaction started: %@", opID);
    return opID;
}

- (void)endTransaction:(NSString *)operationID {
    [self logOperation:@"END"
                 phase:OperationPhaseComplete
                target:@""
                result:OperationResultSuccess
              exitCode:0
             rawOutput:@""
              rawError:@""
              duration:0
               context:@{}
         operationID:operationID];

    dispatch_async(self.queue, ^{
        if ([self.activeTransactionID isEqualToString:operationID]) {
            self.activeTransactionID = nil;
        }
        [self saveLogs];
    });

    NSLog(@"[OperationLog] Transaction ended: %@", operationID);
}

#pragma mark - Core Logging

- (void)logOperation:(NSString *)operation
             phase:(OperationPhase)phase
            target:(NSString *)target
            result:(OperationResult)result
          exitCode:(int)exitCode
          rawOutput:(NSString *)rawOutput
           rawError:(NSString *)rawError
          duration:(NSTimeInterval)duration
           context:(NSDictionary *)context
     operationID:(NSString *)operationID {

    OperationRecord *record = [[OperationRecord alloc] initWithOperationID:operationID
                                                                       phase:phase
                                                                   operation:operation
                                                                      target:target
                                                                      result:result
                                                                    exitCode:exitCode
                                                                   rawOutput:rawOutput
                                                                    rawError:rawError
                                                                    duration:duration
                                                                     context:context];

    dispatch_async(self.queue, ^{
        if (!self.transactions[operationID]) {
            self.transactions[operationID] = [NSMutableArray array];
        }
        [self.transactions[operationID] addObject:record];
    });

    // Always print to console
    NSLog(@"%@", [record logLine]);
    if (rawError.length > 0) NSLog(@"[OperationLog] ERROR: %@", rawError);
}

- (void)logCommand:(NSString *)command
              args:(NSArray *)args
            target:(NSString *)target
            result:(OperationResult)result
          exitCode:(int)exitCode
          rawOutput:(NSString *)rawOutput
           rawError:(NSString *)rawError
          duration:(NSTimeInterval)duration
     operationID:(NSString *)operationID {

    NSString *fullCmd = [NSString stringWithFormat:@"%@ %@", command, [args componentsJoinedByString:@" "]];
    [self logOperation:fullCmd
                 phase:OperationPhaseUnknown
                target:target
                result:result
              exitCode:exitCode
             rawOutput:rawOutput
              rawError:rawError
              duration:duration
               context:@{@"command": command, @"args": args ?: @[]}
         operationID:operationID];
}

- (void)logFileOp:(NSString *)operation
             from:(NSString *)sourcePath
               to:(NSString *)destPath
           result:(OperationResult)result
         exitCode:(int)exitCode
          rawError:(NSString *)rawError
         duration:(NSTimeInterval)duration
    operationID:(NSString *)operationID {

    NSString *target = destPath.length > 0 ? [NSString stringWithFormat:@"%@ -> %@", sourcePath, destPath] : sourcePath;
    OperationPhase phase = OperationPhaseFileCopy;
    if ([operation containsString:@"chmod"]) phase = OperationPhasePermission;
    else if ([operation containsString:@"remove"] || [operation containsString:@"rm"]) phase = OperationPhaseCleanup;
    else if ([operation containsString:@"sign"] || [operation containsString:@"ldid"]) phase = OperationPhaseSign;

    [self logOperation:operation
                 phase:phase
                target:target
                result:result
              exitCode:exitCode
             rawOutput:@""
              rawError:rawError
              duration:duration
               context:@{@"source": sourcePath ?: @"", @"destination": destPath ?: @""}
         operationID:operationID];
}

#pragma mark - Phase Markers

- (OperationRecord *)markPhaseStart:(OperationPhase)phase
                          operation:(NSString *)operation
                             target:(NSString *)target
                      operationID:(NSString *)operationID {

    OperationRecord *record = [[OperationRecord alloc] initWithOperationID:operationID
                                                                       phase:phase
                                                                   operation:operation
                                                                      target:target
                                                                      result:OperationResultPending
                                                                    exitCode:0
                                                                   rawOutput:@""
                                                                    rawError:@""
                                                                    duration:0
                                                                     context:@{}];

    dispatch_async(self.queue, ^{
        if (!self.transactions[operationID]) self.transactions[operationID] = [NSMutableArray array];
        [self.transactions[operationID] addObject:record];
    });

    NSLog(@"[OperationLog] ▶️  %@: %@", [record phaseName], operation);
    return record;
}

- (void)markPhaseEnd:(OperationPhase)phase
            record:(OperationRecord *)record
            result:(OperationResult)result
          exitCode:(int)exitCode
          rawOutput:(NSString *)rawOutput
           rawError:(NSString *)rawError
          duration:(NSTimeInterval)duration
           context:(NSDictionary *)context {

    if (!record) return;

    // Update the record in-place
    [record setValue:@(result) forKey:@"result"];
    [record setValue:@(exitCode) forKey:@"exitCode"];
    [record setValue:(rawOutput ?: @"") forKey:@"rawOutput"];
    [record setValue:(rawError ?: @"") forKey:@"rawError"];
    [record setValue:@(duration) forKey:@"duration"];
    [record setValue:(context ?: @{}) forKey:@"context"];

    NSString *icon = result == OperationResultSuccess ? @"✅" : (result == OperationResultFailed ? @"❌" : @"⏭");
    NSLog(@"[OperationLog] %@ %@ completed in %.3fs | exit=%d", icon, [record phaseName], duration, exitCode);
    if (rawError.length > 0) NSLog(@"[OperationLog]   Error: %@", rawError);

    dispatch_async(self.queue, ^{ [self saveLogs]; });
}

#pragma mark - Query

- (NSArray<OperationRecord *> *)recordsForTransaction:(NSString *)operationID {
    __block NSArray<OperationRecord *> *result;
    dispatch_sync(self.queue, ^{ result = [self.transactions[operationID] copy]; });
    return result ?: @[];
}

- (NSArray<OperationRecord *> *)allRecords {
    __block NSMutableArray *all = [NSMutableArray array];
    dispatch_sync(self.queue, ^{
        for (NSString *tid in self.transactionOrder) {
            [all addObjectsFromArray:self.transactions[tid]];
        }
    });
    return all;
}

- (NSArray<OperationRecord *> *)failedRecords {
    NSMutableArray *failed = [NSMutableArray array];
    for (OperationRecord *r in [self allRecords]) {
        if (r.result == OperationResultFailed) [failed addObject:r];
    }
    return failed;
}

- (NSArray<OperationRecord *> *)recordsForPhase:(OperationPhase)phase {
    NSMutableArray *result = [NSMutableArray array];
    for (OperationRecord *r in [self allRecords]) {
        if (r.phase == phase) [result addObject:r];
    }
    return result;
}

- (OperationRecord *)lastRecordForTransaction:(NSString *)operationID {
    NSArray *records = [self recordsForTransaction:operationID];
    return records.lastObject;
}

#pragma mark - Reports

- (NSString *)transactionReport:(NSString *)operationID {
    NSArray<OperationRecord *> *records = [self recordsForTransaction:operationID];
    if (records.count == 0) return @"No records for this transaction.";

    NSMutableString *report = [NSMutableString string];
    [report appendString:@"═══════════════════════════════════════════════════\n"];
    [report appendString:@"  IPA INSTALLER PRO — INSTALLATION AUDIT TRAIL\n"];
    [report appendString:@"═══════════════════════════════════════════════════\n\n"];
    [report appendFormat:@"Transaction: %@\n", operationID];
    [report appendFormat:@"Total Operations: %lu\n\n", (unsigned long)records.count];

    // Statistics
    NSUInteger success = 0, failed = 0, skipped = 0;
    NSTimeInterval totalDuration = 0;
    for (OperationRecord *r in records) {
        switch (r.result) {
            case OperationResultSuccess: success++; break;
            case OperationResultFailed: failed++; break;
            case OperationResultSkipped: skipped++; break;
            default: break;
        }
        totalDuration += r.duration;
    }

    [report appendString:@"━━━ STATISTICS ━━━\n"];
    [report appendFormat:@"✅ Success: %lu\n", (unsigned long)success];
    [report appendFormat:@"❌ Failed: %lu\n", (unsigned long)failed];
    [report appendFormat:@"⏭ Skipped: %lu\n", (unsigned long)skipped];
    [report appendFormat:@"⏱ Total Duration: %.3f seconds\n\n", totalDuration];

    // Operation list
    [report appendString:@"━━━ OPERATIONS ━━━\n\n"];
    for (OperationRecord *r in records) {
        [report appendString:[r logLine]];
        [report appendString:@"\n"];
        if (r.rawError.length > 0) {
            [report appendFormat:@"     ERROR: %@\n", r.rawError];
        }
        if (r.rawOutput.length > 0 && r.rawOutput.length < 500) {
            [report appendFormat:@"     OUTPUT: %@\n", r.rawOutput];
        }
    }

    // Final status
    [report appendString:@"\n━━━ FINAL STATUS ━━━\n"];
    OperationRecord *last = records.lastObject;
    if (last.phase == OperationPhaseComplete && last.result == OperationResultSuccess) {
        [report appendString:@"✅ INSTALLATION COMPLETED\n"];
    } else if (failed > 0) {
        [report appendFormat:@"❌ INSTALLATION FAILED (%lu operation(s) failed)\n", (unsigned long)failed];
    } else {
        [report appendString:@"⚠️ INSTALLATION STATUS UNCLEAR\n"];
    }

    return report;
}

- (NSString *)transactionSummary:(NSString *)operationID {
    NSArray<OperationRecord *> *records = [self recordsForTransaction:operationID];
    if (records.count == 0) return @"No data";

    NSUInteger failed = 0;
    for (OperationRecord *r in records) {
        if (r.result == OperationResultFailed) failed++;
    }

    OperationRecord *first = records.firstObject;
    OperationRecord *last = records.lastObject;

    if (failed > 0) {
        return [NSString stringWithFormat:@"❌ Failed (%lu errors) | %@ operations", (unsigned long)failed, @(records.count)];
    } else if (last.phase == OperationPhaseComplete) {
        return [NSString stringWithFormat:@"✅ Completed | %@ operations | %.1fs", @(records.count), last.duration];
    } else {
        return [NSString stringWithFormat:@"⏳ In Progress | %@ operations", @(records.count)];
    }
}

- (NSDictionary *)transactionStats:(NSString *)operationID {
    NSArray<OperationRecord *> *records = [self recordsForTransaction:operationID];
    NSUInteger success = 0, failed = 0, skipped = 0;
    NSTimeInterval totalDuration = 0;
    for (OperationRecord *r in records) {
        switch (r.result) {
            case OperationResultSuccess: success++; break;
            case OperationResultFailed: failed++; break;
            case OperationResultSkipped: skipped++; break;
            default: break;
        }
        totalDuration += r.duration;
    }
    return @{
        @"totalOperations": @(records.count),
        @"success": @(success),
        @"failed": @(failed),
        @"skipped": @(skipped),
        @"totalDuration": @(totalDuration),
        @"successRate": records.count > 0 ? @(success / (double)records.count) : @0
    };
}

#pragma mark - Export

- (NSString *)exportTransactionAsJSON:(NSString *)operationID {
    NSArray<OperationRecord *> *records = [self recordsForTransaction:operationID];
    NSMutableArray *dicts = [NSMutableArray array];
    for (OperationRecord *r in records) {
        [dicts addObject:[r dictionaryRepresentation]];
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dicts options:NSJSONWritingPrettyPrinted error:&error];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

- (NSString *)exportAllAsJSON {
    NSMutableDictionary *all = [NSMutableDictionary dictionary];
    dispatch_sync(self.queue, ^{
        for (NSString *tid in self.transactionOrder) {
            NSMutableArray *dicts = [NSMutableArray array];
            for (OperationRecord *r in self.transactions[tid]) {
                [dicts addObject:[r dictionaryRepresentation]];
            }
            all[tid] = dicts;
        }
    });
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:all options:NSJSONWritingPrettyPrinted error:&error];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

#pragma mark - Management

- (void)clearTransaction:(NSString *)operationID {
    dispatch_async(self.queue, ^{
        [self.transactions removeObjectForKey:operationID];
        [self.transactionOrder removeObject:operationID];
        [self saveLogs];
    });
}

- (void)clearAll {
    dispatch_async(self.queue, ^{
        [self.transactions removeAllObjects];
        [self.transactionOrder removeAllObjects];
        self.activeTransactionID = nil;
        [self saveLogs];
    });
}

#pragma mark - Persistence

- (void)saveLogs {
    NSMutableArray *data = [NSMutableArray array];
    dispatch_sync(self.queue, ^{
        for (NSString *tid in self.transactionOrder) {
            NSMutableArray *records = [NSMutableArray array];
            for (OperationRecord *r in self.transactions[tid]) {
                [records addObject:[r dictionaryRepresentation]];
            }
            [data addObject:@{@"transactionID": tid, @"records": records}];
        }
    });
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:kOperationLogStorageKey];
}

- (void)loadLogs {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kOperationLogStorageKey];
    if (!saved) return;

    dispatch_async(self.queue, ^{
        for (NSDictionary *tDict in saved) {
            NSString *tid = tDict[@"transactionID"];
            NSArray *rDicts = tDict[@"records"];
            NSMutableArray *records = [NSMutableArray array];
            for (NSDictionary *dict in rDicts) {
                OperationRecord *r = [[OperationRecord alloc] initWithOperationID:dict[@"operationID"] ?: tid
                                                                              phase:OperationPhaseUnknown
                                                                          operation:dict[@"operation"] ?: @"unknown"
                                                                             target:dict[@"target"] ?: @""
                                                                             result:OperationResultSuccess
                                                                           exitCode:[dict[@"exitCode"] intValue]
                                                                          rawOutput:dict[@"rawOutput"] ?: @""
                                                                           rawError:dict[@"rawError"] ?: @""
                                                                           duration:[dict[@"duration"] doubleValue]
                                                                            context:dict[@"context"] ?: @{}];
                [records addObject:r];
            }
            self.transactions[tid] = records;
            [self.transactionOrder addObject:tid];
        }
    });
}

#pragma mark - Properties

- (NSArray<NSString *> *)allTransactionIDs {
    __block NSArray<NSString *> *result;
    dispatch_sync(self.queue, ^{ result = [self.transactionOrder copy]; });
    return result;
}

@end
