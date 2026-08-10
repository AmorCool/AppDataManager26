#import "SystemInstallationProvider.h"
#import <objc/runtime.h>
#import "Logger.h"

@implementation SystemInstallationProvider

- (NSString *)providerName { return @"System"; }
- (NSString *)providerDescription { return @"تثبيت عبر نظام iOS"; }
- (NSInteger)priority { return 50; }

- (BOOL)isAvailable {
    // Check if we have LSApplicationWorkspace
    Class cls = objc_getClass("LSApplicationWorkspace");
    return cls != nil;
}

- (void)installIPA:(NSString *)ipaPath completion:(void (^)(InstallationResult *))completion {
    if (!completion) return;

    [[Logger sharedLogger] info:[NSString stringWithFormat:@"System: Installing %@", ipaPath]];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Try using LSApplicationWorkspace for installation
        Class LSApplicationWorkspace_class = objc_getClass("LSApplicationWorkspace");
        if (!LSApplicationWorkspace_class) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([InstallationResult failureResult:@"خدمة تثبيت النظام غير متوفرة"
                                                      error:[NSError errorWithDomain:@"IPAInstallerPro" code:-1 userInfo:nil]]);
            });
            return;
        }

        id workspace = [LSApplicationWorkspace_class performSelector:@selector(defaultWorkspace)];
        if (!workspace) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([InstallationResult failureResult:@"تعذر الوصول إلى مدير التطبيقات"
                                                      error:[NSError errorWithDomain:@"IPAInstallerPro" code:-2 userInfo:nil]]);
            });
            return;
        }

        // Try to install using openApplicationWithBundleID or similar
        // Note: Direct IPA installation via LSApplicationWorkspace is limited on modern iOS
        // This is a fallback provider

        dispatch_async(dispatch_get_main_queue(), ^{
            completion([InstallationResult failureResult:@"التثبيت المباشر عبر النظام غير مدعوم في هذا الإصدار"
                                                  error:[NSError errorWithDomain:@"IPAInstallerPro" code:-3 userInfo:nil]]);
        });
    });
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    if (!completion) return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        Class LSApplicationWorkspace_class = objc_getClass("LSApplicationWorkspace");
        if (!LSApplicationWorkspace_class) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"خدمة إدارة التطبيقات غير متوفرة");
            });
            return;
        }

        id workspace = [LSApplicationWorkspace_class performSelector:@selector(defaultWorkspace)];
        if (!workspace) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"تعذر الوصول إلى مدير التطبيقات");
            });
            return;
        }

        // Try uninstallApplication:
        BOOL success = NO;
        @try {
            if ([workspace respondsToSelector:@selector(uninstallApplication:)]) {
                success = [workspace performSelector:@selector(uninstallApplication:) withObject:bundleID];
            } else if ([workspace respondsToSelector:@selector(uninstallApplication:withOptions:)]) {
                success = [workspace performSelector:@selector(uninstallApplication:withOptions:) withObject:bundleID withObject:@{}];
            }
        } @catch (NSException *e) {
            [[Logger sharedLogger] error:[NSString stringWithFormat:@"Uninstall exception: %@", e.reason]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(success, success ? nil : @"فشل في حذف التطبيق");
        });
    });
}

@end
