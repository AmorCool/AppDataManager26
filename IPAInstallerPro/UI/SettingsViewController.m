//
// SettingsViewController.m
// IPA Installer Pro
//
// v2.4 — Frame-based layout for reliability
//

#import "SettingsViewController.h"
#import "CapabilityManager.h"
#import "JailbreakEnvironment.h"
#import "RootlessManager.h"
#import "Logger.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface SettingsViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *envLabel;
@property (nonatomic, strong) UILabel *capLabel;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"الإعدادات";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat top = 20;
    if (@available(iOS 11.0, *)) {
        top = self.view.safeAreaInsets.top + 20;
    }

    // ScrollView
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.scrollView];

    // Environment Header
    UILabel *envHeader = [[UILabel alloc] initWithFrame:CGRectMake(16, top, w - 32, 30)];
    envHeader.text = @"🔧 بيئة التشغيل";
    envHeader.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    envHeader.textColor = [UIColor whiteColor];
    envHeader.textAlignment = NSTextAlignmentRight;
    envHeader.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.scrollView addSubview:envHeader];

    // Environment Info
    self.envLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, top + 40, w - 32, 200)];
    self.envLabel.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.envLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    self.envLabel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.envLabel.layer.cornerRadius = 10;
    self.envLabel.clipsToBounds = YES;
    self.envLabel.numberOfLines = 0;
    self.envLabel.textAlignment = NSTextAlignmentRight;
    self.envLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.scrollView addSubview:self.envLabel];

    // Capabilities Header
    UILabel *capHeader = [[UILabel alloc] initWithFrame:CGRectMake(16, top + 260, w - 32, 30)];
    capHeader.text = @"⚙️ القدرات";
    capHeader.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    capHeader.textColor = [UIColor whiteColor];
    capHeader.textAlignment = NSTextAlignmentRight;
    capHeader.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.scrollView addSubview:capHeader];

    // Capabilities Info
    self.capLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, top + 300, w - 32, 300)];
    self.capLabel.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.capLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    self.capLabel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.capLabel.layer.cornerRadius = 10;
    self.capLabel.clipsToBounds = YES;
    self.capLabel.numberOfLines = 0;
    self.capLabel.textAlignment = NSTextAlignmentRight;
    self.capLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.scrollView addSubview:self.capLabel];

    [self refreshData];

    // Set scroll content size
    self.scrollView.contentSize = CGSizeMake(w, top + 620);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    self.scrollView.frame = CGRectMake(0, 0, w, h);
}

- (void)refreshData {
    JailbreakEnvironment *env = [JailbreakEnvironment sharedEnvironment];
    CapabilityManager *cap = [CapabilityManager sharedManager];

    NSMutableString *envStr = [NSMutableString string];
    [envStr appendFormat:@"Jailbreak: %@\n", env.jailbreakType ?: @"Unknown"];
    [envStr appendFormat:@"Rootless: %@\n", env.isRootless ? @"Yes" : @"No"];
    [envStr appendFormat:@"OS Version: %@\n", env.osVersion ?: @"Unknown"];
    [envStr appendFormat:@"Device: %@\n", env.deviceModel ?: @"Unknown"];
    [envStr appendFormat:@"Applications: %@\n", env.applicationsPath ?: @"N/A"];
    [envStr appendFormat:@"usr/bin: %@\n", env.usrBinPath ?: @"N/A"];
    [envStr appendFormat:@"Documents: %@\n", env.mobileDocumentsPath ?: @"N/A"];
    [envStr appendFormat:@"Root Path: %@\n", env.rootPath ?: @"N/A"];

    self.envLabel.text = envStr;

    NSMutableString *capStr = [NSMutableString string];
    [capStr appendFormat:@"%@\n", [cap installationReadinessStatus]];
    [capStr appendString:@"\n=== Tools ===\n"];
    for (Capability *c in [cap allCapabilities]) {
        NSString *icon = c.isAvailable ? @"✅" : @"❌";
        [capStr appendFormat:@"%@ %@: %@\n", icon, c.name, c.statusMessage];
    }

    self.capLabel.text = capStr;
}

@end
