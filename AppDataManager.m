//
//  AppDataManager.m
//  AppDataManager
//
//  v1.6.0 — Crash-Resilient Core Engine
//

#import "AppDataManager.h"
#import "rootless.h"
#import <objc/runtime.h>
#import <sys/stat.h>
#import <dlfcn.h>
#import <stdio.h>

static NSString * const kBackupDir = @"/var/mobile/Documents/AppDataManager/Backups";

@interface AppDataManager ()
@property (nonatomic, strong) dispatch_queue_t fileQueue;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;
@property (nonatomic, assign) NSUInteger iosMajorVersion;
@end

@implementation AppDataManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static AppDataManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sizeCache = [[NSCache alloc] init];
        _sizeCache.countLimit = 500;

        _iconCache = [[NSCache alloc] init];
        _iconCache.countLimit = 200;

        _fileQueue = dispatch_queue_create(
            "com.appdatamanager.fileops", DISPATCH_QUEUE_SERIAL);
        _cacheQueue = dispatch_queue_create(
            "com.appdatamanager.cache", DISPATCH_QUEUE_SERIAL);

        _iosMajorVersion = [self detectIOSMajorVersion];
    }
    return self;
}

- (NSUInteger)detectIOSMajorVersion {
    @try {
        NSProcessInfo *info = [NSProcessInfo processInfo];
        if ([info respondsToSelector:
                @selector(operatingSystemVersion)]) {
            NSOperatingSystemVersion ver =
                info.operatingSystemVersion;
            return ver.majorVersion;
        }
    } @catch (NSException *e) { }

    @try {
        NSString *version =
            [[UIDevice currentDevice] systemVersion];
        NSArray *parts = [version componentsSeparatedByString:@"."];
        if (parts.count > 0) return [parts[0] integerValue];
    } @catch (NSException *e) { }

    return 15;
}

#pragma mark - Cache

- (void)clearCache {
    dispatch_sync(self.cacheQueue, ^{
        [self.sizeCache removeAllObjects];
        [self.iconCache removeAllObjects];
    });
}

#pragma mark - Application Discovery

- (NSArray *)allInstalledApplications {
    NSMutableArray *apps = [NSMutableArray array];

    @try {
        // Strategy 1: LSApplicationWorkspace
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        if (wsClass) {
            id workspace = [wsClass performSelector:
                @selector(defaultWorkspace)];
            if (workspace) {
                NSArray *proxies = nil;
                @try {
                    proxies = [workspace performSelector:
                        @selector(allInstalledApplications)];
                } @catch (NSException *e) { }

                if (![proxies isKindOfClass:[NSArray class]]) {
                    @try {
                        proxies = [workspace performSelector:
                            @selector(allApplications)];
                    } @catch (NSException *e) { }
                }

                if ([proxies isKindOfClass:[NSArray class]]) {
                    for (id proxy in proxies) {
                        @autoreleasepool {
                            NSDictionary *info =
                                [self extractInfoFromProxy:proxy];
                            if (info) [apps addObject:info];
                        }
                    }
                }
            }
        }

        // Strategy 2: Filesystem fallback
        if (apps.count == 0) {
            [apps addObjectsFromArray:
                [self discoverAppsFromFilesystem]];
        }

    } @catch (NSException *e) {
        NSLog(@"[ADM] discovery exception: %@", e);
    }

    return [apps sortedArrayUsingComparator:
        ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSString *n1 = a[@"name"] ?: @"";
            NSString *n2 = b[@"name"] ?: @"";
            return [n1 localizedCaseInsensitiveCompare:n2];
        }];
}

