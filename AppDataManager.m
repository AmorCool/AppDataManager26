//
//  AppDataManager.m
//  AppDataManager
//
//  v1.7.0 — Crash-Resilient Core Engine
//

#import "AppDataManager.h"
#import "rootless.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <errno.h>
#import <unistd.h>
#import <pwd.h>
#import <grp.h>
#import <dlfcn.h>
#import <stdio.h>

static NSString * const kBackupDir =
    @"/var/mobile/Documents/AppDataManager/Backups";
static NSString * const kContainerMetadataFile =
    @".com.apple.mobile_container_manager.metadata.plist";

static void ADMLogFileError(NSString *operation,
                            NSString *path,
                            NSError *error) {
    NSLog(@"[ADM] %@ failed path=%@ domain=%@ code=%ld description=%@",
          operation ?: @"filesystem operation",
          path ?: @"<nil>",
          error.domain ?: @"<none>",
          (long)error.code,
          error.localizedDescription ?: @"<none>");
}

static void ADMSetError(NSError **error,
                        NSInteger code,
                        NSString *description,
                        NSString *path) {
    if (!error) {
        return;
    }

    *error = [NSError errorWithDomain:@"AppDataManager"
                                  code:code
                              userInfo:@{
        NSLocalizedDescriptionKey: description ?: @"Restore failed",
        @"path": path ?: @""
    }];
}

@interface AppDataManager ()
@property (nonatomic, strong) dispatch_queue_t fileQueue;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;
@property (nonatomic, assign) NSUInteger iosMajorVersion;
@end

@implementation AppDataManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static AppDataManager *sharedManager = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });

    return sharedManager;
}

- (instancetype)init {
    self = [super init];

    if (self) {
        _sizeCache = [[NSCache alloc] init];
        _sizeCache.countLimit = 500;

        _iconCache = [[NSCache alloc] init];
        _iconCache.countLimit = 200;

        /*
         * File operations are serialized.
         *
         * This is intentional. AppDataManager performs destructive
         * operations such as wipe/restore, therefore correctness is
         * more important than allowing concurrent filesystem mutation.
         */
        _fileQueue =
            dispatch_queue_create("com.appdatamanager.fileops",
                                   DISPATCH_QUEUE_SERIAL);

        /*
         * Cache operations can safely run concurrently.
         * Barrier writes are used whenever multiple cache operations
         * need synchronization.
         */
        _cacheQueue =
            dispatch_queue_create("com.appdatamanager.cache",
                                   DISPATCH_QUEUE_CONCURRENT);

        _iosMajorVersion = [self detectIOSMajorVersion];
    }

    return self;
}

#pragma mark - iOS Version

- (NSUInteger)detectIOSMajorVersion {
    @try {
        NSProcessInfo *info = [NSProcessInfo processInfo];

        if ([info respondsToSelector:@selector(operatingSystemVersion)]) {
            NSOperatingSystemVersion version =
                info.operatingSystemVersion;

            if (version.majorVersion > 0) {
                return (NSUInteger)version.majorVersion;
            }
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] iOS version detection exception: %@",
              exception.reason);
    }

    @try {
        NSString *version =
            [[UIDevice currentDevice] systemVersion];

        NSArray *components =
            [version componentsSeparatedByString:@"."];

        if (components.count > 0) {
            NSInteger major =
                [components.firstObject integerValue];

            if (major > 0) {
                return (NSUInteger)major;
            }
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] fallback version detection exception: %@",
              exception.reason);
    }

    return 15;
}

#pragma mark - Cache

- (void)clearCache {
    dispatch_barrier_sync(self.cacheQueue, ^{
        [self.sizeCache removeAllObjects];
        [self.iconCache removeAllObjects];
    });
}

#pragma mark - Application Discovery

- (NSArray *)allInstalledApplications {
    /*
     * Startup-safe discovery deliberately uses the filesystem only.
     * LSApplicationWorkspace is a private LaunchServices service and is not
     * a safe dependency for the first frame or the first background scan.
     * The filesystem snapshot contains the real installed bundle metadata
     * and is sufficient for the list and for subsequent data-path lookup.
     */
    NSArray *applications = [self discoverAppsFromFilesystem];
    if (![applications isKindOfClass:[NSArray class]]) {
        return @[];
    }

    return [applications sortedArrayUsingComparator:
        ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *nameA = a[@"name"];
        NSString *nameB = b[@"name"];
        if (![nameA isKindOfClass:[NSString class]]) nameA = @"";
        if (![nameB isKindOfClass:[NSString class]]) nameB = @"";
        return [nameA localizedCaseInsensitiveCompare:nameB];
    }];
}

- (NSDictionary *)extractInfoFromProxy:(id)proxy {
    if (!proxy) {
        return nil;
    }

    @try {
        NSString *bundleID = nil;
        NSString *name = nil;
        NSString *version = @"1.0";
        NSString *bundlePath = @"";
        BOOL isSystem = NO;

        if ([proxy respondsToSelector:@selector(bundleIdentifier)]) {
            bundleID =
                [proxy performSelector:@selector(bundleIdentifier)];
        }

        if (![bundleID isKindOfClass:[NSString class]] ||
            bundleID.length == 0) {
            return nil;
        }

        if ([proxy respondsToSelector:@selector(localizedName)]) {
            name =
                [proxy performSelector:@selector(localizedName)];
        }

        if (![name isKindOfClass:[NSString class]] ||
            name.length == 0) {

            if ([proxy respondsToSelector:@selector(itemName)]) {
                name =
                    [proxy performSelector:@selector(itemName)];
            }
        }

        if (![name isKindOfClass:[NSString class]] ||
            name.length == 0) {
            name = bundleID;
        }

        if ([proxy respondsToSelector:
                @selector(shortVersionString)]) {

            NSString *proxyVersion =
                [proxy performSelector:
                    @selector(shortVersionString)];

            if ([proxyVersion isKindOfClass:[NSString class]] &&
                proxyVersion.length > 0) {
                version = proxyVersion;
            }
        }

        if ([proxy respondsToSelector:@selector(bundleContainerURL)]) {
            NSURL *url =
                [proxy performSelector:@selector(bundleContainerURL)];

            if ([url isKindOfClass:[NSURL class]]) {
                bundlePath = url.path ?: @"";
            }
        }

        if (bundlePath.length == 0 &&
            [proxy respondsToSelector:@selector(bundleURL)]) {

            NSURL *url =
                [proxy performSelector:@selector(bundleURL)];

            if ([url isKindOfClass:[NSURL class]]) {
                bundlePath = url.path ?: @"";
            }
        }

        /*
         * Do not classify an application as system solely because
         * its bundle identifier starts with com.apple.
         *
         * The actual installation path is a stronger signal.
         */
        isSystem =
            [bundlePath hasPrefix:@"/System/"] ||
            [bundlePath hasPrefix:@"/var/jb/System/"] ||
            [bundlePath hasPrefix:@"/Applications/"] ||
            [bundlePath hasPrefix:@"/var/jb/Applications/"];

        return @{
            @"bundleID": bundleID,
            @"name": name ?: bundleID,
            @"version": version ?: @"1.0",
            @"bundlePath": bundlePath ?: @"",
            @"isSystem": @(isSystem)
        };
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] proxy extraction exception: %@",
              exception.reason);
        return nil;
    }
}

- (NSArray *)discoverAppsFromFilesystem {
    NSMutableArray *applications =
        [NSMutableArray array];

    @try {
        NSFileManager *fm =
            [NSFileManager defaultManager];

        NSArray *searchPaths = @[
            @"/var/containers/Bundle/Application",
            @"/private/var/containers/Bundle/Application",
            ROOT_PATH_NS(@"/var/containers/Bundle/Application"),
            ROOT_PATH_NS(@"/private/var/containers/Bundle/Application")
        ];

        NSMutableSet *knownBundleIDs =
            [NSMutableSet set];

        for (NSString *basePath in searchPaths) {
            if (![self pathExists:basePath]) {
                continue;
            }

            NSArray *uuidDirectories =
                [fm contentsOfDirectoryAtPath:basePath error:nil];

            if (![uuidDirectories isKindOfClass:[NSArray class]]) {
                continue;
            }

            for (NSString *uuidDirectory in uuidDirectories) {
                @autoreleasepool {
                    NSString *container =
                        [basePath stringByAppendingPathComponent:
                            uuidDirectory];

                    NSArray *contents =
                        [fm contentsOfDirectoryAtPath:
                            container
                                             error:nil];

                    if (![contents isKindOfClass:[NSArray class]]) {
                        continue;
                    }

                    for (NSString *item in contents) {
                        @autoreleasepool {
                            if (![item hasSuffix:@".app"]) {
                                continue;
                            }

                            NSString *appPath =
                                [container stringByAppendingPathComponent:
                                    item];

                            NSString *infoPath =
                                [appPath stringByAppendingPathComponent:
                                    @"Info.plist"];

                            NSDictionary *info =
                                [NSDictionary dictionaryWithContentsOfFile:
                                    infoPath];

                            if (![info isKindOfClass:[NSDictionary class]]) {
                                continue;
                            }

                            NSString *bundleID =
                                info[@"CFBundleIdentifier"];

                            if (![bundleID isKindOfClass:[NSString class]] ||
                                bundleID.length == 0) {
                                continue;
                            }

                            if ([knownBundleIDs containsObject:bundleID]) {
                                continue;
                            }

                            NSString *name =
                                info[@"CFBundleDisplayName"];

                            if (![name isKindOfClass:[NSString class]] ||
                                name.length == 0) {
                                name = info[@"CFBundleName"];
                            }

                            if (![name isKindOfClass:[NSString class]] ||
                                name.length == 0) {
                                name = bundleID;
                            }

                            NSString *version =
                                info[@"CFBundleShortVersionString"];

                            if (![version isKindOfClass:[NSString class]] ||
                                version.length == 0) {
                                version = @"1.0";
                            }

                            BOOL system =
                                [appPath hasPrefix:@"/System/"] ||
                                [appPath hasPrefix:@"/var/jb/System/"] ||
                                [appPath hasPrefix:@"/Applications/"] ||
                                [appPath hasPrefix:@"/var/jb/Applications/"];

                            [applications addObject:@{
                                @"bundleID": bundleID,
                                @"name": name,
                                @"version": version,
                                @"bundlePath": appPath,
                                @"isSystem": @(system)
                            }];

                            [knownBundleIDs addObject:bundleID];

                            /*
                             * One .app is expected per application
                             * container in the normal layout.
                             */
                            break;
                        }
                    }
                }
            }
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] filesystem discovery exception: %@",
              exception.reason);
    }

    return [applications copy];
}

#pragma mark - Data Paths

- (NSString *)dataPathForBundleID:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return nil;
    }

    /*
     * The normal read-only path is filesystem based and safe from any
     * LaunchServices/MCM private API side effects. It is also the source
     * used by the real size statistics, so the displayed value matches the
     * files that are actually measured.
     */
    @try {
        NSString *path = [self dataPathViaFilesystemSearch:bundleID];
        if (path.length > 0 && [self pathExists:path]) {
            return path;
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] filesystem data path exception for %@: %@",
              bundleID,
              exception.reason);
    }

    return nil;
}

