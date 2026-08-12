//
// CrashDiscovery.m
// IPAInstallerPro
//

#import "CrashDiscovery.h"
#import "RootlessManager.h"

@implementation CrashDiscoveryResult
@end

@interface CrashDiscovery ()
@property (nonatomic, strong, readwrite) NSArray<NSString *> *crashLogDirectories;
@property (nonatomic, strong) NSDateFormatter *isoFormatter;
@end

@implementation CrashDiscovery

+ (instancetype)sharedDiscovery {
    static CrashDiscovery *s = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupDirectories];
        _isoFormatter = [[NSDateFormatter alloc] init];
        _isoFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS Z";
    }
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
    self.crashLogDirectories = dirs;
}

- (NSArray<NSString *> *)allCrashLogPaths {
    NSMutableArray *allPaths = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in self.crashLogDirectories) {
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

- (NSString *)peekBundleIDAtPath:(NSString *)path {
    // Quick peek: read first 4KB and look for bundle_identifier
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return nil;
    NSData *data = [fh readDataOfLength:4096];
    [fh closeFile];
    if (!data || data.length == 0) return nil;

    NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!content) content = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!content) return nil;

    // Try JSON format first
    NSRange bidRange = [content rangeOfString:@"\"bundle_identifier\""];
    if (bidRange.location != NSNotFound) {
        NSRange colonRange = [content rangeOfString:@":" options:0 range:NSMakeRange(bidRange.location, content.length - bidRange.location)];
        if (colonRange.location != NSNotFound) {
            NSRange quoteStart = [content rangeOfString:@"\"" options:0 range:NSMakeRange(colonRange.location, content.length - colonRange.location)];
            if (quoteStart.location != NSNotFound) {
                NSRange quoteEnd = [content rangeOfString:@"\"" options:0 range:NSMakeRange(quoteStart.location + 1, content.length - quoteStart.location - 1)];
                if (quoteEnd.location != NSNotFound) {
                    return [content substringWithRange:NSMakeRange(quoteStart.location + 1, quoteEnd.location - quoteStart.location - 1)];
                }
            }
        }
    }

    // Try text format
    NSRange textRange = [content rangeOfString:@"Identifier:"];
    if (textRange.location != NSNotFound) {
        NSString *after = [content substringFromIndex:textRange.location + textRange.length];
        after = [after stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSRange newline = [after rangeOfString:@"\n"];
        if (newline.location != NSNotFound) {
            after = [after substringToIndex:newline.location];
        }
        return [after stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }

    return nil;
}

- (BOOL)isCrashLogManaged:(NSString *)path forBundleIDs:(NSArray<NSString *> *)bundleIDs {
    NSString *bid = [self peekBundleIDAtPath:path];
    if (!bid || !bundleIDs) return NO;
    for (NSString *managed in bundleIDs) {
        if ([bid isEqualToString:managed]) return YES;
    }
    return NO;
}

- (CrashDiscoveryResult *)discoverCrashLogsForBundleIDs:(NSArray<NSString *> *)bundleIDs
                                            sinceDate:(NSDate *)sinceDate {
    CrashDiscoveryResult *result = [[CrashDiscoveryResult alloc] init];
    NSMutableArray *freshPaths = [NSMutableArray array];
    NSMutableArray *allManagedPaths = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    for (NSString *path in [self allCrashLogPaths]) {
        if ([self isCrashLogManaged:path forBundleIDs:bundleIDs]) {
            [allManagedPaths addObject:path];
            if (sinceDate) {
                NSError *error = nil;
                NSDictionary *attrs = [fm attributesOfItemAtPath:path error:&error];
                NSDate *modDate = attrs[NSFileModificationDate];
                if (modDate && [modDate compare:sinceDate] == NSOrderedDescending) {
                    [freshPaths addObject:path];
                }
            } else {
                [freshPaths addObject:path];
            }
        }
    }

    result.allPaths = allManagedPaths;
    result.freshPaths = freshPaths;
    result.scanTime = [NSDate date];
    return result;
}

@end
