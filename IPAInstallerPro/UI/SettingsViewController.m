#import "SettingsViewController.h"
#import "../Core/JailbreakEnvironment.h"
#import "../Core/CapabilityManager.h"
#import "../Core/Logger.h"
#import "../Core/InstallationEngine.h"
#import "../Core/CrashReporter.h"
#import "CrashReporterViewController.h"

@interface SettingsViewController ()
@property (nonatomic, strong) NSArray *sectionTitles;
@property (nonatomic, strong) NSArray *capabilities;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"الإعدادات";
    self.view.backgroundColor = [UIColor blackColor];

    // Safe initialization with defaults
    self.sectionTitles = @[@"معلومات الأداة", @"التبعيات", @"النظام", @"التشخيص", @"المطور"];
    self.capabilities = @[];

    [self setupTableView];
    [self setupLoadingIndicator];
    [self loadCapabilities];
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

- (void)loadCapabilities {
    [self.loadingIndicator startAnimating];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSArray *caps = [[CapabilityManager sharedManager] allCapabilities];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.capabilities = caps ?: @[];
                [self.loadingIndicator stopAnimating];
                [self.tableView reloadData];
            });
        } @catch (NSException *e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.capabilities = @[];
                [self.loadingIndicator stopAnimating];
                [self.tableView reloadData];
            });
        }
    });
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sectionTitles.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;
    if (section == 1) return 2;
    if (section == 2) return 2;
    if (section == 3) return 2;
    return 1;
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

    @try {
        if (indexPath.section == 0) {
            [self configureAppInfoCell:cell atRow:indexPath.row];
        } else if (indexPath.section == 1) {
            [self configureCapabilitiesCell:cell atRow:indexPath.row];
        } else if (indexPath.section == 2) {
            [self configureSystemCell:cell atRow:indexPath.row];
        } else if (indexPath.section == 3) {
            [self configureDiagnosticsCell:cell atRow:indexPath.row];
        } else if (indexPath.section == 4) {
            cell.textLabel.text = @"عن الأداة";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } @catch (NSException *e) {
        cell.textLabel.text = @"خطأ";
        cell.detailTextLabel.text = e.reason ?: @"Unknown error";
    }

    return cell;
}

- (void)configureAppInfoCell:(UITableViewCell *)cell atRow:(NSInteger)row {
    if (row == 0) {
        cell.textLabel.text = @"الإصدار";
        cell.detailTextLabel.text = @"1.0.22";
    } else if (row == 1) {
        cell.textLabel.text = @"المحرك المفضل";
        NSString *provider = @"غير معروف";
        @try {
            provider = [[InstallationEngine sharedEngine] currentProviderName] ?: @"غير معروف";
        } @catch (NSException *e) {}
        cell.detailTextLabel.text = provider;
    } else if (row == 2) {
        cell.textLabel.text = @"حالة التثبيت";
        NSString *status = @"غير معروف";
        @try {
            status = [[CapabilityManager sharedManager] canInstallIPA] ? @"جاهز ✓" : @"غير جاهز ✗";
        } @catch (NSException *e) {}
        cell.detailTextLabel.text = status;
    }
}

- (void)configureCapabilitiesCell:(UITableViewCell *)cell atRow:(NSInteger)row {
    if (row < self.capabilities.count) {
        Capability *cap = self.capabilities[row];
        cell.textLabel.text = cap.name ?: @"Unknown";
        cell.detailTextLabel.text = cap.statusMessage ?: @"";
        cell.detailTextLabel.textColor = cap.isAvailable ? [UIColor greenColor] : [UIColor redColor];
    } else {
        cell.textLabel.text = @"—";
        cell.detailTextLabel.text = @"";
    }
}

- (void)configureSystemCell:(UITableViewCell *)cell atRow:(NSInteger)row {
    JailbreakEnvironment *env = [JailbreakEnvironment sharedEnvironment];
    if (row == 0) {
        cell.textLabel.text = @"نوع الجيلبريك";
        cell.detailTextLabel.text = env.jailbreakType ?: @"غير معروف";
    } else if (row == 1) {
        cell.textLabel.text = @"إصدار iOS";
        cell.detailTextLabel.text = env.osVersion ?: @"غير معروف";
    }
}

- (void)configureDiagnosticsCell:(UITableViewCell *)cell atRow:(NSInteger)row {
    if (row == 0) {
        cell.textLabel.text = @"📊 Crash Reporter";
        cell.detailTextLabel.text = @"عرض سجلات الكراش";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (row == 1) {
        cell.textLabel.text = @"📤 تصدير التقرير";
        cell.detailTextLabel.text = @"مشاركة التقرير الكامل";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
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
                NSString *report = [[CrashReporter sharedReporter] generateFullReport];
                UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[report] applicationActivities:nil];
                [self presentViewController:activity animated:YES completion:nil];
            }
        } else if (indexPath.section == 4) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"IPA Installer Pro"
                                                                             message:@"أداة احترافية لتثبيت تطبيقات IPA على الأجهزة المجربكة\n\nVersion: 1.0.22\nDeveloper: @Zainqkvd"
                                                                      preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    } @catch (NSException *e) {
        NSLog(@"[Settings] didSelectRow error: %@", e.reason);
    }
}

@end