- (NSString *)dataPathViaContainerManager:(NSString *)bundleID {
    if (bundleID.length == 0) {
        return nil;
    }

    @try {
        Class cls =
            NSClassFromString(@"MCMContainer");

        if (!cls) {
            return nil;
        }

        SEL selector =
            @selector(containerWithIdentifier:createIfNecessary:error:);

        if ([cls respondsToSelector:selector]) {
            NSMethodSignature *signature =
                [cls methodSignatureForSelector:selector];

            if (signature) {
                NSInvocation *invocation =
                    [NSInvocation invocationWithMethodSignature:
                        signature];

                [invocation setSelector:selector];
                [invocation setTarget:cls];

                NSString *identifier = bundleID;
                BOOL createIfNecessary = NO;
                NSError *error = nil;

                [invocation setArgument:&identifier atIndex:2];
                [invocation setArgument:&createIfNecessary atIndex:3];
                [invocation setArgument:&error atIndex:4];

                @try {
                    [invocation invoke];
                }
                @catch (NSException *exception) {
                    NSLog(@"[ADM] MCM invocation exception: %@",
                          exception.reason);
                }

                id result = nil;

                if (signature.methodReturnLength > 0) {
                    [invocation getReturnValue:&result];
                }

                if (result &&
                    [result respondsToSelector:@selector(url)]) {

                    NSURL *url =
                        [result performSelector:@selector(url)];

                    if ([url isKindOfClass:[NSURL class]] &&
                        url.path.length > 0) {
                        return url.path;
                    }
                }
            }
        }

        SEL fallbackSelector =
            @selector(containerWithIdentifier:error:);

        if ([cls respondsToSelector:fallbackSelector]) {
            NSMethodSignature *signature =
                [cls methodSignatureForSelector:fallbackSelector];

            if (signature) {
                NSInvocation *invocation =
                    [NSInvocation invocationWithMethodSignature:
                        signature];

                [invocation setSelector:fallbackSelector];
                [invocation setTarget:cls];

                NSString *identifier = bundleID;
                NSError *error = nil;

                [invocation setArgument:&identifier atIndex:2];
                [invocation setArgument:&error atIndex:3];

                @try {
                    [invocation invoke];
                }
                @catch (NSException *exception) {
                    NSLog(@"[ADM] MCM fallback exception: %@",
                          exception.reason);
                }

                id result = nil;

                if (signature.methodReturnLength > 0) {
                    [invocation getReturnValue:&result];
                }

                if (result &&
                    [result respondsToSelector:@selector(url)]) {

                    NSURL *url =
                        [result performSelector:@selector(url)];

                    if ([url isKindOfClass:[NSURL class]] &&
                        url.path.length > 0) {
                        return url.path;
                    }
                }
            }
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] container manager exception: %@",
              exception.reason);
    }

    return nil;
}

- (NSString *)dataPathViaProxy:(NSString *)bundleID {
    if (bundleID.length == 0) {
        return nil;
    }

    @try {
        Class cls =
            NSClassFromString(@"LSApplicationProxy");

        if (!cls) {
            return nil;
        }

        SEL selector =
            @selector(applicationProxyForIdentifier:);

        if (![cls respondsToSelector:selector]) {
            return nil;
        }

        NSMethodSignature *signature =
            [cls methodSignatureForSelector:selector];

        if (!signature) {
            return nil;
        }

        NSInvocation *invocation =
            [NSInvocation invocationWithMethodSignature:signature];
        [invocation setSelector:selector];
        [invocation setTarget:cls];

        NSString *identifier = bundleID;
        [invocation setArgument:&identifier atIndex:2];

        @try {
            [invocation invoke];
        }
        @catch (NSException *exception) {
            NSLog(@"[ADM] application proxy invocation exception: %@",
                  exception.reason);
            return nil;
        }

        id proxy = nil;

        if (signature.methodReturnLength > 0) {
            [invocation getReturnValue:&proxy];
        }

        if (!proxy) {
            return nil;
        }

        if ([proxy respondsToSelector:@selector(dataContainerURL)]) {
            NSURL *url =
                [proxy performSelector:@selector(dataContainerURL)];

            if ([url isKindOfClass:[NSURL class]] &&
                url.path.length > 0) {
                return url.path;
            }
        }

        if ([proxy respondsToSelector:@selector(containerURL)]) {
            NSURL *url =
                [proxy performSelector:@selector(containerURL)];

            if ([url isKindOfClass:[NSURL class]] &&
                url.path.length > 0) {
                return url.path;
            }
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] proxy data path exception: %@",
              exception.reason);
    }

    return nil;
}

- (NSString *)dataPathViaFilesystemSearch:(NSString *)bundleID {
    if (bundleID.length == 0) {
        return nil;
    }

    @try {
        NSFileManager *fm = [NSFileManager defaultManager];

        /*
         * User data containers are on the mobile data volume. Rootless does
         * not mean that /var/mobile must be prefixed with /var/jb; doing so
         * points at a different, usually nonexistent tree. Keep the real
         * paths first and retain prefixed paths only for unusual layouts.
         */
        NSArray *dataBases = @[
            @"/var/mobile/Containers/Data/Application",
            @"/private/var/mobile/Containers/Data/Application",
            ROOT_PATH_NS(@"/var/mobile/Containers/Data/Application"),
            ROOT_PATH_NS(@"/private/var/mobile/Containers/Data/Application")
        ];
        NSMutableSet *visitedBases = [NSMutableSet set];

        /* Primary match: the container metadata remains authoritative. */
        for (NSString *basePath in dataBases) {
            if (![basePath isKindOfClass:[NSString class]] ||
                basePath.length == 0 ||
                [visitedBases containsObject:basePath]) {
                continue;
            }
            [visitedBases addObject:basePath];

            BOOL baseIsDirectory = NO;
            if (![fm fileExistsAtPath:basePath
                           isDirectory:&baseIsDirectory] ||
                !baseIsDirectory) {
                continue;
            }

            NSError *listError = nil;
            NSArray *directories =
                [fm contentsOfDirectoryAtPath:basePath error:&listError];
            if (![directories isKindOfClass:[NSArray class]]) {
                ADMLogFileError(@"enumerate data base", basePath, listError);
                continue;
            }

            for (NSString *directory in directories) {
                @autoreleasepool {
                    NSString *container =
                        [basePath stringByAppendingPathComponent:directory];
                    BOOL isDirectory = NO;
                    if (![fm fileExistsAtPath:container
                                   isDirectory:&isDirectory] ||
                        !isDirectory) {
                        continue;
                    }

                    NSString *metadata =
                        [container stringByAppendingPathComponent:
                            kContainerMetadataFile];
                    NSDictionary *info =
                        [NSDictionary dictionaryWithContentsOfFile:metadata];
                    NSString *identifier = info[@"MCMMetadataIdentifier"];

                    if ([identifier isKindOfClass:[NSString class]] &&
                        [identifier isEqualToString:bundleID]) {
                        return container;
                    }
                }
            }
        }

        /*
         * Do not infer a data-container UUID from the bundle-container UUID.
         * Those UUIDs are independent on iOS. If metadata cannot identify a
         * data container, fail explicitly instead of writing to a plausible
         * but wrong directory.
         */
        NSLog(@"[ADM] data path unavailable for bundle %@; searched real data roots",
              bundleID);
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] filesystem data search exception for %@: %@",
              bundleID,
              exception.reason);
    }

    return nil;
}

- (NSArray *)allDataPathsForBundleID:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return @[];
    }

    NSMutableArray *paths =
        [NSMutableArray array];

    NSString *mainPath =
        [self dataPathForBundleID:bundleID];

    if (mainPath.length > 0 &&
        [self pathExists:mainPath]) {
        [paths addObject:mainPath];
    }

    NSArray *groupPaths =
        [self groupContainerPathsForBundleID:bundleID];

    for (NSString *path in groupPaths) {
        if (![path isKindOfClass:[NSString class]] ||
            path.length == 0) {
            continue;
        }

        if (![paths containsObject:path] &&
            [self pathExists:path]) {
            [paths addObject:path];
        }
    }

    return [paths copy];
}

- (NSArray *)groupContainerPathsForBundleID:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return @[];
    }

    /*
     * LaunchServices group-container SPI is not safe on the serialized
     * filesystem queue. Keep the SPI call on the main thread and return a
     * retained immutable snapshot to the caller. This removes the direct
     * background private-API crash path used by Backup/Restore.
     */
    if (![NSThread isMainThread]) {
        __block NSArray *mainThreadPaths = @[];
        dispatch_sync(dispatch_get_main_queue(), ^{
            mainThreadPaths = [self groupContainerPathsForBundleID:bundleID];
        });
        return mainThreadPaths ?: @[];
    }

    NSMutableArray *paths =
        [NSMutableArray array];

    @try {
        Class cls =
            NSClassFromString(@"LSApplicationProxy");

        if (cls &&
            [cls respondsToSelector:
                @selector(applicationProxyForIdentifier:)]) {

            id proxy =
                [cls performSelector:
                    @selector(applicationProxyForIdentifier:)
                    withObject:bundleID];

            if (proxy &&
                [proxy respondsToSelector:
                    @selector(groupContainerURLs)]) {

                id result =
                    [proxy performSelector:
                        @selector(groupContainerURLs)];

                if ([result isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *urls = result;

                    for (id value in urls.allValues) {
                        @autoreleasepool {
                            if (![value isKindOfClass:[NSURL class]]) {
                                continue;
                            }

                            NSString *path =
                                [(NSURL *)value path];

                            if (path.length > 0 &&
                                ![paths containsObject:path]) {
                                [paths addObject:path];
                            }
                        }
                    }
                }
            }
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] group container exception: %@",
              exception.reason);
    }

    return [paths copy];
}

#pragma mark - Size Calculation

- (unsigned long long)dataSizeForBundleID:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return 0;
    }

    NSNumber *cached =
        [self.sizeCache objectForKey:bundleID];

    if (cached) {
        return cached.unsignedLongLongValue;
    }

    unsigned long long total = 0;

    @autoreleasepool {
        @try {
            NSString *primaryPath =
                [self dataPathForBundleID:bundleID];
            NSArray *paths = primaryPath.length > 0
                ? @[primaryPath]
                : @[];

            for (NSString *path in paths) {
                @autoreleasepool {
                    if (path.length == 0) {
                        continue;
                    }

                    total +=
                        [self fastDirectorySize:path];
                }
            }
        }
        @catch (NSException *exception) {
            NSLog(@"[ADM] size exception for %@: %@",
                  bundleID,
                  exception.reason);
            total = 0;
        }
    }

    NSNumber *value = @(total);

    dispatch_barrier_async(self.cacheQueue, ^{
        [self.sizeCache setObject:value
                           forKey:bundleID];
    });

    return total;
}

- (unsigned long long)accurateDataSizeForBundleID:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return 0;
    }

    unsigned long long total = 0;

    @autoreleasepool {
        @try {
            NSString *primaryPath =
                [self dataPathForBundleID:bundleID];
            NSArray *paths = primaryPath.length > 0
                ? @[primaryPath]
                : @[];

            for (NSString *path in paths) {
                @autoreleasepool {
                    if (path.length == 0) {
                        continue;
                    }

                    total +=
                        [self fastDirectorySize:path];
                }
            }
        }
        @catch (NSException *exception) {
            NSLog(@"[ADM] accurate size exception: %@",
                  exception.reason);
        }
    }

    return total;
}

