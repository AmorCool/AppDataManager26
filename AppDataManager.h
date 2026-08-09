#import <UIKit/UIKit.h>

@interface AppDataManager : NSObject

+ (instancetype)sharedManager;

// جلب كل التطبيقات المثبتة (سريع - بدون حساب الحجم)
- (NSArray *)allInstalledApplications;

// حساب الأحجام في الخلفية
- (void)calculateSizesForApps:(NSArray *)apps completion:(void (^)(void))completion;
- (void)calculateSizeForBundleID:(NSString *)bundleID completion:(void (^)(unsigned long long size, NSString *sizeString))completion;

// مسار بيانات التطبيق (Sandbox)
- (NSString *)dataPathForBundleID:(NSString *)bundleID;

// حجم بيانات التطبيق
- (unsigned long long)dataSizeForBundleID:(NSString *)bundleID;

// مسح بيانات التطبيق
- (BOOL)wipeAppData:(NSString *)bundleID;

// نسخ احتياطي
- (BOOL)backupAppData:(NSString *)bundleID;
- (BOOL)restoreAppData:(NSString *)bundleID fromBackup:(NSString *)backupPath;

// قائمة النسخ الاحتياطية المتوفرة
- (NSArray *)availableBackupsForBundleID:(NSString *)bundleID;

// حذف نسخة احتياطية
- (BOOL)deleteBackup:(NSString *)backupPath;

// === UI Support Methods ===
- (UIImage *)iconForBundleID:(NSString *)bundleID;
- (NSString *)versionForBundleID:(NSString *)bundleID;
- (NSString *)documentsPathForBundleID:(NSString *)bundleID;
- (NSUInteger)documentsCountForBundleID:(NSString *)bundleID;
- (NSDate *)lastBackupDateForBundleID:(NSString *)bundleID;
- (unsigned long long)totalBackupsSize;
- (unsigned long long)totalAppsDataSize;

// Format bytes helper
- (NSString *)formatBytes:(unsigned long long)bytes;

// Cache management
- (void)clearCache;

// System app protection
- (BOOL)isSystemApp:(NSString *)bundleID;

@end
