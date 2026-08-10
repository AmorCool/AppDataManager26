#import "SystemInstallationProvider.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import "Logger.h"
#import "RootlessManager.h"

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

        NSURL *ipaURL = [NSURL fileURLWithPath:ipaPath];
        NSMutableDictionary *options = [NSMutableDictionary dictionary];
        options[@"PackageType"] = @"User";
        options[@"ApplicationType"] = @"User";

        BOOL installed = NO;
        NSString *errorMsg = nil;

        @try {
            // Try installApplication:withOptions:error: using objc_msgSend
            SEL installSel = NSSelectorFromString(@"installApplication:withOptions:error:");
            if ([workspace respondsToSelector:installSel]) {
                typedef BOOL (*InstallMethod)(id, SEL, NSURL *, NSDictionary *, NSError **);
                InstallMethod method = (InstallMethod)objc_msgSend;
                NSError *installError = nil;
                installed = method(workspace, installSel, ipaURL, options, &installError);
                if (!installed && installError) {
                    errorMsg = installError.localizedDescription;
                }
            }
            // Try installApplication:withOptions:
            else {
                SEL installSel2 = NSSelectorFromString(@"installApplication:withOptions:");
                if ([workspace respondsToSelector:installSel2]) {
                    typedef BOOL (*InstallMethod2)(id, SEL, NSURL *, NSDictionary *);
                    InstallMethod2 method2 = (InstallMethod2)objc_msgSend;
                    installed = method2(workspace, installSel2, ipaURL, options);
                }
                // Try installApplication:
                else {
                    SEL installSel3 = NSSelectorFromString(@"installApplication:");
                    if ([workspace respondsToSelector:installSel3]) {
                        typedef BOOL (*InstallMethod3)(id, SEL, NSURL *);
                        InstallMethod3 method3 = (InstallMethod3)objc_msgSend;
                        installed = method3(workspace, installSel3, ipaURL);
                    }
                    else {
                        errorMsg = @"لا توجد طريقة تثبيت متاحة عبر النظام";
                    }
                }
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

        BOOL success = NO;
        @try {
            SEL uninstallSel = NSSelectorFromString(@"uninstallApplication:");
            if ([workspace respondsToSelector:uninstallSel]) {
                typedef BOOL (*UninstallMethod)(id, SEL, NSString *);
                UninstallMethod method = (UninstallMethod)objc_msgSend;
                success = method(workspace, uninstallSel, bundleID);
            } else {
                SEL uninstallSel2 = NSSelectorFromString(@"uninstallApplication:withOptions:");
                if ([workspace respondsToSelector:uninstallSel2]) {
                    typedef BOOL (*UninstallMethod2)(id, SEL, NSString *, NSDictionary *);
                    UninstallMethod2 method2 = (UninstallMethod2)objc_msgSend;
                    success = method2(workspace, uninstallSel2, bundleID, @{});
                }
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