- (unsigned long long)fastDirectorySize:(NSString *)path {
    if (![path isKindOfClass:[NSString class]] ||
        path.length == 0) {
        return 0;
    }

    if (![self pathExists:path]) {
        return 0;
    }

    unsigned long long total = 0;

    @try {
        NSFileManager *fm =
            [NSFileManager defaultManager];

        NSURL *rootURL =
            [NSURL fileURLWithPath:path
                       isDirectory:YES];

        /*
         * Hidden files MUST NOT be skipped.
         *
         * App data commonly contains hidden metadata/database files.
         * Skipping them makes the displayed size incorrect.
         */
        NSDirectoryEnumerator *enumerator =
            [fm enumeratorAtURL:rootURL
     includingPropertiesForKeys:@[
         NSURLFileSizeKey,
         NSURLIsDirectoryKey,
         NSURLIsSymbolicLinkKey
     ]
                        options:0
                   errorHandler:^BOOL(NSURL *url, NSError *error) {
            return YES;
        }];

        if (!enumerator) {
            return 0;
        }

        NSMutableSet *visitedInodes =
            [NSMutableSet set];

        NSUInteger fileCount = 0;

        for (NSURL *fileURL in enumerator) {
            @autoreleasepool {
                @try {
                    if ([fileURL.lastPathComponent
                            isEqualToString:kContainerMetadataFile]) {
                        continue;
                    }

                    NSNumber *isSymlink = nil;

                    [fileURL getResourceValue:&isSymlink
                                       forKey:NSURLIsSymbolicLinkKey
                                        error:nil];

                    if (isSymlink.boolValue) {
                        continue;
                    }

                    const char *filesystemPath =
                        fileURL.path.fileSystemRepresentation;

                    if (!filesystemPath) {
                        continue;
                    }

                    struct stat st;

                    if (lstat(filesystemPath, &st) != 0) {
                        continue;
                    }

                    /*
                     * Only regular files contribute their logical file
                     * size. Directory metadata itself is not included.
                     */
                    if (!S_ISREG(st.st_mode)) {
                        continue;
                    }

                    NSString *inodeKey =
                        [NSString stringWithFormat:
                            @"%llu:%llu",
                            (unsigned long long)st.st_dev,
                            (unsigned long long)st.st_ino];

                    if ([visitedInodes containsObject:inodeKey]) {
                        continue;
                    }

                    [visitedInodes addObject:inodeKey];

                    total +=
                        (unsigned long long)st.st_size;
                }
                @catch (NSException *exception) {
                    continue;
                }
            }

            fileCount++;

            /*
             * Give the system a tiny opportunity to schedule other
             * work when processing very large containers.
             */
            if ((fileCount % 2000) == 0) {
                [NSThread sleepForTimeInterval:0.001];
            }
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] directory size exception for %@: %@",
              path,
              exception.reason);
    }

    return total;
}

#pragma mark - Wipe

- (BOOL)wipeAppData:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return NO;
    }

    if ([self isSystemApp:bundleID]) {
        return NO;
    }

    __block BOOL success = YES;

    /*
     * Serialize destructive filesystem operations.
     */
    dispatch_sync(self.fileQueue, ^{
        @autoreleasepool {
            @try {
                NSArray *paths =
                    [self allDataPathsForBundleID:bundleID];

                if (paths.count == 0) {
                    success = NO;
                    return;
                }

                NSFileManager *fm =
                    [NSFileManager defaultManager];

                for (NSString *path in paths) {
                    if (path.length == 0 ||
                        ![self pathExists:path]) {
                        continue;
                    }

                    NSArray *contents =
                        [fm contentsOfDirectoryAtPath:path
                                                 error:nil];

                    if (![contents isKindOfClass:[NSArray class]]) {
                        success = NO;
                        continue;
                    }

                    for (NSString *item in contents) {
                        @autoreleasepool {
                            if (item.length == 0 ||
                                [item isEqualToString:kContainerMetadataFile]) {
                                /* Keep MCM metadata so the container remains discoverable. */
                                continue;
                            }

                            NSString *fullPath =
                                [path stringByAppendingPathComponent:item];

                            NSError *error = nil;

                            BOOL removed =
                                [fm removeItemAtPath:fullPath
                                               error:&error];

                            if (!removed) {
                                success = NO;

                                NSLog(@"[ADM] wipe failed: %@ (%@)",
                                      fullPath,
                                      error.localizedDescription);
                            }
                        }
                    }
                }
            }
            @catch (NSException *exception) {
                NSLog(@"[ADM] wipe exception: %@",
                      exception.reason);
                success = NO;
            }
        }
    });

    if (success) {
        dispatch_barrier_sync(self.cacheQueue, ^{
            [self.sizeCache removeObjectForKey:bundleID];
        });
    }

    return success;
}

#pragma mark - Backup Directory

- (NSString *)backupDirectory {
    /*
     * This is user data, not a rootless package path. Never apply
     * ROOT_PATH_NS to /var/mobile/Documents. v1.7.x accidentally created a
     * different /var/jb/var/mobile tree while postinst created the real tree.
     */
    NSString *path = [kBackupDir stringByStandardizingPath];
    NSString *legacyPath =
        [ROOT_PATH_NS(kBackupDir) stringByStandardizingPath];
    NSFileManager *fm = [NSFileManager defaultManager];

    if (path.length == 0) {
        NSLog(@"[ADM] backup directory unavailable: canonical path is empty");
        return nil;
    }

    @try {
        BOOL pathIsDirectory = NO;
        BOOL exists = [fm fileExistsAtPath:path isDirectory:&pathIsDirectory];

        /* Migrate backups created by the incorrect v1.7.x rootless path. */
        if (!exists &&
            legacyPath.length > 0 &&
            ![legacyPath isEqualToString:path]) {
            BOOL legacyIsDirectory = NO;
            if ([fm fileExistsAtPath:legacyPath
                          isDirectory:&legacyIsDirectory] &&
                legacyIsDirectory) {
                NSError *legacyListError = nil;
                NSArray *legacyItems =
                    [fm contentsOfDirectoryAtPath:legacyPath
                                             error:&legacyListError];
                if ([legacyItems isKindOfClass:[NSArray class]]) {
                    NSError *parentError = nil;
                    NSString *parent = [path stringByDeletingLastPathComponent];
                    if (![fm createDirectoryAtPath:parent
                       withIntermediateDirectories:YES
                                        attributes:nil
                                             error:&parentError]) {
                        ADMLogFileError(@"create canonical backup parent", parent, parentError);
                    } else {
                        for (NSString *item in legacyItems) {
                            NSString *source =
                                [legacyPath stringByAppendingPathComponent:item];
                            NSString *target =
                                [path stringByAppendingPathComponent:item];
                            if ([fm fileExistsAtPath:target]) {
                                continue;
                            }
                            NSError *moveError = nil;
                            if (![fm moveItemAtPath:source
                                              toPath:target
                                               error:&moveError]) {
                                ADMLogFileError(@"migrate legacy backup", source, moveError);
                            }
                        }
                    }
                } else {
                    ADMLogFileError(@"enumerate legacy backup directory", legacyPath, legacyListError);
                }
            }
        }

        exists = [fm fileExistsAtPath:path isDirectory:&pathIsDirectory];
        if (!exists) {
            NSError *createError = nil;
            if (![fm createDirectoryAtPath:path
                withIntermediateDirectories:YES
                                 attributes:@{NSFilePosixPermissions: @(0755)}
                                      error:&createError]) {
                ADMLogFileError(@"create backup directory", path, createError);
                return nil;
            }
            pathIsDirectory = YES;
        }

        if (!pathIsDirectory) {
            NSLog(@"[ADM] backup directory invalid: not a directory path=%@", path);
            return nil;
        }

        if (![fm isReadableFileAtPath:path] ||
            ![fm isWritableFileAtPath:path]) {
            NSLog(@"[ADM] backup directory permission failure path=%@ readable=%d writable=%d",
                  path,
                  [fm isReadableFileAtPath:path],
                  [fm isWritableFileAtPath:path]);
            return nil;
        }

        NSError *verifyError = nil;
        NSArray *contents =
            [fm contentsOfDirectoryAtPath:path error:&verifyError];
        if (![contents isKindOfClass:[NSArray class]]) {
            ADMLogFileError(@"verify backup directory", path, verifyError);
            return nil;
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] backup directory exception path=%@ reason=%@",
              path,
              exception.reason);
        return nil;
    }

    NSLog(@"[ADM] backup directory ready path=%@", path);
    return path;
}

#pragma mark - Backup

- (BOOL)backupAppData:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return NO;
    }

    if ([self isSystemApp:bundleID]) {
        return NO;
    }

    __block BOOL success = YES;

    dispatch_sync(self.fileQueue, ^{
        @autoreleasepool {
            @try {
                NSString *backupDir =
                    [self backupDirectory];

                if (backupDir.length == 0) {
                    success = NO;
                    return;
                }

                /*
                 * Ask LaunchServices to terminate the app before reading its
                 * containers. This is best-effort because an app can already
                 * be terminated or unavailable while the device is changing
                 * state, but it prevents most partially-written backups.
                 */
                if (![self killApp:bundleID]) {
                    NSLog(@"[ADM] app was not terminated before backup: %@",
                          bundleID);
                }

                NSString *primaryPath =
                    [self dataPathForBundleID:bundleID];

                if (primaryPath.length == 0 ||
                    ![self pathExists:primaryPath]) {
                    NSLog(@"[ADM] backup failed: primary data container unavailable for %@",
                          bundleID);
                    success = NO;
                    return;
                }

                NSArray *dataPaths =
                    [self allDataPathsForBundleID:bundleID];

                if (dataPaths.count == 0 ||
                    ![dataPaths.firstObject isEqualToString:primaryPath]) {
                    NSLog(@"[ADM] backup failed: primary container is not first in data path snapshot");
                    success = NO;
                    return;
                }

                NSDateFormatter *formatter =
                    [[NSDateFormatter alloc] init];

                formatter.locale =
                    [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

                formatter.dateFormat =
                    @"yyyy-MM-dd_HH-mm-ss";

                NSString *timestamp =
                    [formatter stringFromDate:[NSDate date]];

                /*
                 * Bundle IDs are normally safe path components, but
                 * sanitize unexpected path separators anyway.
                 */
                NSString *safeBundleID =
                    [bundleID stringByReplacingOccurrencesOfString:@"/"
                                                           withString:@"_"];

                NSString *backupName =
                    [NSString stringWithFormat:@"%@_%@",
                        safeBundleID,
                        timestamp];

                NSString *destination =
                    [backupDir stringByAppendingPathComponent:
                        backupName];

                NSFileManager *fm =
                    [NSFileManager defaultManager];

                NSError *directoryError = nil;

                if (![fm createDirectoryAtPath:destination
                    withIntermediateDirectories:YES
                                     attributes:@{NSFilePosixPermissions: @(0755)}
                                          error:&directoryError]) {

                    ADMLogFileError(@"create backup destination", destination, directoryError);
                    success = NO;
                    return;
                }

                BOOL destinationIsDirectory = NO;
                if (![fm fileExistsAtPath:destination
                              isDirectory:&destinationIsDirectory] ||
                    !destinationIsDirectory ||
                    ![fm isReadableFileAtPath:destination] ||
                    ![fm isWritableFileAtPath:destination]) {
                    NSLog(@"[ADM] backup destination validation failed path=%@ directory=%d readable=%d writable=%d",
                          destination,
                          destinationIsDirectory,
                          [fm isReadableFileAtPath:destination],
                          [fm isWritableFileAtPath:destination]);
                    success = NO;
                    return;
                }

                NSUInteger index = 0;
                BOOL primaryCopied = NO;
                NSMutableArray *manifestContainers =
                    [NSMutableArray arrayWithCapacity:dataPaths.count];

                for (NSString *source in dataPaths) {
                    @autoreleasepool {
                        BOOL isPrimary = (index == 0);

                        if (source.length == 0 ||
                            ![self pathExists:source]) {
                            NSLog(@"[ADM] backup skipped unavailable %@ container: %@",
                                  isPrimary ? @"primary" : @"group",
                                  source);
                            if (isPrimary) {
                                success = NO;
                            }
                            continue;
                        }

                        /*
                         * Use a unique destination name instead of relying
                         * only on lastPathComponent. This prevents collisions
                         * between containers that happen to have the same
                         * UUID basename in unusual environments.
                         */
                        NSString *baseName =
                            source.lastPathComponent;

                        if (baseName.length == 0) {
                            baseName =
                                [NSString stringWithFormat:
                                    @"container_%lu",
                                    (unsigned long)index];
                        }

                        NSString *itemDestination =
                            [destination stringByAppendingPathComponent:
                                baseName];

                        if ([fm fileExistsAtPath:itemDestination]) {
                            itemDestination =
                                [destination stringByAppendingPathComponent:
                                    [NSString stringWithFormat:
                                        @"%@_%lu",
                                        baseName,
                                        (unsigned long)index]];
                        }

                        NSError *copyError = nil;

                        BOOL copied =
                            [fm copyItemAtPath:source
                                        toPath:itemDestination
                                         error:&copyError];

                        if (!copied) {
                            NSLog(@"[ADM] backup %@ container copy skipped: %@ -> %@ (%@)",
                                  isPrimary ? @"primary" : @"group",
                                  source,
                                  itemDestination,
                                  copyError.localizedDescription);
                            if (isPrimary) {
                                success = NO;
                            }
                        } else {
                            BOOL copiedDirectory = NO;
                            BOOL outputExists =
                                [fm fileExistsAtPath:itemDestination
                                          isDirectory:&copiedDirectory];
                            if (!outputExists || !copiedDirectory) {
                                NSLog(@"[ADM] backup output verification failed path=%@",
                                      itemDestination);
                                if (isPrimary) {
                                    success = NO;
                                }
                            } else {
                                if (isPrimary) {
                                    primaryCopied = YES;
                                }
                                [manifestContainers addObject:@{
                                    @"name": itemDestination.lastPathComponent,
                                    @"isPrimary": @(isPrimary)
                                }];
                            }
                        }

                        index++;
                    }
                }

                /*
                 * Persist a small manifest for future restores. It records
                 * which copied container is the primary app container, so a
                 * later reinstall can restore it even after UUID changes.
                 */
                if (success) {
                    NSString *manifestPath =
                        [destination stringByAppendingPathComponent:
                            @"manifest.plist"];
                    NSDictionary *manifest = @{
                        @"formatVersion": @1,
                        @"bundleID": bundleID,
                        @"containers": [manifestContainers copy]
                    };

                    if (![manifest writeToFile:manifestPath atomically:YES]) {
                        /*
                         * The copied containers are already a valid backup.
                         * A manifest is an optimization for future mapping,
                         * not a reason to discard a complete backup.
                         */
                        NSLog(@"[ADM] backup manifest write skipped: %@",
                              manifestPath);
                    }
                }

                if (!primaryCopied || manifestContainers.count == 0) {
                    NSLog(@"[ADM] backup final verification failed path=%@ primaryCopied=%d containers=%lu",
                          destination,
                          primaryCopied,
                          (unsigned long)manifestContainers.count);
                    success = NO;
                }

                /* Never leave a backup when final verification failed. */
                if (!success) {
                    NSError *cleanupError = nil;
                    if (![fm removeItemAtPath:destination error:&cleanupError]) {
                        ADMLogFileError(@"remove incomplete backup", destination, cleanupError);
                    }
                }
            }
            @catch (NSException *exception) {
                NSLog(@"[ADM] backup exception: %@",
                      exception.reason);
                success = NO;
            }
        }
    });

    return success;
}

