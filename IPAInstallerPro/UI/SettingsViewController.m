#import "SettingsViewController.h"
#import "../Core/JailbreakEnvironment.h"
#import "../Core/CapabilityManager.h"
#import "../Core/InstallationEngine.h"
#import "../Core/CrashReporter.h"
#import "CrashReporterViewController.h"
#import <sys/utsname.h>

@interface SettingsViewController ()
@property (nonatomic, strong) NSArray *sectionTitles;
@property (nonatomic, strong) NSArray *capabilities;
@property (nonatomic, strong) JailbreakEnvironment *env;
@property (nonatomic, strong) CapabilityManager *capMgr;
@property (nonatomic, strong) InstallationEngine *engine;
@property (nonatomic, strong) CrashReporter *reporter;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"الإعدادات";
    self.view.backgroundColor = [UIColor blackColor];

    self.env = [JailbreakEnvironment sharedEnvironment];
    self.capMgr = [CapabilityManager sharedManager];
    self.engine = [InstallationEngine sharedEngine];
    self.reporter = [CrashReporter sharedReporter];

    self.sectionTitles = @[@"معلومات الأداة", @"التبعيات", @"النظام", @"التشخيص", @"المطور"];

    // Scan capabilities in background then reload
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.capMgr scanCapabilities];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.capabilities = [self.capMgr allCapabilities];
            [self.tableView reloadData];
        });
    });

    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.separatorColor = [UIColor darkGrayColor];
}

#pragma mark - Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;
    if (section == 1) return 5;
    if (section == 2) return 3;
    if (section == 3) return 2;
    if (section == 4) return 1;
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section < self.sectionTitles.count) return self.sectionTitles[section];
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"SettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
    }

    cell.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.text = @"";
    cell.detailTextLabel.text = @"";

    switch (indexPath.section) {
        case 0: [self configureAppInfo:cell row:indexPath.row]; break;
        case 1: [self configureDeps:cell row:indexPath.row]; break;
        case 2: [self configureSystem:cell row:indexPath.row]; break;
        case 3: [self configureDiag:cell row:indexPath.row]; break;
        case 4: [self configureDev:cell row:indexPath.row]; break;
    }

    return cell;
}

#pragma mark - Cell Configurations

- (void)configureAppInfo:(UITableViewCell *)cell row:(NSInteger)row {
    switch (row) {
        case 0:
            cell.textLabel.text = @"الإصدار";
            cell.detailTextLabel.text = @"1.0.24";
            break;
        case 1: {
            cell.textLabel.text = @"المحرك المفضل";
            NSString *name = @"غير معروف";
            @try { name = [self.engine currentProviderName]; } @catch (NSException *e) {}
            if (!name || name.length == 0) name = @"غير معروف";
            cell.detailTextLabel.text = name;
            break;
        }
        case 2: {
            cell.textLabel.text = @"حالة التثبيت";
            BOOL ready = NO;
            @try { ready = [self.capMgr canInstallIPA]; } @catch (NSException *e) {}
            cell.detailTextLabel.text = ready ? @"جاهز ✓" : @"غير جاهز ✗";
            cell.detailTextLabel.textColor = ready ? [UIColor greenColor] : [UIColor redColor];
            break;
        }
    }
}

- (void)configureDeps:(UITableViewCell *)cell row:(NSInteger)row {
    NSArray *names = @[@"AppSync Unified", @"appinst", @"ldid", @"uicache", @"unzip"];
    NSArray *checks = @[@"isAppSyncAvailable", @"isAppInstAvailable", @"isLDIDAvailable", @"isUICacheAvailable", @"isUnzipAvailable"];

    if (row < names.count) {
        cell.textLabel.text = names[row];
        BOOL avail = NO;
        NSString *check = checks[row];
        @try {
            if ([check isEqualToString:@"isAppSyncAvailable"]) avail = [self.capMgr isAppSyncAvailable];
            else if ([check isEqualToString:@"isAppInstAvailable"]) avail = [self.capMgr isAppInstAvailable];
            else if ([check isEqualToString:@"isLDIDAvailable"]) avail = [self.capMgr isLDIDAvailable];
            else if ([check isEqualToString:@"isUICacheAvailable"]) avail = [self.capMgr isUICacheAvailable];
            else if ([check isEqualToString:@"isUnzipAvailable"]) avail = [self.capMgr isUnzipAvailable];
        } @catch (NSException *e) {}

        cell.detailTextLabel.text = avail ? @"✓" : @"✗";
        cell.detailTextLabel.textColor = avail ? [UIColor greenColor] : [UIColor redColor];
    }
}

- (void)configureSystem:(UITableViewCell *)cell row:(NSInteger)row {
    switch (row) {
        case 0: {
            cell.textLabel.text = @"الجيلبريك";
            NSString *jb = @"غير معروف";
            @try {
                jb = self.env.jailbreakType;
                if (self.env.isRootless) jb = [jb stringByAppendingString:@" (Rootless)"];
            } @catch (NSException *e) {}
            if (!jb || jb.length == 0) jb = @"غير معروف";
            cell.detailTextLabel.text = jb;
            break;
        }
        case 1: {
            cell.textLabel.text = @"iOS";
            NSString *ver = @"غير معروف";
            @try { ver = self.env.osVersion; } @catch (NSException *e) {}
            if (!ver || ver.length == 0) ver = [[UIDevice currentDevice] systemVersion];
            cell.detailTextLabel.text = ver;
            break;
        }
        case 2: {
            cell.textLabel.text = @"الجهاز";
            NSString *model = @"غير معروف";
            @try { model = self.env.deviceModel; } @catch (NSException *e) {}
            if (!model || model.length == 0) {
                struct utsname u;
                uname(&u);
                model = [NSString stringWithCString:u.machine encoding:NSUTF8StringEncoding];
            }
            cell.detailTextLabel.text = model;
            break;
        }
    }
}

- (void)configureDiag:(UITableViewCell *)cell row:(NSInteger)row {
    if (row == 0) {
        cell.textLabel.text = @"📊 Diagnostic Center";
        NSUInteger count = 0;
        @try { count = [self.reporter totalCrashCount]; } @catch (NSException *e) {}
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu crash%@", (unsigned long)count, count == 1 ? @"" : @"es"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (row == 1) {
        cell.textLabel.text = @"📤 تصدير التقرير";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
}

- (void)configureDev:(UITableViewCell *)cell row:(NSInteger)row {
    cell.textLabel.text = @"عن الأداة";
    cell.detailTextLabel.text = @"@Zainqkvd";
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
}

#pragma mark - Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 3 && indexPath.row == 0) {
        @try {
            CrashReporterViewController *vc = [[CrashReporterViewController alloc] initWithStyle:UITableViewStyleGrouped];
            [self.navigationController pushViewController:vc animated:YES];
        } @catch (NSException *e) {
            NSLog(@"[Settings] CrashReporter error: %@", e.reason);
        }
    } else if (indexPath.section == 3 && indexPath.row == 1) {
        @try {
            NSString *report = [self.reporter generateFullReport];
            UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[report] applicationActivities:nil];
            [self presentViewController:activity animated:YES completion:nil];
        } @catch (NSException *e) {}
    } else if (indexPath.section == 4) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"IPA Installer Pro"
                                                                     message:@"Version 1.0.24\nDopamine 3.0 Compatible\n\n@Zainqkvd"
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end
