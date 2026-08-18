#import "SettingsViewController.h"
#import "AppDataManager.h"

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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 3;
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"SettingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:1.0];
        cell.layer.cornerRadius = 12; cell.layer.masksToBounds = YES;
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.accessoryType = UITableViewCellAccessoryNone; cell.imageView.image = nil;

    if (indexPath.section == 0) {
        cell.textLabel.text = @"الإصدار";
        cell.detailTextLabel.text = @"1.6.7";
        cell.imageView.image = [[UIImage systemImageNamed:@"info.circle.fill"] imageWithTintColor:[UIColor colorWithRed:0.42 green:0.31 blue:0.90 alpha:1.0]];
    } else if (indexPath.section == 1) {
        NSArray *titles = @[@"مسح كل النسخ", @"تصدير النسخ", @"استيراد النسخ"];
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
        if (indexPath.row == 0) {
            cell.textLabel.text = @"عن الأداة";
            cell.detailTextLabel.text = @"@Zainqkvd";
            cell.imageView.image = [[UIImage systemImageNamed:@"person.fill"] imageWithTintColor:[UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"حول AppData Manager";
            cell.imageView.image = [[UIImage systemImageNamed:@"hand.raised.fill"] imageWithTintColor:[UIColor colorWithRed:0.9 green:0.5 blue:0.2 alpha:1.0]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 54; }

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] init]; header.backgroundColor = [UIColor clearColor];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 6, 300, 22)];
    NSArray *titles = @[@"معلومات الأداة", @"إدارة النسخ الاحتياطية", @"المطور"];
    label.text = titles[section];
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    label.textColor = [UIColor colorWithWhite:0.38 alpha:1.0];
    [header addSubview:label]; return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 30; }

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تنبيه"
                message:@"سيتم حذف جميع النسخ الاحتياطية بشكل دائم. هل أنت متأكد؟"
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"مسح الكل" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    AppDataManager *mgr = [AppDataManager sharedManager];
                    BOOL ok = [mgr deleteAllBackups];
                    dispatch_async(dispatch_get_main_queue(), ^{ [self showToast:ok ? @"تم مسح كل النسخ الاحتياطية" : @"فشل المسح"]; });
                });
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        } else if (indexPath.row == 1) {
            AppDataManager *mgr = [AppDataManager sharedManager];
            NSString *path = [mgr backupDirectory];
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            pasteboard.string = path;
            [self showToast:[NSString stringWithFormat:@"تم نسخ المسار: %@", path]];
        } else if (indexPath.row == 2) {
            [self showToast:@"انسخ ملفات النسخ إلى مجلد النسخ الاحتياطية"];
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            NSString *info = @"AppData Manager v1.6.7\n\n"
                @"أداة احترافية لإدارة بيانات التطبيقات\n"
                @"لأجهزة iOS Jailbreak.\n\n"
                @"• متوافق مع Dopamine 3.0\n"
                @"• دعم Rootless Jailbreak\n"
                @"• دعم iOS 15 - iOS 26\n"
                @"• نسخ احتياطي شامل\n\n"
                @"المطور: @Zainqkvd";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"عن الأداة" message:info preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        } else {
            NSString *aboutText = @"\n"
                @"مجانية بالكامل — لا تُباع ولا تتطلب أي رسوم.\n\n"
                @"إذا حاول أي شخص بيع الأداة أو طلب مبلغ مقابل الحصول عليها، فهذا غير رسمي.\n\n"
                @"للإبلاغ عن أي حالة بيع أو استغلال للأداة:\n"
                @"X: @Zainqkvd\n\n"
                @"المطور: ZAIN";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"حول AppData Manager" message:aboutText preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

- (void)showToast:(NSString *)message {
    UILabel *toast = [[UILabel alloc] init];
    toast.text = message; toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    toast.layer.cornerRadius = 12; toast.layer.masksToBounds = YES; toast.numberOfLines = 0;
    CGSize size = [message boundingRectWithSize:CGSizeMake(self.view.bounds.size.width - 60, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: toast.font} context:nil].size;
    toast.frame = CGRectMake(0, 0, size.width + 32, size.height + 24);
    toast.center = CGPointMake(self.view.center.x, self.view.bounds.size.height - 120);
    [self.view addSubview:toast];
    [UIView animateWithDuration:0.3 delay:2.5 options:UIViewAnimationOptionCurveEaseOut animations:^{ toast.alpha = 0; }
        completion:^(BOOL finished) { [toast removeFromSuperview]; }];
}

@end
