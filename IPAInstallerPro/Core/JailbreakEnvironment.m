#import "JailbreakEnvironment.h"
#import "Logger.h"
#import "rootless.h"
#include <sys/utsname.h>

@interface JailbreakEnvironment ()
@property (readwrite, nonatomic) BOOL isJailbroken;
@property (readwrite, nonatomic) BOOL isRootless;
@property (readwrite, nonatomic) NSString *jailbreakType;
@property (readwrite, nonatomic) NSString *rootPath;
@property (readwrite, nonatomic) NSString *applicationsPath;
@property (readwrite, nonatomic) NSString *usrBinPath;
@property (readwrite, nonatomic) NSString *mobileDocumentsPath;
@property (readwrite, nonatomic) NSString *osVersion;
@property (readwrite, nonatomic) NSString *deviceModel;
@end

@implementation JailbreakEnvironment

+ (instancetype)sharedEnvironment {
    static JailbreakEnvironment *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (void)detectEnvironment {
    [[Logger sharedLogger] info:@"Detecting jailbreak environment..."];

    // Detect rootless
    self.isRootless = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"];
    self.rootPath = self.isRootless ? @"/var/jb" : @"";

    // Detect jailbreak type
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/bin/dopamine"]) {
        self.jailbreakType = @"Dopamine";
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/.installed_unc0ver"]) {
        self.jailbreakType = @"unc0ver";
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/.installed_taurine"]) {
        self.jailbreakType = @"Taurine";
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/.installed_xina"]) {
        self.jailbreakType = @"XinaA15";
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/bin/ellekit"]) {
        self.jailbreakType = @"Dopamine/ElleKit";
    } else {
        self.jailbreakType = @"Unknown";
    }

    self.isJailbroken = self.isRootless || [[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/ldid"];

    // Paths
    self.applicationsPath = ROOT_PATH_NS(@"/Applications");
    self.usrBinPath = ROOT_PATH_NS(@"/usr/bin");
    self.mobileDocumentsPath = @"/var/mobile/Documents";

    // Device info
    self.osVersion = [[UIDevice currentDevice] systemVersion];
    struct utsname systemInfo;
    uname(&systemInfo);
    self.deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];

    [[Logger sharedLogger] info:[NSString stringWithFormat:@"Environment: %@, Rootless: %@, iOS: %@, Device: %@",
        self.jailbreakType, self.isRootless ? @"YES" : @"NO", self.osVersion, self.deviceModel]];
}

@end