- (NSDictionary *)extractInfoFromProxy:(id)proxy {
    @try {
        if (!proxy) return nil;

        NSString *bundleID = nil;
        NSString *name = nil;
        NSString *version = @"1.0";
        NSString *bundlePath = @"";
        BOOL isSystem = NO;

        if ([proxy respondsToSelector:@selector(bundleIdentifier)]) {
            bundleID = [proxy performSelector:@selector(bundleIdentifier)];
        }
        if (![bundleID isKindOfClass:[NSString class]] ||
            bundleID.length == 0) return nil;

        if ([proxy respondsToSelector:@selector(localizedName)]) {
            name = [proxy performSelector:@selector(localizedName)];
        }
        if (![name isKindOfClass:[NSString class]] || name.length == 0) {
            if ([proxy respondsToSelector:@selector(itemName)]) {
                name = [proxy performSelector:@selector(itemName)];
            }
        }
        if (![name isKindOfClass:[NSString class]] || name.length == 0) {
            name = bundleID;
        }

        if ([proxy respondsToSelector:@selector(shortVersionString)]) {
            version = [proxy performSelector:@selector(shortVersionString)];
            if (![version isKindOfClass:[NSString class]])
                version = @"1.0";
        }

        if ([proxy respondsToSelector:@selector(bundleContainerURL)]) {
            NSURL *url = [proxy performSelector:@selector(bundleContainerURL)];
            bundlePath = url.path ?: @"";
        }
        if (!bundlePath.length &&
            [proxy respondsToSelector:@selector(bundleURL)]) {
            NSURL *url = [proxy performSelector:@selector(bundleURL)];
            bundlePath = url.path ?: @"";
        }

        isSystem = [bundlePath hasPrefix:@"/System/"] ||
            [bundlePath hasPrefix:@"/var/jb/System/"] ||
            [bundlePath hasPrefix:@"/Applications/"] ||
            [bundlePath hasPrefix:@"/var/jb/Applications/"];

        return @{
            @"bundleID": bundleID,
            @"name": name ?: bundleID,
            @"version": version,
            @"bundlePath": bundlePath,
            @"isSystem": @(isSystem)
        };

    } @catch (NSException *e) {
        return nil;
    }
}

- (NSArray *)discoverAppsFromFilesystem {
    NSMutableArray *apps = [NSMutableArray array];

    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *searchPaths = @[
            @"/var/containers/Bundle/Application",
            @"/private/var/containers/Bundle/Application",
            ROOT_PATH_NS(@"/var/containers/Bundle/Application"),
            ROOT_PATH_NS(@"/private/var/containers/Bundle/Application")
        ];

        for (NSString *basePath in searchPaths) {
            if (![fm fileExistsAtPath:basePath]) continue;

            NSArray *uuidDirs = nil;
            @try {
                uuidDirs = [fm contentsOfDirectoryAtPath:basePath error:nil];
            } @catch (NSException *e) { continue; }

            for (NSString *uuidDir in uuidDirs) {
                @autoreleasepool {
                    NSString *container =
                        [basePath stringByAppendingPathComponent:uuidDir];
                    NSArray *contents = nil;
                    @try {
                        contents = [fm contentsOfDirectoryAtPath:container
                                                           error:nil];
                    } @catch (NSException *e) { continue; }

                    for (NSString *item in contents) {
                        if (![item hasSuffix:@".app"]) continue;

                        NSString *infoPath =
                            [container stringByAppendingPathComponent:
                                [item stringByAppendingPathComponent:
                                    @"Info.plist"]];
                        NSDictionary *info = nil;
                        @try {
                            info = [NSDictionary
                                dictionaryWithContentsOfFile:infoPath];
                        } @catch (NSException *e) { continue; }

                        if (!info) continue;

                        NSString *bid = info[@"CFBundleIdentifier"];
                        NSString *name =
                            info[@"CFBundleDisplayName"] ?:
                            info[@"CFBundleName"] ?: bid;
                        NSString *ver =
                            info[@"CFBundleShortVersionString"] ?: @"1.0";

                        if (bid) {
                            [apps addObject:@{
                                @"bundleID": bid,
                                @"name": name ?: bid,
                                @"version": ver,
                                @"bundlePath":
                                    [container stringByAppendingPathComponent:item],
                                @"isSystem": @NO
                            }];
                        }
                        break;
                    }
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[ADM] filesystem discovery exception: %@", e);
    }

    return apps;
}

#pragma mark - Data Paths

- (NSString *)dataPathForBundleID:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) return nil;

    @try {
        NSString *path = [self dataPathViaContainerManager:bundleID];
        if (path && [self pathExists:path]) return path;

        path = [self dataPathViaFilesystemSearch:bundleID];
        if (path && [self pathExists:path]) return path;

        path = [self dataPathViaProxy:bundleID];
        if (path && [self pathExists:path]) return path;

    } @catch (NSException *e) { }

    return nil;
}

