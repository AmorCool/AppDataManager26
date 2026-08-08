#import "AppDataManager.h"
#import <rootless.h>
#import <dlfcn.h>
#import <objc/runtime.h>

@implementation AppDataManager

+ (instancetype)sharedManager {
    static AppDataManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (NSArray<NSDictionary *> *)allInstalledApplications {
    // iOS 18: Use objc_getClass for stealth and robustness
    Class LSApplicationWorkspace_class = objc_getClass("LSApplicationWorkspace");
    if (!LSApplicationWorkspace_class) {
        NSLog(@"[AppDataManager] ❌ LSApplicationWorkspace not available");
        return @[];
    }

    id workspace = [LSApplicationWorkspace_class performSelector:@selector(defaultWorkspace)];
    if (!workspace) {
        NSLog(@"[AppDataManager] ❌ LSApplicationWorkspace defaultWorkspace returned nil");
        return @[];
    }

    NSArray *apps = nil;
    @try {
        apps = [workspace performSelector:@selector(allInstalledApplications)];
    } @catch (NSException *e) {
        NSLog(@"[AppDataManager] ⚠️ Exception getting apps: %@", e);
        return @[];
    }

    if (!apps || apps.count == 0) {
        NSLog(@"[AppDataManager] ⚠️ No apps returned");
        return @[];
    }

    NSMutableArray *appList = [NSMutableArray array];
    for (id app in apps) {
        @try {
            NSString *bundleID = nil;
            NSString *name = nil;

            if ([app respondsToSelector:@selector(bundleIdentifier)]) {
                bundleID = [app performSelector:@selector(bundleIdentifier)];
            }
            if ([app respondsToSelector:@selector(localizedName)]) {
                name = [app performSelector:@selector(localizedName)];
            }

            if (!bundleID || !name) continue;

            NSString *appType = @"User";
            if ([app respondsToSelector:@selector(applicationType)]) {
                appType = [app performSelector:@selector(applicationType)] ?: @"User";
            }

            unsigned long long size = [self dataSizeForBundleID:bundleID];
            NSString *sizeStr = [self formatBytes:size];

            [appList addObject:@{
                @"name": name,
                @"bundleID": bundleID,
                @"type": appType,
                @"size": @(size),
                @"sizeString": sizeStr,
                @"hasBackup": @([self availableBackupsForBundleID:bundleID].count > 0),
                @"isSystemApp": @([self isSystemApp:bundleID])
            }];
        } @catch (NSException *e) {
            NSLog(@"[AppDataManager] ⚠️ Exception processing app: %@", e);
            continue;
        }
    }

    return [appList sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] compare:b[@"name"]];
    }];
}

- (BOOL)isSystemApp:(NSString *)bundleID {
    if (!bundleID) return NO;
    NSArray *systemApps = @[@"com.apple.springboard", @"com.apple.Preferences", 
                            @"com.apple.mobilesafari", @"com.apple.MobileSMS",
                            @"com.apple.mobilephone", @"com.apple.camera",
                            @"com.apple.mobilemail", @"com.apple.Maps",
                            @"com.apple.mobilecal", @"com.apple.mobileslideshow",
                            @"com.apple.AppStore", @"com.apple.ios.StoreKitUIService"];
    return [systemApps containsObject:bundleID];
}

