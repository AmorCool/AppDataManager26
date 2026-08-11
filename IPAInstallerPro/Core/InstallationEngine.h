#import <Foundation/Foundation.h>
#import "InstallationProvider.h"

typedef NS_ENUM(NSInteger, InstallationStage) {
    InstallationStageIdle = 0,
    InstallationStagePreparing = 1,
    InstallationStageValidating = 2,
    InstallationStageInstalling = 3,
    InstallationStageRegistering = 4,
    InstallationStageCompleted = 5,
    InstallationStageFailed = 6
};

@interface InstallationEngine : NSObject
+ (instancetype)sharedEngine;
- (NSArray<id<InstallationProvider>> *)availableProviders;
- (id<InstallationProvider>)bestProvider;
- (void)installIPA:(NSString *)ipaPath
    progress:(void (^)(NSString *statusMessage))progress
       completion:(void (^)(InstallationResult *result))completion;
- (void)uninstallAppWithBundleID:(NSString *)bundleID
                      completion:(void (^)(BOOL success, NSString *error))completion;
- (NSString *)stageDescription:(InstallationStage)stage;
@end
