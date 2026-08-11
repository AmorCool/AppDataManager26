#import "CrashLogParser.h"
#import "Logger.h"
#import "RootlessManager.h"

@interface CrashLogParser ()
@property (nonatomic, strong) NSArray<NSString *> *crashLogDirs;
@end

@implementation CrashLogParser

+ (instancetype)sharedParser {
    static CrashLogParser *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) { [self setupDirectories]; }
    return self;
}

- (void)setupDirectories {
    NSMutableArray *dirs = [NSMutableArray array];
    NSArray *paths = @[
        @"/var/mobile/Library/Logs/CrashReporter",
        @"/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs",
        @"/var/jb/var/mobile/Library/Logs/CrashReporter"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        if ([fm fileExistsAtPath:path]) [dirs addObject:path];
    }
    self.crashLogDirs = dirs;
}

- (NSArray<NSString *> *)scanCrashLogDirectories {
    NSMutableArray *allPaths = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in self.crashLogDirs) {
        NSError *error = nil;
        NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:&error];
        if (error) continue;
        for (NSString *file in contents) {
            if ([file hasSuffix:@".ips"] || [file hasSuffix:@".crash"] || [file hasSuffix:@".plist"]) {
                [allPaths addObject:[dir stringByAppendingPathComponent:file]];
            }
        }
    }
    return allPaths;
}

- (NSDictionary *)parseCrashLogAtPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return nil;
    NSData *data = [fm contentsAtPath:path];
    if (!data) return nil;
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"source_path"] = path;
    result[@"source_filename"] = [path lastPathComponent];
    NSError *attrError = nil;
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:&attrError];
    NSDate *modDate = attrs[NSFileModificationDate];
    result[@"timestamp_date"] = modDate ?: [NSDate date];
    result[@"timestamp"] = [modDate description] ?: @"Unknown";
    NSError *jsonError = nil;
    id jsonObj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (jsonObj && [jsonObj isKindOfClass:[NSDictionary class]]) {
        [self parseJSONCrashLog:jsonObj into:result];
    } else {
        NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [self parseTextCrashLog:content into:result];
    }
    [self classifyCrashEvent:result];
    return result;
}

- (void)parseJSONCrashLog:(NSDictionary *)json into:(NSMutableDictionary *)result {
    NSDictionary *header = json[@"header"];
    if (header) {
        result[@"process_name"] = header[@"process_name"] ?: @"Unavailable";
        result[@"bundle_identifier"] = header[@"bundle_identifier"] ?: @"Unavailable";
        result[@"executable_path"] = header[@"executable_path"] ?: @"Unavailable";
        result[@"app_version"] = header[@"app_version"] ?: @"Unavailable";
        result[@"os_version"] = header[@"os_version"] ?: @"Unavailable";
        result[@"device_model"] = header[@"device_model"] ?: @"Unavailable";
        result[@"pid"] = header[@"pid"] ?: @"Unavailable";
        result[@"parent_process"] = header[@"parent_process"] ?: @"Unavailable";
    }
    NSDictionary *exception = json[@"exception"];
    if (exception) {
        result[@"exception_type"] = exception[@"type"] ?: @"Unavailable";
        result[@"exception_codes"] = exception[@"codes"] ?: @"Unavailable";
        result[@"exception_signal"] = exception[@"signal"] ?: @"Unavailable";
    }
    NSDictionary *termination = json[@"termination"];
    if (termination) {
        result[@"termination_reason"] = termination[@"reason"] ?: @"Unavailable";
        result[@"termination_namespace"] = termination[@"namespace"] ?: @"Unavailable";
        result[@"termination_code"] = termination[@"code"] ?: @"Unavailable";
        result[@"termination_indicator"] = termination[@"indicator"] ?: @"Unavailable";
        result[@"termination_details"] = termination[@"details"] ?: @"Unavailable";
    }
    if (json[@"jetsam"]) {
        result[@"jetsam_event"] = @YES;
        result[@"jetsam_reason"] = json[@"jetsam"][@"jetsam_reason"] ?: @"Unavailable";
    }
    result[@"crashed_thread"] = json[@"crashed_thread"] ?: json[@"triggered_thread"] ?: @"Unavailable";
    result[@"threads"] = json[@"threads"] ?: @"Unavailable";
    result[@"thread_state"] = json[@"thread_state"] ?: @"Unavailable";
    result[@"registers"] = json[@"registers"] ?: @"Unavailable";
    result[@"binary_images"] = json[@"binary_images"] ?: @"Unavailable";
    NSArray *threads = json[@"threads"];
    if (threads && [threads isKindOfClass:[NSArray class]]) {
        NSMutableString *bt = [NSMutableString string];
        for (NSDictionary *thread in threads) {
            NSString *tname = thread[@"name"] ?: [NSString stringWithFormat:@"Thread %@", thread[@"id"] ?: @"?"];
            [bt appendFormat:@"\n=== %@ ===\n", tname];
            NSArray *frames = thread[@"frames"];
            if (frames && [frames isKindOfClass:[NSArray class]]) {
                for (int i = 0; i < frames.count; i++) {
                    NSDictionary *f = frames[i];
                    [bt appendFormat:@"%d. %@ (%@ + %@)\n", i, f[@"symbol"] ?: f[@"imageOffset"] ?: @"???", f[@"imageName"] ?: @"???", f[@"offset"] ?: @"0"];
                }
            }
        }
        result[@"backtrace_text"] = bt;
    }
    result[@"raw_json"] = json;
}

