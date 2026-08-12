//
// OperationLog.h
// IPAInstallerPro
//
// Installation Operation Audit Trail.
// Records exactly what the installer did, step by step.
// No interpretation. No guesswork. Just facts.
//

#import <Foundation/Foundation.h>

// Result of an operation — exactly what happened
typedef NS_ENUM(NSInteger, OperationResult) {
    OperationResultPending = 0,   // Operation started, waiting for result
    OperationResultSuccess = 1,   // Operation completed as intended
    OperationResultFailed = 2,    // Operation failed
    OperationResultSkipped = 3,   // Operation was skipped (not needed)
    OperationResultPartial = 4    // Operation partially succeeded
};

// Phase of installation — what area of work
typedef NS_ENUM(NSInteger, OperationPhase) {
    OperationPhaseStart = 0,
    OperationPhaseIPAOpen = 1,        // Opening IPA file
    OperationPhaseIPAValidate = 2,    // Validating IPA structure
    OperationPhaseIPAExtract = 3,     // Extracting IPA payload
    OperationPhaseAppIdentify = 4,    // Identifying bundle, Info.plist
    OperationPhaseFileCopy = 5,       // Copying files to /Applications
    OperationPhaseFramework = 6,      // Processing Frameworks
    OperationPhaseDylib = 7,          // Processing dylibs
    OperationPhaseSign = 8,           // Code signing
    OperationPhasePermission = 9,     // Setting permissions
    OperationPhaseUICache = 10,       // Running uicache
    OperationPhaseVerify = 11,        // Post-install verification
    OperationPhaseLaunch = 12,        // Launch attempt
    OperationPhaseCleanup = 13,       // Cleanup temp files
    OperationPhaseComplete = 14,      // Installation complete
    OperationPhaseUnknown = 15
};

// Single operation record — immutable fact
@interface OperationRecord : NSObject

@property (nonatomic, strong, readonly) NSString *recordID;      // Unique ID
@property (nonatomic, strong, readonly) NSString *operationID;   // Transaction ID (links all records in one install)
@property (nonatomic, strong, readonly) NSDate *timestamp;       // When it happened
@property (nonatomic, assign, readonly) OperationPhase phase;    // What phase
@property (nonatomic, strong, readonly) NSString *operation;     // What was done (e.g. "copyfile", "ldid -S", "chmod")
@property (nonatomic, strong, readonly) NSString *target;        // What was operated on (path, bundle ID, etc.)
@property (nonatomic, assign, readonly) OperationResult result;  // SUCCESS / FAILED / SKIPPED
@property (nonatomic, assign, readonly) int exitCode;            // Process exit code or errno
@property (nonatomic, strong, readonly) NSString *rawOutput;     // Raw stdout/stderr (unfiltered)
@property (nonatomic, strong, readonly) NSString *rawError;      // Raw error message (unfiltered)
@property (nonatomic, assign, readonly) NSTimeInterval duration; // How long it took (seconds)
@property (nonatomic, strong, readonly) NSDictionary *context;   // Extra context (file sizes, paths, etc.)

// Formatted timestamp: [HH:MM:SS.mmm]
- (NSString *)formattedTimestamp;

// Human-readable line for display
- (NSString *)logLine;

// Full detail dump
- (NSString *)detailDump;

@end

// ============================================================
// OperationLog — The Logger
// ============================================================

@interface OperationLog : NSObject

+ (instancetype)sharedLog;

// Start a new installation transaction
// Returns operationID that links all records
- (NSString *)beginTransactionForIPA:(NSString *)ipaPath;

// End a transaction
- (void)endTransaction:(NSString *)operationID;

// Log an operation that was attempted and completed
// This is the PRIMARY method — call it AFTER the operation finishes with the REAL result
- (void)logOperation:(NSString *)operation
             phase:(OperationPhase)phase
            target:(NSString *)target
            result:(OperationResult)result
          exitCode:(int)exitCode
          rawOutput:(NSString *)rawOutput
           rawError:(NSString *)rawError
          duration:(NSTimeInterval)duration
           context:(NSDictionary *)context
     operationID:(NSString *)operationID;

// Convenience: log a system command that was executed
- (void)logCommand:(NSString *)command
              args:(NSArray *)args
            target:(NSString *)target
            result:(OperationResult)result
          exitCode:(int)exitCode
          rawOutput:(NSString *)rawOutput
           rawError:(NSString *)rawError
          duration:(NSTimeInterval)duration
     operationID:(NSString *)operationID;

// Convenience: log a file operation
- (void)logFileOp:(NSString *)operation           // "copyfile", "remove", "chmod"
             from:(NSString *)sourcePath
               to:(NSString *)destPath
           result:(OperationResult)result
         exitCode:(int)exitCode
          rawError:(NSString *)rawError
         duration:(NSTimeInterval)duration
    operationID:(NSString *)operationID;

// Mark the start of a phase (creates a PENDING record)
- (OperationRecord *)markPhaseStart:(OperationPhase)phase
                          operation:(NSString *)operation
                             target:(NSString *)target
                      operationID:(NSString *)operationID;

// Mark the end of a phase (updates the PENDING record with actual result)
- (void)markPhaseEnd:(OperationPhase)phase
            record:(OperationRecord *)record
            result:(OperationResult)result
          exitCode:(int)exitCode
          rawOutput:(NSString *)rawOutput
           rawError:(NSString *)rawError
          duration:(NSTimeInterval)duration
           context:(NSDictionary *)context;

// Query
- (NSArray<OperationRecord *> *)recordsForTransaction:(NSString *)operationID;
- (NSArray<OperationRecord *> *)allRecords;
- (NSArray<OperationRecord *> *)failedRecords;
- (NSArray<OperationRecord *> *)recordsForPhase:(OperationPhase)phase;
- (OperationRecord *)lastRecordForTransaction:(NSString *)operationID;

// Reports
- (NSString *)transactionReport:(NSString *)operationID;   // Full human-readable report
- (NSString *)transactionSummary:(NSString *)operationID;  // One-line summary
- (NSDictionary *)transactionStats:(NSString *)operationID; // Statistics

// Export
- (NSString *)exportTransactionAsJSON:(NSString *)operationID;
- (NSString *)exportAllAsJSON;

// Management
- (void)clearTransaction:(NSString *)operationID;
- (void)clearAll;

// Current active transaction
@property (nonatomic, strong, readonly) NSString *activeTransactionID;
@property (nonatomic, strong, readonly) NSArray<NSString *> *allTransactionIDs;

@end