/*
 * Data copied by a root-privileged jailbreak utility can inherit root:wheel
 * ownership. The target application normally runs as mobile, so existence
 * alone is not enough: normalize and verify ownership before declaring a
 * restore usable by the app.
 */
- (BOOL)normalizeDataOwnershipAtPath:(NSString *)path
                               error:(NSError **)error {
    if (error) {
        *error = nil;
    }

    struct passwd *mobileUser = getpwnam("mobile");
    struct group *mobileGroup = getgrnam("mobile");
    if (!mobileUser || !mobileGroup) {
        if (error) {
            *error = [NSError errorWithDomain:@"AppDataManager"
                                         code:620
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"تعذر تحديد مالك mobile أو مجموعته",
                @"path": path ?: @"<nil>"
            }];
        }
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL rootIsDirectory = NO;
    if (![fm fileExistsAtPath:path isDirectory:&rootIsDirectory] ||
        !rootIsDirectory) {
        if (error) {
            *error = [NSError errorWithDomain:@"AppDataManager"
                                         code:621
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"مسار Data Container غير موجود لتصحيح الملكية",
                @"path": path ?: @"<nil>"
            }];
        }
        return NO;
    }

    NSURL *rootURL = [NSURL fileURLWithPath:path isDirectory:YES];
    __block NSError *enumerationError = nil;
    NSDirectoryEnumerator *enumerator =
        [fm enumeratorAtURL:rootURL
  includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey]
                     options:0
                errorHandler:^BOOL(NSURL *url, NSError *enumError) {
        if (!enumerationError) {
            enumerationError = enumError;
        }
        return YES;
    }];

    NSMutableArray *paths = [NSMutableArray arrayWithObject:path];
    for (NSURL *url in enumerator) {
        /* MCM metadata is container state, not app-owned data. */
        if ([url.lastPathComponent isEqualToString:kContainerMetadataFile]) {
            continue;
        }
        if (url.path.length > 0) {
            [paths addObject:url.path];
        }
    }

    if (enumerationError) {
        ADMLogFileError(@"enumerate target for ownership", path, enumerationError);
        if (error) {
            *error = enumerationError;
        }
        return NO;
    }

    for (NSString *itemPath in paths) {
        @autoreleasepool {
            const char *filesystemPath = itemPath.fileSystemRepresentation;
            if (!filesystemPath) {
                continue;
            }

            struct stat st;
            if (lstat(filesystemPath, &st) != 0) {
                NSError *statError =
                    [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:errno
                                     userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"تعذر فحص ملكية %@", itemPath],
                    @"path": itemPath
                }];
                ADMLogFileError(@"lstat target ownership", itemPath, statError);
                if (error) {
                    *error = statError;
                }
                return NO;
            }

            if (S_ISLNK(st.st_mode)) {
                continue;
            }

            if (lchown(filesystemPath,
                       mobileUser->pw_uid,
                       mobileGroup->gr_gid) != 0) {
                NSError *ownerError =
                    [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:errno
                                     userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"تعذر تغيير مالك %@ إلى mobile", itemPath],
                    @"path": itemPath
                }];
                ADMLogFileError(@"chown restored item", itemPath, ownerError);
                if (error) {
                    *error = ownerError;
                }
                return NO;
            }

            mode_t mode = st.st_mode & 07777;
            if (S_ISDIR(st.st_mode)) {
                mode |= S_IRUSR | S_IWUSR | S_IXUSR;
            } else if (S_ISREG(st.st_mode)) {
                mode |= S_IRUSR | S_IWUSR;
            }

            if (chmod(filesystemPath, mode) != 0) {
                NSError *modeError =
                    [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:errno
                                     userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"تعذر ضبط صلاحيات %@", itemPath],
                    @"path": itemPath
                }];
                ADMLogFileError(@"chmod restored item", itemPath, modeError);
                if (error) {
                    *error = modeError;
                }
                return NO;
            }
        }
    }

    for (NSString *itemPath in paths) {
        @autoreleasepool {
            struct stat st;
            if (lstat(itemPath.fileSystemRepresentation, &st) != 0) {
                continue;
            }
            if (!S_ISREG(st.st_mode) && !S_ISDIR(st.st_mode)) {
                continue;
            }
            if (st.st_uid != mobileUser->pw_uid ||
                st.st_gid != mobileGroup->gr_gid) {
                NSLog(@"[ADM] ownership verification failed path=%@ uid=%u gid=%u expectedUid=%u expectedGid=%u",
                      itemPath,
                      st.st_uid,
                      st.st_gid,
                      mobileUser->pw_uid,
                      mobileGroup->gr_gid);
                if (error) {
                    *error = [NSError errorWithDomain:@"AppDataManager"
                                                 code:622
                                             userInfo:@{
                        NSLocalizedDescriptionKey: @"ملكية الملفات المستعادة ليست mobile",
                        @"path": itemPath
                    }];
                }
                return NO;
            }
            if (![fm isReadableFileAtPath:itemPath]) {
                NSLog(@"[ADM] restored item is not readable path=%@", itemPath);
                if (error) {
                    *error = [NSError errorWithDomain:@"AppDataManager"
                                                 code:623
                                             userInfo:@{
                        NSLocalizedDescriptionKey: @"الملف المستعاد غير قابل للقراءة من النظام",
                        @"path": itemPath
                    }];
                }
                return NO;
            }
        }
    }

    NSLog(@"[ADM] restored ownership normalized path=%@ uid=%u gid=%u",
          path,
          mobileUser->pw_uid,
          mobileGroup->gr_gid);
    return YES;
}

/*
 * Return a deterministic snapshot of a container. This is used as evidence
 * for restore verification; a successful copy call alone is not evidence.
 */
- (NSDictionary *)filesystemSnapshotAtPath:(NSString *)path
                                     error:(NSError **)error {
    if (error) {
        *error = nil;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDirectory] ||
        !isDirectory) {
        if (error) {
            *error = [NSError errorWithDomain:@"AppDataManager"
                                         code:610
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"container path is missing or not a directory",
                @"path": path ?: @"<nil>"
            }];
        }
        return nil;
    }

    NSError *listError = nil;
    NSArray *topLevelItems =
        [fm contentsOfDirectoryAtPath:path error:&listError];
    if (![topLevelItems isKindOfClass:[NSArray class]]) {
        ADMLogFileError(@"snapshot enumerate top level", path, listError);
        if (error) {
            *error = listError;
        }
        return nil;
    }

    NSMutableArray *sortedTopLevel = [topLevelItems mutableCopy];
    [sortedTopLevel sortUsingSelector:@selector(compare:)];

    __block NSError *enumerationError = nil;
    NSURL *rootURL = [NSURL fileURLWithPath:path isDirectory:YES];
    NSDirectoryEnumerator *enumerator =
        [fm enumeratorAtURL:rootURL
  includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey]
                     options:0
                errorHandler:^BOOL(NSURL *url, NSError *enumError) {
        if (!enumerationError) {
            enumerationError = enumError;
        }
        return YES;
    }];

    unsigned long long size = 0;
    NSUInteger fileCount = 0;
    NSMutableArray *relativeFiles = [NSMutableArray array];
    for (NSURL *fileURL in enumerator) {
        @autoreleasepool {
            NSNumber *isSymlink = nil;
            [fileURL getResourceValue:&isSymlink
                               forKey:NSURLIsSymbolicLinkKey
                                error:nil];
            if (isSymlink.boolValue ||
                [fileURL.lastPathComponent
                    isEqualToString:kContainerMetadataFile]) {
                /* MCM metadata belongs to the current container and is intentionally preserved. */
                continue;
            }

            const char *filesystemPath =
                fileURL.path.fileSystemRepresentation;
            if (!filesystemPath) {
                continue;
            }

            struct stat st;
            if (lstat(filesystemPath, &st) != 0) {
                NSError *statError =
                    [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:errno
                                     userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"lstat failed for %@", fileURL.path ?: @"<nil>"],
                    @"path": fileURL.path ?: @"<nil>"
                }];
                ADMLogFileError(@"snapshot lstat", fileURL.path, statError);
                if (error) {
                    *error = statError;
                }
                return nil;
            }

            if (!S_ISREG(st.st_mode)) {
                continue;
            }

            fileCount++;
            size += (unsigned long long)st.st_size;
            NSString *relativePath = fileURL.path;
            if ([relativePath hasPrefix:[path stringByAppendingString:@"/"]]) {
                relativePath = [relativePath substringFromIndex:path.length + 1];
            }
            [relativeFiles addObject:@{
                @"path": relativePath ?: @"",
                @"bytes": @((unsigned long long)st.st_size)
            }];
        }
    }

    if (enumerationError) {
        ADMLogFileError(@"snapshot recursive enumeration", path, enumerationError);
        if (error) {
            *error = enumerationError;
        }
        return nil;
    }

    NSDictionary *attributes =
        [fm attributesOfItemAtPath:path error:nil];
    NSLog(@"[ADM] snapshot path=%@ files=%lu bytes=%llu owner=%@ group=%@ mode=%@",
          path,
          (unsigned long)fileCount,
          size,
          attributes[NSFileOwnerAccountID] ?: @"<unknown>",
          attributes[NSFileGroupOwnerAccountID] ?: @"<unknown>",
          attributes[NSFilePosixPermissions] ?: @"<unknown>");

    [relativeFiles sortUsingComparator:
        ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"path"] compare:b[@"path"]];
    }];

    return @{
        @"fileCount": @(fileCount),
        @"bytes": @(size),
        @"topLevelItems": [sortedTopLevel copy],
        @"files": [relativeFiles copy]
    };
}

