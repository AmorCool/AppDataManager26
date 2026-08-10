#import "SettingsViewController.h"
#import "Core/JailbreakEnvironment.h"
#import "Core/CapabilityManager.h"
#import "Core/Logger.h"
#import "Core/InstallationEngine.h"

@interface SettingsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"الإعدادات";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    [self setupNavigationBar];
    [self setupTableView];
}

- (void)setupNavigationBar {
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 40, 0);
    [self.view addSubview:self.tableView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;
    if (section == 1) return 2;
    if (section == 2) return 2;
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"SettingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:1.0];
        cell.layer.cornerRadius = 12;
        cell.layer.masksToBounds = YES;
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.image = nil;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];

    JailbreakEnvironment *env = [JailbreakEnvironment sharedEnvironment];
    CapabilityManager *capMgr = [CapabilityManager sharedManager];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) { cell.textLabel.text = @"الإصدار"; cell.detailTextLabel.text = @"1.0.0"; cell.imageView.image = [[UIImage systemImageNamed:@"info.circle.fill"] imageWithTintColor:[UIColor colorWithWhite:0.5 alpha:1.0]]; }
        else if (indexPath.row == 1) { cell.textLabel.text = @"نظام iOS"; cell.detailTextLabel.text = env.osVersion; cell.imageView.image = [[UIImage systemImageNamed:@"iphone"] imageWithTintColor:[UIColor colorWithWhite:0.5 alpha:1.0]]; }
        else { cell.textLabel.text = @"الجهاز"; cell.detailTextLabel.text = env.deviceModel; cell.imageView.image = [[UIImage systemImageNamed:@"cpu"] imageWithTintColor:[UIColor colorWithWhite:0.5 alpha:1.0]]; }
    } else if (indexPath.section == 1) {
        NSArray *caps = [capMgr allCapabilities];
        Capability *cap = caps[indexPath.row];
        cell.textLabel.text = cap.name;
        cell.detailTextLabel.text = cap.statusMessage;
        cell.detailTextLabel.textColor = cap.isAvailable ? [UIColor colorWithRed:0.3 green:0.7 blue:0.5 alpha:1.0] : [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0];
        cell.imageView.image = [[UIImage systemImageNamed:cap.isAvailable ? @"checkmark.shield.fill" : @"exclamationmark.shield.fill"] imageWithTintColor:[UIColor colorWithWhite:0.5 alpha:1.0]];
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"بيئة الجيلبريك";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@)", env.jailbreakType, env.isRootless ? @"Rootless" : @"Rootful"];
            cell.imageView.image = [[UIImage systemImageNamed:@"lock.shield.fill"] imageWithTintColor:[UIColor colorWithWhite:0.5 alpha:1.0]];
        } else {
            cell.textLabel.text = @"محرك التثبيت";
            NSArray *providers = [[InstallationEngine sharedEngine] availableProviders];
            cell.detailTextLabel.text = providers.count > 0 ? @"جاهز ✓" : @"غير جاهز";
            cell.detailTextLabel.textColor = providers.count > 0 ? [UIColor colorWithRed:0.3 green:0.7 blue:0.5 alpha:1.0] : [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0];
            cell.imageView.image = [[UIImage systemImageNamed:@"gearshape.2.fill"] imageWithTintColor:[UIColor colorWithWhite:0.5 alpha:1.0]];
        }
    } else {
        cell.textLabel.text = @"عن الأداة";
        cell.detailTextLabel.text = @"@Zainqkvd";
        cell.imageView.image = [[UIImage systemImageNamed:@"person.fill"] imageWithTintColor:[UIColor colorWithWhite:0.5 alpha:1.0]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 54; }

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = [UIColor clearColor];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 6, 300, 22)];
    NSArray *titles = @[@"معلومات الأداة", @"التبعيات", @"النظام", @"المطور"];
    label.text = titles[section];
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    label.textColor = [UIColor colorWithWhite:0.38 alpha:1.0];
    [header addSubview:label];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 30; }

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 3) {
        NSString *info = @"IPA Installer Pro v1.0.0\n\nأداة احترافية لتثبيت تطبيقات IPA\nعلى أجهزة iOS Jailbreak.\n\n• متوافقة مع Dopamine 3.0\n• دعم Rootless Jailbreak\n• دعم iOS 15 - iOS 26\n• واجهة عربية احترافية\n\nالمطور: @Zainqkvd\nالريبو: A-ZAIN Repo";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"عن الأداة" message:info preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end
