//
//  InstallationEngine.m
//  IPAInstallerPro
//
//  v2.0 — OperationLog is the source of truth for every installation
//

#import "InstallationEngine.h"
#import "IPAValidator.h"
#import "DirectInstallationProvider.h"
#import "SystemInstallationProvider.h"
#import "AppInstInstallationProvider.h"
#import "OperationLog.h"
#import "Logger.h"
#import <Foundation/Foundation.h>

@interface InstallationEngine ()
@property (nonatomic, strong) NSMutableArray<id<InstallationProvider>> *providers;
@property (nonatomic, strong) NSString *activeTxnID;
@property (nonatomic, strong) OperationLog *opLog;
@end

@implementation InstallationEngine

+ (instancetype)sharedEngine {
    static InstallationEngine *s = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.providers = [NSMutableArray array];
        self.opLog = [OperationLog sharedLog];
        [self registerDefaultProviders];
    }
    return self;
}

- (void)registerDefaultProviders {
    [self registerProvider:[[DirectInstallationProvider alloc] init]];
    [self registerProvider:[[AppInstInstallationProvider alloc] init]];
    [self registerProvider:[[SystemInstallationProvider alloc] init]];
}

- (void)registerProvider:(id<InstallationProvider>)provider {
    if (provider && ![self.providers containsObject:provider]) [self.providers addObject:provider];
}

- (NSArray<id<InstallationProvider>> *)availableProviders {
    NSMutableArray *a = [NSMutableArray array];
    for (id p in self.providers) if ([p isAvailable]) [a addObject:p];
    return a;
}

- (id<InstallationProvider>)bestProvider {
    NSArray *a = [self availableProviders];
    if (a.count == 0) return nil;
    NSArray *s = [a sortedArrayUsingComparator:^NSComparisonResult(id x, id y) {
        return [@([y priority]) compare:@([x priority])];
    }];
    // Prefer Direct Install
    for (id p in s) if ([[p providerName] isEqualToString:@"Direct Install"]) return p;
    return s.firstObject;
}

- (NSString *)currentProviderName {
    id p = [self bestProvider];
    return p ? [p providerName] : @"No provider available";
}

- (NSString *)stageDescription:(InstallationStage)stage {
    switch (stage) {
        case InstallationStageIdle: return @"Idle";
        case InstallationStagePreparing: return @"Preparing";
        case InstallationStageValidating: return @"Validating";
        case InstallationStageInstalling: return @"Installing";
        case InstallationStageRegistering: return @"Registering";
        case InstallationStageCompleted: return @"Completed";
        case InstallationStageFailed: return @"Failed";
        default: return @"Unknown";
    }
}

- (NSString *)activeTransactionID {
    return self.activeTxnID;
}

- (NSString *)transactionReport:(NSString *)txnID {
    return [self.opLog transactionReport:txnID];
}

#pragma mark - Main Install

- (void)installIPA:(NSString *)ipaPath
     progressBlock:(void (^)(InstallationStage, NSString *, float))progressBlock
        completion:(void (^)(InstallationResult *))completion {

    // 1. Validate IPA
    if (progressBlock) progressBlock(InstallationStageValidating, @"Validating IPA...", 0.05f);

    IPAValidator *v = [IPAValidator sharedValidator];
    IPAValidationResult *vr = [v validateIPAAtPath:ipaPath];

    if (vr.status != IPAValidationStatusValid) {
        NSString *msg = [NSString stringWithFormat:@"Validation failed: %@", [vr.issues componentsJoinedByString:@", "]];
        if (completion) completion([InstallationResult failureResult:msg provider:@"Engine" transaction:@"" error:nil evidence:@{@"validationIssues": vr.issues}]);
        return;
    }

    for (NSString *w in vr.issues) NSLog(@"[IPAInstallerPro] Warning: %@", w);

    // 2. Begin OperationLog transaction
    NSString *txnID = [self.opLog beginTransactionForIPA:ipaPath];
    self.activeTxnID = txnID;

    // 3. Get providers
    NSArray *providers = [self availableProviders];
    if (providers.count == 0) {
        [self.opLog endTransaction:txnID finalResult:OperationResultFailed];
        self.activeTxnID = nil;
        if (completion) completion([InstallationResult failureResult:@"No installation provider available" provider:@"Engine" transaction:txnID error:nil evidence:nil]);
        return;
    }

    // 4. Try providers with fallback chain
    [self tryProviders:providers forIPA:ipaPath transactionID:txnID attempt:0 progressBlock:progressBlock completion:completion];
}

