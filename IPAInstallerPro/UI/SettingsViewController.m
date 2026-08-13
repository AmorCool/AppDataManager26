//
// SettingsViewController.m
// IPA Installer Pro
//
// v2.1 — Standalone mode environment display
//

#import "SettingsViewController.h"
#import "CapabilityManager.h"
#import "JailbreakEnvironment.h"
#import "RootlessManager.h"
#import "Logger.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface SettingsViewController ()
@property (nonatomic, strong) UITextView *environmentTextView;
@property (nonatomic, strong) UISwitch *darkModeSwitch;
@property (nonatomic, strong) UISwitch *autoCleanSwitch;
@property (nonatomic, strong) UISwitch *verboseLogSwitch;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"الإعدادات";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self setupUI];
    [self refreshEnvironment];
}

- (void)setupUI {
    CGFloat w = self.view.bounds.size.width;
    CGFloat margin = 20;

    UILabel *envHeader = [[UILabel alloc] initWithFrame:CGRectMake(margin, 100, w - margin * 2, 24)];
    envHeader.text = @"🔧 بيئة التشغيل";
    envHeader.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    envHeader.textColor = [UIColor labelColor];
    [self.view addSubview:envHeader];

    self.environmentTextView = [[UITextView alloc] initWithFrame:CGRectMake(margin, 130, w - margin * 2, 280)];
    self.environmentTextView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.environmentTextView.textColor = [UIColor labelColor];
    self.environmentTextView.font = [UIFont systemFontOfSize:13];
    self.environmentTextView.editable = NO;
    self.environmentTextView.layer.cornerRadius = 10;
    self.environmentTextView.textAlignment = NSTextAlignmentRight;
    [self.view addSubview:self.environmentTextView];

    UILabel *optionsHeader = [[UILabel alloc] initWithFrame:CGRectMake(margin, 430, w - margin * 2, 24)];
    optionsHeader.text = @"⚙️ الخيارات";
    optionsHeader.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    optionsHeader.textColor = [UIColor labelColor];
    [self.view addSubview:optionsHeader];

    [self addOptionAtY:470 label:@"الوضع الداكن" switchTag:1];
    [self addOptionAtY:520 label:@"تنظيف تلقائي" switchTag:2];
    [self addOptionAtY:570 label:@"تسجيل مفصل" switchTag:3];
}

- (void)addOptionAtY:(CGFloat)y label:(NSString *)label switchTag:(NSInteger)tag {
    CGFloat w = self.view.bounds.size.width;
    CGFloat margin = 20;

    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, w - margin * 2 - 60, 30)];
    l.text = label;
    l.font = [UIFont systemFontOfSize:15];
    l.textColor = [UIColor labelColor];
    l.textAlignment = NSTextAlignmentRight;
    [self.view addSubview:l];

    UISwitch *s = [[UISwitch alloc] initWithFrame:CGRectMake(w - margin - 55, y, 51, 31)];
    s.tag = tag;
    s.on = (tag == 3); // verbose log default ON
    [s addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:s];

    if (tag == 1) self.darkModeSwitch = s;
    if (tag == 2) self.autoCleanSwitch = s;
    if (tag == 3) self.verboseLogSwitch = s;
}

- (void)switchChanged:(UISwitch *)sender {
    switch (sender.tag) {
        case 1:
            [[Logger sharedLogger] info:[NSString stringWithFormat:@"Dark mode: %@", sender.isOn ? @"ON" : @"OFF"]];
            break;
        case 2:
            [[Logger sharedLogger] info:[NSString stringWithFormat:@"Auto clean: %@", sender.isOn ? @"ON" : @"OFF"]];
            break;
        case 3:
            [[Logger sharedLogger] setVerbose:sender.isOn];
            break;
    }
}

- (void)refreshEnvironment {
    [[CapabilityManager sharedManager] refreshCapabilities];
    NSMutableString *info = [NSMutableString string];
    [info appendString:@"🔧 IPA Installer Pro v2.1 (Standalone Mode)\n\n"];
    [info appendString:@"Required System Tools:\n"];

    NSArray *required = @[@"ldid", @"uicache", @"unzip", @"chmod", @"chown", @"cp", @"rm", @"mkdir"];
    for (NSString *tool in required) {
        BOOL has = [[CapabilityManager sharedManager] hasCapability:tool];
        NSString *path = [[CapabilityManager sharedManager] pathForTool:tool] ?: @"N/A";
        [info appendFormat:@"%@ %@: %@\n", has ? @"✅" : @"❌", tool, path];
    }

    [info appendString:@"\nOptional:\n"];
    BOOL helper = [[CapabilityManager sharedManager] hasCapability:@"root_helper"];
    [info appendFormat:@"%@ Root Helper: %@\n", helper ? @"✅" : @"⚠️", helper ? @"Active" : @"Not found (some operations may need manual confirmation)"];

    BOOL ls = [[CapabilityManager sharedManager] hasCapability:@"ls_workspace"];
    [info appendFormat:@"%@ LSApplicationWorkspace: %@ (verification only)\n", ls ? @"✅" : @"⚠️", ls ? @"Available" : @"Limited"];

    [info appendString:@"\n📝 Note: This tool works independently without AppSync or appinst.\n"];
    [info appendString:@"All operations use IPA Installer Pro\'s proprietary signing engine.\n"];

    self.environmentTextView.text = info;
}

@end
