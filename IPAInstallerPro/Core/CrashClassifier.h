//
// CrashClassifier.h
// IPAInstallerPro
//
// Evidence-based crash classification — no assumptions, only data.
// Maps raw crash report fields to structured CrashIncident.
//

#import <Foundation/Foundation.h>
#import "CrashIncident.h"

@interface CrashClassificationResult : NSObject
@property (nonatomic, strong) NSString *crashType;
@property (nonatomic, assign) CrashSeverity severity;
@property (nonatomic, assign) CrashPhase phase;
@property (nonatomic, strong) NSString *rootCause;
@property (nonatomic, assign) CrashConfidence confidence;
@property (nonatomic, strong) NSDictionary *evidence;
@property (nonatomic, strong) NSString *humanReadableSummary;
@end

@interface CrashClassifier : NSObject
+ (instancetype)sharedClassifier;

// Main entry: take a parsed crash log dictionary → return structured classification
- (CrashClassificationResult *)classifyCrashLog:(NSDictionary *)parsedLog;

// Specific classifiers (exposed for testing)
- (CrashClassificationResult *)classifyDYLDError:(NSDictionary *)log;
- (CrashClassificationResult *)classifyJetsam:(NSDictionary *)log;
- (CrashClassificationResult *)classifyWatchdog:(NSDictionary *)log;
- (CrashClassificationResult *)classifySignal:(NSDictionary *)log;
- (CrashClassificationResult *)classifyException:(NSDictionary *)log;
- (CrashClassificationResult *)classifyForcedTermination:(NSDictionary *)log;
- (CrashClassificationResult *)classifySpringboardKill:(NSDictionary *)log;
- (CrashClassificationResult *)classifyUnknown:(NSDictionary *)log;

// Evidence extractors
- (NSString *)extractLibraryFromDetails:(NSString *)details;
- (NSNumber *)extractErrnoFromDetails:(NSString *)details;
- (NSString *)extractDylibPathFromDetails:(NSString *)details;
@end
