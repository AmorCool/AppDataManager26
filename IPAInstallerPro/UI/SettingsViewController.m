//
//  SettingsViewController.m
//  IPAInstallerPro
//

#import "SettingsViewController.h"
#import "Core/CapabilityManager.h"
#import "Core/RootlessManager.h"
#import "Core/Logger.h"
#import "Core/InstallationEngine.h"
#import <UIKit/UIKit.h>

@interface SettingsViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) CapabilityManager *capManager;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"الإعدادات";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    self.capManager = [CapabilityManager sharedManager];
    [self setupSections];
}

- (void)setupSections {
    self.sections = @[
        @{
            @"title": @"معلومات التطبيق",
            @"items": @[
                @{@"title": @"الإصدار", @"detail": @"2.0.0", @"icon": @"info.circle.fill", @"color": @[@(0.35), @(0.65), @(0.95)]},
                @{@"title": @"الإصدار المتوافق", @"detail": @"iOS 15.0+", @"icon": @"iphone", @"color": @[@(0.35), @(0.65), @(0.95)]}
            ]
        },
        @{
            @"title": @"البيئة",
            @"items": @[
                @{@"title": @"Root Helper", @"detail": [self.capManager isRootHelperAvailable] ? @"✅ متوفر" : @"⚠️ غير متوفر", @"icon": @"person.badge.key.fill", @"color": @[@(0.9), @(0.6), @(0.2)]},
                @{@"title": @"ldid", @"detail": [self.capManager isLDIDAvailable] ? @"✅ متوفر" : @"❌ غير متوفر", @"icon": @"signature", @"color": @[@(0.9), @(0.6), @(0.2)]},
                @{@"title": @"uicache", @"detail": [self.capManager isUICacheAvailable] ? @"✅ متوفر" : @"❌ غير متوفر", @"icon": @"arrow.clockwise.circle.fill", @"color": @[@(0.9), @(0.6), @(0.2)]},
                @{@"title": @"unzip", @"detail": [self.capManager isUnzipAvailable] ? @"✅ متوفر" : @"❌ غير متوفر", @"icon": @"doc.zipper", @"color": @[@(0.9), @(0.6), @(0.2)]},
                @{@"title": @"AppSync", @"detail": [self.capManager isAppSyncAvailable] ? @"✅ مثبت" : @"⚠️ غير مثبت", @"icon": @"checkmark.seal.fill", @"color": @[@(0.9), @(0.6), @(0.2)]},
                @{@"title": @"appinst", @"detail": [self.capManager isAppInstAvailable] ? @"✅ متوفر" : @"⚠️ غير متوفر", @"icon": @"arrow.down.app.fill", @"color": @[@(0.9), @(0.6), @(0.2)]}
            ]
        },
        @{
            @"title": @"مزود التثبيت",
            @"items": @[
                @{@"title": @"المزود الحالي", @"detail": [[InstallationEngine sharedEngine] currentProviderName], @"icon": @"wrench.fill", @"color": @[@(0.3), @(0.8), @(0.5)]}
            ]
        },
        @{
            @"title": @"عن التطبيق",
            @"items": @[
                @{@"title": @"المطور", @"detail": @"AppDataManager Team", @"icon": @"person.fill", @"color": @[@(0.5), @(0.5), @(0.5)]},
                @{@"title": @"GitHub", @"detail": @"aosaid3224-ops/AppDataManager", @"icon": @"link", @"color": @[@(0.5), @(0.5), @(0.5)]}
            ]
        }
    ];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.sections[section][@"items"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.sections[section][@"title"]; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"SettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.09 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    NSDictionary *item = self.sections[indexPath.section][@"items"][indexPath.row];
    cell.textLabel.text = item[@"title"];
    cell.detailTextLabel.text = item[@"detail"];
    NSArray *colorArr = item[@"color"];
    UIColor *iconColor = [UIColor colorWithRed:[colorArr[0] floatValue] green:[colorArr[1] floatValue] blue:[colorArr[2] floatValue] alpha:1.0];
    if (item[@"icon"]) {
        UIImage *icon = [UIImage systemImageNamed:item[@"icon"]];
        cell.imageView.image = [icon imageWithTintColor:iconColor];
    }
    return cell;
}

@end
