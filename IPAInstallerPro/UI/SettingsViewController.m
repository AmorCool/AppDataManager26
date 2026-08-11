#import "SettingsViewController.h"
#import "../Core/JailbreakEnvironment.h"
#import "../Core/CapabilityManager.h"
#import "../Core/Logger.h"
#import "../Core/InstallationEngine.h"
#import "../Core/CrashReporter.h"
#import "CrashReporterViewController.h"
#import <UIKit/UIKit.h>
#import <sys/utsname.h>

@interface SettingsViewController ()
@property (nonatomic, strong) NSArray *sectionTitles;
@property (nonatomic, strong) NSArray *capabilities;
@property (nonatomic, strong) JailbreakEnvironment *env;
@property (nonatomic, strong) CapabilityManager *capMgr;
@property (nonatomic, strong) InstallationEngine *engine;
@property (nonatomic, strong) CrashReporter *reporter;
@property (nonatomic, strong) NSString *appVersion;
@property (nonatomic, strong) NSString *bestProvider;
@property (nonatomic, assign) BOOL canInstall;
@property (nonatomic, assign) NSUInteger crashCount;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"الإعدادات";
    self.view.backgroundColor = [UIColor blackColor];

    // Initialize all data sources
    self.env = [JailbreakEnvironment sharedEnvironment];
    self.capMgr = [CapabilityManager sharedManager];
    self.engine = [InstallationEngine sharedEngine];
    self.reporter = [CrashReporter sharedReporter];

    // Read real app version from Info.plist
    self.appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0.23";

    // Scan capabilities
    [self.capMgr scanCapabilities];
    self.capabilities = [self.capMgr allCapabilities] ?: @[];

    // Read real provider
    self.bestProvider = [self.engine currentProviderName] ?: @"غير معروف";

    // Read real install status
    self.canInstall = [self.capMgr canInstallIPA];

    // Read real crash count
    self.crashCount = [self.reporter totalCrashCount];

    self.sectionTitles = @[@"معلومات الأداة", @"التبعيات", @"النظام", @"التشخيص", @"المطور"];

    [self setupTableView];
    [self setupLoadingIndicator];
}

- (void)setupTableView {
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.separatorColor = [UIColor darkGrayColor];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"SettingsCell"];
}

- (void)setupLoadingIndicator {
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingIndicator.color = [UIColor whiteColor];
    self.loadingIndicator.hidesWhenStopped = YES;
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.loadingIndicator];
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

#pragma mark - Real Data Methods

- (NSString *)realInstallStatus {
    if (!self.canInstall) return @"غير جاهز ✗";

    NSMutableArray *ready = [NSMutableArray array];
    if ([self.capMgr isLDIDAvailable]) [ready addObject:@"ldid"];
    if ([self.capMgr isUICacheAvailable]) [ready addObject:@"uicache"];
    if ([self.capMgr isUnzipAvailable]) [ready addObject:@"unzip"];
    if ([self.capMgr isAppSyncAvailable]) [ready addObject:@"AppSync"];
    if ([self.capMgr isRootHelperAvailable]) [ready addObject:@"Helper"];

    if (ready.count == 0) return @"جاهز ✓";
    return [NSString stringWithFormat:@"جاهز (%@) ✓", [ready componentsJoinedByString:@", "]];
}

- (NSString *)realJailbreakType {
    NSString *type = self.env.jailbreakType ?: @"غير معروف";
    if (self.env.isRootless) {
        return [NSString stringWithFormat:@"%@ (Rootless)", type];
    }
    return type;
}

- (NSString *)realDeviceInfo {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *machine = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    NSString *model = self.env.deviceModel ?: machine ?: @"غير معروف";
    return model;
}

- (NSString *)realProviderStatus {
    NSArray *providers = [self.engine availableProviders];
    if (providers.count == 0) return @"لا يوجد محرك";

    NSMutableArray *names = [NSMutableArray array];
    for (id<InstallationProvider> p in providers) {
        [names addObject:[p providerName] ?: @"Unknown"];
    }
    return [NSString stringWithFormat:@"%@ (%lu متاح)", self.bestProvider, (unsigned long)providers.count];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sectionTitles.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 3;  // App Info
        case 1: return 5;  // Dependencies (AppSync, appinst, ldid, uicache, unzip)
        case 2: return 3;  // System (jailbreak, iOS, device)
        case 3: return 2;  // Diagnostics
        case 4: return 1;  // Developer
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section < self.sectionTitles.count) {
        return self.sectionTitles[section];
    }
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SettingsCell" forIndexPath:indexPath];
    cell.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;

    @try {
        switch (indexPath.section) {
            case 0: [self configureAppInfoCell:cell atRow:indexPath.row]; break;
            case 1: [self configureDependencyCell:cell atRow:indexPath.row]; break;
            case 2: [self configureSystemCell:cell atRow:indexPath.row]; break;
            case 3: [self configureDiagnosticsCell:cell atRow:indexPath.row]; break;
            case 4: [self configureDeveloperCell:cell atRow:indexPath.row]; break;
        }
    } @catch (NSException *e) {
        cell.textLabel.text = @"خطأ";
        cell.detailTextLabel.text = e.reason ?: @"Unknown";
        cell.detailTextLabel.textColor = [UIColor redColor];
    }

    return cell;
}

