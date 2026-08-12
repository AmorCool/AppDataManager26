//
//  InstallationEngine.m
//  IPAInstallerPro
//
//  Updated v1.1.0 — Live Logger Integration + Provider Selection
//

#import "InstallationEngine.h"
#import "DirectInstallationProvider.h"
#import "SystemInstallationProvider.h"
#import "AppInstInstallationProvider.h"
#import "LiveInstallationLogger.h"
#import <Foundation/Foundation.h>

@interface InstallationEngine ()
@property (nonatomic, strong) NSArray<id<InstallationProvider>> *providers;
@property (nonatomic, strong) LiveInstallationLogger *logger;
@end

@implementation InstallationEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _providers = @[
            [[DirectInstallationProvider alloc] init],
            [[AppInstInstallationProvider alloc] init],
            [[SystemInstallationProvider alloc] init]
        ];
        _logger = [LiveInstallationLogger sharedLogger];
    }
    return self;
}

- (int)installIPAAtPath:(NSString *)ipaPath progress:(void(^)(float))progress {
    // Extract basic info for logging
    NSString *bundleID = [self extractBundleID:ipaPath];
    [self.logger beginSessionWithBundleID:bundleID sourcePath:ipaPath];
    [self.logger logInfo:[NSString stringWithFormat:@"InstallationEngine starting for %@", bundleID]];

    // Score and select best provider
    NSMutableArray *scores = [NSMutableArray array];
    for (id<InstallationProvider> provider in self.providers) {
        int score = [provider scoreForEnvironment];
        NSString *name = NSStringFromClass([provider class]);
        [self.logger logInfo:[NSString stringWithFormat:@"Provider %@ score=%d", name, score]];
        [scores addObject:@(score)];
    }

    // Find provider with highest score
    int bestScore = -1;
    id<InstallationProvider> bestProvider = nil;
    for (int i = 0; i < self.providers.count; i++) {
        int score = [scores[i] intValue];
        if (score > bestScore) {
            bestScore = score;
            bestProvider = self.providers[i];
        }
    }

    if (!bestProvider || bestScore < 0) {
        [self.logger logCritical:@"No suitable installation provider found"];
        [self.logger endSession];
        return -1;
    }

    NSString *providerName = NSStringFromClass([bestProvider class]);
    [self.logger logInfo:[NSString stringWithFormat:@"Selected provider: %@ (score=%d)", providerName, bestScore]];

    // Determine destination
    NSString *appPath = [self determineAppPath:ipaPath bundleID:bundleID];
    [self.logger logInfo:[NSString stringWithFormat:@"Destination path: %@", appPath]];

    // Install
    int result = [bestProvider installIPA:ipaPath toApp:appPath progress:progress];

    if (result != 0) {
        [self.logger logError:[NSString stringWithFormat:@"Provider %@ failed with code %d", providerName, result]];

        // Try fallback providers
        for (id<InstallationProvider> provider in self.providers) {
            if (provider == bestProvider) continue;
            NSString *fallbackName = NSStringFromClass([provider class]);
            [self.logger logWarning:[NSString stringWithFormat:@"Trying fallback: %@", fallbackName]];
            int fallbackResult = [provider installIPA:ipaPath toApp:appPath progress:progress];
            if (fallbackResult == 0) {
                [self.logger logInfo:[NSString stringWithFormat:@"Fallback %@ succeeded", fallbackName]];
                [self.logger endSession];
                return 0;
            }
            [self.logger logError:[NSString stringWithFormat:@"Fallback %@ also failed: %d", fallbackName, fallbackResult]];
        }
    } else {
        [self.logger logInfo:[NSString stringWithFormat:@"Provider %@ succeeded", providerName]];
    }

    [self.logger endSession];
    return result;
}

- (NSString *)extractBundleID:(NSString *)ipaPath {
    // Quick extraction — in real implementation, use IPAExtractor
    return @"com.unknown.app";
}

- (NSString *)determineAppPath:(NSString *)ipaPath bundleID:(NSString *)bundleID {
    NSString *appName = [bundleID lastPathComponent];
    if (!appName || appName.length == 0) appName = @"App";
    return [@"/Applications" stringByAppendingPathComponent:[appName stringByAppendingString:@".app"]];
}

@end
