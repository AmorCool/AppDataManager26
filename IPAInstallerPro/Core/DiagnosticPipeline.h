//
// DiagnosticPipeline.h
// IPAInstallerPro
//
// End-to-end diagnostic pipeline:
// Discovery → Parsing → Classification → Deduplication → Correlation → Report
//

#import <Foundation/Foundation.h>
#import "CrashIncident.h"
#import "CrashCorrelator.h"

@interface DiagnosticReport : NSObject
@property (nonatomic, strong) NSDate *generatedAt;
@property (nonatomic, strong) NSArray<CrashIncident *> *incidents;
@property (nonatomic, strong) NSArray<CrashCorrelation *> *correlations;
@property (nonatomic, strong) NSDictionary *summary;
@property (nonatomic, strong) NSString *humanReadableReport;
@end

@interface DiagnosticPipeline : NSObject
+ (instancetype)sharedPipeline;

// Managed bundle IDs (apps we care about)
@property (nonatomic, strong) NSMutableArray<NSString *> *managedBundleIDs;

// Main pipeline: run full diagnostic cycle
- (DiagnosticReport *)runPipeline;

// Run pipeline for specific bundle IDs
- (DiagnosticReport *)runPipelineForBundleIDs:(NSArray<NSString *> *)bundleIDs;

// Run pipeline since a specific date
- (DiagnosticReport *)runPipelineSince:(NSDate *)sinceDate;

// Add/remove managed bundle IDs
- (void)addManagedBundleID:(NSString *)bundleID;
- (void)removeManagedBundleID:(NSString *)bundleID;

// Register events for correlation
- (void)registerInstallation:(NSString *)bundleID installationID:(NSString *)installID;
- (void)registerLaunch:(NSString *)bundleID launchID:(NSString *)launchID;

// Clear all state
- (void)reset;

// Statistics
@property (nonatomic, readonly) NSUInteger totalIncidentsProcessed;
@property (nonatomic, readonly) NSUInteger totalDuplicatesSuppressed;
@end
