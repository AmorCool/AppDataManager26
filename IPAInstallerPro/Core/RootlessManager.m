#import "RootlessManager.h"
#import "JailbreakEnvironment.h"
#import "Logger.h"
#import "rootless.h"

@implementation RootlessManager

+ (instancetype)sharedManager {
    static RootlessManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (NSString *)resolvePath:(NSString *)logicalPath {
    if (!logicalPath || logicalPath.length == 0) return logicalPath;
    return ROOT_PATH_NS(logicalPath);
}

- (BOOL)fileExistsAtLogicalPath:(NSString *)path {
    NSString *resolved = [self resolvePath:path];
    return [[NSFileManager defaultManager] fileExistsAtPath:resolved];
}

- (BOOL)createDirectoryAtLogicalPath:(NSString *)path error:(NSError **)error {
    NSString *resolved = [self resolvePath:path];
    return [[NSFileManager defaultManager] createDirectoryAtPath:resolved
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:error];
}

@end
