#import "InstallationProvider.h"

@implementation InstallationResult

+ (InstallationResult *)successResult:(NSString *)msg {
    InstallationResult *result = [[InstallationResult alloc] init];
    result.success = YES;
    result.message = msg ?: @"Success";
    result.detailedOutput = msg ?: @"Success";
    result.bundleID = nil;
    result.error = nil;
    return result;
}

+ (InstallationResult *)failureResult:(NSString *)msg error:(NSError *)error {
    InstallationResult *result = [[InstallationResult alloc] init];
    result.success = NO;
    result.message = msg ?: @"Unknown error";
    result.detailedOutput = msg ?: @"Unknown error";
    result.bundleID = nil;
    result.error = error;
    return result;
}

@end