#pragma mark - Restore

- (BOOL)restoreAppData:(NSString *)bundleID
            fromBackup:(NSString *)backupPath {
    return [self restoreAppData:bundleID
                      fromBackup:backupPath
                           error:nil];
}

- (BOOL)restoreAppData:(NSString *)bundleID
            fromBackup:(NSString *)backupPath
                 error:(NSError **)error {
    if (error) {
        *error = nil;
    }

    __block NSError *restoreError = nil;

    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return NO;
    }

    if (![backupPath isKindOfClass:[NSString class]] ||
        backupPath.length == 0) {
        return NO;
    }

    if ([self isSystemApp:bundleID]) {
        return NO;
    }

    __block BOOL success = NO;

    dispatch_sync(self.fileQueue, ^{
        @autoreleasepool {
            @try {
                NSString *backupRoot = [self backupDirectory];
                if (backupRoot.length == 0) {
                    NSLog(@"[ADM] restore failed: backup directory unavailable");
                    ADMSetError(&restoreError, 601, @"مجلد النسخ الاحتياطية غير متاح", backupRoot);
                    return;
                }

                NSString *standardBackup =
                    [backupRoot stringByStandardizingPath];
                NSString *standardSelected =
                    [backupPath stringByStandardizingPath];
                NSString *prefix =
                    [standardBackup stringByAppendingString:@"/"];

                if (![standardSelected hasPrefix:prefix]) {
                    NSLog(@"[ADM] restore rejected: source outside backup directory");
                    ADMSetError(&restoreError, 602, @"مسار النسخة خارج مجلد النسخ الاحتياطية", standardSelected);
                    return;
                }

                NSFileManager *fm = [NSFileManager defaultManager];
                BOOL selectedIsDirectory = NO;
                NSError *readError = nil;

                if (![fm fileExistsAtPath:standardSelected
                               isDirectory:&selectedIsDirectory] ||
                    !selectedIsDirectory) {
                    NSLog(@"[ADM] restore failed: selected backup is not a directory");
                    ADMSetError(&restoreError, 603, @"النسخة المحددة ليست مجلداً صالحاً", standardSelected);
                    return;
                }

                NSString *safeBundleID =
                    [bundleID stringByReplacingOccurrencesOfString:@"/"
                                                           withString:@"_"];
                NSString *expectedPrefix =
                    [safeBundleID stringByAppendingString:@"_"];

                if (![standardSelected.lastPathComponent
                        hasPrefix:expectedPrefix]) {
                    NSLog(@"[ADM] restore rejected: backup belongs to another app (%@)",
                          standardSelected.lastPathComponent);
                    ADMSetError(&restoreError, 605, @"النسخة الاحتياطية تخص تطبيقاً آخر", standardSelected);
                    return;
                }

                /*
                 * New backups carry a manifest. Existing backups without it
                 * continue through metadata and UUID-based compatibility paths.
                 */
                NSString *manifestPath =
                    [standardSelected stringByAppendingPathComponent:
                        @"manifest.plist"];
                NSDictionary *manifest =
                    [NSDictionary dictionaryWithContentsOfFile:manifestPath];
                NSArray *manifestContainers = manifest[@"containers"];

                if ([manifest isKindOfClass:[NSDictionary class]]) {
                    NSString *manifestBundleID = manifest[@"bundleID"];
                    if ([manifestBundleID isKindOfClass:[NSString class]] &&
                        ![manifestBundleID isEqualToString:bundleID]) {
                        NSLog(@"[ADM] restore rejected: manifest bundle ID mismatch");
                        return;
                    }
                }

                NSArray *backupItems =
                    [fm contentsOfDirectoryAtPath:standardSelected
                                             error:&readError];
                if (![backupItems isKindOfClass:[NSArray class]]) {
                    NSLog(@"[ADM] restore failed: backup cannot be read (%@)",
                          readError.localizedDescription);
                    ADMSetError(&restoreError, 604, readError.localizedDescription ?: @"تعذر قراءة محتوى النسخة", standardSelected);
                    return;
                }

                NSMutableArray *sourcePaths = [NSMutableArray array];
                for (NSString *item in backupItems) {
                    if (![item isKindOfClass:[NSString class]] ||
                        item.length == 0 ||
                        [item isEqualToString:@"manifest.plist"]) {
                        continue;
                    }

                    NSString *source =
                        [standardSelected stringByAppendingPathComponent:item];
                    BOOL sourceIsDirectory = NO;
                    if (![fm fileExistsAtPath:source
                                   isDirectory:&sourceIsDirectory]) {
                        NSLog(@"[ADM] restore source disappeared: %@", source);
                        return;
                    }

                    /* Ignore unrelated files but never accept a file as a container. */
                    if (!sourceIsDirectory) {
                        NSLog(@"[ADM] restore ignored non-container entry: %@", source);
                        continue;
                    }

                    [sourcePaths addObject:source];
                }

                if (sourcePaths.count == 0) {
                    NSLog(@"[ADM] restore failed: backup has no containers");
                    ADMSetError(&restoreError, 605, @"النسخة لا تحتوي على حاويات بيانات", standardSelected);
                    return;
                }

                NSArray *discoveredDestinations =
                    [self allDataPathsForBundleID:bundleID];
                NSMutableArray *destinationPaths = [NSMutableArray array];
                for (NSString *destination in discoveredDestinations) {
                    BOOL isDirectory = NO;
                    if ([destination isKindOfClass:[NSString class]] &&
                        destination.length > 0 &&
                        [fm fileExistsAtPath:destination
                                  isDirectory:&isDirectory] &&
                        isDirectory &&
                        ![destinationPaths containsObject:destination]) {
                        [destinationPaths addObject:destination];
                    }
                }

                NSString *mainDestination = [self dataPathForBundleID:bundleID];
                if (![mainDestination isKindOfClass:[NSString class]] ||
                    mainDestination.length == 0 ||
                    ![destinationPaths containsObject:mainDestination]) {
                    mainDestination = destinationPaths.firstObject;
                }

                if (mainDestination.length == 0) {
                    NSLog(@"[ADM] restore failed: main destination container not found for %@",
                          bundleID);
                    ADMSetError(&restoreError, 606, @"تعذر تحديد Data Container قبل الاستعادة", bundleID);
                    return;
                }

                /* Find the primary backup container from the new manifest first. */
                NSString *primarySourceName = nil;
                if ([manifestContainers isKindOfClass:[NSArray class]]) {
                    for (NSDictionary *entry in manifestContainers) {
                        if ([entry isKindOfClass:[NSDictionary class]] &&
                            [entry[@"isPrimary"] boolValue] &&
                            [entry[@"name"] isKindOfClass:[NSString class]]) {
                            primarySourceName = entry[@"name"];
                            break;
                        }
                    }
                }

                NSString *primarySource = nil;
                if (primarySourceName.length > 0) {
                    NSString *candidate =
                        [standardSelected stringByAppendingPathComponent:
                            primarySourceName];
                    if ([sourcePaths containsObject:candidate]) {
                        primarySource = candidate;
                    }
                }

                /* Existing backups: identify the main container by its metadata. */
                if (!primarySource) {
                    for (NSString *source in sourcePaths) {
                        NSString *metadataPath =
                            [source stringByAppendingPathComponent:
                                kContainerMetadataFile];
                        NSDictionary *metadata =
                            [NSDictionary dictionaryWithContentsOfFile:metadataPath];
                        NSString *identifier = metadata[@"MCMMetadataIdentifier"];
                        if ([identifier isKindOfClass:[NSString class]] &&
                            [identifier isEqualToString:bundleID]) {
                            primarySource = source;
                            break;
                        }
                    }
                }

                /* The common single-container backup needs no metadata fallback. */
                if (!primarySource && sourcePaths.count == 1) {
                    primarySource = sourcePaths.firstObject;
                }

                if (!primarySource) {
                    NSLog(@"[ADM] restore failed: primary backup container not identified");
                    ADMSetError(&restoreError, 606, @"تعذر تحديد الحاوية الرئيسية داخل النسخة الاحتياطية", standardSelected);
                    return;
                }

                NSError *sourceSnapshotError = nil;
                NSDictionary *primarySourceSnapshot =
                    [self filesystemSnapshotAtPath:primarySource
                                             error:&sourceSnapshotError];
                if (![primarySourceSnapshot isKindOfClass:[NSDictionary class]]) {
                    ADMLogFileError(@"snapshot backup primary container",
                                    primarySource,
                                    sourceSnapshotError);
                    ADMSetError(&restoreError, 607, sourceSnapshotError.localizedDescription ?: @"تعذر قراءة محتوى النسخة", primarySource);
                    return;
                }

                /* Re-discover destinations after the delete/wipe step. */
                [self killApp:bundleID];
                [destinationPaths removeAllObjects];
                NSArray *refreshedDestinations =
                    [self allDataPathsForBundleID:bundleID];
                for (NSString *destination in refreshedDestinations) {
                    BOOL refreshedIsDirectory = NO;
                    if ([destination isKindOfClass:[NSString class]] &&
                        destination.length > 0 &&
                        [fm fileExistsAtPath:destination
                                  isDirectory:&refreshedIsDirectory] &&
                        refreshedIsDirectory &&
                        ![destinationPaths containsObject:destination]) {
                        [destinationPaths addObject:destination];
                    }
                }

                NSString *refreshedMainDestination =
                    [self dataPathForBundleID:bundleID];
                if (refreshedMainDestination.length > 0) {
                    mainDestination = refreshedMainDestination;
                }
                if (mainDestination.length == 0 ||
                    ![fm fileExistsAtPath:mainDestination
                              isDirectory:&selectedIsDirectory] ||
                    !selectedIsDirectory) {
                    NSLog(@"[ADM] restore failed: destination unavailable after re-discovery bundle=%@",
                          bundleID);
                    ADMSetError(&restoreError, 608, @"تعذر إعادة اكتشاف Data Container بعد الحذف", bundleID);
                    return;
                }
                if (![destinationPaths containsObject:mainDestination]) {
                    [destinationPaths insertObject:mainDestination atIndex:0];
                }

                NSMutableArray *restorePairs = [NSMutableArray array];
                NSMutableArray *remainingSources = [sourcePaths mutableCopy];
                NSMutableArray *remainingDestinations = [destinationPaths mutableCopy];

                [remainingSources removeObject:primarySource];
                [remainingDestinations removeObject:mainDestination];
                [restorePairs addObject:@{
                    @"source": primarySource,
                    @"destination": mainDestination,
                    @"isPrimary": @(YES)
                }];

                /* Preserve exact UUID matches for group containers. */
                NSMutableArray *unmatchedSources = [NSMutableArray array];
                for (NSString *source in remainingSources) {
                    NSString *matchingDestination = nil;
                    for (NSString *destination in remainingDestinations) {
                        if ([[destination lastPathComponent]
                                isEqualToString:source.lastPathComponent]) {
                            matchingDestination = destination;
                            break;
                        }
                    }

                    if (matchingDestination) {
                        [restorePairs addObject:@{
                            @"source": source,
                            @"destination": matchingDestination,
                            @"isPrimary": @(NO)
                        }];
                        [remainingDestinations removeObject:matchingDestination];
                    } else {
                        [unmatchedSources addObject:source];
                    }
                }

                /*
                 * Regenerated group UUIDs are paired deterministically when
                 * both sides are available. Missing group destinations are
                 * non-fatal: the primary app container remains restorable.
                 */
                [unmatchedSources sortUsingComparator:
                    ^NSComparisonResult(NSString *a, NSString *b) {
                    return [a.lastPathComponent
                        compare:b.lastPathComponent
                        options:NSCaseInsensitiveSearch];
                }];
                [remainingDestinations sortUsingComparator:
                    ^NSComparisonResult(NSString *a, NSString *b) {
                    return [a.lastPathComponent
                        compare:b.lastPathComponent
                        options:NSCaseInsensitiveSearch];
                }];

                NSUInteger pairCount =
                    MIN(unmatchedSources.count, remainingDestinations.count);
                for (NSUInteger index = 0; index < pairCount; index++) {
                    [restorePairs addObject:@{
                        @"source": unmatchedSources[index],
                        @"destination": remainingDestinations[index],
                        @"isPrimary": @(NO)
                    }];
                }

                if (unmatchedSources.count > pairCount) {
                    NSLog(@"[ADM] restore skipped %lu unavailable group containers",
                          (unsigned long)(unmatchedSources.count - pairCount));
                }

                /*
                 * The primary container determines the operation result.
                 * App Group containers can be unavailable or protected on
                 * some devices; they must not turn a valid primary restore
                 * into a generic failure.
                 */
                for (NSDictionary *pair in restorePairs) {
                    NSString *destination = pair[@"destination"];
                    BOOL isPrimary = [pair[@"isPrimary"] boolValue];
                    NSError *contentsError = nil;
                    NSArray *contents =
                        [fm contentsOfDirectoryAtPath:destination
                                                 error:&contentsError];
                    if (![contents isKindOfClass:[NSArray class]]) {
                        NSLog(@"[ADM] restore wipe skipped for %@ (%@)",
                              destination,
                              contentsError.localizedDescription);
                        if (isPrimary) {
                            ADMSetError(&restoreError, 617, contentsError.localizedDescription ?: @"تعذر قراءة الحاوية الحالية قبل الاستعادة", destination);
                            return;
                        }
                        continue;
                    }

                    BOOL groupWipeFailed = NO;
                    for (NSString *item in contents) {
                        if ([item isEqualToString:kContainerMetadataFile]) {
                            continue;
                        }
                        NSString *fullPath =
                            [destination stringByAppendingPathComponent:item];
                        NSError *removeError = nil;
                        if ([fm fileExistsAtPath:fullPath] &&
                            ![fm removeItemAtPath:fullPath
                                           error:&removeError]) {
                            groupWipeFailed = YES;
                            NSLog(@"[ADM] restore wipe failed: %@ (%@)",
                                  fullPath,
                                  removeError.localizedDescription);
                            if (isPrimary) {
                                ADMSetError(&restoreError, 617, removeError.localizedDescription ?: @"تعذر حذف بيانات الحاوية قبل الاستعادة", fullPath);
                                return;
                            }
                            break;
                        }
                    }
                    if (groupWipeFailed && !isPrimary) {
                        NSLog(@"[ADM] restore continuing without group container: %@",
                              destination);
                    }
                }

                /* Restore contents, keeping the destination container itself. */
                for (NSDictionary *pair in restorePairs) {
                    NSString *source = pair[@"source"];
                    NSString *destination = pair[@"destination"];
                    BOOL isPrimary = [pair[@"isPrimary"] boolValue];
                    NSError *contentsError = nil;
                    NSArray *children =
                        [fm contentsOfDirectoryAtPath:source
                                                 error:&contentsError];
                    if (![children isKindOfClass:[NSArray class]]) {
                        NSLog(@"[ADM] restore read skipped for %@ (%@)",
                              source,
                              contentsError.localizedDescription);
                        if (isPrimary) {
                            ADMSetError(&restoreError, 618, contentsError.localizedDescription ?: @"تعذر قراءة حاوية النسخة الرئيسية", source);
                            return;
                        }
                        continue;
                    }

                    BOOL groupRestoreFailed = NO;
                    for (NSString *child in children) {
                        NSString *childSource =
                            [source stringByAppendingPathComponent:child];
                        if ([child isEqualToString:kContainerMetadataFile] &&
                            [fm fileExistsAtPath:
                                [destination stringByAppendingPathComponent:child]]) {
                            continue;
                        }
                        NSString *childDestination =
                            [destination stringByAppendingPathComponent:child];
                        NSError *copyError = nil;

                        if ([fm fileExistsAtPath:childDestination] &&
                            ![fm removeItemAtPath:childDestination
                                           error:&copyError]) {
                            groupRestoreFailed = YES;
                            NSLog(@"[ADM] restore conflict removal skipped: %@ (%@)",
                                  childDestination,
                                  copyError.localizedDescription);
                            if (isPrimary) {
                                ADMSetError(&restoreError, 619, copyError.localizedDescription ?: @"تعذر إزالة ملف متعارض قبل الاستعادة", childDestination);
                                return;
                            }
                            break;
                        }

                        copyError = nil;
                        if (![fm copyItemAtPath:childSource
                                         toPath:childDestination
                                          error:&copyError]) {
                            groupRestoreFailed = YES;
                            NSLog(@"[ADM] restore copy failed: %@ -> %@ (%@)",
                                  childSource,
                                  childDestination,
                                  copyError.localizedDescription);
                            if (isPrimary) {
                                ADMSetError(&restoreError, 620, copyError.localizedDescription ?: @"تعذر نسخ ملف من النسخة الاحتياطية", childDestination);
                                return;
                            }
                            break;
                        }
                    }
                    if (groupRestoreFailed && !isPrimary) {
                        NSLog(@"[ADM] restore continuing after unavailable group container: %@",
                              source);
                    }
                }

                NSError *ownershipError = nil;
                if (![self normalizeDataOwnershipAtPath:mainDestination
                                                  error:&ownershipError]) {
                    ADMLogFileError(@"normalize restored ownership",
                                    mainDestination,
                                    ownershipError);
                    ADMSetError(&restoreError, 624,
                                ownershipError.localizedDescription ?: @"تعذر جعل البيانات قابلة للقراءة من التطبيق",
                                mainDestination);
                    return;
                }

                NSError *destinationSnapshotError = nil;
                NSDictionary *destinationSnapshot =
                    [self filesystemSnapshotAtPath:mainDestination
                                             error:&destinationSnapshotError];
                if (![destinationSnapshot isKindOfClass:[NSDictionary class]]) {
                    ADMLogFileError(@"snapshot restored primary container",
                                    mainDestination,
                                    destinationSnapshotError);
                    ADMSetError(&restoreError, 621, destinationSnapshotError.localizedDescription ?: @"تعذر فحص الحاوية بعد الاستعادة", mainDestination);
                    return;
                }

                NSUInteger backupFileCount =
                    [primarySourceSnapshot[@"fileCount"] unsignedIntegerValue];
                unsigned long long backupBytes =
                    [primarySourceSnapshot[@"bytes"] unsignedLongLongValue];
                NSUInteger restoredFileCount =
                    [destinationSnapshot[@"fileCount"] unsignedIntegerValue];
                unsigned long long restoredBytes =
                    [destinationSnapshot[@"bytes"] unsignedLongLongValue];

                NSLog(@"[ADM] restore verification backupFiles=%lu backupBytes=%llu restoredFiles=%lu restoredBytes=%llu target=%@",
                      (unsigned long)backupFileCount,
                      backupBytes,
                      (unsigned long)restoredFileCount,
                      restoredBytes,
                      mainDestination);

                if (backupFileCount > 0 &&
                    (restoredFileCount == 0 ||
                     restoredFileCount < backupFileCount ||
                     restoredBytes < backupBytes)) {
                    NSLog(@"[ADM] restore verification failed: restored content is smaller than backup");
                    ADMSetError(&restoreError, 609, [NSString stringWithFormat:
                        @"فشل التحقق: النسخة تحتوي %lu ملفاً و%llu بايت، بينما تمت استعادة %lu ملفاً و%llu بايت",
                        (unsigned long)backupFileCount,
                        backupBytes,
                        (unsigned long)restoredFileCount,
                        restoredBytes],
                        mainDestination);
                    return;
                }

                /*
                 * Compare every source relative file and byte count with the
                 * target. A non-empty target with unrelated files is not a
                 * successful restore of this backup.
                 */
                NSMutableDictionary *targetMap = [NSMutableDictionary dictionary];
                for (NSDictionary *entry in destinationSnapshot[@"files"]) {
                    NSString *relativePath = entry[@"path"];
                    if ([relativePath isKindOfClass:[NSString class]]) {
                        targetMap[relativePath] = entry[@"bytes"] ?: @0;
                    }
                }
                for (NSDictionary *entry in primarySourceSnapshot[@"files"]) {
                    NSString *relativePath = entry[@"path"];
                    NSNumber *expectedBytes = entry[@"bytes"];
                    NSNumber *actualBytes = targetMap[relativePath];
                    if (![actualBytes isKindOfClass:[NSNumber class]] ||
                        actualBytes.unsignedLongLongValue != expectedBytes.unsignedLongLongValue) {
                        NSString *targetFile =
                            [mainDestination stringByAppendingPathComponent:relativePath ?: @""];
                        NSLog(@"[ADM] restore verification file mismatch relative=%@ expectedBytes=%@ actualBytes=%@ target=%@",
                              relativePath,
                              expectedBytes,
                              actualBytes,
                              targetFile);
                        ADMSetError(&restoreError, 625,
                                    @"فشل التحقق: ملف مستعاد مفقود أو حجمه مختلف عن النسخة",
                                    targetFile);
                        return;
                    }
                }

                NSArray *expectedTopLevel = primarySourceSnapshot[@"topLevelItems"];
                for (NSString *item in expectedTopLevel) {
                    NSString *targetItem =
                        [mainDestination stringByAppendingPathComponent:item];
                    BOOL targetIsDirectory = NO;
                    if (![fm fileExistsAtPath:targetItem
                                  isDirectory:&targetIsDirectory]) {
                        NSLog(@"[ADM] restore verification missing top-level item: %@",
                              targetItem);
                        ADMSetError(&restoreError, 610, @"فشل التحقق: ملف أو مجلد متوقع غير موجود بعد الاستعادة", targetItem);
                        return;
                    }

                    if ([item isEqualToString:@"Documents"] ||
                        [item isEqualToString:@"Library"] ||
                        [item isEqualToString:@"tmp"]) {
                        if (!targetIsDirectory ||
                            ![fm isReadableFileAtPath:targetItem]) {
                            NSLog(@"[ADM] restore verification invalid standard directory: %@",
                                  targetItem);
                            ADMSetError(&restoreError, 611, @"فشل التحقق: Documents أو Library غير صالح بعد الاستعادة", targetItem);
                            return;
                        }
                    }
                }

                NSDictionary *destinationAttributes =
                    [fm attributesOfItemAtPath:mainDestination error:nil];
                NSLog(@"[ADM] restore target attributes owner=%@ group=%@ mode=%@ readable=%d writable=%d",
                      destinationAttributes[NSFileOwnerAccountID] ?: @"<unknown>",
                      destinationAttributes[NSFileGroupOwnerAccountID] ?: @"<unknown>",
                      destinationAttributes[NSFilePosixPermissions] ?: @"<unknown>",
                      [fm isReadableFileAtPath:mainDestination],
                      [fm isWritableFileAtPath:mainDestination]);

                if (![fm isReadableFileAtPath:mainDestination]) {
                    NSLog(@"[ADM] restore verification failed: target is not readable");
                    ADMSetError(&restoreError, 612, @"فشل التحقق: Data Container غير قابل للقراءة بعد الاستعادة", mainDestination);
                    return;
                }

                NSString *verifiedDataPath =
                    [self dataPathForBundleID:bundleID];
                if (verifiedDataPath.length == 0 ||
                    ![verifiedDataPath isEqualToString:mainDestination]) {
                    NSLog(@"[ADM] restore verification failed: data path mismatch expected=%@ actual=%@",
                          mainDestination,
                          verifiedDataPath);
                    ADMSetError(&restoreError, 613, @"فشل التحقق: تم اكتشاف Data Container مختلف بعد الاستعادة", verifiedDataPath ?: mainDestination);
                    return;
                }

                if (![self killApp:bundleID]) {
                    NSLog(@"[ADM] restore completed but target app termination was not confirmed: %@",
                          bundleID);
                }

                success = YES;
            }
            @catch (NSException *exception) {
                NSLog(@"[ADM] restore exception: %@", exception.reason);
                ADMSetError(&restoreError, 614, exception.reason ?: @"حدث استثناء أثناء الاستعادة", backupPath);
                success = NO;
            }
        }
    });

    if (error) {
        *error = restoreError;
    }

    dispatch_barrier_sync(self.cacheQueue, ^{
        [self.sizeCache removeObjectForKey:bundleID];
    });

    return success;
}

