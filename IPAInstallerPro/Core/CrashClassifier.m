//
// CrashClassifier.m
// IPAInstallerPro
//
// Evidence-based classification. Every decision is traceable.
//

#import "CrashClassifier.h"

@implementation CrashClassificationResult
@end

@implementation CrashClassifier

+ (instancetype)sharedClassifier {
    static CrashClassifier *s = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; });
    return s;
}

#pragma mark - Main Entry

- (CrashClassificationResult *)classifyCrashLog:(NSDictionary *)parsedLog {
    if (!parsedLog || parsedLog.count == 0) {
        return [self classifyUnknown:parsedLog];
    }

    NSString *termNS = parsedLog[@"termination_namespace"];
    NSString *termIndicator = parsedLog[@"termination_indicator"];
    NSString *termReason = parsedLog[@"termination_reason"];
    NSString *excType = parsedLog[@"exception_type"];
    NSString *termDetails = parsedLog[@"termination_details"];
    BOOL isJetsam = [parsedLog[@"jetsam_event"] boolValue];

    // Priority 1: DYLD errors (launch failures)
    if ([termNS isEqualToString:@"DYLD"]) {
        return [self classifyDYLDError:parsedLog];
    }

    // Priority 2: Jetsam (memory pressure)
    if (isJetsam || [termReason containsString:@"jetsam"] || [termNS containsString:@"JETSAM"]) {
        return [self classifyJetsam:parsedLog];
    }

    // Priority 3: Watchdog
    if ([termReason containsString:@"watchdog"] || [termIndicator containsString:@"watchdog"]) {
        return [self classifyWatchdog:parsedLog];
    }

    // Priority 4: SpringBoard forced termination
    if ([termNS containsString:@"SPRINGBOARD"]) {
        return [self classifySpringboardKill:parsedLog];
    }

    // Priority 5: Exception-based classification
    if (excType && ![excType isEqualToString:@"Unavailable"]) {
        if ([excType containsString:@"EXC_BAD_ACCESS"]) {
            return [self classifySignal:parsedLog];
        }
        if ([excType containsString:@"EXC_CRASH"]) {
            // Check if DYLD-related even if namespace isn't DYLD
            if ([termIndicator containsString:@"Library"] ||
                [termDetails containsString:@"Library not loaded"] ||
                [termDetails containsString:@"dyld"]) {
                return [self classifyDYLDError:parsedLog];
            }
            if ([termReason containsString:@"watchdog"]) {
                return [self classifyWatchdog:parsedLog];
            }
            return [self classifyException:parsedLog];
        }
        if ([excType containsString:@"EXC_BREAKPOINT"] ||
            [excType containsString:@"EXC_GUARD"] ||
            [excType containsString:@"EXC_SOFTWARE"]) {
            return [self classifyException:parsedLog];
        }
    }

    // Priority 6: Forced termination
    if ([termReason containsString:@"Termination"] ||
        [termNS containsString:@"TERMINATION"]) {
        return [self classifyForcedTermination:parsedLog];
    }

    // Priority 7: Library not loaded (may appear in details without DYLD namespace)
    if ([termDetails containsString:@"Library not loaded"] ||
        [termIndicator containsString:@"Library missing"]) {
        return [self classifyDYLDError:parsedLog];
    }

    // Fallback
    return [self classifyUnknown:parsedLog];
}

#pragma mark - DYLD Classification

