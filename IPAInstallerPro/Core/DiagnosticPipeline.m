//
// DiagnosticPipeline.m
// IPAInstallerPro
//
// Evidence-based diagnostic pipeline. No assumptions. Only data.
//

#import "DiagnosticPipeline.h"
#import "CrashDiscovery.h"
#import "CrashLogParser.h"
#import "CrashClassifier.h"
#import "CrashDeduplicator.h"
#import "CrashCorrelator.h"
#import "Logger.h"

@implementation DiagnosticReport
@end

@interface DiagnosticPipeline ()
@property (nonatomic, strong) CrashDiscovery *discovery;
@property (nonatomic, strong) CrashLogParser *parser;
@property (nonatomic, strong) CrashClassifier *classifier;
@property (nonatomic, strong) CrashDeduplicator *deduplicator;
@property (nonatomic, strong) CrashCorrelator *correlator;
@property (nonatomic, strong) NSDate *lastPipelineRun;
@property (nonatomic, readwrite) NSUInteger totalIncidentsProcessed;
@property (nonatomic, readwrite) NSUInteger totalDuplicatesSuppressed;
@end

@implementation DiagnosticPipeline

+ (instancetype)sharedPipeline {
    static DiagnosticPipeline *s = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _discovery = [CrashDiscovery sharedDiscovery];
        _parser = [CrashLogParser sharedParser];
        _classifier = [CrashClassifier sharedClassifier];
        _deduplicator = [CrashDeduplicator sharedDeduplicator];
        _correlator = [CrashCorrelator sharedCorrelator];
        _managedBundleIDs = [NSMutableArray array];
        _lastPipelineRun = nil;
        _totalIncidentsProcessed = 0;
        _totalDuplicatesSuppressed = 0;
    }
    return self;
}

#pragma mark - Managed Bundle IDs

- (void)addManagedBundleID:(NSString *)bundleID {
    if (!bundleID || [self.managedBundleIDs containsObject:bundleID]) return;
    [self.managedBundleIDs addObject:bundleID];
    [[Logger sharedLogger] info:[NSString stringWithFormat:@"DiagnosticPipeline: Now managing %@", bundleID]];
}

- (void)removeManagedBundleID:(NSString *)bundleID {
    [self.managedBundleIDs removeObject:bundleID];
}

#pragma mark - Event Registration

- (void)registerInstallation:(NSString *)bundleID installationID:(NSString *)installID {
    [self.correlator registerInstallation:bundleID installationID:installID timestamp:[NSDate date]];
    [self addManagedBundleID:bundleID];
}

- (void)registerLaunch:(NSString *)bundleID launchID:(NSString *)launchID {
    [self.correlator registerLaunch:bundleID launchID:launchID timestamp:[NSDate date]];
}

#pragma mark - Main Pipeline

- (DiagnosticReport *)runPipeline {
    return [self runPipelineSince:self.lastPipelineRun];
}

- (DiagnosticReport *)runPipelineForBundleIDs:(NSArray<NSString *> *)bundleIDs {
    DiagnosticReport *report = [[DiagnosticReport alloc] init];
    report.generatedAt = [NSDate date];

    if (bundleIDs.count == 0) {
        report.incidents = @[];
        report.correlations = @[];
        report.summary = @{ @"total_incidents": @0, @"message": @"No bundle IDs specified" };
        report.humanReadableReport = @"No bundle IDs specified for diagnostic.";
        return report;
    }

    [[Logger sharedLogger] info:[NSString stringWithFormat:@"DiagnosticPipeline: Running for %lu bundle IDs", (unsigned long)bundleIDs.count]];

    // STEP 1: DISCOVERY
    CrashDiscoveryResult *discoveryResult = [self.discovery discoverCrashLogsForBundleIDs:bundleIDs sinceDate:self.lastPipelineRun];
    [[Logger sharedLogger] info:[NSString stringWithFormat:@"Discovery: %lu new logs, %lu total managed", (unsigned long)discoveryResult.newPaths.count, (unsigned long)discoveryResult.allPaths.count]];

    // STEP 2-5: PARSE → CLASSIFY → DEDUP → CORRELATE
    NSMutableArray<CrashIncident *> *incidents = [NSMutableArray array];
    NSMutableArray<CrashCorrelation *> *correlations = [NSMutableArray array];

    for (NSString *path in discoveryResult.newPaths) {
        // Parse
        NSDictionary *parsed = [self.parser parseCrashLogAtPath:path];
        if (!parsed) {
            [[Logger sharedLogger] warning:[NSString stringWithFormat:@"Failed to parse: %@", path]];
            continue;
        }

        // Classify
        CrashClassificationResult *classification = [self.classifier classifyCrashLog:parsed];

        // Build incident
        NSString *bundleID = parsed[@"bundle_identifier"] ?: @"unknown";
        NSString *procName = parsed[@"process_name"] ?: @"Unknown";
        NSDate *timestamp = parsed[@"timestamp_date"] ?: [NSDate date];

        CrashIncident *incident = [CrashIncident incidentWithBundleID:bundleID processName:procName timestamp:timestamp];
        incident.crashType = classification.crashType;
        incident.severity = classification.severity;
        incident.phase = classification.phase;
        incident.rootCause = classification.rootCause;
        incident.confidence = classification.confidence;
        incident.evidence = classification.evidence;
        incident.rawReport = parsed;
        incident.humanReadableSummary = classification.humanReadableSummary;
        incident.sourcePath = path;
        incident.sourceFilename = [path lastPathComponent];

        // Deduplication
        if ([self.deduplicator isDuplicate:incident]) {
            self.totalDuplicatesSuppressed++;
            continue;
        }
        [self.deduplicator recordIncident:incident];

        // Correlation
        CrashCorrelation *correlation = [self.correlator correlateIncident:incident];
        [correlations addObject:correlation];

        [incidents addObject:incident];
        self.totalIncidentsProcessed++;
    }

    // Build summary
    NSMutableDictionary *summary = [NSMutableDictionary dictionary];
    summary[@"total_incidents"] = @(incidents.count);
    summary[@"total_duplicates_suppressed"] = @(self.totalDuplicatesSuppressed);
    summary[@"total_processed"] = @(self.totalIncidentsProcessed);
    summary[@"new_logs_found"] = @(discoveryResult.newPaths.count);
    summary[@"managed_apps"] = @(bundleIDs.count);

    // Severity breakdown
    NSUInteger critical = 0, high = 0, medium = 0, low = 0;
    for (CrashIncident *i in incidents) {
        switch (i.severity) {
            case CrashSeverityCritical: critical++; break;
            case CrashSeverityHigh: high++; break;
            case CrashSeverityMedium: medium++; break;
            case CrashSeverityLow: low++; break;
            default: break;
        }
    }
    summary[@"severity_breakdown"] = @{
        @"CRITICAL": @(critical),
        @"HIGH": @(high),
        @"MEDIUM": @(medium),
        @"LOW": @(low)
    };

    // Type breakdown
    NSMutableDictionary *typeCounts = [NSMutableDictionary dictionary];
    for (CrashIncident *i in incidents) {
        NSString *type = i.crashType ?: @"UNKNOWN";
        NSNumber *current = typeCounts[type] ?: @0;
        typeCounts[type] = @(current.integerValue + 1);
    }
    summary[@"type_breakdown"] = typeCounts;

    // Install-related count
    NSUInteger installRelated = 0;
    for (CrashCorrelation *c in correlations) {
        if (c.isInstallRelated) installRelated++;
    }
    summary[@"install_related"] = @(installRelated);

    report.incidents = incidents;
    report.correlations = correlations;
    report.summary = summary;
    report.humanReadableReport = [self generateHumanReadableReport:report];

    self.lastPipelineRun = [NSDate date];

    [[Logger sharedLogger] info:[NSString stringWithFormat:@"DiagnosticPipeline: Complete. %lu incidents, %lu deduped", (unsigned long)incidents.count, (unsigned long)self.totalDuplicatesSuppressed]];

    return report;
}

