#import "SettingsViewController.h"

@interface SettingsViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];

    [self setupNavigationBar];
    [self setupTableView];
}

- (void)setupNavigationBar {
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    [self.navigationController.navigationBar setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}];
    [self.navigationController.navigationBar setLargeTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
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

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 3;
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"SettingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
        cell.layer.cornerRadius = 10;
        cell.layer.masksToBounds = YES;
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    if (indexPath.section == 0) {
        cell.textLabel.text = @"Version";
        cell.detailTextLabel.text = @"1.2.0";
        cell.imageView.image = [[UIImage systemImageNamed:@"info.circle.fill"] imageWithTintColor:[UIColor colorWithRed:0.42 green:0.31 blue:0.90 alpha:1.0]];
    } else if (indexPath.section == 1) {
        NSArray *titles = @[@"Clear All Backups", @"Export Backups", @"Import Backups"];
        NSArray *icons = @[@"trash.circle.fill", @"square.and.arrow.up.fill", @"square.and.arrow.down.fill"];
        NSArray *colors = @[
            [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0],
            [UIColor colorWithRed:0.3 green:0.6 blue:0.9 alpha:1.0],
            [UIColor colorWithRed:0.3 green:0.8 blue:0.5 alpha:1.0]
        ];
        cell.textLabel.text = titles[indexPath.row];
        cell.imageView.image = [[UIImage systemImageNamed:icons[indexPath.row]] imageWithTintColor:colors[indexPath.row]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = @"About";
        cell.detailTextLabel.text = @"@aosaid3224";
        cell.imageView.image = [[UIImage systemImageNamed:@"person.fill"] imageWithTintColor:[UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0]];
    }

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 56;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = [UIColor clearColor];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, 200, 20)];
    NSArray *titles = @[@"App Info", @"Backup Management", @"Developer"];
    label.text = titles[section];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    label.text = [label.text uppercaseString];
    [header addSubview:label];

    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 32;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"⚠️ Clear All Backups"
                                                                           message:@"This will delete ALL backup files permanently. Are you sure?"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Clear All" style:UIAlertActionStyleDestructive handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        } else {
            [self showToast:@"ℹ️ Feature coming in next update"];
        }
    } else if (indexPath.section == 2) {
        NSString *info = @"AppData Manager v1.2.0\n\n"
                         @"Professional app data management tool\n"
                         @"for jailbroken iOS devices.\n\n"
                         @"• Dopamine 3.0 Compatible\n"
                         @"• Rootless Jailbreak Support\n"
                         @"• iOS 15 - iOS 26 Support\n\n"
                         @"Developer: @aosaid3224";

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"About"
                                                                       message:info
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)showToast:(NSString *)message {
    UILabel *toast = [[UILabel alloc] init];
    toast.text = message;
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    toast.layer.cornerRadius = 12;
    toast.layer.masksToBounds = YES;
    toast.numberOfLines = 0;

    CGSize size = [message boundingRectWithSize:CGSizeMake(self.view.bounds.size.width - 60, CGFLOAT_MAX)
                                        options:NSStringDrawingUsesLineFragmentOrigin
                                     attributes:@{NSFontAttributeName: toast.font}
                                        context:nil].size;
    toast.frame = CGRectMake(0, 0, size.width + 32, size.height + 24);
    toast.center = CGPointMake(self.view.center.x, self.view.bounds.size.height - 120);

    [self.view addSubview:toast];

    [UIView animateWithDuration:0.3 delay:2.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        toast.alpha = 0;
    } completion:^(BOOL finished) {
        [toast removeFromSuperview];
    }];
}

@end