- (CrashClassificationResult *)classifyDYLDError:(NSDictionary *)log {
    CrashClassificationResult *r = [[CrashClassificationResult alloc] init];
    r.crashType = @"DYLD_LIBRARY_MISSING";
    r.severity = CrashSeverityCritical;
    r.phase = CrashPhaseProcessLaunch;
    r.confidence = CrashConfidenceHigh;

    NSString *termIndicator = log[@"termination_indicator"] ?: @"";
    NSString *termDetails = log[@"termination_details"] ?: @"";
    NSString *termReason = log[@"termination_reason"] ?: @"";

    NSString *library = [self extractLibraryFromDetails:termDetails];
    NSString *dylibPath = [self extractDylibPathFromDetails:termDetails];
    NSNumber *errnoNum = [self extractErrnoFromDetails:termDetails];

    NSMutableDictionary *evidence = [NSMutableDictionary dictionary];
    evidence[@"termination_namespace"] = log[@"termination_namespace"] ?: @"DYLD";
    evidence[@"termination_indicator"] = termIndicator;
    evidence[@"termination_reason"] = termReason;
    evidence[@"termination_details"] = termDetails;
    if (library) evidence[@"library"] = library;
    if (dylibPath) evidence[@"dylib_path"] = dylibPath;
    if (errnoNum) evidence[@"errno"] = errnoNum;
    if (log[@"exception_type"]) evidence[@"exception_type"] = log[@"exception_type"];
    if (log[@"exception_codes"]) evidence[@"exception_codes"] = log[@"exception_codes"];

    r.evidence = evidence;

    // Build root cause
    NSMutableString *rootCause = [NSMutableString string];
    [rootCause appendString:@"Required dynamic library could not be loaded by dyld during process launch."];
    r.rootCause = rootCause;

    // Build human-readable summary
    NSMutableString *summary = [NSMutableString string];
    [summary appendFormat:@"Type: DYLD_LIBRARY_MISSING\n"];
    [summary appendFormat:@"Severity: CRITICAL\n"];
    [summary appendFormat:@"Phase: PROCESS_LAUNCH\n"];
    if (library) [summary appendFormat:@"Library: %@\n", library];
    if (dylibPath) [summary appendFormat:@"Load Path: %@\n", dylibPath];
    if (errnoNum) [summary appendFormat:@"Failure: open() failed with errno=%@\n", errnoNum];
    [summary appendFormat:@"Root Cause: %@\n", r.rootCause];
    [summary appendFormat:@"Confidence: HIGH\n"];
    r.humanReadableSummary = summary;

    return r;
}

#pragma mark - Jetsam Classification

- (CrashClassificationResult *)classifyJetsam:(NSDictionary *)log {
    CrashClassificationResult *r = [[CrashClassificationResult alloc] init];
    r.crashType = @"JETSAM_MEMORY_PRESSURE";
    r.severity = CrashSeverityHigh;
    r.phase = CrashPhaseBackground;
    r.confidence = CrashConfidenceHigh;

    NSMutableDictionary *evidence = [NSMutableDictionary dictionary];
    evidence[@"jetsam_reason"] = log[@"jetsam_reason"] ?: log[@"termination_reason"] ?: @"Unknown";
    evidence[@"termination_namespace"] = log[@"termination_namespace"] ?: @"JETSAM";
    r.evidence = evidence;

    r.rootCause = @"System terminated the process due to memory pressure (Jetsam).";

    NSMutableString *summary = [NSMutableString string];
    [summary appendFormat:@"Type: JETSAM_MEMORY_PRESSURE\n"];
    [summary appendFormat:@"Severity: HIGH\n"];
    [summary appendFormat:@"Phase: BACKGROUND\n"];
    [summary appendFormat:@"Root Cause: %@\n", r.rootCause];
    [summary appendFormat:@"Confidence: HIGH\n"];
    r.humanReadableSummary = summary;

    return r;
}

#pragma mark - Watchdog Classification

- (CrashClassificationResult *)classifyWatchdog:(NSDictionary *)log {
    CrashClassificationResult *r = [[CrashClassificationResult alloc] init];
    r.crashType = @"WATCHDOG_TIMEOUT";
    r.severity = CrashSeverityHigh;
    r.phase = CrashPhaseProcessLaunch;
    r.confidence = CrashConfidenceHigh;

    NSMutableDictionary *evidence = [NSMutableDictionary dictionary];
    evidence[@"termination_reason"] = log[@"termination_reason"] ?: @"Unknown";
    r.evidence = evidence;

    r.rootCause = @"Application failed to respond within the watchdog time limit during launch or resume.";

    NSMutableString *summary = [NSMutableString string];
    [summary appendFormat:@"Type: WATCHDOG_TIMEOUT\n"];
    [summary appendFormat:@"Severity: HIGH\n"];
    [summary appendFormat:@"Phase: PROCESS_LAUNCH\n"];
    [summary appendFormat:@"Root Cause: %@\n", r.rootCause];
    [summary appendFormat:@"Confidence: HIGH\n"];
    r.humanReadableSummary = summary;

    return r;
}

#pragma mark - Signal Classification