- (NSString *)dataPathViaContainerManager:(NSString *)bundleID {
    @try {
        Class cls = NSClassFromString(@"MCMContainer");
        if (!cls) return nil;

        id container = nil;
        if ([cls respondsToSelector:
                @selector(containerWithIdentifier:createIfNecessary:error:)]) {
            NSMethodSignature *sig = [cls methodSignatureForSelector:
                @selector(containerWithIdentifier:createIfNecessary:error:)];
            if (sig) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setSelector:@selector(containerWithIdentifier:createIfNecessary:error:)];
                [inv setTarget:cls];
                NSString *bid = bundleID;
                BOOL create = NO;
                [inv setArgument:&bid atIndex:2];
                [inv setArgument:&create atIndex:3];
                [inv invoke];
                [inv getReturnValue:&container];
            }
        }
        if (!container && [cls respondsToSelector:
                @selector(containerWithIdentifier:error:)]) {
            container = [cls performSelector:
                @selector(containerWithIdentifier:error:)
                withObject:bundleID withObject:nil];
        }

        if (container && [container respondsToSelector:@selector(url)]) {
            NSURL *url = [container performSelector:@selector(url)];
            return url.path;
        }
    } @catch (NSException *e) { }
    return nil;
}

- (NSString *)dataPathViaFilesystemSearch:(NSString *)bundleID {
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *paths = @[
            @"/var/mobile/Containers/Data/Application",
            @"/private/var/mobile/Containers/Data/Application",
            ROOT_PATH_NS(@"/var/mobile/Containers/Data/Application"),
            ROOT_PATH_NS(@"/private/var/mobile/Containers/Data/Application")
        ];

        for (NSString *base in paths) {
            if (![fm fileExistsAtPath:base]) continue;

            NSArray *dirs = [fm contentsOfDirectoryAtPath:base error:nil];
            for (NSString *dir in dirs) {
                @autoreleasepool {
                    NSString *metaPath = [base stringByAppendingPathComponent:
                        [dir stringByAppendingPathComponent:
                            @".com.apple.mobile_container_manager.metadata.plist"]];
                    NSDictionary *meta =
                        [NSDictionary dictionaryWithContentsOfFile:metaPath];
                    if ([meta[@"MCMMetadataIdentifier"]
                            isEqualToString:bundleID]) {
                        return [base stringByAppendingPathComponent:dir];
                    }
                }
            }
        }
    } @catch (NSException *e) { }
    return nil;
}

- (NSString *)dataPathViaProxy:(NSString *)bundleID {
    @try {
        Class cls = NSClassFromString(@"LSApplicationProxy");
        if (!cls) return nil;

        id proxy = [cls performSelector:
            @selector(applicationProxyForIdentifier:)
            withObject:bundleID];
        if (!proxy) return nil;

        if ([proxy respondsToSelector:@selector(containerURL)]) {
            NSURL *url = [proxy performSelector:@selector(containerURL)];
            return url.path;
        }
        if ([proxy respondsToSelector:@selector(dataContainerURL)]) {
            NSURL *url = [proxy performSelector:@selector(dataContainerURL)];
            return url.path;
        }
    } @catch (NSException *e) { }
    return nil;
}

- (NSArray *)allDataPathsForBundleID:(NSString *)bundleID {
    if (!bundleID) return @[];
    NSMutableArray *paths = [NSMutableArray array];
    NSString *main = [self dataPathForBundleID:bundleID];
    if (main) [paths addObject:main];
    [paths addObjectsFromArray:
        [self groupContainerPathsForBundleID:bundleID]];
    return [paths copy];
}

