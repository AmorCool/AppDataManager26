//
//  SettingsViewController.m
//  IPAInstallerPro
//
//  v2.0 — Removed diagnostics/logs section per Audit
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

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];

    [self setupSections];
}

- (void)setupSections {
    self.sections = @[
        @{
            @"title": @"معلومات التطبيق",
            @"items": @[
                @{@"title": @"الإصدار", @"detail": @"2.0.0", @"icon": @"info.circle.fill", @"color": @[@(0.35), @(0.65), @(0.95)]},
                @{@"title": @"الإصدار المتوافق", @"detail": @"iOS 15.0+", @"icon": @"iphone", @"color": @[@(0.35), @(0.65), @(0.95)]},
                @{@"title": @"نوع الجيلبريك", @"detail": [self.capManager isRootHelperAvailable] ? @"Rootless" : @"Rootful", @"icon": @"lock.shield.fill", @"color": @[@(0.35), @(0.65), @(0.95)]}
            ]
        },
        @{
            @"title": @"البيئة",
            @"items": @[
                @{@"title": @"Dopamine 3.0", @"detail": NO ? @"✅ متوفر" : @"❌ غير متوفر", @"icon": @"bolt.fill", @"color": @[@(0.9), @(0.6), @(0.2)]},
                @{@"title": @"Root Helper", @"detail": [self.capManager hasRootHelper] ? @"✅ متوفر" : @"⚠️ غير متوفر", @"icon": @"person.badge.key.fill", @"color": @[@(0.9), @(0.6), @(0.2)]},
                @{@"title": @"ldid", @"detail": [self.capManager hasLDID] ? @"✅ متوفر" : @"❌ غير متوفر", @"icon": @"signature", @"color": @[@(0.9), @(0.6), @(0.2)]},
                @{@"title": @"uicache", @"detail": [self.capManager hasUICache] ? @"✅ متوفر" : @"❌ غير متوفر", @"icon": @"arrow.clockwise.circle.fill", @"color": @[@(0.9), @(0.6), @(0.2)]},
                @{@"title": @"unzip", @"detail": [self.capManager hasUnzip] ? @"✅ متوفر" : @"❌ غير متوفر", @"icon": @"doc.zipper", @"color": @[@(0.9), @(0.6), @(0.2)]},
                @{@"title": @"AppSync", @"detail": [self.capManager hasAppSync] ? @"✅ مثبت" : @"⚠️ غير مثبت", @"icon": @"checkmark.seal.fill", @"color": @[@(0.9), @(0.6), @(0.2)]},
                @{@"title": @"appinst", @"detail": [self.capManager hasAppInst] ? @"✅ متوفر" : @"⚠️ غير متوفر", @"icon": @"arrow.down.app.fill", @"color": @[@(0.9), @(0.6), @(0.2)]}
            ]
        },
        @{
            @"title": @"مزود التثبيت",
            @"items": @[
                @{@"title": @"المزود الحالي", @"detail": [[InstallationEngine sharedEngine] currentProviderName], @"icon": @"wrench.fill", @"color": @[@(0.3), @(0.8), @(0.5)]},
                @{@"title": @"التحقق من البيئة", @"detail": @"اضغط للتحقق", @"icon": @"checkmark.circle.fill", @"color": @[@(0.3), @(0.8), @(0.5)], @"action": @"verifyEnvironment"}
            ]
        },
        @{
            @"title": @"عن التطبيق",
            @"items": @[
                @{@"title": @"المطور", @"detail": @"AppDataManager Team", @"icon": @"person.fill", @"color": @[@(0.5), @(0.5), @(0.5)]},
                @{@"title": @"GitHub", @"detail": @"aosaid3224-ops/AppDataManager", @"icon": @"link", @"color": @[@(0.5), @(0.5), @(0.5)]},
                @{@"title": @"التواصل", @"detail": @"support@appdatamanager.com", @"icon": @"envelope.fill", @"color": @[@(0.5), @(0.5), @(0.5)]}
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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.sections[indexPath.section][@"items"][indexPath.row];
    if ([item[@"action"] isEqualToString:@"verifyEnvironment"]) [self verifyEnvironment];
}

- (void)verifyEnvironment {
    CapabilityManager *cm = [CapabilityManager sharedManager];
    NSMutableString *report = [NSMutableString string];
    [report appendString:@"📊 تقرير البيئة\n\n"];
    [report appendFormat:@"Dopamine 3.0: %@\n", NO ? @"✅" : @"❌"];
    [report appendFormat:@"Root Helper: %@\n", [cm isRootHelperAvailable] ? @"✅" : @"⚠️"];
    [report appendFormat:@"ldid: %@\n", [cm isLDIDAvailable] ? @"✅" : @"❌"];
    [report appendFormat:@"uicache: %@\n", [cm isUICacheAvailable] ? @"✅" : @"❌"];
    [report appendFormat:@"unzip: %@\n", [cm isUnzipAvailable] ? @"✅" : @"❌"];
    [report appendFormat:@"AppSync: %@\n", [cm isAppSyncAvailable] ? @"✅" : @"⚠️"];
    [report appendFormat:@"appinst: %@\n", [cm isAppInstAvailable] ? @"✅" : @"⚠️"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"التحقق من البيئة" message:report preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"موافق" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