#pragma mark - Backup Management

- (NSArray *)availableBackupsForBundleID:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return @[];
    }

    @try {
        NSString *directory =
            [self backupDirectory];

        if (directory.length == 0) {
            return @[];
        }

        NSFileManager *fm =
            [NSFileManager defaultManager];

        NSArray *contents =
            [fm contentsOfDirectoryAtPath:directory
                                     error:nil];

        if (![contents isKindOfClass:[NSArray class]]) {
            return @[];
        }

        NSMutableArray *backups =
            [NSMutableArray array];

        NSString *safeBundleID =
            [bundleID stringByReplacingOccurrencesOfString:@"/"
                                               withString:@"_"];
        NSString *prefix =
            [safeBundleID stringByAppendingString:@"_"];

        for (NSString *item in contents) {
            @autoreleasepool {
                if (![item hasPrefix:prefix]) {
                    continue;
                }

                NSString *fullPath =
                    [directory stringByAppendingPathComponent:item];

                BOOL isDirectory = NO;

                if (![fm fileExistsAtPath:fullPath
                               isDirectory:&isDirectory] ||
                    !isDirectory) {
                    continue;
                }

                NSDictionary *attributes =
                    [fm attributesOfItemAtPath:fullPath
                                         error:nil];

                NSDate *date =
                    attributes[NSFileModificationDate];

                if (![date isKindOfClass:[NSDate class]]) {
                    date = [NSDate date];
                }

                [backups addObject:@{
                    @"path": fullPath,
                    @"date": date,
                    @"name": item
                }];
            }
        }

        return [backups sortedArrayUsingComparator:
            ^NSComparisonResult(NSDictionary *a,
                                NSDictionary *b) {

            NSDate *dateA = a[@"date"];
            NSDate *dateB = b[@"date"];

            return [dateB compare:dateA];
        }];
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] available backups exception: %@",
              exception.reason);
        return @[];
    }
}

