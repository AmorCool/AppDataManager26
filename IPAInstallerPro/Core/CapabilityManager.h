#import <Foundation/Foundation.h>

@interface Capability : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *identifier;
@property (nonatomic, assign) BOOL isAvailable;
@property (nonatomic, strong) NSString *version;
@property (nonatomic, strong) NSString *statusMessage;
@property (nonatomic, strong) NSString *path;
@end

@interface CapabilityManager : NSObject
+ (instancetype)sharedManager;
- (void)scanCapabilities;
- (NSArray<Capability *> *)allCapabilities;
- (Capability *)capabilityForIdentifier:(NSString *)identifier;
- (BOOL)isAppSyncAvailable;
- (BOOL)isAppInstAvailable;
- (BOOL)isUnzipAvailable;
- (BOOL)isSystemInstallationAvailable;
- (NSString *)installationReadinessStatus;
- (BOOL)canInstallIPA;
@end