- (void)tryProviders:(NSArray *)providers
             forIPA:(NSString *)ipaPath
      transactionID:(NSString *)txnID
            attempt:(NSInteger)attempt
      progressBlock:(void (^)(InstallationStage, NSString *, float))progressBlock
         completion:(void (^)(InstallationResult *))completion {

    if (attempt >= providers.count) {
        // All providers failed
        [self.opLog endTransaction:txnID finalResult:OperationResultFailed];
        self.activeTxnID = nil;

        // Build failure evidence from all attempts
        NSArray *failedRecords = [self.opLog failedRecordsInTransaction:txnID];
        NSMutableArray *attemptEvidence = [NSMutableArray array];
        for (OperationRecord *rec in failedRecords) {
            [attemptEvidence addObject:@{
                @"phase": [rec phaseName],
                @"operation": rec.operation,
                @"target": rec.target,
                @"exitCode": @(rec.exitCode),
                @"verified": @(rec.verified),
                @"error": rec.rawError ?: @""
            }];
        }

        if (completion) completion([InstallationResult failureResult:@"All providers failed"
                                                            provider:@"Engine"
                                                         transaction:txnID
                                                               error:nil
                                                            evidence:@{@"failedAttempts": attemptEvidence}]);
        return;
    }

    id<InstallationProvider> provider = providers[attempt];
    NSString *providerName = [provider providerName];

    if (progressBlock) progressBlock(InstallationStageInstalling,
                                     [NSString stringWithFormat:@"Installing via %@...", providerName],
                                     0.1f + (attempt * 0.1f));

    // Log provider attempt start
    NSString *attemptRec = [self.opLog beginPhase:OperationPhaseStart
                                        operation:[NSString stringWithFormat:@"PROVIDER_ATTEMPT_%@", providerName]
                                           target:ipaPath
                                            input:@""
                                    transactionID:txnID];

    [provider installIPA:ipaPath operationLog:self.opLog completion:^(InstallationResult *result) {

        // End attempt record
        [self.opLog endPhase:attemptRec
                    exitCode:result.success ? 0 : 1
                   rawOutput:result.detailedOutput ?: @""
                    rawError:result.success ? @"" : result.message
                verification:[NSString stringWithFormat:@"provider=%@ success=%@", providerName, result.success ? @"YES" : @"NO"]
                    verified:result.success
                    duration:0];

        if (result.success) {
            // Success! End transaction
            [self.opLog endTransaction:txnID finalResult:OperationResultSuccess];
            self.activeTxnID = nil;

            if (progressBlock) progressBlock(InstallationStageCompleted, @"Installation complete!", 1.0f);
            if (completion) completion(result);
        } else {
            // Provider failed — log and try next
            NSLog(@"[IPAInstallerPro] %@ failed: %@", providerName, result.message);

            if (progressBlock) progressBlock(InstallationStageInstalling,
                                             [NSString stringWithFormat:@"%@ failed, trying next...", providerName],
                                             0.1f + (attempt * 0.1f));

            [self tryProviders:providers forIPA:ipaPath transactionID:txnID attempt:attempt + 1 progressBlock:progressBlock completion:completion];
        }
    }];
}

- (void)uninstallAppWithBundleID:(NSString *)bundleID completion:(void (^)(BOOL, NSString *))completion {
    id p = [self bestProvider];
    if (!p) { if (completion) completion(NO, @"No provider available"); return; }
    [p uninstallAppWithBundleID:bundleID completion:completion];
}

@end