- (BOOL)deleteBackup:(NSString *)backupPath {
    if (![backupPath isKindOfClass:[NSString class]] ||
        backupPath.length == 0) {
        return NO;
    }

    __block BOOL success = NO;

    dispatch_sync(self.fileQueue, ^{
        @autoreleasepool {
            @try {
                NSString *directory =
                    [self backupDirectory];

                if (directory.length == 0) {
                    return;
                }

                NSString *root =
                    [directory stringByStandardizingPath];

                NSString *target =
                    [backupPath stringByStandardizingPath];

                NSString *prefix =
                    [root stringByAppendingString:@"/"];

                if (![target hasPrefix:prefix]) {
                    return;
                }

                NSFileManager *fm =
                    [NSFileManager defaultManager];

                if (![fm fileExistsAtPath:target]) {
                    return;
                }

                NSError *error = nil;

                success =
                    [fm removeItemAtPath:target
                                   error:&error];

                if (!success) {
                    NSLog(@"[ADM] delete backup failed: %@ (%@)",
                          target,
                          error.localizedDescription);
                }
            }
            @catch (NSException *exception) {
                NSLog(@"[ADM] delete backup exception: %@",
                      exception.reason);
            }
        }
    });

    return success;
}

- (BOOL)deleteAllBackups {
    __block BOOL success = YES;

    dispatch_sync(self.fileQueue, ^{
        @autoreleasepool {
            @try {
                NSString *directory =
                    [self backupDirectory];

                if (directory.length == 0) {
                    success = NO;
                    return;
                }

                NSFileManager *fm =
                    [NSFileManager defaultManager];

                NSArray *contents =
                    [fm contentsOfDirectoryAtPath:directory
                                             error:nil];

                if (![contents isKindOfClass:[NSArray class]]) {
                    success = NO;
                    return;
                }

                for (NSString *item in contents) {
                    @autoreleasepool {
                        NSString *fullPath =
                            [directory stringByAppendingPathComponent:item];

                        NSError *error = nil;

                        if (![fm removeItemAtPath:fullPath
                                            error:&error]) {
                            success = NO;

                            NSLog(@"[ADM] delete backup failed: %@ (%@)",
                                  fullPath,
                                  error.localizedDescription);
                        }
                    }
                }
            }
            @catch (NSException *exception) {
                NSLog(@"[ADM] delete all backups exception: %@",
                      exception.reason);
                success = NO;
            }
        }
    });

    return success;
}

#pragma mark - ZIP Export

- (NSString *)exportBackupsToZip:(NSError **)error {
    if (error) {
        *error = nil;
    }

    @try {
        NSString *directory =
            [self backupDirectory];

        if (directory.length == 0) {
            if (error) {
                *error =
                    [NSError errorWithDomain:@"AppDataManager"
                                         code:500
                                     userInfo:@{
                    NSLocalizedDescriptionKey:
                        @"تعذر الوصول إلى مجلد النسخ الاحتياطية"
                }];
            }

            return nil;
        }

        NSString *zipPath =
            [directory stringByAppendingPathComponent:
                @"backups_export.zip"];

        /*
         * Remove an old export before creating the new one.
         */
        [[NSFileManager defaultManager]
            removeItemAtPath:zipPath
                       error:nil];

        /*
         * The backup directory is internally controlled and does not
         * contain user-provided shell fragments. Still, quote every
         * path before invoking the system utility.
         */
        NSString *escapedDirectory =
            [directory stringByReplacingOccurrencesOfString:@"\""
                                                  withString:@"\\\""];

        NSString *escapedZip =
            [zipPath stringByReplacingOccurrencesOfString:@"\""
                                                withString:@"\\\""];

        NSString *command =
            [NSString stringWithFormat:
                @"cd \"%@\" && /usr/bin/zip -r \"%@\" . -x \"*.zip\"",
                escapedDirectory,
                escapedZip];

        FILE *pipe =
            popen(command.UTF8String, "r");

        if (!pipe) {
            if (error) {
                *error =
                    [NSError errorWithDomain:@"AppDataManager"
                                         code:501
                                     userInfo:@{
                    NSLocalizedDescriptionKey:
                        @"تعذر تشغيل أداة الضغط"
                }];
            }

            return nil;
        }

        int result =
            pclose(pipe);

        if (result == 0 &&
            [self pathExists:zipPath]) {
            return zipPath;
        }

        if (error) {
            *error =
                [NSError errorWithDomain:@"AppDataManager"
                                     code:502
                                 userInfo:@{
                NSLocalizedDescriptionKey:
                    @"فشل إنشاء ملف النسخة المضغوطة"
            }];
        }

        return nil;
    }
    @catch (NSException *exception) {
        if (error) {
            *error =
                [NSError errorWithDomain:@"AppDataManager"
                                     code:503
                                 userInfo:@{
                NSLocalizedDescriptionKey:
                    exception.reason ?: @"Unknown error"
            }];
        }

        return nil;
    }
}

#pragma mark - Disk Space

- (unsigned long long)totalFreeSpace {
    @try {
        NSDictionary *attributes =
            [[NSFileManager defaultManager]
                attributesOfFileSystemForPath:
                    NSHomeDirectory()
                                      error:nil];

        return [attributes[NSFileSystemFreeSize]
            unsignedLongLongValue];
    }
    @catch (NSException *exception) {
        return 0;
    }
}

- (unsigned long long)totalDiskSpace {
    @try {
        NSDictionary *attributes =
            [[NSFileManager defaultManager]
                attributesOfFileSystemForPath:
                    NSHomeDirectory()
                                      error:nil];

        return [attributes[NSFileSystemSize]
            unsignedLongLongValue];
    }
    @catch (NSException *exception) {
        return 0;
    }
}

#pragma mark - Icon

