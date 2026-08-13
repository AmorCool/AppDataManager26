//
// SettingsViewController.m
// IPA Installer Pro
//
// v2.3 — Fixed with correct property names
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
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *envHeader;
@property (nonatomic, strong) UITextView *envTextView;
@property (nonatomic, strong) UILabel *capHeader;
@property (nonatomic, strong) UITextView *capTextView;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"الإعدادات";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    [self setupUI];
    [self refreshData];
}

- (void)setupUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    self.envHeader = [[UILabel alloc] init];
    self.envHeader.text = @"🔧 بيئة التشغيل";
    self.envHeader.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.envHeader.textColor = [UIColor whiteColor];
    self.envHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.envHeader];

    self.envTextView = [[UITextView alloc] init];
    self.envTextView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.envTextView.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    self.envTextView.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.envTextView.editable = NO;
    self.envTextView.selectable = YES;
    self.envTextView.layer.cornerRadius = 10;
    self.envTextView.textAlignment = NSTextAlignmentRight;
    self.envTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.envTextView];

    self.capHeader = [[UILabel alloc] init];
    self.capHeader.text = @"⚙️ القدرات";
    self.capHeader.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.capHeader.textColor = [UIColor whiteColor];
    self.capHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.capHeader];

    self.capTextView = [[UITextView alloc] init];
    self.capTextView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.capTextView.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    self.capTextView.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.capTextView.editable = NO;
    self.capTextView.selectable = YES;
    self.capTextView.layer.cornerRadius = 10;
    self.capTextView.textAlignment = NSTextAlignmentRight;
    self.capTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.capTextView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:16],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:16],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-16],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-16],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-32],

        [self.envHeader.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.envHeader.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.envHeader.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

        [self.envTextView.topAnchor constraintEqualToAnchor:self.envHeader.bottomAnchor constant:8],
        [self.envTextView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.envTextView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.envTextView.heightAnchor constraintEqualToConstant:200],

        [self.capHeader.topAnchor constraintEqualToAnchor:self.envTextView.bottomAnchor constant:24],
        [self.capHeader.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.capHeader.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

        [self.capTextView.topAnchor constraintEqualToAnchor:self.capHeader.bottomAnchor constant:8],
        [self.capTextView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.capTextView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.capTextView.heightAnchor constraintEqualToConstant:250],
        [self.capTextView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    ]];
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

    self.envTextView.text = envStr;

    NSMutableString *capStr = [NSMutableString string];
    [capStr appendFormat:@"%@\n", [cap installationReadinessStatus]];
    [capStr appendString:@"\n=== Tools ===\n"];
    for (Capability *c in [cap allCapabilities]) {
        NSString *icon = c.isAvailable ? @"✅" : @"❌";
        [capStr appendFormat:@"%@ %@: %@\n", icon, c.name, c.statusMessage];
    }

    self.capTextView.text = capStr;
}

@end
