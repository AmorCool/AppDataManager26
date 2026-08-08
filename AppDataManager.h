#import <Foundation/Foundation.h>

@interface AppDataManager : NSObject

+ (instancetype)sharedManager;

// جلب كل التطبيقات المثبتة
- (NSArray<NSDictionary *> *)allInstalledApplications;

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
- (NSArray<NSDictionary *> *)availableBackupsForBundleID:(NSString *)bundleID;

// حذف نسخة احتياطية
- (BOOL)deleteBackup:(NSString *)backupPath;

@end