- (CrashClassificationResult *)classifySignal:(NSDictionary *)log {
    CrashClassificationResult *r = [[CrashClassificationResult alloc] init];
    r.crashType = @"SIGNAL_CRASH";
    r.severity = CrashSeverityCritical;
    r.phase = CrashPhaseRuntime;
    r.confidence = CrashConfidenceMedium;

    NSMutableDictionary *evidence = [NSMutableDictionary dictionary];
    evidence[@"exception_type"] = log[@"exception_type"] ?: @"Unknown";
    evidence[@"exception_codes"] = log[@"exception_codes"] ?: @"Unknown";
    evidence[@"exception_signal"] = log[@"exception_signal"] ?: @"Unknown";
    r.evidence = evidence;

    r.rootCause = @"Signal-based crash (EXC_BAD_ACCESS) — likely null pointer dereference or memory corruption.";

    NSMutableString *summary = [NSMutableString string];
    [summary appendFormat:@"Type: SIGNAL_CRASH\n"];
    [summary appendFormat:@"Severity: CRITICAL\n"];
    [summary appendFormat:@"Phase: RUNTIME\n"];
    [summary appendFormat:@"Exception: %@\n", evidence[@"exception_type"]];
    [summary appendFormat:@"Signal: %@\n", evidence[@"exception_signal"]];
    [summary appendFormat:@"Root Cause: %@\n", r.rootCause];
    [summary appendFormat:@"Confidence: MEDIUM\n"];
    r.humanReadableSummary = summary;

    return r;
}

#pragma mark - Exception Classification

- (CrashClassificationResult *)classifyException:(NSDictionary *)log {
    CrashClassificationResult *r = [[CrashClassificationResult alloc] init];
    r.crashType = @"OBJC_EXCEPTION";
    r.severity = CrashSeverityHigh;
    r.phase = CrashPhaseRuntime;
    r.confidence = CrashConfidenceMedium;

    NSMutableDictionary *evidence = [NSMutableDictionary dictionary];
    evidence[@"exception_type"] = log[@"exception_type"] ?: @"Unknown";
    evidence[@"exception_codes"] = log[@"exception_codes"] ?: @"Unknown";
    r.evidence = evidence;

    r.rootCause = @"Objective-C/Swift exception raised during runtime execution.";

    NSMutableString *summary = [NSMutableString string];
    [summary appendFormat:@"Type: OBJC_EXCEPTION\n"];
    [summary appendFormat:@"Severity: HIGH\n"];
    [summary appendFormat:@"Phase: RUNTIME\n"];
    [summary appendFormat:@"Exception: %@\n", evidence[@"exception_type"]];
    [summary appendFormat:@"Root Cause: %@\n", r.rootCause];
    [summary appendFormat:@"Confidence: MEDIUM\n"];
    r.humanReadableSummary = summary;

    return r;
}

#pragma mark - Forced Termination

- (CrashClassificationResult *)classifyForcedTermination:(NSDictionary *)log {
    CrashClassificationResult *r = [[CrashClassificationResult alloc] init];
    r.crashType = @"FORCED_TERMINATION";
    r.severity = CrashSeverityMedium;
    r.phase = CrashPhaseRuntime;
    r.confidence = CrashConfidenceMedium;

    NSMutableDictionary *evidence = [NSMutableDictionary dictionary];
    evidence[@"termination_reason"] = log[@"termination_reason"] ?: @"Unknown";
    evidence[@"termination_namespace"] = log[@"termination_namespace"] ?: @"Unknown";
    r.evidence = evidence;

    r.rootCause = @"Process was forcibly terminated by the system or another process.";

    NSMutableString *summary = [NSMutableString string];
    [summary appendFormat:@"Type: FORCED_TERMINATION\n"];
    [summary appendFormat:@"Severity: MEDIUM\n"];
    [summary appendFormat:@"Phase: RUNTIME\n"];
    [summary appendFormat:@"Root Cause: %@\n", r.rootCause];
    [summary appendFormat:@"Confidence: MEDIUM\n"];
    r.humanReadableSummary = summary;

    return r;
}

#pragma mark - SpringBoard Kill

- (CrashClassificationResult *)classifySpringboardKill:(NSDictionary *)log {
    CrashClassificationResult *r = [[CrashClassificationResult alloc] init];
    r.crashType = @"SPRINGBOARD_KILL";
    r.severity = CrashSeverityMedium;
    r.phase = CrashPhaseRuntime;
    r.confidence = CrashConfidenceHigh;

    NSMutableDictionary *evidence = [NSMutableDictionary dictionary];
    evidence[@"termination_namespace"] = log[@"termination_namespace"] ?: @"SPRINGBOARD";
    evidence[@"termination_reason"] = log[@"termination_reason"] ?: @"Unknown";
    r.evidence = evidence;

    r.rootCause = @"SpringBoard forcibly terminated the application (likely due to policy violation or user action).";

    NSMutableString *summary = [NSMutableString string];
    [summary appendFormat:@"Type: SPRINGBOARD_KILL\n"];
    [summary appendFormat:@"Severity: MEDIUM\n"];
    [summary appendFormat:@"Phase: RUNTIME\n"];
    [summary appendFormat:@"Root Cause: %@\n", r.rootCause];
    [summary appendFormat:@"Confidence: HIGH\n"];
    r.humanReadableSummary = summary;

    return r;
}

