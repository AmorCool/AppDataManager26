#import <Foundation/Foundation.h>

@class InstallationResult;

@protocol InstallationProvider <NSObject>
@required
- (NSString *)providerName;
- (NSString *)providerDescription;
- (BOOL)isAvailable;
- (NSInteger)priority;
- (void)installIPA:(NSString *)ipaPath
        completion:(void (^)(InstallationResult *result))completion;
- (void)uninstallAppWithBundleID:(NSString *)bundleID
                      completion:(void (^)(BOOL success, NSString *error))completion;
@end

@interface InstallationResult : NSObject
@property (nonatomic, assign) BOOL success;
@property (nonatomic, strong) NSString *message;
@property (nonatomic, strong) NSString *detailedOutput;
@property (nonatomic, strong) NSString *bundleID;
@property (nonatomic, strong) NSError *error;
+ (InstallationResult *)successResult:(NSString *)msg;
+ (InstallationResult *)failureResult:(NSString *)msg error:(NSError *)error;
@end
