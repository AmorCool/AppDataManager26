#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, IPAValidationStatus) {
    IPAValidationStatusUnknown = 0,
    IPAValidationStatusValid = 1,
    IPAValidationStatusInvalidZip = 2,
    IPAValidationStatusMissingPayload = 3,
    IPAValidationStatusMissingAppBundle = 4,
    IPAValidationStatusMissingInfoPlist = 5,
    IPAValidationStatusMissingExecutable = 6,
    IPAValidationStatusIncompatibleArchitecture = 7,
    IPAValidationStatusIncompatibleOS = 8,
    IPAValidationStatusInvalidBundleID = 9
};

@interface IPAValidationResult : NSObject
@property (nonatomic, assign) IPAValidationStatus status;
@property (nonatomic, strong) NSString *statusMessage;
@property (nonatomic, strong) NSArray<NSString *> *issues;
@property (nonatomic, assign) BOOL isReadyForInstall;
@end

@interface IPAValidator : NSObject
+ (instancetype)sharedValidator;
- (IPAValidationResult *)validateIPAAtPath:(NSString *)ipaPath;
- (IPAValidationResult *)validateExtractedAppAtPath:(NSString *)appPath;
@end