#pragma mark - Unknown (Fallback)

- (CrashClassificationResult *)classifyUnknown:(NSDictionary *)log {
    CrashClassificationResult *r = [[CrashClassificationResult alloc] init];
    r.crashType = @"UNKNOWN_TERMINATION";
    r.severity = CrashSeverityUnknown;
    r.phase = CrashPhaseUnknown;
    r.confidence = CrashConfidenceLow;

    NSMutableDictionary *evidence = [NSMutableDictionary dictionary];
    if (log[@"exception_type"]) evidence[@"exception_type"] = log[@"exception_type"];
    if (log[@"termination_reason"]) evidence[@"termination_reason"] = log[@"termination_reason"];
    if (log[@"termination_namespace"]) evidence[@"termination_namespace"] = log[@"termination_namespace"];
    r.evidence = evidence;

    r.rootCause = @"Unable to determine root cause from available evidence. Manual investigation required.";

    NSMutableString *summary = [NSMutableString string];
    [summary appendFormat:@"Type: UNKNOWN_TERMINATION\n"];
    [summary appendFormat:@"Severity: UNKNOWN\n"];
    [summary appendFormat:@"Phase: UNKNOWN\n"];
    [summary appendFormat:@"Root Cause: %@\n", r.rootCause];
    [summary appendFormat:@"Confidence: LOW\n"];
    if (evidence.count > 0) {
        [summary appendString:@"\nAvailable Evidence:\n"];
        for (NSString *key in evidence) {
            [summary appendFormat:@"  %@: %@\n", key, evidence[key]];
        }
    }
    r.humanReadableSummary = summary;

    return r;
}

#pragma mark - Evidence Extractors

- (NSString *)extractLibraryFromDetails:(NSString *)details {
    if (!details || details.length == 0) return nil;
    // Pattern: "Library not loaded: @rpath/libXXX.dylib" or "Library not loaded: /path/libXXX.dylib"
    NSRange range = [details rangeOfString:@"Library not loaded:"];
    if (range.location != NSNotFound) {
        NSString *after = [details substringFromIndex:range.location + range.length];
        after = [after stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSRange newline = [after rangeOfString:@"\n"];
        if (newline.location != NSNotFound) {
            after = [after substringToIndex:newline.location];
        }
        // Extract just the library name
        NSString *libName = [after lastPathComponent];
        if (libName.length > 0) return libName;
        return after;
    }
    // Alternative: look for "Referenced from:" which often follows library name
    NSRange refRange = [details rangeOfString:@"Referenced from:"];
    if (refRange.location != NSNotFound) {
        // Try to find library name before "Referenced from"
        NSString *before = [details substringToIndex:refRange.location];
        NSRange libRange = [before rangeOfString:@".dylib" options:NSBackwardsSearch];
        if (libRange.location != NSNotFound) {
            NSRange startRange = [before rangeOfString:@"/" options:NSBackwardsSearch range:NSMakeRange(0, libRange.location)];
            if (startRange.location != NSNotFound) {
                NSString *libPath = [before substringWithRange:NSMakeRange(startRange.location, libRange.location - startRange.location + libRange.length)];
                return [libPath lastPathComponent];
            }
        }
    }
    return nil;
}

- (NSNumber *)extractErrnoFromDetails:(NSString *)details {
    if (!details || details.length == 0) return nil;
    // Pattern: "errno=13" or "errno=2" or "with errno=13"
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"errno[=:]\\s*(\\d+)" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:details options:0 range:NSMakeRange(0, details.length)];
    if (match && match.numberOfRanges > 1) {
        NSString *numStr = [details substringWithRange:[match rangeAtIndex:1]];
        return @([numStr integerValue]);
    }
    return nil;
}

- (NSString *)extractDylibPathFromDetails:(NSString *)details {
    if (!details || details.length == 0) return nil;
    NSRange range = [details rangeOfString:@"Library not loaded:"];
    if (range.location != NSNotFound) {
        NSString *after = [details substringFromIndex:range.location + range.length];
        after = [after stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSRange newline = [after rangeOfString:@"\n"];
        if (newline.location != NSNotFound) {
            after = [after substringToIndex:newline.location];
        }
        return [after stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return nil;
}

@end