- (void)parseTextCrashLog:(NSString *)content into:(NSMutableDictionary *)result {
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        if ([line hasPrefix:@"Process:"]) result[@"process_name"] = [[line componentsSeparatedByString:@":"] lastObject] ?: @"Unavailable";
        else if ([line hasPrefix:@"Identifier:"]) result[@"bundle_identifier"] = [[line componentsSeparatedByString:@":"] lastObject] ?: @"Unavailable";
        else if ([line hasPrefix:@"Path:"]) result[@"executable_path"] = [[line componentsSeparatedByString:@":"] lastObject] ?: @"Unavailable";
        else if ([line hasPrefix:@"Version:"]) result[@"app_version"] = [[line componentsSeparatedByString:@":"] lastObject] ?: @"Unavailable";
        else if ([line hasPrefix:@"OS Version:"]) result[@"os_version"] = [[line componentsSeparatedByString:@":"] lastObject] ?: @"Unavailable";
        else if ([line hasPrefix:@"Exception Type:"]) result[@"exception_type"] = [[line componentsSeparatedByString:@":"] lastObject] ?: @"Unavailable";
        else if ([line hasPrefix:@"Exception Codes:"]) result[@"exception_codes"] = [[line componentsSeparatedByString:@":"] lastObject] ?: @"Unavailable";
        else if ([line hasPrefix:@"Crashed Thread:"]) result[@"crashed_thread"] = [[line componentsSeparatedByString:@":"] lastObject] ?: @"Unavailable";
        else if ([line hasPrefix:@"Termination Reason:"]) result[@"termination_reason"] = [[line componentsSeparatedByString:@":"] lastObject] ?: @"Unavailable";
    }
    NSRange btRange = [content rangeOfString:@"Thread 0"];
    if (btRange.location != NSNotFound) result[@"backtrace_text"] = [content substringFromIndex:btRange.location];
    result[@"raw_text"] = content;
}

