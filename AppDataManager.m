#import "AppDataManager.h"
#import <rootless.h>
#import <dlfcn.h>

// Private API Headers
@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSArray *iconDataSources;
@property (nonatomic, readonly) NSString *applicationType; // User, System, Internal
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (NSArray *)allApplications;
@end

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
    LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
    NSArray *apps = [workspace allInstalledApplications];

    NSMutableArray *appList = [NSMutableArray array];
    for (LSApplicationProxy *app in apps) {
        if (app.bundleIdentifier && app.localizedName) {
            NSString *appType = @"User";
            if ([app respondsToSelector:@selector(applicationType)]) {
                appType = app.applicationType ?: @"User";
            }

            unsigned long long size = [self dataSizeForBundleID:app.bundleIdentifier];
            NSString *sizeStr = [self formatBytes:size];

            [appList addObject:@{
                @"name": app.localizedName,
                @"bundleID": app.bundleIdentifier,
                @"type": appType,
                @"size": @(size),
                @"sizeString": sizeStr,
                @"hasBackup": @([self availableBackupsForBundleID:app.bundleIdentifier].count > 0)
            }];
        }
    }

    return [appList sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] compare:b[@"name"]];
    }];
}

- (NSString *)dataPathForBundleID:(NSString *)bundleID {
    dlopen("/System/Library/PrivateFrameworks/MobileContainerManager.framework/MobileContainerManager", RTLD_NOW);

    Class MCMAppDataContainer = NSClassFromString(@"MCMAppDataContainer");
    if (MCMAppDataContainer) {
        NSError *error = nil;
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id container = [MCMAppDataContainer performSelector:@selector(containerWithIdentifier:error:)
                                                  withObject:bundleID
                                                  withObject:error];
        #pragma clang diagnostic pop
        if (container) {
            return [container valueForKey:@"path"];
        }
    }

    // Fallback
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

    return nil;
}

- (unsigned long long)dataSizeForBundleID:(NSString *)bundleID {
    NSString *path = [self dataPathForBundleID:bundleID];
    if (!path) return 0;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm subpathsAtPath:path];
    unsigned long long totalSize = 0;

    for (NSString *item in contents) {
        NSString *fullPath = [path stringByAppendingPathComponent:item];
        NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
        if (attrs) {
            totalSize += [attrs fileSize];
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
        if ([item hasPrefix:@"."]) continue; // تجاهل الملفات المخفية
        NSString *fullPath = [dataPath stringByAppendingPathComponent:item];
        BOOL success = [fm removeItemAtPath:fullPath error:&error];
        if (!success) {
            NSLog(@"[AppDataManager] ⚠️ Failed to remove %@: %@", item, error);
            allSuccess = NO;
        }
    }

    NSLog(@"[AppDataManager] %@ Wiped data for: %@", allSuccess ? @"✅" : @"⚠️", bundleID);
    return allSuccess;
}

- (NSArray<NSDictionary *> *)availableBackupsForBundleID:(NSString *)bundleID {
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
        return [b[@"date"] compare:a[@"date"]]; // الأحدث أولاً
    }];
}

- (BOOL)restoreAppData:(NSString *)bundleID fromBackup:(NSString *)backupPath {
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

    return success;
}

- (BOOL)deleteBackup:(NSString *)backupPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    BOOL success = [fm removeItemAtPath:backupPath error:&error];
    if (!success) {
        NSLog(@"[AppDataManager] ❌ Failed to delete backup: %@", error);
    }
    return success;
}

@end