- (NSArray *)groupContainerPathsForBundleID:(NSString *)bundleID {
    if (!bundleID) return @[];
    NSMutableArray *paths = [NSMutableArray array];

    @try {
        Class cls = NSClassFromString(@"LSApplicationProxy");
        if (cls) {
            id proxy = [cls performSelector:
                @selector(applicationProxyForIdentifier:)
                withObject:bundleID];
            if (proxy && [proxy respondsToSelector:
                    @selector(groupContainerURLs)]) {
                NSDictionary *urls = [proxy performSelector:
                    @selector(groupContainerURLs)];
                if ([urls isKindOfClass:[NSDictionary class]]) {
                    for (NSURL *url in [urls allValues]) {
                        if ([url isKindOfClass:[NSURL class]] && url.path) {
                            [paths addObject:url.path];
                        }
                    }
                }
            }
        }

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *groupBase =
            @"/var/mobile/Containers/Shared/AppGroup";
        NSArray *groupDirs = [fm contentsOfDirectoryAtPath:groupBase
                                                       error:nil];
        for (NSString *dir in groupDirs) {
            @autoreleasepool {
                NSString *metaPath = [groupBase stringByAppendingPathComponent:
                    [dir stringByAppendingPathComponent:
                        @".com.apple.mobile_container_manager.metadata.plist"]];
                NSDictionary *meta =
                    [NSDictionary dictionaryWithContentsOfFile:metaPath];
                if ([meta[@"MCMMetadataIdentifier"]
                        isEqualToString:bundleID]) {
                    [paths addObject:
                        [groupBase stringByAppendingPathComponent:dir]];
                }
            }
        }
    } @catch (NSException *e) { }

    return [paths copy];
}

#pragma mark - Size Calculation

- (unsigned long long)dataSizeForBundleID:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) return 0;

    __block NSNumber *cached = nil;
    dispatch_sync(self.cacheQueue, ^{
        cached = [self.sizeCache objectForKey:bundleID];
    });
    if (cached) return [cached unsignedLongLongValue];

    __block unsigned long long total = 0;
    dispatch_sync(self.fileQueue, ^{
        @autoreleasepool {
            @try {
                NSArray *paths =
                    [self allDataPathsForBundleID:bundleID];
                for (NSString *path in paths) {
                    if (!path || path.length == 0) continue;
                    total += [self fastDirectorySize:path];
                }
            } @catch (NSException *e) {
                NSLog(@"[ADM] size exception for %@: %@", bundleID, e);
                total = 0;
            }
        }
    });

    dispatch_sync(self.cacheQueue, ^{
        [self.sizeCache setObject:@(total) forKey:bundleID];
    });

    return total;
}

- (unsigned long long)accurateDataSizeForBundleID:(NSString *)bundleID {
    if (!bundleID) return 0;
    __block unsigned long long total = 0;
    dispatch_sync(self.fileQueue, ^{
        @autoreleasepool {
            @try {
                NSArray *paths =
                    [self allDataPathsForBundleID:bundleID];
                for (NSString *path in paths) {
                    if (!path || path.length == 0) continue;
                    total += [self fastDirectorySize:path];
                }
            } @catch (NSException *e) { }
        }
    });
    return total;
}

