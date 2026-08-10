#import "AppInstInstallationProvider.h"
#import "Logger.h"
#import "RootlessManager.h"
#import "JailbreakEnvironment.h"
#include <spawn.h>
#include <unistd.h>
#include <sys/wait.h>

@implementation AppInstInstallationProvider

- (NSString *)providerName { return @"appinst"; }
- (NSString *)providerDescription { return @"أداة سطر أوامر لتثبيت IPA"; }
- (NSInteger)priority { return 100; }

- (BOOL)isAvailable {
    return [[RootlessManager sharedManager] fileExistsAtLogicalPath:@"/usr/bin/appinst"];
}

- (void)installIPA:(NSString *)ipaPath completion:(void (^)(InstallationResult *))completion {
    if (!completion) return;

    [[Logger sharedLogger] info:[NSString stringWithFormat:@"AppInst: Installing %@", ipaPath]];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *appinstPath = [[RootlessManager sharedManager] resolvePath:@"/usr/bin/appinst"];

        // Use posix_spawn instead of NSTask for better compatibility
        const char *path = appinstPath.UTF8String;
        const char *args[] = { path, "-i", ipaPath.UTF8String, NULL };

        pid_t pid;
        int status;

        posix_spawn_file_actions_t action;
        posix_spawn_file_actions_init(&action);

        // Create pipe for output
        int pipefd[2];
        pipe(pipefd);
        posix_spawn_file_actions_adddup2(&action, pipefd[1], STDOUT_FILENO);
        posix_spawn_file_actions_adddup2(&action, pipefd[1], STDERR_FILENO);
        posix_spawn_file_actions_addclose(&action, pipefd[0]);

        int ret = posix_spawn(&pid, path, &action, NULL, (char **)args, NULL);
        posix_spawn_file_actions_destroy(&action);
        close(pipefd[1]);

        if (ret != 0) {
            close(pipefd[0]);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([InstallationResult failureResult:@"فشل في تشغيل محرك التثبيت"
                                                      error:[NSError errorWithDomain:@"IPAInstallerPro"
                                                                                code:ret
                                                                            userInfo:@{NSLocalizedDescriptionKey: @"posix_spawn failed"}]]);
            });
            return;
        }

        // Read output
        NSMutableData *outputData = [NSMutableData data];
        char buffer[1024];
        ssize_t n;
        while ((n = read(pipefd[0], buffer, sizeof(buffer))) > 0) {
            [outputData appendBytes:buffer length:n];
        }
        close(pipefd[0]);

        waitpid(pid, &status, 0);

        NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] ?: @"";
        BOOL success = (WIFEXITED(status) && WEXITSTATUS(status) == 0);

        [[Logger sharedLogger] info:[NSString stringWithFormat:@"AppInst exit status: %d, output length: %lu", 
            WEXITSTATUS(status), (unsigned long)output.length]];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                InstallationResult *result = [InstallationResult successResult:@"تم التثبيت بنجاح"];
                result.detailedOutput = output;
                completion(result);
            } else {
                NSString *errorMsg = output.length > 0 ? output : @"فشل التثبيت دون رسائل خطأ";
                InstallationResult *result = [InstallationResult failureResult:@"فشل في تثبيت التطبيق"
                                                                         error:[NSError errorWithDomain:@"IPAInstallerPro"
                                                                                                   code:WEXITSTATUS(status)
                                                                                               userInfo:@{NSLocalizedDescriptionKey: errorMsg}]];
                result.detailedOutput = output;
                completion(result);
            }
        });
    });
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    if (!completion) return;
    // appinst doesn't support uninstall directly, use system method
    [[Logger sharedLogger] warning:@"AppInst provider does not support uninstall"];
    completion(NO, @"محرك appinst لا يدعم الحذف المباشر");
}

@end