- (DiagnosticReport *)runPipelineSince:(NSDate *)sinceDate {
    return [self runPipelineForBundleIDs:self.managedBundleIDs];
}

#pragma mark - Report Generation

- (NSString *)generateHumanReadableReport:(DiagnosticReport *)report {
    NSMutableString *r = [NSMutableString string];
    [r appendString:@"═══════════════════════════════════════════════════\n"];
    [r appendString:@"  IPA INSTALLER PRO — DIAGNOSTIC REPORT\n"];
    [r appendString:@"═══════════════════════════════════════════════════\n\n"];

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    [r appendFormat:@"Generated: %@\n", [fmt stringFromDate:report.generatedAt]];
    [r appendFormat:@"Managed Apps: %@\n", report.summary[@"managed_apps"]];
    [r appendFormat:@"New Incidents: %@\n", report.summary[@"total_incidents"]];
    [r appendFormat:@"Duplicates Suppressed: %@\n", report.summary[@"total_duplicates_suppressed"]];
    [r appendFormat:@"Install-Related: %@\n\n", report.summary[@"install_related"]];

    if (report.incidents.count == 0) {
        [r appendString:@"✅ No new incidents detected.\n"];
        return r;
    }

    [r appendString:@"━━━ INCIDENTS ━━━\n\n"];

    for (NSUInteger i = 0; i < report.incidents.count; i++) {
        CrashIncident *incident = report.incidents[i];
        [r appendFormat:@"[#%lu] %@ | %@ | %@\n", (unsigned long)(i + 1), incident.crashType, [incident severityString], incident.bundleID];
        [r appendFormat:@"     Time: %@\n", [incident formattedTimestamp]];
        [r appendFormat:@"     Phase: %@ | Confidence: %@\n", [incident phaseString], [incident confidenceString]];
        [r appendFormat:@"     Root Cause: %@\n", incident.rootCause];
        if (incident.evidence[@"library"]) {
            [r appendFormat:@"     Library: %@\n", incident.evidence[@"library"]];
        }
        if (incident.evidence[@"errno"]) {
            [r appendFormat:@"     errno: %@\n", incident.evidence[@"errno"]];
        }
        if (incident.correlatedInstallationID) {
            [r appendFormat:@"     Correlated Install: %@\n", incident.correlatedInstallationID];
        }
        [r appendString:@"\n"];
    }

    [r appendString:@"━━━ SUMMARY ━━━\n"];
    [r appendFormat:@"Critical: %@ | High: %@ | Medium: %@ | Low: %@\n",
        report.summary[@"severity_breakdown"][@"CRITICAL"],
        report.summary[@"severity_breakdown"][@"HIGH"],
        report.summary[@"severity_breakdown"][@"MEDIUM"],
        report.summary[@"severity_breakdown"][@"LOW"]];

    return r;
}

#pragma mark - Reset

- (void)reset {
    [self.deduplicator clearAll];
    self.totalIncidentsProcessed = 0;
    self.totalDuplicatesSuppressed = 0;
    self.lastPipelineRun = nil;
    [self.managedBundleIDs removeAllObjects];
    [[Logger sharedLogger] info:@"DiagnosticPipeline: Reset complete"];
}

@end