- (unsigned long long)fastDirectorySize:(NSString *)path {
    if (!path || path.length == 0) return 0;
    if (![self pathExists:path]) return 0;

    unsigned long long total = 0;

    @try {
        NSFileManager *fm = [[NSFileManager alloc] init];
        NSURL *url = [NSURL fileURLWithPath:path];

        NSDirectoryEnumerator *enumerator =
            [fm enumeratorAtURL:url
     includingPropertiesForKeys:@[NSURLFileSizeKey,
                                    NSURLIsSymbolicLinkKey]
                        options:NSDirectoryEnumerationSkipsPackageDescendants |
                                NSDirectoryEnumerationSkipsHiddenFiles
                   errorHandler:^BOOL(NSURL *u, NSError *error) {
                       return YES;
                   }];

        NSMutableSet *visitedInodes = [NSMutableSet set];

        for (NSURL *fileURL in enumerator) {
            @autoreleasepool {
                @try {
                    NSNumber *isSymlink = nil;
                    [fileURL getResourceValue:&isSymlink
                                       forKey:NSURLIsSymbolicLinkKey
                                        error:nil];
                    if ([isSymlink boolValue]) continue;

                    const char *cpath =
                        [fileURL.path fileSystemRepresentation];
                    struct stat st;
                    if (lstat(cpath, &st) == 0) {
                        NSString *key =
                            [NSString stringWithFormat:@"%llu-%llu",
                                (unsigned long long)st.st_dev,
                                (unsigned long long)st.st_ino];
                        if ([visitedInodes containsObject:key]) continue;
                        [visitedInodes addObject:key];
                        total += (unsigned long long)st.st_size;
                    }
                } @catch (NSException *e) { continue; }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[ADM] fastDirectorySize exception: %@", e);
    }

    return total;
}

#pragma mark - Wipe / Backup / Restore

- (BOOL)wipeAppData:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) return NO;
    if ([self isSystemApp:bundleID]) return NO;

    __block BOOL success = YES;
    dispatch_sync(self.fileQueue, ^{
        @autoreleasepool {
            @try {
                NSArray *paths =
                    [self allDataPathsForBundleID:bundleID];
                NSFileManager *fm = [NSFileManager defaultManager];

                for (NSString *path in paths) {
                    if (!path || path.length == 0) continue;
                    NSArray *contents =
                        [fm contentsOfDirectoryAtPath:path error:nil];
                    for (NSString *item in contents) {
                        @autoreleasepool {
                            NSString *full =
                                [path stringByAppendingPathComponent:item];
                            @try {
                                [fm removeItemAtPath:full error:nil];
                            } @catch (NSException *e) {
                                success = NO;
                            }
                        }
                    }
                }

                dispatch_sync(self.cacheQueue, ^{
                    [self.sizeCache removeObjectForKey:bundleID];
                });

            } @catch (NSException *e) {
                success = NO;
            }
        }
    });

    return success;
}

- (NSString *)backupDirectory {
    NSString *path = ROOT_PATH_NS(kBackupDir);
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        @try {
            [fm createDirectoryAtPath:path
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
        } @catch (NSException *e) { }
    }
    return path;
}

- (BOOL)backupAppData:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) return NO;

    @try {
        NSString *backupDir = [self backupDirectory];
        if (!backupDir) return NO;

        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
        NSString *ts = [df stringFromDate:[NSDate date]];
        NSString *name =
            [NSString stringWithFormat:@"%@_%@", bundleID, ts];
        NSString *dest = [backupDir stringByAppendingPathComponent:name];

        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:dest
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];

        NSArray *dataPaths =
            [self allDataPathsForBundleID:bundleID];
        for (NSString *src in dataPaths) {
            if (!src || src.length == 0) continue;
            NSString *itemDest =
                [dest stringByAppendingPathComponent:[src lastPathComponent]];
            @try {
                [fm copyItemAtPath:src toPath:itemDest error:nil];
            } @catch (NSException *e) { }
        }

        return YES;
    } @catch (NSException *e) {
        return NO;
    }
}

- (BOOL)restoreAppData:(NSString *)bundleID
            fromBackup:(NSString *)backupPath {
    if (!bundleID || !backupPath || backupPath.length == 0) return NO;
    if ([self isSystemApp:bundleID]) return NO;

    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:backupPath]) return NO;

        [self killApp:bundleID];
        [self wipeAppData:bundleID];

        NSArray *destPaths =
            [self allDataPathsForBundleID:bundleID];
        for (NSString *dest in destPaths) {
            if (!dest || dest.length == 0) continue;
            NSString *src =
                [backupPath stringByAppendingPathComponent:
                    [dest lastPathComponent]];
            if ([fm fileExistsAtPath:src]) {
                @try {
                    [fm copyItemAtPath:src toPath:dest error:nil];
                } @catch (NSException *e) { }
            }
        }

        dispatch_sync(self.cacheQueue, ^{
            [self.sizeCache removeObjectForKey:bundleID];
        });

        return YES;
    } @catch (NSException *e) {
        return NO;
    }
}

