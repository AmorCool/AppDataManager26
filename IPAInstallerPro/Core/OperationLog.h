//
// OperationLog.h
// IPAInstallerPro
//
// Rigorous Installation Operation Audit Trail.
// Principle: START → Execute → Verify → Result.
// SUCCESS is never assumed. It must be proven by verification.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, OperationResult) {
    OperationResultPending = 0,
    OperationResultSuccess = 1,
    OperationResultFailed = 2,
    OperationResultSkipped = 3,
    OperationResultPartial = 4
};

typedef NS_ENUM(NSInteger, OperationPhase) {
    OperationPhaseStart = 0,
    OperationPhaseIPAOpen = 1,
    OperationPhaseIPAExtract = 2,
    OperationPhaseAppIdentify = 3,
    OperationPhaseFileCopy = 4,
    OperationPhaseFramework = 5,
    OperationPhaseDylib = 6,
    OperationPhaseSign = 7,
    OperationPhasePermission = 8,
    OperationPhaseUICache = 9,
    OperationPhaseVerify = 10,
    OperationPhaseCleanup = 11,
    OperationPhaseComplete = 12,
    OperationPhaseUnknown = 13
};

// ─── OperationRecord ───
// Immutable fact. Every field represents something that actually happened.
@interface OperationRecord : NSObject

@property (nonatomic, strong, readonly) NSString *recordID;
@property (nonatomic, strong, readonly) NSString *transactionID;
@property (nonatomic, strong, readonly) NSDate *timestamp;

// What
@property (nonatomic, assign, readonly) OperationPhase phase;
@property (nonatomic, strong, readonly) NSString *operation;
@property (nonatomic, strong, readonly) NSString *target;

// Input
@property (nonatomic, strong, readonly) NSString *input;

// Execution result
@property (nonatomic, assign, readonly) int exitCode;
@property (nonatomic, strong, readonly) NSString *rawOutput;
@property (nonatomic, strong, readonly) NSString *rawError;

// Verification (the critical part)
@property (nonatomic, strong, readonly) NSString *verification;  // What was checked
@property (nonatomic, assign, readonly) BOOL verified;           // Did the check pass?

// Final result — derived from execution + verification
@property (nonatomic, assign, readonly) OperationResult result;

// Timing
@property (nonatomic, assign, readonly) NSTimeInterval duration;

// Extra context
@property (nonatomic, strong, readonly) NSDictionary *context;

- (NSString *)phaseName;
- (NSString *)resultSymbol;
- (NSString *)resultName;
- (NSString *)logLine;
- (NSString *)detailDump;
- (NSDictionary *)dictionaryRepresentation;

@end

// ─── OperationLog ───
@interface OperationLog : NSObject

+ (instancetype)sharedLog;

// Transaction lifecycle
- (NSString *)beginTransactionForIPA:(NSString *)ipaPath;
- (void)endTransaction:(NSString *)transactionID finalResult:(OperationResult)result;

// Phase lifecycle: START → (execute) → END with verification
// Returns recordID. Use this to end the phase with actual results.
- (NSString *)beginPhase:(OperationPhase)phase
               operation:(NSString *)operation
                  target:(NSString *)target
                   input:(NSString *)input
           transactionID:(NSString *)transactionID;

// End a phase with execution results AND verification.
// result is determined by: exitCode + verified flag.
// If verified==NO, result is ALWAYS FAILED regardless of exitCode.
- (void)endPhase:(NSString *)recordID
        exitCode:(int)exitCode
       rawOutput:(NSString *)rawOutput
        rawError:(NSString *)rawError
    verification:(NSString *)verification
        verified:(BOOL)verified
        duration:(NSTimeInterval)duration
         context:(NSDictionary *)context;

// Convenience: end with automatic result determination
- (void)endPhase:(NSString *)recordID
        exitCode:(int)exitCode
       rawOutput:(NSString *)rawOutput
        rawError:(NSString *)rawError
    verification:(NSString *)verification
        verified:(BOOL)verified
        duration:(NSTimeInterval)duration;

// Query
- (NSArray<OperationRecord *> *)recordsForTransaction:(NSString *)transactionID;
- (OperationRecord *)recordByID:(NSString *)recordID;
- (NSArray<OperationRecord *> *)failedRecordsInTransaction:(NSString *)transactionID;
- (OperationRecord *)firstFailureInTransaction:(NSString *)transactionID;
- (BOOL)transactionHasFailures:(NSString *)transactionID;

// Reports
- (NSString *)transactionReport:(NSString *)transactionID;
- (NSString *)transactionSummary:(NSString *)transactionID;
- (NSDictionary *)transactionStats:(NSString *)transactionID;

// Export
- (NSString *)exportTransactionAsJSON:(NSString *)transactionID;

// Management
- (void)clearTransaction:(NSString *)transactionID;
- (void)clearAll;

@property (nonatomic, strong, readonly) NSString *activeTransactionID;
@property (nonatomic, strong, readonly) NSArray<NSString *> *allTransactionIDs;

@end