- (void)classifyCrashEvent:(NSMutableDictionary *)result {
    NSString *excType = result[@"exception_type"];
    NSString *termReason = result[@"termination_reason"];
    NSString *termNS = result[@"termination_namespace"];
    NSString *termIndicator = result[@"termination_indicator"];
    NSString *eventType = @"UNKNOWN_EXIT";

    // DYLD errors = Launch Failure (missing libraries, bad Mach-O, etc.)
    if (termNS && [termNS isEqualToString:@"DYLD"]) {
        eventType = @"LAUNCH_FAILURE";
    } else if ([result[@"jetsam_event"] boolValue]) {
        eventType = @"JETSAM";
    } else if (excType && ![excType isEqualToString:@"Unavailable"]) {
        if ([excType containsString:@"EXC_BAD_ACCESS"]) eventType = @"SIGNAL";
        else if ([excType containsString:@"EXC_CRASH"]) {
            // Check if DYLD related even if namespace isn't DYLD
            if (termIndicator && [termIndicator containsString:@"Library"]) {
                eventType = @"LAUNCH_FAILURE";
            } else {
                eventType = [termReason containsString:@"watchdog"] ? @"WATCHDOG" : @"CRASH";
            }
        } else if ([excType containsString:@"EXC_BREAKPOINT"] || [excType containsString:@"EXC_GUARD"]) {
            eventType = @"CRASH";
        } else {
            eventType = @"EXCEPTION";
        }
    } else if (termReason && ![termReason isEqualToString:@"Unavailable"]) {
        if ([termReason containsString:@"jetsam"]) eventType = @"JETSAM";
        else if ([termReason containsString:@"watchdog"]) eventType = @"WATCHDOG";
        else if ([termNS containsString:@"SPRINGBOARD"]) eventType = @"FORCED_TERMINATION";
        else if ([termNS containsString:@"JETSAM"]) eventType = @"JETSAM";
        else if ([termReason containsString:@"Library not loaded"]) eventType = @"LAUNCH_FAILURE";
        else eventType = @"CRASH";
    }
    result[@"event_type"] = eventType;
    if ([eventType isEqualToString:@"JETSAM"]) result[@"event_description"] = @"Memory pressure termination (Jetsam)";
    else if ([eventType isEqualToString:@"WATCHDOG"]) result[@"event_description"] = @"Watchdog timeout";
    else if ([eventType isEqualToString:@"SIGNAL"]) result[@"event_description"] = @"Signal-based crash";
    else if ([eventType isEqualToString:@"EXCEPTION"]) result[@"event_description"] = @"Objective-C/Swift exception";
    else if ([eventType isEqualToString:@"FORCED_TERMINATION"]) result[@"event_description"] = @"Forced termination";
    else if ([eventType isEqualToString:@"LAUNCH_FAILURE"]) {
        NSString *details = @"";
        if (termIndicator) details = [NSString stringWithFormat:@" (%@)", termIndicator];
        result[@"event_description"] = [NSString stringWithFormat:@"Launch failure%@: %@", details, termReason ?: @"Unknown"];
    }
    else if ([eventType isEqualToString:@"CRASH"]) result[@"event_description"] = @"Application crash";
    else result[@"event_description"] = @"Unknown termination";
}

- (NSArray<NSDictionary *> *)parseAllRecentCrashLogs {
    NSArray *paths = [self scanCrashLogDirectories];
    NSMutableArray *parsed = [NSMutableArray array];
    for (NSString *path in paths) {
        NSDictionary *crash = [self parseCrashLogAtPath:path];
        if (crash) [parsed addObject:crash];
    }
    return [parsed sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"timestamp_date"] compare:a[@"timestamp_date"]];
    }];
}

- (NSArray<NSDictionary *> *)crashLogsForBundleID:(NSString *)bundleID {
    if (!bundleID) return @[];
    NSArray *all = [self parseAllRecentCrashLogs];
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *log in all) {
        if ([log[@"bundle_identifier"] isEqualToString:bundleID]) [filtered addObject:log];
    }
    return filtered;
}

- (NSArray<NSDictionary *> *)newCrashLogsSince:(NSDate *)date {
    if (!date) return [self parseAllRecentCrashLogs];
    NSArray *all = [self parseAllRecentCrashLogs];
    NSMutableArray *newLogs = [NSMutableArray array];
    for (NSDictionary *log in all) {
        NSDate *logDate = log[@"timestamp_date"];
        if (logDate && [logDate compare:date] == NSOrderedDescending) [newLogs addObject:log];
    }
    return newLogs;
}

- (NSArray<NSString *> *)crashLogPathsForBundleID:(NSString *)bundleID {
    if (!bundleID) return @[];
    NSArray *allPaths = [self scanCrashLogDirectories];
    NSMutableArray *matching = [NSMutableArray array];
    for (NSString *path in allPaths) {
        NSDictionary *parsed = [self parseCrashLogAtPath:path];
        if (parsed && [parsed[@"bundle_identifier"] isEqualToString:bundleID]) [matching addObject:path];
    }
    return matching;
}

@end
