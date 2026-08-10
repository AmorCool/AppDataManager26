#import "InstallationProvider.h"

@implementation InstallationResult

+ (InstallationResult *)successResult:(NSString *)msg {
    InstallationResult *r = [[InstallationResult alloc] init];
    r.success = YES;
    r.message = msg;
    return r;
}

+ (InstallationResult *)failureResult:(NSString *)msg error:(NSError *)error {
    InstallationResult *r = [[InstallationResult alloc] init];
    r.success = NO;
    r.message = msg;
    r.error = error;
    return r;
}

@end