#pragma mark - Cell Configurations

- (void)configureAppInfoCell:(UITableViewCell *)cell atRow:(NSInteger)row {
    switch (row) {
        case 0:
            cell.textLabel.text = @"الإصدار";
            cell.detailTextLabel.text = self.appVersion;
            break;
        case 1:
            cell.textLabel.text = @"المحرك المفضل";
            cell.detailTextLabel.text = [self realProviderStatus];
            break;
        case 2:
            cell.textLabel.text = @"حالة التثبيت";
            cell.detailTextLabel.text = [self realInstallStatus];
            cell.detailTextLabel.textColor = self.canInstall ? [UIColor greenColor] : [UIColor redColor];
            break;
    }
}

- (void)configureDependencyCell:(UITableViewCell *)cell atRow:(NSInteger)row {
    NSArray *deps = @[
        @{@"name": @"AppSync Unified", @"check": @"isAppSyncAvailable"},
        @{@"name": @"appinst", @"check": @"isAppInstAvailable"},
        @{@"name": @"ldid", @"check": @"isLDIDAvailable"},
        @{@"name": @"uicache", @"check": @"isUICacheAvailable"},
        @{@"name": @"unzip", @"check": @"isUnzipAvailable"}
    ];

    if (row < deps.count) {
        NSDictionary *dep = deps[row];
        NSString *name = dep[@"name"];
        NSString *check = dep[@"check"];

        BOOL available = NO;
        if ([check isEqualToString:@"isAppSyncAvailable"]) available = [self.capMgr isAppSyncAvailable];
        else if ([check isEqualToString:@"isAppInstAvailable"]) available = [self.capMgr isAppInstAvailable];
        else if ([check isEqualToString:@"isLDIDAvailable"]) available = [self.capMgr isLDIDAvailable];
        else if ([check isEqualToString:@"isUICacheAvailable"]) available = [self.capMgr isUICacheAvailable];
        else if ([check isEqualToString:@"isUnzipAvailable"]) available = [self.capMgr isUnzipAvailable];

        cell.textLabel.text = name;
        cell.detailTextLabel.text = available ? @"متوفر ✓" : @"غير متوفر ✗";
        cell.detailTextLabel.textColor = available ? [UIColor greenColor] : [UIColor redColor];
    }
}

- (void)configureSystemCell:(UITableViewCell *)cell atRow:(NSInteger)row {
    switch (row) {
        case 0:
            cell.textLabel.text = @"نوع الجيلبريك";
            cell.detailTextLabel.text = [self realJailbreakType];
            break;
        case 1:
            cell.textLabel.text = @"إصدار iOS";
            cell.detailTextLabel.text = self.env.osVersion ?: @"غير معروف";
            break;
        case 2:
            cell.textLabel.text = @"الجهاز";
            cell.detailTextLabel.text = [self realDeviceInfo];
            break;
    }
}

- (void)configureDiagnosticsCell:(UITableViewCell *)cell atRow:(NSInteger)row {
    switch (row) {
        case 0:
            cell.textLabel.text = @"📊 Crash Reporter";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu سجل", (unsigned long)self.crashCount];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        case 1:
            cell.textLabel.text = @"📤 تصدير التقرير";
            cell.detailTextLabel.text = @"مشاركة التقرير الكامل";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
    }
}

- (void)configureDeveloperCell:(UITableViewCell *)cell atRow:(NSInteger)row {
    cell.textLabel.text = @"عن IPA Installer Pro";
    cell.detailTextLabel.text = @"@Zainqkvd | Dopamine 3.0 Ready";
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    @try {
        if (indexPath.section == 3) {
            if (indexPath.row == 0) {
                CrashReporterViewController *vc = [[CrashReporterViewController alloc] initWithStyle:UITableViewStyleGrouped];
                [self.navigationController pushViewController:vc animated:YES];
            } else if (indexPath.row == 1) {
                NSString *report = [self.reporter generateFullReport];
                UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[report] applicationActivities:nil];
                [self presentViewController:activity animated:YES completion:nil];
            }
        } else if (indexPath.section == 4) {
            NSString *msg = [NSString stringWithFormat:@"IPA Installer Pro\n\nVersion: %@\nDopamine 3.0 Compatible\n\nDeveloper: @Zainqkvd\n\nFeatures:\n• Direct Install (ldid + uicache)\n• System Install (LSApplicationWorkspace)\n• Crash Reporter\n• Real-time Diagnostics", self.appVersion];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"عن الأداة" message:msg preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    } @catch (NSException *e) {
        NSLog(@"[Settings] didSelectRow error: %@", e.reason);
    }
}

@end