- (NSArray *)availableBackupsForBundleID:(NSString *)bundleID {
    if (!bundleID) return @[];

    @try {
        NSString *dir = [self backupDirectory];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:nil];
        NSMutableArray *backups = [NSMutableArray array];

        for (NSString *item in contents) {
            if ([item hasPrefix:bundleID]) {
                NSString *full = [dir stringByAppendingPathComponent:item];
                NSDictionary *attrs =
                    [fm attributesOfItemAtPath:full error:nil];
                [backups addObject:@{
                    @"path": full,
                    @"date": attrs[NSFileModificationDate] ?: [NSDate date],
                    @"name": item
                }];
            }
        }

        return [backups sortedArrayUsingComparator:
            ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                return [b[@"date"] compare:a[@"date"]];
            }];

    } @catch (NSException *e) {
        return @[];
    }
}

- (BOOL)deleteBackup:(NSString *)backupPath {
    if (!backupPath || backupPath.length == 0) return NO;
    @try {
        [[NSFileManager defaultManager] removeItemAtPath:backupPath
                                                   error:nil];
        return YES;
    } @catch (NSException *e) { return NO; }
}

- (BOOL)deleteAllBackups {
    @try {
        NSString *dir = [self backupDirectory];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *item in contents) {
            @autoreleasepool {
                @try {
                    [fm removeItemAtPath:
                        [dir stringByAppendingPathComponent:item]
                                   error:nil];
                } @catch (NSException *e) { }
            }
        }
        return YES;
    } @catch (NSException *e) { return NO; }
}

- (NSString *)exportBackupsToZip:(NSError **)error {
    @try {
        NSString *dir = [self backupDirectory];
        NSString *zip = [dir stringByAppendingPathComponent:
            @"backups_export.zip"];
        NSString *cmd =
            [NSString stringWithFormat:
                @"cd \"%@\" && zip -r \"%@\" . -x \"*.zip\"",
                dir, zip];
        int result = system([cmd UTF8String]);
        if (result == 0 && [self pathExists:zip]) return zip;
        return nil;
    } @catch (NSException *e) {
        if (error) {
            *error = [NSError errorWithDomain:@"AppDataManager"
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    e.reason ?: @"Unknown"}];
        }
        return nil;
    }
}

#pragma mark - Disk Space

- (unsigned long long)totalFreeSpace {
    @try {
        NSDictionary *attrs =
            [[NSFileManager defaultManager]
                attributesOfFileSystemForPath:NSHomeDirectory()
                                        error:nil];
        return [attrs[NSFileSystemFreeSize] unsignedLongLongValue];
    } @catch (NSException *e) { return 0; }
}

- (unsigned long long)totalDiskSpace {
    @try {
        NSDictionary *attrs =
            [[NSFileManager defaultManager]
                attributesOfFileSystemForPath:NSHomeDirectory()
                                        error:nil];
        return [attrs[NSFileSystemSize] unsignedLongLongValue];
    } @catch (NSException *e) { return 0; }
}

#pragma mark - UI Support

