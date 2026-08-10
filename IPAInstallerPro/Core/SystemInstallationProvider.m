#import "SystemInstallationProvider.h"
#import <objc/runtime.h>
#import "Logger.h"
#import "RootlessManager.h"
#include <spawn.h>
#include <sys/wait.h>

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

        // Try installApplication:withOptions:error: or installApplication:withOptions:
        BOOL installed = NO;
        NSString *errorMsg = nil;

        @try {
            // Method 1: installApplication:withOptions:error: (iOS 11+)
            if ([workspace respondsToSelector:@selector(installApplication:withOptions:error:)]) {
                NSURL *ipaURL = [NSURL fileURLWithPath:ipaPath];
                NSMutableDictionary *options = [NSMutableDictionary dictionary];
                options[@"PackageType"] = @"User";
                options[@"ApplicationType"] = @"User";

                NSError *installError = nil;
                installed = [workspace installApplication:ipaURL withOptions:options error:&installError];
                if (!installed && installError) {
                    errorMsg = installError.localizedDescription;
                }
            }
            // Method 2: installApplication:withOptions: (older iOS)
            else if ([workspace respondsToSelector:@selector(installApplication:withOptions:)]) {
                NSURL *ipaURL = [NSURL fileURLWithPath:ipaPath];
                NSMutableDictionary *options = [NSMutableDictionary dictionary];
                options[@"PackageType"] = @"User";
                options[@"ApplicationType"] = @"User";

                installed = [workspace installApplication:ipaURL withOptions:options];
            }
            // Method 3: installApplication: (oldest)
            else if ([workspace respondsToSelector:@selector(installApplication:)]) {
                NSURL *ipaURL = [NSURL fileURLWithPath:ipaPath];
                installed = [workspace installApplication:ipaURL];
            }
            else {
                errorMsg = @"لا توجد طريقة تثبيت متاحة عبر النظام";
            }
        } @catch (NSException *e) {
            errorMsg = [NSString stringWithFormat:@"استثناء أثناء التثبيت: %@", e.reason];
            [[Logger sharedLogger] error:errorMsg];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (installed) {
                InstallationResult *result = [InstallationResult successResult:@"تم التثبيت عبر النظام بنجاح"];
                completion(result);
            } else {
                NSString *msg = errorMsg ?: @"فشل التثبيت عبر النظام";
                completion([InstallationResult failureResult:msg
                                                          error:[NSError errorWithDomain:@"IPAInstallerPro" code:-3 userInfo:@{NSLocalizedDescriptionKey: msg}]]);
            }
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
