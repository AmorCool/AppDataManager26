//
// CrashIncident.h
// IPAInstallerPro
//
// Unified incident model — every crash/launch/install event is a CrashIncident
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, CrashSeverity) {
    CrashSeverityCritical = 0,   // App cannot launch / install blocked
    CrashSeverityHigh = 1,       // App launches but crashes quickly
    CrashSeverityMedium = 2,     // Feature broken but app runs
    CrashSeverityLow = 3,        // Warning / info only
    CrashSeverityUnknown = 4
};

typedef NS_ENUM(NSInteger, CrashPhase) {
    CrashPhaseUnknown = 0,
    CrashPhaseProcessLaunch = 1,     // dyld, early init
    CrashPhaseRuntime = 2,           // During normal execution
    CrashPhaseBackground = 3,        // Background termination
    CrashPhaseInstall = 4,           // During installation
    CrashPhaseSign = 5               // During code signing
};

typedef NS_ENUM(NSInteger, CrashConfidence) {
    CrashConfidenceHigh = 0,     // Multiple evidence points agree
    CrashConfidenceMedium = 1,   // Some evidence, one interpretation
    CrashConfidenceLow = 2       // Ambiguous, needs manual review
};

@interface CrashIncident : NSObject

// Identity
@property (nonatomic, strong, readonly) NSString *incidentID;
@property (nonatomic, strong, readonly) NSString *fingerprint;
@property (nonatomic, strong) NSString *bundleID;
@property (nonatomic, strong) NSString *processName;
@property (nonatomic, strong) NSDate *timestamp;

// Classification
@property (nonatomic, strong) NSString *crashType;           // e.g. "DYLD_LIBRARY_MISSING"
@property (nonatomic, assign) CrashSeverity severity;
@property (nonatomic, assign) CrashPhase phase;
@property (nonatomic, strong) NSString *rootCause;           // Human-readable root cause
@property (nonatomic, assign) CrashConfidence confidence;

// Evidence (structured data extracted from report)
@property (nonatomic, strong) NSDictionary *evidence;

// Raw report (the full original crash log)
@property (nonatomic, strong) NSDictionary *rawReport;

// Human-readable summary
@property (nonatomic, strong) NSString *humanReadableSummary;

// Source tracking
@property (nonatomic, strong) NSString *sourcePath;
@property (nonatomic, strong) NSString *sourceFilename;

// Correlation
@property (nonatomic, strong) NSString *correlatedInstallationID;
@property (nonatomic, strong) NSString *correlatedLaunchID;

+ (instancetype)incidentWithBundleID:(NSString *)bundleID
                         processName:(NSString *)processName
                           timestamp:(NSDate *)timestamp;

- (NSString *)severityString;
- (NSString *)phaseString;
- (NSString *)confidenceString;
- (NSString *)formattedTimestamp;
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)incidentFromDictionary:(NSDictionary *)dict;

@end