- (UIImage *)iconForBundleID:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) return nil;

    __block UIImage *cached = nil;
    dispatch_sync(self.cacheQueue, ^{
        cached = [self.iconCache objectForKey:bundleID];
    });
    if (cached) return cached;

    __block UIImage *icon = nil;

    @try {
        // Strategy 1: LSApplicationProxy
        Class cls = NSClassFromString(@"LSApplicationProxy");
        if (cls) {
            id proxy = [cls performSelector:
                @selector(applicationProxyForIdentifier:)
                withObject:bundleID];
            if (proxy) {
                for (NSNumber *variant in @[@(2), @(0)]) {
                    if ([proxy respondsToSelector:
                            @selector(iconDataForVariant:)]) {
                        NSData *data = [proxy performSelector:
                            @selector(iconDataForVariant:)
                            withObject:variant];
                        if ([data isKindOfClass:[NSData class]]) {
                            icon = [UIImage imageWithData:data];
                            if (icon) break;
                        }
                    }
                }
            }
        }

        // Strategy 2: Filesystem
        if (!icon) {
            NSString *dataPath = [self dataPathForBundleID:bundleID];
            if (dataPath) {
                NSFileManager *fm = [NSFileManager defaultManager];
                NSArray *items =
                    [fm contentsOfDirectoryAtPath:dataPath error:nil];
                for (NSString *item in items) {
                    if (![item hasSuffix:@".app"]) continue;
                    NSString *appPath =
                        [dataPath stringByAppendingPathComponent:item];
                    NSArray *iconNames = @[@"AppIcon60x60",
                                             @"AppIcon76x76",
                                             @"Icon-60",
                                             @"Icon",
                                             @"icon"];
                    for (NSString *name in iconNames) {
                        for (NSString *ext in @[@"png", @"jpg",
                                                @"@2x.png",
                                                @"@3x.png"]) {
                            NSString *ip = [appPath
                                stringByAppendingPathComponent:
                                    [name stringByAppendingPathExtension:ext]];
                            if ([fm fileExistsAtPath:ip]) {
                                icon = [UIImage imageWithContentsOfFile:ip];
                                if (icon) break;
                            }
                        }
                        if (icon) break;
                    }
                    break;
                }
            }
        }

        // Strategy 3: SpringBoardServices
        if (!icon) {
            void *handle = dlopen(
                "/System/Library/PrivateFrameworks/"
                "SpringBoardServices.framework/SpringBoardServices",
                RTLD_LAZY);
            if (handle) {
                NSData *(*func)(NSString *) = dlsym(handle,
                    "SBSCopyIconImagePNGDataForDisplayIdentifier");
                if (func) {
                    NSData *data = func(bundleID);
                    if (data) icon = [UIImage imageWithData:data];
                }
                dlclose(handle);
            }
        }

    } @catch (NSException *e) {
        NSLog(@"[ADM] icon exception for %@: %@", bundleID, e);
    }

    if (icon) {
        dispatch_sync(self.cacheQueue, ^{
            [self.iconCache setObject:icon forKey:bundleID];
        });
    }

    return icon;
}

- (NSString *)formatBytes:(unsigned long long)bytes {
    @try {
        if (bytes == 0) return @"0 B";

        NSArray *units = @[@"B", @"KB", @"MB", @"GB", @"TB"];
        NSUInteger idx = 0;
        double size = (double)bytes;

        while (size >= 1024.0 && idx < units.count - 1) {
            size /= 1024.0;
            idx++;
        }

        if (idx == 0) {
            return [NSString stringWithFormat:@"%llu %@",
                    bytes, units[idx]];
        } else if (size < 10) {
            return [NSString stringWithFormat:@"%.2f %@",
                    size, units[idx]];
        } else if (size < 100) {
            return [NSString stringWithFormat:@"%.1f %@",
                    size, units[idx]];
        } else {
            return [NSString stringWithFormat:@"%.0f %@",
                    size, units[idx]];
        }
    } @catch (NSException *e) { return @"0 B"; }
}