- (UIImage *)iconForBundleID:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return nil;
    }

    UIImage *cached =
        [self.iconCache objectForKey:bundleID];

    if (cached) {
        return cached;
    }

    UIImage *icon = nil;

    @try {
        /*
         * Strategy 1:
         * LSApplicationProxy
         */
        Class cls =
            NSClassFromString(@"LSApplicationProxy");

        if (cls &&
            [cls respondsToSelector:
                @selector(applicationProxyForIdentifier:)]) {

            id proxy =
                [cls performSelector:
                    @selector(applicationProxyForIdentifier:)
                    withObject:bundleID];

            if (proxy &&
                [proxy respondsToSelector:
                    @selector(iconDataForVariant:)]) {

                for (NSNumber *variant in @[
                    @(2),
                    @(0)
                ]) {
                    @autoreleasepool {
                        NSData *data = nil;

                        @try {
                            data =
                                [proxy performSelector:
                                    @selector(iconDataForVariant:)
                                    withObject:variant];
                        }
                        @catch (NSException *exception) {
                            data = nil;
                        }

                        if ([data isKindOfClass:[NSData class]] &&
                            data.length > 0) {

                            UIImage *candidate =
                                [UIImage imageWithData:data];

                            if (candidate) {
                                icon = candidate;
                                break;
                            }
                        }
                    }
                }
            }
        }

        /*
         * Strategy 2:
         * Filesystem fallback.
         */
        if (!icon) {
            NSString *dataPath =
                [self dataPathForBundleID:bundleID];

            if (dataPath.length > 0) {
                NSFileManager *fm =
                    [NSFileManager defaultManager];

                NSArray *items =
                    [fm contentsOfDirectoryAtPath:
                        dataPath
                                             error:nil];

                NSArray *iconNames = @[
                    @"AppIcon60x60",
                    @"AppIcon76x76",
                    @"AppIcon",
                    @"Icon-60",
                    @"Icon",
                    @"icon"
                ];

                NSArray *extensions = @[
                    @"png",
                    @"jpg",
                    @"jpeg"
                ];

                for (NSString *item in items) {
                    @autoreleasepool {
                        if (![item hasSuffix:@".app"]) {
                            continue;
                        }

                        NSString *appPath =
                            [dataPath stringByAppendingPathComponent:
                                item];

                        for (NSString *iconName in iconNames) {
                            if (icon) {
                                break;
                            }

                            for (NSString *extension in extensions) {
                                @autoreleasepool {
                                    NSString *iconPath =
                                        [appPath
                                            stringByAppendingPathComponent:
                                                [iconName
                                                    stringByAppendingPathExtension:
                                                        extension]];

                                    if ([fm fileExistsAtPath:iconPath]) {
                                        UIImage *candidate =
                                            [UIImage imageWithContentsOfFile:
                                                iconPath];

                                        if (candidate) {
                                            icon = candidate;
                                            break;
                                        }
                                    }

                                    /*
                                     * Also check retina suffixes.
                                     */
                                    NSArray *suffixes = @[
                                        @"@2x",
                                        @"@3x"
                                    ];

                                    for (NSString *suffix in suffixes) {
                                        NSString *retinaName =
                                            [NSString stringWithFormat:
                                                @"%@%@.%@",
                                                iconName,
                                                suffix,
                                                extension];

                                        NSString *retinaPath =
                                            [appPath
                                                stringByAppendingPathComponent:
                                                    retinaName];

                                        if ([fm fileExistsAtPath:
                                                retinaPath]) {

                                            UIImage *candidate =
                                                [UIImage imageWithContentsOfFile:
                                                    retinaPath];

                                            if (candidate) {
                                                icon = candidate;
                                                break;
                                            }
                                        }
                                    }

                                    if (icon) {
                                        break;
                                    }
                                }
                            }
                        }

                        if (icon) {
                            break;
                        }
                    }
                }
            }
        }

        /*
         * Strategy 3:
         * SpringBoardServices.
         */
        if (!icon) {
            void *handle =
                dlopen(
                    "/System/Library/PrivateFrameworks/"
                    "SpringBoardServices.framework/"
                    "SpringBoardServices",
                    RTLD_LAZY);

            if (handle) {
                NSData *(*copyIconData)(NSString *) =
                    dlsym(handle,
                          "SBSCopyIconImagePNGDataForDisplayIdentifier");

                if (copyIconData) {
                    @try {
                        NSData *data =
                            copyIconData(bundleID);

                        if ([data isKindOfClass:[NSData class]] &&
                            data.length > 0) {
                            icon =
                                [UIImage imageWithData:data];
                        }
                    }
                    @catch (NSException *exception) {
                        NSLog(@"[ADM] SBS icon exception: %@",
                              exception.reason);
                    }
                }

                dlclose(handle);
            }
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] icon exception for %@: %@",
              bundleID,
              exception.reason);
    }

    if (icon) {
        UIImage *cacheImage = icon;

        dispatch_barrier_async(self.cacheQueue, ^{
            [self.iconCache setObject:cacheImage
                               forKey:bundleID];
        });
    }

    return icon;
}

#pragma mark - Formatting

- (NSString *)formatBytes:(unsigned long long)bytes {
    @try {
        if (bytes == 0) {
            return @"0 B";
        }

        NSArray *units = @[
            @"B",
            @"KB",
            @"MB",
            @"GB",
            @"TB"
        ];

        NSUInteger index = 0;
        double size = (double)bytes;

        while (size >= 1024.0 &&
               index < units.count - 1) {

            size /= 1024.0;
            index++;
        }

        if (index == 0) {
            return [NSString stringWithFormat:
                @"%llu %@",
                bytes,
                units[index]];
        }

        if (size < 10.0) {
            return [NSString stringWithFormat:
                @"%.2f %@",
                size,
                units[index]];
        }

        if (size < 100.0) {
            return [NSString stringWithFormat:
                @"%.1f %@",
                size,
                units[index]];
        }

        return [NSString stringWithFormat:
            @"%.0f %@",
            size,
            units[index]];
    }
    @catch (NSException *exception) {
        return @"0 B";
    }
}

#pragma mark - Version

- (NSString *)versionForBundleID:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return @"1.0";
    }

    @try {
        Class cls =
            NSClassFromString(@"LSApplicationProxy");

        if (cls &&
            [cls respondsToSelector:
                @selector(applicationProxyForIdentifier:)]) {

            id proxy =
                [cls performSelector:
                    @selector(applicationProxyForIdentifier:)
                    withObject:bundleID];

            if (proxy &&
                [proxy respondsToSelector:
                    @selector(shortVersionString)]) {

                NSString *version =
                    [proxy performSelector:
                        @selector(shortVersionString)];

                if ([version isKindOfClass:[NSString class]] &&
                    version.length > 0) {
                    return version;
                }
            }
        }

        NSString *dataPath =
            [self dataPathForBundleID:bundleID];

        if (dataPath.length > 0) {
            NSFileManager *fm =
                [NSFileManager defaultManager];

            NSArray *items =
                [fm contentsOfDirectoryAtPath:
                    dataPath
                                         error:nil];

            for (NSString *item in items) {
                @autoreleasepool {
                    if (![item hasSuffix:@".app"]) {
                        continue;
                    }

                    NSString *infoPath =
                        [dataPath
                            stringByAppendingPathComponent:
                                [item
                                    stringByAppendingPathComponent:
                                        @"Info.plist"]];

                    NSDictionary *info =
                        [NSDictionary dictionaryWithContentsOfFile:
                            infoPath];

                    NSString *version =
                        info[@"CFBundleShortVersionString"];

                    if ([version isKindOfClass:[NSString class]] &&
                        version.length > 0) {
                        return version;
                    }
                }
            }
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] version exception for %@: %@",
              bundleID,
              exception.reason);
    }

    return @"1.0";
}

#pragma mark - Documents

- (NSString *)documentsPathForBundleID:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return nil;
    }

    NSString *dataPath =
        [self dataPathForBundleID:bundleID];

    if (dataPath.length == 0) {
        return nil;
    }

    NSString *documents =
        [dataPath stringByAppendingPathComponent:@"Documents"];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;

    if (![fm fileExistsAtPath:documents isDirectory:&isDirectory]) {
        NSLog(@"[ADM] documents unavailable: path does not exist bundle=%@ data=%@ documents=%@",
              bundleID,
              dataPath,
              documents);
        return nil;
    }

    if (!isDirectory || ![fm isReadableFileAtPath:documents]) {
        NSLog(@"[ADM] documents unavailable: invalid permissions/type bundle=%@ path=%@ directory=%d readable=%d",
              bundleID,
              documents,
              isDirectory,
              [fm isReadableFileAtPath:documents]);
        return nil;
    }

    return documents;
}

- (NSUInteger)documentsCountForBundleID:(NSString *)bundleID {
    NSString *documents =
        [self documentsPathForBundleID:bundleID];

    if (documents.length == 0) {
        return 0;
    }

    @try {
        NSError *error = nil;
        NSArray *contents =
            [[NSFileManager defaultManager]
                contentsOfDirectoryAtPath:documents
                                    error:&error];
        if (![contents isKindOfClass:[NSArray class]]) {
            ADMLogFileError(@"enumerate Documents", documents, error);
            return 0;
        }

        return contents.count;
    }
    @catch (NSException *exception) {
        return 0;
    }
}

#pragma mark - Backup Information

- (NSDate *)lastBackupDateForBundleID:(NSString *)bundleID {
    NSArray *backups =
        [self availableBackupsForBundleID:bundleID];

    if (backups.count == 0) {
        return nil;
    }

    NSDate *date =
        backups.firstObject[@"date"];

    return [date isKindOfClass:[NSDate class]]
        ? date
        : nil;
}

- (unsigned long long)totalBackupsSize {
    NSString *directory =
        [self backupDirectory];

    if (directory.length == 0) {
        return 0;
    }

    @try {
        return [self fastDirectorySize:directory];
    }
    @catch (NSException *exception) {
        return 0;
    }
}

- (unsigned long long)totalAppsDataSize {
    @try {
        NSArray *applications =
            [self allInstalledApplications];

        unsigned long long total = 0;

        for (NSDictionary *application in applications) {
            @autoreleasepool {
                NSString *bundleID =
                    application[@"bundleID"];

                if (![bundleID isKindOfClass:[NSString class]] ||
                    bundleID.length == 0) {
                    continue;
                }

                /*
                 * Skip system applications. The manager is intended
                 * to report user application data.
                 */
                if ([application[@"isSystem"] boolValue]) {
                    continue;
                }

                total +=
                    [self dataSizeForBundleID:bundleID];
            }
        }

        return total;
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] total apps data size exception: %@",
              exception.reason);
        return 0;
    }
}

#pragma mark - System Application Detection

- (BOOL)isSystemApp:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return NO;
    }

    @try {
        NSArray *applications =
            [self allInstalledApplications];

        for (NSDictionary *application in applications) {
            NSString *identifier =
                application[@"bundleID"];

            if ([identifier isKindOfClass:[NSString class]] &&
                [identifier isEqualToString:bundleID]) {

                return [application[@"isSystem"] boolValue];
            }
        }

        /*
         * Fallback only when LaunchServices/filesystem discovery
         * cannot identify the application.
         */
        NSArray *systemPrefixes = @[
            @"com.apple.",
            @"system."
        ];

        for (NSString *prefix in systemPrefixes) {
            if ([bundleID hasPrefix:prefix]) {
                return YES;
            }
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] system app detection exception: %@",
              exception.reason);
    }

    return NO;
}

#pragma mark - Application Termination

- (BOOL)killApp:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0) {
        return NO;
    }

    /* LSApplicationWorkspace must never be invoked from fileQueue. */
    if (![NSThread isMainThread]) {
        __block BOOL terminated = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            terminated = [self killApp:bundleID];
        });
        return terminated;
    }

    @try {
        Class cls =
            NSClassFromString(@"LSApplicationWorkspace");

        if (cls &&
            [cls respondsToSelector:@selector(defaultWorkspace)]) {

            id workspace =
                [cls performSelector:
                    @selector(defaultWorkspace)];

            SEL selector =
                @selector(
                    terminateApplicationWithBundleIdentifier:);

            if (workspace &&
                [workspace respondsToSelector:selector]) {

                @try {
                    NSMethodSignature *signature =
                        [workspace methodSignatureForSelector:selector];

                    if (signature) {
                        NSInvocation *invocation =
                            [NSInvocation invocationWithMethodSignature:
                                signature];

                        [invocation setSelector:selector];
                        [invocation setTarget:workspace];

                        NSString *identifier = bundleID;

                        [invocation setArgument:&identifier
                                        atIndex:2];

                        [invocation invoke];

                        return YES;
                    }
                }
                @catch (NSException *exception) {
                    NSLog(@"[ADM] application termination exception: %@",
                          exception.reason);
                }
            }
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] killApp exception: %@",
              exception.reason);
    }

    /*
     * Deliberately no shell fallback.
     *
     * The previous implementation constructed:
     *
     *     killall -9 '<bundleID>'
     *
     * which was unnecessary and introduced command parsing risk.
     * LaunchServices is the correct primary mechanism here.
     */
    return NO;
}

#pragma mark - Helpers

- (BOOL)pathExists:(NSString *)path {
    if (![path isKindOfClass:[NSString class]] ||
        path.length == 0) {
        return NO;
    }

    @try {
        return [[NSFileManager defaultManager]
            fileExistsAtPath:path];
    }
    @catch (NSException *exception) {
        return NO;
    }
}

@end
