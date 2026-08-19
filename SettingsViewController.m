#import "SettingsViewController.h"
#import "AppDataManager.h"

static UIColor *ADMSettingsBackground(void) { return [UIColor colorWithRed:0.035 green:0.035 blue:0.055 alpha:1.0]; }
static UIColor *ADMSettingsCard(void) { return [UIColor colorWithRed:0.085 green:0.085 blue:0.125 alpha:1.0]; }
static UIColor *ADMSettingsSecondary(void) { return [UIColor colorWithWhite:0.56 alpha:1.0]; }
static UIColor *ADMSettingsAccent(void) { return [UIColor colorWithRed:0.54 green:0.42 blue:0.98 alpha:1.0]; }

@interface SettingsViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"الإعدادات";
    self.view.backgroundColor = ADMSettingsBackground();
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [self setupNavigationBar];
    [self setupTableView];
}

- (void)setupNavigationBar {
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.barTintColor = ADMSettingsBackground();
    self.navigationController.navigationBar.backgroundColor = ADMSettingsBackground();
    self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    self.navigationController.navigationBar.largeTitleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor, NSFontAttributeName: [UIFont systemFontOfSize:34 weight:UIFontWeightBold]};
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = ADMSettingsBackground();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 36, 0);
    self.tableView.sectionHeaderHeight = 36;
    self.tableView.sectionFooterHeight = 10;
    [self.view addSubview:self.tableView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 3;
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"SettingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellID];
        cell.backgroundColor = ADMSettingsCard();
        cell.layer.cornerRadius = 16;
        cell.layer.masksToBounds = YES;
        cell.textLabel.textColor = UIColor.whiteColor;
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        cell.detailTextLabel.textColor = ADMSettingsSecondary();
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;

    if (indexPath.section == 0) {
        cell.textLabel.text = @"الإصدار";
        cell.detailTextLabel.text = @"1.4.2";
        cell.imageView.image = [[UIImage systemImageNamed:@"info.circle.fill"] imageWithTintColor:ADMSettingsAccent()];
    } else if (indexPath.section == 1) {
        NSArray *titles = @[@"مسح كل النسخ", @"تصدير النسخ", @"استيراد النسخ"];
        NSArray *icons = @[@"trash.circle.fill", @"square.and.arrow.up.fill", @"square.and.arrow.down.fill"];
        NSArray *colors = @[
            [UIColor colorWithRed:0.98 green:0.34 blue:0.40 alpha:1.0],
            [UIColor colorWithRed:0.30 green:0.66 blue:0.96 alpha:1.0],
            [UIColor colorWithRed:0.30 green:0.82 blue:0.55 alpha:1.0]
        ];
        cell.textLabel.text = titles[indexPath.row];
        cell.imageView.image = [[UIImage systemImageNamed:icons[indexPath.row]] imageWithTintColor:colors[indexPath.row]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"عن الأداة";
            cell.detailTextLabel.text = @"@Zainqkvd";
            cell.imageView.image = [[UIImage systemImageNamed:@"person.fill"] imageWithTintColor:ADMSettingsAccent()];
        } else {
            cell.textLabel.text = @"حول AppData Manager";
            cell.imageView.image = [[UIImage systemImageNamed:@"hand.raised.fill"] imageWithTintColor:[UIColor colorWithRed:0.98 green:0.62 blue:0.28 alpha:1.0]];
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 58; }

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = ADMSettingsBackground();
    UILabel *label = [[UILabel alloc] init];
    label.text = @[@"معلومات الأداة", @"إدارة النسخ الاحتياطية", @"المطور"][section];
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    label.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-7]
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 34; }

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (cell.layer.presentationLayer) return;
    cell.alpha = 0.0;
    cell.transform = CGAffineTransformMakeTranslation(0, 8);
    [UIView animateWithDuration:0.28 delay:MIN(indexPath.row * 0.04, 0.16) options:UIViewAnimationOptionCurveEaseOut animations:^{
        cell.alpha = 1.0;
        cell.transform = CGAffineTransformIdentity;
    } completion:nil];
}

#pragma mark - Existing actions preserved

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تنبيه" message:@"سيتم حذف جميع النسخ الاحتياطية بشكل دائم. هل أنت متأكد؟" preferredStyle:UIAlertControllerStyleAlert];
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
            NSString *info = @"AppData Manager v1.4.2\n\n"
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
    toast.text = message;
    toast.textColor = UIColor.whiteColor;
    toast.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.96];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    toast.layer.cornerRadius = 15;
    toast.layer.masksToBounds = YES;
    toast.numberOfLines = 0;
    CGSize size = [message boundingRectWithSize:CGSizeMake(self.view.bounds.size.width - 60, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: toast.font} context:nil].size;
    toast.frame = CGRectMake(0, 0, size.width + 32, size.height + 24);
    toast.center = CGPointMake(self.view.center.x, self.view.bounds.size.height - 120);
    toast.alpha = 0.0;
    [self.view addSubview:toast];
    [UIView animateWithDuration:0.22 animations:^{ toast.alpha = 1.0; } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.28 delay:2.2 options:UIViewAnimationOptionCurveEaseOut animations:^{ toast.alpha = 0.0; } completion:^(BOOL done) { [toast removeFromSuperview]; }];
    }];
}

@end
