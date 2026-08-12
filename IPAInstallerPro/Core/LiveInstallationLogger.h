//
//  LiveInstallationLogger.h
//  IPAInstallerPro
//
//  Created by System Architect
//  Copyright (c) 2026 AppDataManager. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * LiveInstallationLogger — نظام سجل تثبيت حي ومباشر
 * 
 * يتتبع كل خطوة في مسار التثبيت الحقيقي مع timestamps دقيقة
 * ويُرسل التحديثات إلى UI عبر delegate pattern
 */

@protocol LiveInstallationLoggerDelegate <NSObject>
@required
- (void)logger:(id)logger didAppendEntry:(NSString *)entry atIndex:(NSUInteger)index;
- (void)logger:(id)logger didUpdatePhase:(NSString *)phase status:(NSString *)status;
@end

typedef NS_ENUM(NSInteger, LiveLogLevel) {
    LiveLogLevelDebug = 0,
    LiveLogLevelInfo = 1,
    LiveLogLevelWarning = 2,
    LiveLogLevelError = 3,
    LiveLogLevelCritical = 4
};

typedef NS_ENUM(NSInteger, LiveLogPhase) {
    LiveLogPhaseNone = 0,
    LiveLogPhaseIPAOpen,
    LiveLogPhaseIPAExtract,
    LiveLogPhaseAppIdentify,
    LiveLogPhaseFileCopy,
    LiveLogPhasePermissionChmod,
    LiveLogPhasePermissionChown,
    LiveLogPhaseSignAll,
    LiveLogPhaseSignExe,
    LiveLogPhaseFramework,
    LiveLogPhaseUICache,
    LiveLogPhaseVerify,
    LiveLogPhaseCleanup,
    LiveLogPhaseComplete,
    LiveLogPhaseFailed
};

@interface LiveInstallationLogger : NSObject

@property (nonatomic, weak) id<LiveInstallationLoggerDelegate> delegate;
@property (nonatomic, readonly) NSArray<NSString *> *entries;
@property (nonatomic, readonly) LiveLogPhase currentPhase;
@property (nonatomic, readonly) NSString *currentPhaseName;
@property (nonatomic, readonly) NSString *targetBundleID;
@property (nonatomic, readonly) NSString *sourceIPAPath;
@property (nonatomic, readonly) NSString *destinationAppPath;
@property (nonatomic, readonly) NSDate *startTime;
@property (nonatomic, readonly) NSTimeInterval elapsedTime;
@property (nonatomic, readonly) BOOL hasErrors;
@property (nonatomic, readonly) NSUInteger errorCount;
@property (nonatomic, readonly) NSUInteger warningCount;

+ (instancetype)sharedLogger;

// Session lifecycle
- (void)beginSessionWithBundleID:(NSString *)bundleID sourcePath:(NSString *)sourcePath;
- (void)endSession;
- (void)resetSession;

// Phase transitions
- (void)enterPhase:(LiveLogPhase)phase;
- (void)enterPhase:(LiveLogPhase)phase withDetail:(NSString *)detail;

// Logging methods
- (void)logDebug:(NSString *)message;
- (void)logInfo:(NSString *)message;
- (void)logWarning:(NSString *)message;
- (void)logError:(NSString *)message;
- (void)logCritical:(NSString *)message;

// Structured logging with verification
- (void)logVerification:(NSString *)checkName result:(BOOL)passed detail:(NSString *)detail;
- (void)logFileOperation:(NSString *)operation path:(NSString *)path result:(BOOL)success error:(nullable NSString *)error;
- (void)logCommandExecution:(NSString *)command exitCode:(int)exitCode output:(nullable NSString *)output;
- (void)logStatResult:(NSString *)path mode:(mode_t)mode uid:(uid_t)uid gid:(gid_t)gid;
- (void)logAccessCheck:(NSString *)path mode:(int)mode result:(BOOL)accessible;

// Export
- (NSString *)fullLogText;
- (NSString *)jsonExport;
- (NSString *)markdownReport;
- (void)saveToFile:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
