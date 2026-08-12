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
@property (nonatomic, strong, readwrite) NSString *transactionID;
@property (nonatomic, strong, readwrite) NSDate *timestamp;
@property (nonatomic, assign, readwrite) OperationPhase phase;
@property (nonatomic, strong, readwrite) NSString *operation;
@property (nonatomic, strong, readwrite) NSString *target;
@property (nonatomic, strong, readwrite) NSString *input;
@property (nonatomic, assign, readwrite) int exitCode;
@property (nonatomic, strong, readwrite) NSString *rawOutput;
@property (nonatomic, strong, readwrite) NSString *rawError;
@property (nonatomic, strong, readwrite) NSString *verification;
@property (nonatomic, assign, readwrite) BOOL verified;
@property (nonatomic, assign, readwrite) OperationResult result;
@property (nonatomic, assign, readwrite) NSTimeInterval duration;
@property (nonatomic, strong, readwrite) NSDictionary *context;
@end

@implementation OperationRecord

- (instancetype)init {
    self = [super init];
    if (self) {
        _recordID = [[NSUUID UUID] UUIDString];
        _timestamp = [NSDate date];
        _phase = OperationPhaseUnknown;
        _operation = @"unknown";
        _target = @"";
        _input = @"";
        _exitCode = -1;
        _rawOutput = @"";
        _rawError = @"";
        _verification = @"";
        _verified = NO;
        _result = OperationResultPending;
        _duration = 0;
        _context = @{};
    }
    return self;
}

