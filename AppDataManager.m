#import "AppDataManager.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import "rootless.h"

@implementation AppDataManager

+ (instancetype)sharedManager {
    static AppDataManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (NSArray *)allInstalledApplications {
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

- (NSArray *)availableBackupsForBundleID:(NSString *)bundleID {
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
    if (!bundleID || !backupPath) {
        NSLog(@"[AppDataManager] ❌ Invalid parameters for restore");
        return NO;
    }

    NSString *dataPath = [self dataPathForBundleID:bundleID];
    if (!dataPath) {
        NSLog(@"[AppDataManager] ❌ Could not find data path for %@", bundleID);
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:backupPath]) {
        NSLog(@"[AppDataManager] ❌ Backup path does not exist: %@", backupPath);
        return NO;
    }

    NSLog(@"[AppDataManager] 🧹 Wiping existing data for %@...", bundleID);
    [self wipeAppData:bundleID];

    if (![fm fileExistsAtPath:dataPath]) {
        NSError *createErr = nil;
        BOOL created = [fm createDirectoryAtPath:dataPath
                    withIntermediateDirectories:YES
                                     attributes:@{NSFileOwnerAccountName: @"mobile",
                                                  NSFileGroupOwnerAccountName: @"mobile"}
                                          error:&createErr];
        if (!created) {
            NSLog(@"[AppDataManager] ❌ Failed to create data directory: %@", createErr);
            return NO;
        }
        NSLog(@"[AppDataManager] 📁 Created data directory: %@", dataPath);
    }

    NSError *contentsErr = nil;
    NSArray *contents = [fm contentsOfDirectoryAtPath:backupPath error:&contentsErr];
    if (contentsErr) {
        NSLog(@"[AppDataManager] ❌ Error reading backup: %@", contentsErr);
        return NO;
    }

    if (contents.count == 0) {
        NSLog(@"[AppDataManager] ⚠️ Backup is empty");
        return YES;
    }

    NSLog(@"[AppDataManager] 📦 Restoring %lu items from backup...", (unsigned long)contents.count);

    BOOL allSuccess = YES;
    NSUInteger successCount = 0;

    for (NSString *item in contents) {
        NSString *srcPath = [backupPath stringByAppendingPathComponent:item];
        NSString *dstPath = [dataPath stringByAppendingPathComponent:item];

        if ([fm fileExistsAtPath:dstPath]) {
            NSError *removeErr = nil;
            [fm removeItemAtPath:dstPath error:&removeErr];
        }

        NSError *copyErr = nil;
        BOOL copied = [fm copyItemAtPath:srcPath toPath:dstPath error:&copyErr];

        if (copied) {
            successCount++;
            NSDictionary *attrs = @{NSFileOwnerAccountName: @"mobile",
                                    NSFileGroupOwnerAccountName: @"mobile"};
            [fm setAttributes:attrs ofItemAtPath:dstPath error:nil];
        } else {
            NSLog(@"[AppDataManager] ⚠️ Failed to restore %@: %@", item, copyErr);
            allSuccess = NO;
        }
    }

    NSLog(@"[AppDataManager] %@ Restored %lu/%lu items for %@",
          allSuccess ? @"✅" : @"⚠️",
          (unsigned long)successCount,
          (unsigned long)contents.count,
          bundleID);

    return allSuccess;
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

#pragma mark - NEW UI Support Methods

- (UIImage *)iconForBundleID:(NSString *)bundleID {
    if (!bundleID) return nil;
    Class LSApplicationProxy_class = objc_getClass("LSApplicationProxy");
    if (LSApplicationProxy_class && [LSApplicationProxy_class respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
        id proxy = [LSApplicationProxy_class performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleID];
        if (proxy && [proxy respondsToSelector:@selector(iconDataForVariant:)]) {
            NSData *iconData = [proxy performSelector:@selector(iconDataForVariant:) withObject:@(2)];
            if (iconData) {
                return [UIImage imageWithData:iconData];
            }
        }
    }
    return nil;
}

- (NSString *)versionForBundleID:(NSString *)bundleID {
    if (!bundleID) return @"Unknown";
    Class LSApplicationProxy_class = objc_getClass("LSApplicationProxy");
    if (LSApplicationProxy_class && [LSApplicationProxy_class respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
        id proxy = [LSApplicationProxy_class performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleID];
        if (proxy && [proxy respondsToSelector:@selector(shortVersionString)]) {
            return [proxy performSelector:@selector(shortVersionString)] ?: @"Unknown";
        }
    }
    return @"Unknown";
}

- (NSString *)documentsPathForBundleID:(NSString *)bundleID {
    NSString *dataPath = [self dataPathForBundleID:bundleID];
    if (!dataPath) return nil;
    return [dataPath stringByAppendingPathComponent:@"Documents"];
}

- (NSUInteger)documentsCountForBundleID:(NSString *)bundleID {
    NSString *docsPath = [self documentsPathForBundleID:bundleID];
    if (!docsPath) return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm contentsOfDirectoryAtPath:docsPath error:nil];
    return contents.count;
}

- (NSDate *)lastBackupDateForBundleID:(NSString *)bundleID {
    NSArray *backups = [self availableBackupsForBundleID:bundleID];
    if (backups.count == 0) return nil;
    return backups[0][@"date"];
}

- (unsigned long long)totalBackupsSize {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *backupDir = [self backupDirectory];
    NSArray *contents = [fm contentsOfDirectoryAtPath:backupDir error:nil];
    unsigned long long total = 0;
    for (NSString *item in contents) {
        NSString *fullPath = [backupDir stringByAppendingPathComponent:item];
        NSArray *subpaths = [fm subpathsAtPath:fullPath];
        for (NSString *sub in subpaths) {
            NSDictionary *attrs = [fm attributesOfItemAtPath:[fullPath stringByAppendingPathComponent:sub] error:nil];
            total += [attrs fileSize];
        }
    }
    return total;
}

- (unsigned long long)totalAppsDataSize {
    NSArray *apps = [self allInstalledApplications];
    unsigned long long total = 0;
    for (NSDictionary *app in apps) {
        total += [app[@"size"] unsignedLongLongValue];
    }
    return total;
}

@end
