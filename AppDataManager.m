//
//  AppDataManager.m
//  AppDataManager
//
//  v1.6.1 — Crash-Resilient Core Engine
//

#import "AppDataManager.h"
#import "rootless.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <dlfcn.h>
#import <stdio.h>

static NSString * const kBackupDir =
    @"/var/mobile/Documents/AppDataManager/Backups";

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
    NSMutableArray *applications =
        [NSMutableArray array];

    @try {
        Class workspaceClass =
            NSClassFromString(@"LSApplicationWorkspace");

        if (workspaceClass) {
            id workspace = nil;

            @try {
                if ([workspaceClass respondsToSelector:
                        @selector(defaultWorkspace)]) {
                    workspace =
                        [workspaceClass performSelector:
                            @selector(defaultWorkspace)];
                }
            }
            @catch (NSException *exception) {
                NSLog(@"[ADM] workspace exception: %@",
                      exception.reason);
            }

            if (workspace) {
                NSArray *proxies = nil;

                @try {
                    if ([workspace respondsToSelector:
                            @selector(allInstalledApplications)]) {
                        proxies =
                            [workspace performSelector:
                                @selector(allInstalledApplications)];
                    }
                }
                @catch (NSException *exception) {
                    NSLog(@"[ADM] installed applications exception: %@",
                          exception.reason);
                }

                if (![proxies isKindOfClass:[NSArray class]]) {
                    @try {
                        if ([workspace respondsToSelector:
                                @selector(allApplications)]) {
                            proxies =
                                [workspace performSelector:
                                    @selector(allApplications)];
                        }
                    }
                    @catch (NSException *exception) {
                        NSLog(@"[ADM] allApplications exception: %@",
                              exception.reason);
                    }
                }

                if ([proxies isKindOfClass:[NSArray class]]) {
                    for (id proxy in proxies) {
                        @autoreleasepool {
                            NSDictionary *info =
                                [self extractInfoFromProxy:proxy];

                            if (info) {
                                [applications addObject:info];
                            }
                        }
                    }
                }
            }
        }

        /*
         * Filesystem discovery is used only when LaunchServices
         * did not return anything. This prevents duplicate entries.
         */
        if (applications.count == 0) {
            NSArray *fallback =
                [self discoverAppsFromFilesystem];

            if (fallback.count > 0) {
                [applications addObjectsFromArray:fallback];
            }
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] discovery exception: %@",
              exception.reason);
    }

    return [applications sortedArrayUsingComparator:
        ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {

        NSString *nameA = a[@"name"];
        NSString *nameB = b[@"name"];

        if (![nameA isKindOfClass:[NSString class]]) {
            nameA = @"";
        }

        if (![nameB isKindOfClass:[NSString class]]) {
            nameB = @"";
        }

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

    @try {
        NSString *path =
            [self dataPathViaContainerManager:bundleID];

        if (path.length > 0 &&
            [self pathExists:path]) {
            return path;
        }

        path =
            [self dataPathViaProxy:bundleID];

        if (path.length > 0 &&
            [self pathExists:path]) {
            return path;
        }

        path =
            [self dataPathViaFilesystemSearch:bundleID];

        if (path.length > 0 &&
            [self pathExists:path]) {
            return path;
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] data path exception for %@: %@",
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

        id proxy =
            [cls performSelector:selector
                      withObject:bundleID];

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
        NSFileManager *fm =
            [NSFileManager defaultManager];

        NSArray *paths = @[
            @"/var/mobile/Containers/Data/Application",
            @"/private/var/mobile/Containers/Data/Application",
            ROOT_PATH_NS(@"/var/mobile/Containers/Data/Application"),
            ROOT_PATH_NS(@"/private/var/mobile/Containers/Data/Application")
        ];

        NSMutableSet *visitedBases =
            [NSMutableSet set];

        for (NSString *basePath in paths) {
            if (![basePath isKindOfClass:[NSString class]] ||
                basePath.length == 0) {
                continue;
            }

            if ([visitedBases containsObject:basePath]) {
                continue;
            }

            [visitedBases addObject:basePath];

            if (![self pathExists:basePath]) {
                continue;
            }

            NSArray *directories =
                [fm contentsOfDirectoryAtPath:basePath error:nil];

            if (![directories isKindOfClass:[NSArray class]]) {
                continue;
            }

            for (NSString *directory in directories) {
                @autoreleasepool {
                    NSString *container =
                        [basePath stringByAppendingPathComponent:
                            directory];

                    NSString *metadata =
                        [container stringByAppendingPathComponent:
                            @".com.apple.mobile_container_manager.metadata.plist"];

                    NSDictionary *info =
                        [NSDictionary dictionaryWithContentsOfFile:
                            metadata];

                    NSString *identifier =
                        info[@"MCMMetadataIdentifier"];

                    if ([identifier isKindOfClass:[NSString class]] &&
                        [identifier isEqualToString:bundleID]) {
                        return container;
                    }
                }
            }
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] filesystem data search exception: %@",
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
            NSArray *paths =
                [self allDataPathsForBundleID:bundleID];

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
            NSArray *paths =
                [self allDataPathsForBundleID:bundleID];

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
                           :@"%llu:%llu",
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
                            if (item.length == 0) {
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
    NSString *path =
        ROOT_PATH_NS(kBackupDir);

    if (![path isKindOfClass:[NSString class]] ||
        path.length == 0) {
        return nil;
    }

    NSFileManager *fm =
        [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:path]) {
        @try {
            NSError *error = nil;

            BOOL created =
                [fm createDirectoryAtPath:path
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&error];

            if (!created) {
                NSLog(@"[ADM] backup directory creation failed: %@",
                      error.localizedDescription);
                return nil;
            }
        }
        @catch (NSException *exception) {
            NSLog(@"[ADM] backup directory exception: %@",
                  exception.reason);
            return nil;
        }
    }

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

                NSArray *dataPaths =
                    [self allDataPathsForBundleID:bundleID];

                if (dataPaths.count == 0) {
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
                                     attributes:nil
                                          error:&directoryError]) {

                    NSLog(@"[ADM] backup directory failed: %@",
                          directoryError.localizedDescription);

                    success = NO;
                    return;
                }

                NSUInteger index = 0;

                for (NSString *source in dataPaths) {
                    @autoreleasepool {
                        if (source.length == 0 ||
                            ![self pathExists:source]) {
                            success = NO;
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
                            success = NO;

                            NSLog(@"[ADM] backup copy failed: %@ -> %@ (%@)",
                                  source,
                                  itemDestination,
                                  copyError.localizedDescription);
                        }

                        index++;
                    }
                }

                /*
                 * Never leave an apparently valid empty backup behind.
                 */
                if (!success) {
                    [fm removeItemAtPath:destination
                                   error:nil];
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

#pragma mark - Restore

- (BOOL)restoreAppData:(NSString *)bundleID
            fromBackup:(NSString *)backupPath {

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

    __block BOOL success = YES;

    dispatch_sync(self.fileQueue, ^{
        @autoreleasepool {
            @try {
                NSString *backupRoot =
                    [self backupDirectory];

                if (backupRoot.length == 0) {
                    success = NO;
                    return;
                }

                /*
                 * Do not allow restore from an arbitrary filesystem path.
                 * The selected backup must reside inside our backup store.
                 */
                NSString *standardBackup =
                    [backupRoot stringByStandardizingPath];

                NSString *standardSelected =
                    [backupPath stringByStandardizingPath];

                NSString *prefix =
                    [standardBackup stringByAppendingString:@"/"];

                if (![standardSelected hasPrefix:prefix]) {
                    NSLog(@"[ADM] rejected restore path outside backup directory");
                    success = NO;
                    return;
                }

                NSFileManager *fm =
                    [NSFileManager defaultManager];

                BOOL isDirectory = NO;

                if (![fm fileExistsAtPath:standardSelected
                               isDirectory:&isDirectory] ||
                    !isDirectory) {
                    success = NO;
                    return;
                }

                /*
                 * Terminate the application before changing its container.
                 */
                [self killApp:bundleID];

                /*
                 * Wipe current data.
                 */
                NSArray *destinationPaths =
                    [self allDataPathsForBundleID:bundleID];

                if (destinationPaths.count == 0) {
                    success = NO;
                    return;
                }

                for (NSString *destination in destinationPaths) {
                    @autoreleasepool {
                        if (destination.length == 0) {
                            continue;
                        }

                        NSArray *contents =
                            [fm contentsOfDirectoryAtPath:
                                destination
                                                   error:nil];

                        for (NSString *item in contents) {
                            @autoreleasepool {
                                NSString *full =
                                    [destination stringByAppendingPathComponent:
                                        item];

                                NSError *removeError = nil;

                                if (![fm removeItemAtPath:full
                                                    error:&removeError]) {
                                    success = NO;

                                    NSLog(@"[ADM] restore wipe failed: %@ (%@)",
                                          full,
                                          removeError.localizedDescription);
                                }
                            }
                        }
                    }
                }

                /*
                 * Restore each backed-up container by copying its CONTENTS
                 * into the existing destination container.
                 *
                 * The old implementation attempted to copy the entire
                 * directory onto an already-existing container, which can
                 * fail because the destination directory already exists.
                 */
                NSArray *backupItems =
                    [fm contentsOfDirectoryAtPath:
                        standardSelected
                                                   error:nil];

                if (![backupItems isKindOfClass:[NSArray class]]) {
                    success = NO;
                    return;
                }

                for (NSString *item in backupItems) {
                    @autoreleasepool {
                        NSString *source =
                            [standardSelected stringByAppendingPathComponent:
                                item];

                        BOOL isDirectory = NO;

                        if (![fm fileExistsAtPath:source
                                       isDirectory:&isDirectory]) {
                            continue;
                        }

                        /*
                         * Match a backup container by basename.
                         */
                        NSString *matchingDestination = nil;

                        NSString *sourceName =
                            source.lastPathComponent;

                        for (NSString *destination in destinationPaths) {
                            if ([[destination lastPathComponent]
                                    isEqualToString:sourceName]) {
                                matchingDestination = destination;
                                break;
                            }
                        }

                        /*
                         * If no exact basename match exists, use the first
                         * available destination only when there is a single
                         * destination. This keeps normal-app restoration
                         * compatible with the common case.
                         */
                        if (!matchingDestination &&
                            destinationPaths.count == 1) {
                            matchingDestination =
                                destinationPaths.firstObject;
                        }

                        if (!matchingDestination ||
                            ![self pathExists:matchingDestination]) {
                            success = NO;
                            continue;
                        }

                        if (isDirectory) {
                            NSArray *children =
                                [fm contentsOfDirectoryAtPath:
                                    source
                                                       error:nil];

                            for (NSString *child in children) {
                                @autoreleasepool {
                                    NSString *childSource =
                                        [source stringByAppendingPathComponent:
                                            child];

                                    NSString *childDestination =
                                        [matchingDestination
                                            stringByAppendingPathComponent:
                                                child];

                                    NSError *copyError = nil;

                                    /*
                                     * Remove conflicting items first.
                                     */
                                    if ([fm fileExistsAtPath:
                                            childDestination]) {

                                        if (![fm removeItemAtPath:
                                                childDestination
                                                              error:&copyError]) {
                                            success = NO;
                                            continue;
                                        }
                                    }

                                    copyError = nil;

                                    if (![fm copyItemAtPath:childSource
                                                     toPath:childDestination
                                                      error:&copyError]) {
                                        success = NO;

                                        NSLog(@"[ADM] restore copy failed: %@ -> %@ (%@)",
                                              childSource,
                                              childDestination,
                                              copyError.localizedDescription);
                                    }
                                }
                            }
                        } else {
                            NSString *destinationFile =
                                [matchingDestination
                                    stringByAppendingPathComponent:
                                        source.lastPathComponent];

                            NSError *copyError = nil;

                            if ([fm fileExistsAtPath:destinationFile]) {
                                [fm removeItemAtPath:destinationFile
                                               error:nil];
                            }

                            if (![fm copyItemAtPath:source
                                              toPath:destinationFile
                                               error:&copyError]) {
                                success = NO;
                            }
                        }
                    }
                }
            }
            @catch (NSException *exception) {
                NSLog(@"[ADM] restore exception: %@",
                      exception.reason);
                success = NO;
            }
        }
    });

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

        NSString *prefix =
            [bundleID stringByAppendingString:@"_"];

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

    @try {
        NSString *directory =
            [self backupDirectory];

        if (directory.length == 0) {
            return NO;
        }

        NSString *root =
            [directory stringByStandardizingPath];

        NSString *target =
            [backupPath stringByStandardizingPath];

        NSString *prefix =
            [root stringByAppendingString:@"/"];

        if (![target hasPrefix:prefix]) {
            return NO;
        }

        NSFileManager *fm =
            [NSFileManager defaultManager];

        if (![fm fileExistsAtPath:target]) {
            return NO;
        }

        NSError *error = nil;

        return [fm removeItemAtPath:target
                              error:&error];
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] delete backup exception: %@",
              exception.reason);
        return NO;
    }
}

- (BOOL)deleteAllBackups {
    @try {
        NSString *directory =
            [self backupDirectory];

        if (directory.length == 0) {
            return NO;
        }

        NSFileManager *fm =
            [NSFileManager defaultManager];

        NSArray *contents =
            [fm contentsOfDirectoryAtPath:directory
                                     error:nil];

        if (![contents isKindOfClass:[NSArray class]]) {
            return NO;
        }

        BOOL success = YES;

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

        return success;
    }
    @catch (NSException *exception) {
        NSLog(@"[ADM] delete all backups exception: %@",
              exception.reason);
        return NO;
    }
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

    return [self pathExists:documents] ? documents : nil;
}

- (NSUInteger)documentsCountForBundleID:(NSString *)bundleID {
    NSString *documents =
        [self documentsPathForBundleID:bundleID];

    if (documents.length == 0) {
        return 0;
    }

    @try {
        NSArray *contents =
            [[NSFileManager defaultManager]
                contentsOfDirectoryAtPath:documents
                                    error:nil];

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
