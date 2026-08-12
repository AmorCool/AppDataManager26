//
// CrashIncident.m
// IPAInstallerPro
//

#import "CrashIncident.h"

@implementation CrashIncident

@synthesize fingerprint = _fingerprint;

+ (instancetype)incidentWithBundleID:(NSString *)bundleID
                         processName:(NSString *)processName
                           timestamp:(NSDate *)timestamp {
    CrashIncident *incident = [[self alloc] init];
    incident->_incidentID = [[NSUUID UUID] UUIDString];
    incident.bundleID = bundleID ?: @"unknown";
    incident.processName = processName ?: @"Unknown";
    incident.timestamp = timestamp ?: [NSDate date];
    incident.severity = CrashSeverityUnknown;
    incident.phase = CrashPhaseUnknown;
    incident.confidence = CrashConfidenceLow;
    incident.evidence = @{};
    incident.rawReport = @{};
    return incident;
}

- (NSString *)severityString {
    switch (self.severity) {
        case CrashSeverityCritical: return @"CRITICAL";
        case CrashSeverityHigh: return @"HIGH";
        case CrashSeverityMedium: return @"MEDIUM";
        case CrashSeverityLow: return @"LOW";
        default: return @"UNKNOWN";
    }
}

- (NSString *)phaseString {
    switch (self.phase) {
        case CrashPhaseProcessLaunch: return @"PROCESS_LAUNCH";
        case CrashPhaseRuntime: return @"RUNTIME";
        case CrashPhaseBackground: return @"BACKGROUND";
        case CrashPhaseInstall: return @"INSTALL";
        case CrashPhaseSign: return @"SIGN";
        default: return @"UNKNOWN";
    }
}

- (NSString *)confidenceString {
    switch (self.confidence) {
        case CrashConfidenceHigh: return @"HIGH";
        case CrashConfidenceMedium: return @"MEDIUM";
        case CrashConfidenceLow: return @"LOW";
        default: return @"UNKNOWN";
    }
}

- (NSString *)formattedTimestamp {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [fmt stringFromDate:self.timestamp];
}

- (NSString *)fingerprint {
    if (_fingerprint) return _fingerprint;
    // Fingerprint = hash of: crashType + bundleID + rootCause + key evidence
    NSMutableString *fp = [NSMutableString string];
    [fp appendFormat:@"%@|", self.crashType ?: @"unknown"];
    [fp appendFormat:@"%@|", self.bundleID ?: @"unknown"];
    [fp appendFormat:@"%@|", self.rootCause ?: @"unknown"];
    if (self.evidence[@"library"]) [fp appendFormat:@"lib:%@|", self.evidence[@"library"]];
    if (self.evidence[@"errno"]) [fp appendFormat:@"errno:%@|", self.evidence[@"errno"]];
    if (self.evidence[@"exception_type"]) [fp appendFormat:@"exc:%@|", self.evidence[@"exception_type"]];
    _fingerprint = [NSString stringWithFormat:@"%lu", (unsigned long)[fp hash]];
    return _fingerprint;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"incidentID": self.incidentID,
        @"fingerprint": self.fingerprint,
        @"bundleID": self.bundleID,
        @"processName": self.processName,
        @"timestamp": [self formattedTimestamp],
        @"crashType": self.crashType ?: @"UNKNOWN",
        @"severity": [self severityString],
        @"phase": [self phaseString],
        @"rootCause": self.rootCause ?: @"Unknown",
        @"confidence": [self confidenceString],
        @"evidence": self.evidence ?: @{},
        @"humanReadableSummary": self.humanReadableSummary ?: @"",
        @"sourcePath": self.sourcePath ?: @"",
        @"sourceFilename": self.sourceFilename ?: @"",
        @"correlatedInstallationID": self.correlatedInstallationID ?: @"",
        @"correlatedLaunchID": self.correlatedLaunchID ?: @""
    };
}

+ (instancetype)incidentFromDictionary:(NSDictionary *)dict {
    if (!dict) return nil;
    CrashIncident *incident = [[self alloc] init];
    incident->_incidentID = dict[@"incidentID"] ?: [[NSUUID UUID] UUIDString];
    incident.bundleID = dict[@"bundleID"] ?: @"unknown";
    incident.processName = dict[@"processName"] ?: @"Unknown";
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    incident.timestamp = [fmt dateFromString:dict[@"timestamp"]] ?: [NSDate date];
    incident.crashType = dict[@"crashType"];
    incident.rootCause = dict[@"rootCause"];
    incident.evidence = dict[@"evidence"];
    incident.humanReadableSummary = dict[@"humanReadableSummary"];
    incident.sourcePath = dict[@"sourcePath"];
    incident.sourceFilename = dict[@"sourceFilename"];
    incident.correlatedInstallationID = dict[@"correlatedInstallationID"];
    incident.correlatedLaunchID = dict[@"correlatedLaunchID"];
    return incident;
}

@end