- (NSString *)phaseName {
    switch (self.phase) {
        case OperationPhaseStart: return @"START";
        case OperationPhaseIPAOpen: return @"IPA_OPEN";
        case OperationPhaseIPAExtract: return @"IPA_EXTRACT";
        case OperationPhaseAppIdentify: return @"APP_IDENTIFY";
        case OperationPhaseFileCopy: return @"FILE_COPY";
        case OperationPhaseFramework: return @"FRAMEWORK";
        case OperationPhaseDylib: return @"DYLIB";
        case OperationPhaseSign: return @"SIGN";
        case OperationPhasePermission: return @"PERMISSION";
        case OperationPhaseUICache: return @"UICACHE";
        case OperationPhaseVerify: return @"VERIFY";
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
    if (self.result == OperationResultPending) {
        return [NSString stringWithFormat:@"[%@] [%@] ⏳ START | %@ | %@",
                [self timestampString], [self phaseName], self.operation, self.target];
    }
    return [NSString stringWithFormat:@"[%@] [%@] %@ %@ | exit=%d | verified=%@ | dur=%.3fs | %@",
            [self timestampString], [self phaseName], [self resultSymbol], self.operation,
            self.exitCode, self.verified ? @"YES" : @"NO", self.duration, self.target];
}

- (NSString *)timestampString {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss.SSS";
    return [fmt stringFromDate:self.timestamp];
}

- (NSString *)detailDump {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"Record: %@\n", self.recordID];
    [s appendFormat:@"Transaction: %@\n", self.transactionID];
    [s appendFormat:@"Time: %@\n", [self timestampString]];
    [s appendFormat:@"Phase: %@\n", [self phaseName]];
    [s appendFormat:@"Operation: %@\n", self.operation];
    [s appendFormat:@"Target: %@\n", self.target];
    [s appendFormat:@"Input: %@\n", self.input];
    [s appendFormat:@"Exit Code: %d\n", self.exitCode];
    [s appendFormat:@"Verification: %@\n", self.verification];
    [s appendFormat:@"Verified: %@\n", self.verified ? @"YES" : @"NO"];
    [s appendFormat:@"Result: %@\n", [self resultName]];
    [s appendFormat:@"Duration: %.3f seconds\n", self.duration];
    if (self.rawOutput.length > 0) [s appendFormat:@"Raw Output:\n%@\n", self.rawOutput];
    if (self.rawError.length > 0) [s appendFormat:@"Raw Error:\n%@\n", self.rawError];
    if (self.context.count > 0) [s appendFormat:@"Context: %@\n", self.context];
    return s;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"recordID": self.recordID,
        @"transactionID": self.transactionID,
        @"timestamp": [self timestampString],
        @"phase": [self phaseName],
        @"operation": self.operation,
        @"target": self.target,
        @"input": self.input,
        @"exitCode": @(self.exitCode),
        @"verification": self.verification,
        @"verified": @(self.verified),
        @"result": [self resultName],
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

static NSString * const kOperationLogStorageKey = @"IPAInstallerPro_OperationLog_v3";

@interface OperationLog ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<OperationRecord *> *> *transactions;
@property (nonatomic, strong) NSMutableArray<NSString *> *transactionOrder;
@property (nonatomic, strong) NSMutableDictionary<NSString *, OperationRecord *> *pendingRecords;
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
        _pendingRecords = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - Transaction Lifecycle

- (NSString *)beginTransactionForIPA:(NSString *)ipaPath {
    NSString *txnID = [NSString stringWithFormat:@"txn_%@_%@",
                       [[ipaPath lastPathComponent] stringByDeletingPathExtension] ?: @"unknown",
                       @((NSUInteger)([[NSDate date] timeIntervalSince1970] * 1000))];

    dispatch_async(self.queue, ^{
        self.transactions[txnID] = [NSMutableArray array];
        [self.transactionOrder addObject:txnID];
        self.activeTransactionID = txnID;
    });

    // Log transaction start as a completed record (no verification needed)
    OperationRecord *rec = [[OperationRecord alloc] init];
    rec.transactionID = txnID;
    rec.phase = OperationPhaseStart;
    rec.operation = @"BEGIN_TRANSACTION";
    rec.target = ipaPath;
    rec.input = ipaPath;
    rec.exitCode = 0;
    rec.verification = @"Transaction initialized";
    rec.verified = YES;
    rec.result = OperationResultSuccess;
    rec.duration = 0;

    dispatch_async(self.queue, ^{
        if (!self.transactions[txnID]) self.transactions[txnID] = [NSMutableArray array];
        [self.transactions[txnID] addObject:rec];
    });

    NSLog(@"[OperationLog] ▶️  TRANSACTION STARTED: %@", txnID);
    return txnID;
}

- (void)endTransaction:(NSString *)transactionID finalResult:(OperationResult)result {
    OperationRecord *rec = [[OperationRecord alloc] init];
    rec.transactionID = transactionID;
    rec.phase = OperationPhaseComplete;
    rec.operation = @"END_TRANSACTION";
    rec.target = @"";
    rec.exitCode = (result == OperationResultSuccess) ? 0 : 1;
    rec.verification = [NSString stringWithFormat:@"Final result: %@", [self resultName:result]];
    rec.verified = (result == OperationResultSuccess);
    rec.result = result;
    rec.duration = 0;

    dispatch_async(self.queue, ^{
        if (!self.transactions[transactionID]) self.transactions[transactionID] = [NSMutableArray array];
        [self.transactions[transactionID] addObject:rec];
        if ([self.activeTransactionID isEqualToString:transactionID]) self.activeTransactionID = nil;
    });

    NSString *icon = (result == OperationResultSuccess) ? @"✅" : @"❌";
    NSLog(@"[OperationLog] %@ TRANSACTION ENDED: %@ | Result: %@", icon, transactionID, [self resultName:result]);
}

#pragma mark - Phase Lifecycle

- (NSString *)beginPhase:(OperationPhase)phase
               operation:(NSString *)operation
                  target:(NSString *)target
                   input:(NSString *)input
           transactionID:(NSString *)transactionID {

    OperationRecord *rec = [[OperationRecord alloc] init];
    rec.transactionID = transactionID;
    rec.phase = phase;
    rec.operation = operation;
    rec.target = target ?: @"";
    rec.input = input ?: @"";
    rec.result = OperationResultPending;

    dispatch_async(self.queue, ^{
        if (!self.transactions[transactionID]) self.transactions[transactionID] = [NSMutableArray array];
        [self.transactions[transactionID] addObject:rec];
        self.pendingRecords[rec.recordID] = rec;
    });

    NSLog(@"[OperationLog] ⏳ [%@] START | %@ | %@", [rec phaseName], operation, target);
    return rec.recordID;
}

- (void)endPhase:(NSString *)recordID
        exitCode:(int)exitCode
       rawOutput:(NSString *)rawOutput
        rawError:(NSString *)rawError
    verification:(NSString *)verification
        verified:(BOOL)verified
        duration:(NSTimeInterval)duration
         context:(NSDictionary *)context {

    dispatch_async(self.queue, ^{
        OperationRecord *rec = self.pendingRecords[recordID];
        if (!rec) {
            NSLog(@"[OperationLog] ⚠️ Cannot end phase: record %@ not found", recordID);
            return;
        }

        rec.exitCode = exitCode;
        rec.rawOutput = rawOutput ?: @"";
        rec.rawError = rawError ?: @"";
        rec.verification = verification ?: @"";
        rec.verified = verified;
        rec.duration = duration;
        rec.context = context ?: @{};

        // Determine final result: verified is the gatekeeper
        if (rec.result == OperationResultSkipped) {
            // Already marked as skipped, keep it
        } else if (!verified) {
            rec.result = OperationResultFailed;
        } else if (exitCode != 0) {
            rec.result = OperationResultFailed;
        } else {
            rec.result = OperationResultSuccess;
        }

        [self.pendingRecords removeObjectForKey:recordID];

        NSString *icon = (rec.result == OperationResultSuccess) ? @"✅" : @"❌";
        NSLog(@"[OperationLog] %@ [%@] END | %@ | exit=%d | verified=%@ | %.3fs | %@",
              icon, [rec phaseName], rec.operation, exitCode,
              verified ? @"YES" : @"NO", duration, rec.target);
        if (rawError.length > 0) NSLog(@"[OperationLog]   Error: %@", rawError);
        if (!verified && verification.length > 0) NSLog(@"[OperationLog]   Verification failed: %@", verification);
    });
}

- (void)endPhase:(NSString *)recordID
        exitCode:(int)exitCode
       rawOutput:(NSString *)rawOutput
        rawError:(NSString *)rawError
    verification:(NSString *)verification
        verified:(BOOL)verified
        duration:(NSTimeInterval)duration {
    [self endPhase:recordID exitCode:exitCode rawOutput:rawOutput rawError:rawError
      verification:verification verified:verified duration:duration context:@{}];
}

#pragma mark - Query

- (NSArray<OperationRecord *> *)recordsForTransaction:(NSString *)transactionID {
    __block NSArray<OperationRecord *> *result;
    dispatch_sync(self.queue, ^{ result = [self.transactions[transactionID] copy]; });
    return result ?: @[];
}

- (OperationRecord *)recordByID:(NSString *)recordID {
    __block OperationRecord *result = nil;
    dispatch_sync(self.queue, ^{
        result = self.pendingRecords[recordID];
        if (!result) {
            for (NSString *tid in self.transactions) {
                for (OperationRecord *rec in self.transactions[tid]) {
                    if ([rec.recordID isEqualToString:recordID]) { result = rec; break; }
                }
                if (result) break;
            }
        }
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

#pragma mark - Reports

- (NSString *)transactionReport:(NSString *)transactionID {
    NSArray<OperationRecord *> *records = [self recordsForTransaction:transactionID];
    if (records.count == 0) return @"No records for this transaction.";

    NSMutableString *r = [NSMutableString string];
    [r appendString:@"═══════════════════════════════════════════════════\n"];
    [r appendString:@"  IPA INSTALLER PRO — INSTALLATION AUDIT TRAIL\n"];
    [r appendString:@"═══════════════════════════════════════════════════\n\n"];
    [r appendFormat:@"Transaction: %@\n", transactionID];
    [r appendFormat:@"Total Records: %lu\n\n", (unsigned long)records.count];

    // Find first failure
    OperationRecord *firstFail = [self firstFailureInTransaction:transactionID];
    if (firstFail) {
        [r appendString:@"⚠️ FIRST FAILURE:\n"];
        [r appendFormat:@"  Phase: %@\n", [firstFail phaseName]];
        [r appendFormat:@"  Operation: %@\n", firstFail.operation];
        [r appendFormat:@"  Target: %@\n", firstFail.target];
        [r appendFormat:@"  Exit Code: %d\n", firstFail.exitCode];
        [r appendFormat:@"  Verification: %@\n", firstFail.verification];
        [r appendFormat:@"  Verified: %@\n", firstFail.verified ? @"YES" : @"NO"];
        [r appendFormat:@"  Error: %@\n\n", firstFail.rawError];
    }

    // Statistics
    NSUInteger success = 0, failed = 0, skipped = 0, pending = 0;
    for (OperationRecord *rec in records) {
        switch (rec.result) {
            case OperationResultSuccess: success++; break;
            case OperationResultFailed: failed++; break;
            case OperationResultSkipped: skipped++; break;
            case OperationResultPending: pending++; break;
            default: break;
        }
    }
    [r appendString:@"━━━ STATISTICS ━━━\n"];
    [r appendFormat:@"✅ Success: %lu\n", (unsigned long)success];
    [r appendFormat:@"❌ Failed: %lu\n", (unsigned long)failed];
    [r appendFormat:@"⏭ Skipped: %lu\n", (unsigned long)skipped];
    [r appendFormat:@"⏳ Pending: %lu\n\n", (unsigned long)pending];

    // Pipeline view
    [r appendString:@"━━━ PIPELINE ━━━\n\n"];
    for (OperationRecord *rec in records) {
        [r appendString:[rec logLine]];
        [r appendString:@"\n"];
        if (rec.rawError.length > 0) {
            [r appendFormat:@"     ERROR: %@\n", rec.rawError];
        }
        if (rec.verification.length > 0 && rec.result != OperationResultSuccess) {
            [r appendFormat:@"     VERIFICATION: %@\n", rec.verification];
        }
    }

    // Final status
    [r appendString:@"\n━━━ FINAL STATUS ━━━\n"];
    if (failed == 0 && pending == 0) {
        [r appendString:@"✅ ALL PHASES COMPLETED SUCCESSFULLY\n"];
    } else if (failed > 0) {
        [r appendFormat:@"❌ INSTALLATION FAILED (%lu phase(s) failed)\n", (unsigned long)failed];
        [r appendString:@"Pipeline continued after failure — review log for details.\n"];
    } else {
        [r appendString:@"⏳ INSTALLATION INCOMPLETE (pending phases)\n"];
    }

    return r;
}

- (NSString *)transactionSummary:(NSString *)transactionID {
    NSArray<OperationRecord *> *records = [self recordsForTransaction:transactionID];
    OperationRecord *firstFail = [self firstFailureInTransaction:transactionID];
    NSUInteger total = records.count;
    NSUInteger failed = [self failedRecordsInTransaction:transactionID].count;

    if (firstFail) {
        return [NSString stringWithFormat:@"❌ FAILED at %@ | %@/%@ phases failed",
                [firstFail phaseName], @(failed), @(total)];
    } else if (total > 0) {
        return [NSString stringWithFormat:@"✅ Completed | %@ phases | no failures", @(total)];
    }
    return @"No data";
}

- (NSDictionary *)transactionStats:(NSString *)transactionID {
    NSArray<OperationRecord *> *records = [self recordsForTransaction:transactionID];
    NSUInteger success = 0, failed = 0, skipped = 0;
    NSTimeInterval totalDuration = 0;
    for (OperationRecord *rec in records) {
        switch (rec.result) {
            case OperationResultSuccess: success++; break;
            case OperationResultFailed: failed++; break;
            case OperationResultSkipped: skipped++; break;
            default: break;
        }
        totalDuration += rec.duration;
    }
    OperationRecord *firstFail = [self firstFailureInTransaction:transactionID];
    return @{
        @"totalPhases": @(records.count),
        @"success": @(success),
        @"failed": @(failed),
        @"skipped": @(skipped),
        @"totalDuration": @(totalDuration),
        @"hasFailures": @(firstFail != nil),
        @"firstFailurePhase": firstFail ? [firstFail phaseName] : @"",
        @"firstFailureOperation": firstFail ? firstFail.operation : @""
    };
}

- (NSString *)exportTransactionAsJSON:(NSString *)transactionID {
    NSArray<OperationRecord *> *records = [self recordsForTransaction:transactionID];
    NSMutableArray *dicts = [NSMutableArray array];
    for (OperationRecord *rec in records) {
        [dicts addObject:[rec dictionaryRepresentation]];
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dicts options:NSJSONWritingPrettyPrinted error:&error];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

#pragma mark - Management

- (void)clearTransaction:(NSString *)transactionID {
    dispatch_async(self.queue, ^{
        [self.transactions removeObjectForKey:transactionID];
        [self.transactionOrder removeObject:transactionID];
        if ([self.activeTransactionID isEqualToString:transactionID]) self.activeTransactionID = nil;
    });
}

- (void)clearAll {
    dispatch_async(self.queue, ^{
        [self.transactions removeAllObjects];
        [self.transactionOrder removeAllObjects];
        [self.pendingRecords removeAllObjects];
        self.activeTransactionID = nil;
    });
}

#pragma mark - Helpers

- (NSString *)resultName:(OperationResult)result {
    switch (result) {
        case OperationResultSuccess: return @"SUCCESS";
        case OperationResultFailed: return @"FAILED";
        case OperationResultSkipped: return @"SKIPPED";
        case OperationResultPartial: return @"PARTIAL";
        case OperationResultPending: return @"PENDING";
        default: return @"UNKNOWN";
    }
}

#pragma mark - Properties

- (NSArray<NSString *> *)allTransactionIDs {
    __block NSArray<NSString *> *result;
    dispatch_sync(self.queue, ^{ result = [self.transactionOrder copy]; });
    return result;
}

@end