- (NSString *)versionForBundleID:(NSString *)bundleID {
    if (!bundleID) return @"1.0";

    @try {
        Class cls = NSClassFromString(@"LSApplicationProxy");
        if (cls) {
            id proxy = [cls performSelector:
                @selector(applicationProxyForIdentifier:)
                withObject:bundleID];
            if (proxy && [proxy respondsToSelector:
                    @selector(shortVersionString)]) {
                NSString *v = [proxy performSelector:
                    @selector(shortVersionString)];
                if ([v isKindOfClass:[NSString class]] && v.length > 0)
                    return v;
            }
        }

        NSString *dp = [self dataPathForBundleID:bundleID];
        if (dp) {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSArray *items = [fm contentsOfDirectoryAtPath:dp error:nil];
            for (NSString *item in items) {
                if ([item hasSuffix:@".app"]) {
                    NSString *ip = [dp stringByAppendingPathComponent:
                        [item stringByAppendingPathComponent:@"Info.plist"]];
                    NSDictionary *info =
                        [NSDictionary dictionaryWithContentsOfFile:ip];
                    NSString *v = info[@"CFBundleShortVersionString"];
                    if (v) return v;
                }
            }
        }
    } @catch (NSException *e) { }

    return @"1.0";
}

- (NSString *)documentsPathForBundleID:(NSString *)bundleID {
    NSString *dp = [self dataPathForBundleID:bundleID];
    if (!dp) return nil;
    NSString *docs = [dp stringByAppendingPathComponent:@"Documents"];
    return [self pathExists:docs] ? docs : nil;
}

- (NSUInteger)documentsCountForBundleID:(NSString *)bundleID {
    NSString *dp = [self documentsPathForBundleID:bundleID];
    if (!dp) return 0;
    @try {
        NSArray *c = [[NSFileManager defaultManager]
            contentsOfDirectoryAtPath:dp error:nil];
        return c.count;
    } @catch (NSException *e) { return 0; }
}

- (NSDate *)lastBackupDateForBundleID:(NSString *)bundleID {
    NSArray *backups = [self availableBackupsForBundleID:bundleID];
    return backups.count > 0 ? backups[0][@"date"] : nil;
}

- (unsigned long long)totalBackupsSize {
    @try {
        return [self fastDirectorySize:[self backupDirectory]];
    } @catch (NSException *e) { return 0; }
}

- (unsigned long long)totalAppsDataSize {
    @try {
        NSArray *apps = [self allInstalledApplications];
        unsigned long long total = 0;
        for (NSDictionary *app in apps) {
            @autoreleasepool {
                NSString *bid = app[@"bundleID"];
                if (bid) total += [self dataSizeForBundleID:bid];
            }
        }
        return total;
    } @catch (NSException *e) { return 0; }
}

- (BOOL)isSystemApp:(NSString *)bundleID {
    if (!bundleID) return NO;

    @try {
        NSArray *apps = [self allInstalledApplications];
        for (NSDictionary *app in apps) {
            if ([app[@"bundleID"] isEqualToString:bundleID]) {
                return [app[@"isSystem"] boolValue];
            }
        }

        NSArray *prefixes = @[@"com.apple.", @"system."];
        for (NSString *p in prefixes) {
            if ([bundleID hasPrefix:p]) return YES;
        }
    } @catch (NSException *e) { }

    return NO;
}

- (BOOL)killApp:(NSString *)bundleID {
    if (!bundleID) return NO;

    @try {
        Class cls = NSClassFromString(@"LSApplicationWorkspace");
        if (cls) {
            id ws = [cls performSelector:@selector(defaultWorkspace)];
            if (ws && [ws respondsToSelector:
                    @selector(terminateApplicationWithBundleIdentifier:)]) {
                [ws performSelector:
                    @selector(terminateApplicationWithBundleIdentifier:)
                    withObject:bundleID];
                return YES;
            }
        }

        NSString *cmd = [NSString stringWithFormat:
            @"killall -9 '%@' 2>/dev/null", bundleID];
        FILE *fp = popen([cmd UTF8String], "r");
        if (fp) pclose(fp);
        return YES;
    } @catch (NSException *e) { return NO; }
}

#pragma mark - Helpers

- (BOOL)pathExists:(NSString *)path {
    if (!path || path.length == 0) return NO;
    @try {
        return [[NSFileManager defaultManager] fileExistsAtPath:path];
    } @catch (NSException *e) { return NO; }
}

@end