- (NSString *)dataPathForBundleID:(NSString *)bundleID {
    if (!bundleID) return nil;

    // Method 1: MobileContainerManager (iOS 15-18)
    @try {
        void *handle = dlopen("/System/Library/PrivateFrameworks/MobileContainerManager.framework/MobileContainerManager", RTLD_LAZY);
        if (handle) {
            Class MCMAppDataContainer = NSClassFromString(@"MCMAppDataContainer");
            if (MCMAppDataContainer && [MCMAppDataContainer respondsToSelector:@selector(containerWithIdentifier:error:)]) {
                NSError *error = nil;
                id container = [MCMAppDataContainer performSelector:@selector(containerWithIdentifier:error:)
                                                          withObject:bundleID
                                                          withObject:error];
                if (container && [container respondsToSelector:@selector(path)]) {
                    NSString *path = [container performSelector:@selector(path)];
                    if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
                        return path;
                    }
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[AppDataManager] ⚠️ MobileContainerManager failed: %@", e);
    }

    // Method 2: Manual plist search
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dataRoot = @"/var/mobile/Containers/Data/Application";
        NSArray *folders = [fm contentsOfDirectoryAtPath:dataRoot error:nil];

        for (NSString *folder in folders) {
            NSString *plistPath = [dataRoot stringByAppendingPathComponent:[folder stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
            if ([fm fileExistsAtPath:plistPath]) {
                NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
                if ([plist[@"MCMMetadataIdentifier"] isEqualToString:bundleID]) {
                    return [dataRoot stringByAppendingPathComponent:folder];
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[AppDataManager] ⚠️ Manual search failed: %@", e);
    }

    return nil;
}

- (unsigned long long)dataSizeForBundleID:(NSString *)bundleID {
    NSString *path = [self dataPathForBundleID:bundleID];
    if (!path) return 0;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm subpathsAtPath:path];
    unsigned long long totalSize = 0;

    for (NSString *item in contents) {
        @try {
            NSString *fullPath = [path stringByAppendingPathComponent:item];
            NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
            if (attrs) {
                totalSize += [attrs fileSize];
            }
        } @catch (NSException *e) {
            continue;
        }
    }

    return totalSize;
}

- (NSString *)formatBytes:(unsigned long long)bytes {
    NSArray *units = @[@"B", @"KB", @"MB", @"GB"];
    double size = (double)bytes;
    int unitIndex = 0;

    while (size >= 1024 && unitIndex < units.count - 1) {
        size /= 1024;
        unitIndex++;
    }

    if (unitIndex == 0) {
        return [NSString stringWithFormat:@"%.0f %@", size, units[unitIndex]];
    }
    return [NSString stringWithFormat:@"%.2f %@", size, units[unitIndex]];
}

- (NSString *)backupDirectory {
    NSString *backupPath = ROOT_PATH_NS(@"/var/mobile/Documents/AppDataBackups");
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:backupPath]) {
        [fm createDirectoryAtPath:backupPath 
      withIntermediateDirectories:YES 
                       attributes:@{NSFileOwnerAccountName: @"mobile", NSFileGroupOwnerAccountName: @"mobile"} 
                            error:nil];
    }
    return backupPath;
}

- (BOOL)backupAppData:(NSString *)bundleID {
    if (!bundleID) return NO;
    NSString *dataPath = [self dataPathForBundleID:bundleID];
    if (!dataPath) return NO;

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];

    NSString *backupName = [NSString stringWithFormat:@"%@_%@", bundleID, timestamp];
    NSString *backupPath = [[self backupDirectory] stringByAppendingPathComponent:backupName];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;

    BOOL success = [fm copyItemAtPath:dataPath toPath:backupPath error:&error];
    if (success) {
        NSLog(@"[AppDataManager] ✅ Backup created: %@", backupPath);
    } else {
        NSLog(@"[AppDataManager] ❌ Backup failed: %@", error);
    }
    return success;
}

- (BOOL)wipeAppData:(NSString *)bundleID {
    if (!bundleID) return NO;
    if ([self isSystemApp:bundleID]) {
        NSLog(@"[AppDataManager] ⛔ Cannot wipe system app: %@", bundleID);
        return NO;
    }

    NSString *dataPath = [self dataPathForBundleID:bundleID];
    if (!dataPath) return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;

    NSArray *contents = [fm contentsOfDirectoryAtPath:dataPath error:&error];
    if (error) {
        NSLog(@"[AppDataManager] ❌ Error reading directory: %@", error);
        return NO;
    }

    BOOL allSuccess = YES;
    for (NSString *item in contents) {
        if ([item hasPrefix:@"."]) continue;
        NSString *fullPath = [dataPath stringByAppendingPathComponent:item];
        NSError *err = nil;
        BOOL success = [fm removeItemAtPath:fullPath error:&err];
        if (!success) {
            NSLog(@"[AppDataManager] ⚠️ Failed to remove %@: %@", item, err);
            allSuccess = NO;
        }
    }

    NSLog(@"[AppDataManager] %@ Wiped data for: %@", allSuccess ? @"✅" : @"⚠️", bundleID);
    return allSuccess;
}

- (NSArray<NSDictionary *> *)availableBackupsForBundleID:(NSString *)bundleID {
    if (!bundleID) return @[];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *backupDir = [self backupDirectory];
    NSArray *contents = [fm contentsOfDirectoryAtPath:backupDir error:nil];

    NSMutableArray *backups = [NSMutableArray array];
    for (NSString *item in contents) {
        if ([item hasPrefix:bundleID]) {
            NSString *fullPath = [backupDir stringByAppendingPathComponent:item];
            NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];

            unsigned long long size = 0;
            NSArray *subpaths = [fm subpathsAtPath:fullPath];
            for (NSString *sub in subpaths) {
                NSDictionary *subAttrs = [fm attributesOfItemAtPath:[fullPath stringByAppendingPathComponent:sub] error:nil];
                size += [subAttrs fileSize];
            }

            [backups addObject:@{
                @"path": fullPath,
                @"name": item,
                @"date": attrs[NSFileModificationDate] ?: [NSDate date],
                @"size": @(size),
                @"sizeString": [self formatBytes:size]
            }];
        }
    }

    return [backups sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"date"] compare:a[@"date"]];
    }];
}

- (BOOL)restoreAppData:(NSString *)bundleID fromBackup:(NSString *)backupPath {
    if (!bundleID || !backupPath) return NO;
    NSString *dataPath = [self dataPathForBundleID:bundleID];
    if (!dataPath || ![[NSFileManager defaultManager] fileExistsAtPath:backupPath]) {
        return NO;
    }

    [self wipeAppData:bundleID];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm contentsOfDirectoryAtPath:backupPath error:nil];

    BOOL success = YES;
    for (NSString *item in contents) {
        NSString *src = [backupPath stringByAppendingPathComponent:item];
        NSString *dst = [dataPath stringByAppendingPathComponent:item];
        NSError *error = nil;
        if (![fm copyItemAtPath:src toPath:dst error:&error]) {
            NSLog(@"[AppDataManager] ⚠️ Restore failed for %@: %@", item, error);
            success = NO;
        }
    }

    NSLog(@"[AppDataManager] %@ Restored %@ from %@", success ? @"✅" : @"⚠️", bundleID, backupPath);
    return success;
}
- (BOOL)deleteBackup:(NSString *)backupPath {
    if (!backupPath) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    BOOL success = [fm removeItemAtPath:backupPath error:&error];
    if (success) {
        NSLog(@"[AppDataManager] ✅ Deleted backup: %@", backupPath);
    } else {
        NSLog(@"[AppDataManager] ❌ Failed to delete backup: %@", error);
    }
    return success;
}

@end