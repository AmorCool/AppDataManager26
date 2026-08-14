//
//  AppDetailViewController.m
//  AppDataManager
//
//  v1.6.0 — Crash-Resilient App Detail
//

#import "AppDetailViewController.h"
#import "AppDataManager.h"
#import "BackupManagerViewController.h"

@interface AppDetailViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIImageView *appIcon;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *bundleIDLabel;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UILabel *dataSizeLabel;
@property (nonatomic, strong) UILabel *documentsSizeLabel;
@property (nonatomic, strong) UILabel *documentsCountLabel;
@property (nonatomic, strong) UILabel *lastBackupLabel;
@property (nonatomic, strong) UILabel *dataPathLabel;
@property (nonatomic, strong) UILabel *documentsPathLabel;
@property (nonatomic, strong) AppDataManager *manager;
@property (nonatomic, assign) BOOL isSystemApp;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) dispatch_queue_t workerQueue;
@end

@implementation AppDetailViewController

- (instancetype)initWithAppInfo:(NSDictionary *)appInfo {
    self = [super init];
    if (self) {
        _appInfo = appInfo;
        _manager = [AppDataManager sharedManager];
        _workerQueue = dispatch_queue_create(
            "com.appdatamanager.detailworker", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"تفاصيل التطبيق";
    self.view.backgroundColor =
        [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];

    [self setupScrollView];
    [self setupHeader];
    [self setupInfoCards];
    [self setupActionButtons];
    [self setupLoadingView];

    [self loadDataAsync];
}

#pragma mark - UI Setup

- (void)setupScrollView {
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    self.scrollView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentView.backgroundColor = [UIColor clearColor];
    [self.scrollView addSubview:self.contentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.topAnchor
            constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.contentView.leadingAnchor
            constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.contentView.trailingAnchor
            constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.contentView.bottomAnchor
            constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.contentView.widthAnchor
            constraintEqualToAnchor:self.scrollView.widthAnchor]
    ]];
}

- (void)setupHeader {
    self.appIcon = [[UIImageView alloc] init];
    self.appIcon.layer.cornerRadius = 20.0;
    self.appIcon.layer.masksToBounds = YES;
    self.appIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.appIcon.backgroundColor =
        [UIColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:1.0];
    self.appIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.appIcon];

    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.font =
        [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
    self.nameLabel.textColor = [UIColor whiteColor];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.nameLabel];

    self.bundleIDLabel = [[UILabel alloc] init];
    self.bundleIDLabel.font =
        [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    self.bundleIDLabel.textColor =
        [UIColor colorWithWhite:0.40 alpha:1.0];
    self.bundleIDLabel.textAlignment = NSTextAlignmentCenter;
    self.bundleIDLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.bundleIDLabel];

    NSString *name = self.appInfo[@"name"] ?: @"Unknown";
    NSString *bid = self.appInfo[@"bundleID"] ?: @"";

    self.nameLabel.text = name;
    self.bundleIDLabel.text = bid;

    dispatch_async(self.workerQueue, ^{
        @autoreleasepool {
            UIImage *icon = nil;
            @try {
                icon = [self.manager iconForBundleID:bid];
            } @catch (NSException *e) { }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (icon) {
                    self.appIcon.image = icon;
                } else {
                    self.appIcon.image =
                        [UIImage systemImageNamed:@"app.fill"];
                    self.appIcon.tintColor =
                        [UIColor colorWithRed:0.55
                                        green:0.45
                                         blue:0.95 alpha:1.0];
                }
            });
        }
    });

    [NSLayoutConstraint activateConstraints:@[
        [self.appIcon.topAnchor
            constraintEqualToAnchor:self.contentView.topAnchor
            constant:20.0],
        [self.appIcon.centerXAnchor
            constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.appIcon.widthAnchor constraintEqualToConstant:80.0],
        [self.appIcon.heightAnchor constraintEqualToConstant:80.0],

        [self.nameLabel.topAnchor
            constraintEqualToAnchor:self.appIcon.bottomAnchor
            constant:12.0],
        [self.nameLabel.leadingAnchor
            constraintEqualToAnchor:self.contentView.leadingAnchor
            constant:20.0],
        [self.nameLabel.trailingAnchor
            constraintEqualToAnchor:self.contentView.trailingAnchor
            constant:-20.0],

        [self.bundleIDLabel.topAnchor
            constraintEqualToAnchor:self.nameLabel.bottomAnchor
            constant:4.0],
        [self.bundleIDLabel.leadingAnchor
            constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.bundleIDLabel.trailingAnchor
            constraintEqualToAnchor:self.nameLabel.trailingAnchor]
    ]];
}

- (UIView *)makeCardWithTitle:(NSString *)title
                        value:(NSString *)value
                         icon:(NSString *)iconName
                       topRef:(UIView *)topRef {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor =
        [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:1.0];
    card.layer.cornerRadius = 14.0;
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *icon =
        [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:iconName]];
    icon.tintColor =
        [UIColor colorWithRed:0.55 green:0.45 blue:0.95 alpha:1.0];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:icon];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.font =
        [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    titleLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    titleLabel.text = title;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:titleLabel];

    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.font =
        [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    valueLabel.textColor = [UIColor whiteColor];
    valueLabel.text = value ?: @"—";
    valueLabel.numberOfLines = 0;
    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:valueLabel];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor
            constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [icon.centerYAnchor
            constraintEqualToAnchor:card.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:22.0],
        [icon.heightAnchor constraintEqualToConstant:22.0],

        [titleLabel.leadingAnchor
            constraintEqualToAnchor:icon.trailingAnchor constant:10.0],
        [titleLabel.topAnchor
            constraintEqualToAnchor:card.topAnchor constant:12.0],
        [titleLabel.trailingAnchor
            constraintEqualToAnchor:card.trailingAnchor constant:-14.0],

        [valueLabel.leadingAnchor
            constraintEqualToAnchor:titleLabel.leadingAnchor],
        [valueLabel.topAnchor
            constraintEqualToAnchor:titleLabel.bottomAnchor constant:3.0],
        [valueLabel.trailingAnchor
            constraintEqualToAnchor:titleLabel.trailingAnchor],
        [valueLabel.bottomAnchor
            constraintEqualToAnchor:card.bottomAnchor constant:-12.0]
    ]];

    [self.contentView addSubview:card];

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor
            constraintEqualToAnchor:self.contentView.leadingAnchor
            constant:16.0],
        [card.trailingAnchor
            constraintEqualToAnchor:self.contentView.trailingAnchor
            constant:-16.0],
        [card.topAnchor
            constraintEqualToAnchor:topRef.bottomAnchor constant:10.0]
    ]];

    return card;
}

- (void)setupInfoCards {
    UIView *ref = self.bundleIDLabel;

    self.versionLabel =
        (UILabel *)[self makeCardWithTitle:@"الإصدار"
                                     value:self.appInfo[@"version"] ?: @"1.0"
                                      icon:@"number"
                                    topRef:ref];

    self.dataSizeLabel =
        (UILabel *)[self makeCardWithTitle:@"حجم البيانات"
                                     value:@"جاري الحساب..."
                                      icon:@"externaldrive.fill"
                                    topRef:(UIView *)self.versionLabel];

    self.documentsSizeLabel =
        (UILabel *)[self makeCardWithTitle:@"حجم المستندات"
                                     value:@"—"
                                      icon:@"doc.fill"
                                    topRef:(UIView *)self.dataSizeLabel];

    self.documentsCountLabel =
        (UILabel *)[self makeCardWithTitle:@"عدد الملفات"
                                     value:@"—"
                                      icon:@"folder.fill"
                                    topRef:(UIView *)self.documentsSizeLabel];

    self.lastBackupLabel =
        (UILabel *)[self makeCardWithTitle:@"آخر نسخة احتياطية"
                                     value:@"—"
                                      icon:@"clock.fill"
                                    topRef:(UIView *)self.documentsCountLabel];

    self.dataPathLabel =
        (UILabel *)[self makeCardWithTitle:@"مسار البيانات"
                                     value:@"—"
                                      icon:@"arrow.right.doc.fill"
                                    topRef:(UIView *)self.lastBackupLabel];

    self.documentsPathLabel =
        (UILabel *)[self makeCardWithTitle:@"مسار المستندات"
                                     value:@"—"
                                      icon:@"doc.text.fill"
                                    topRef:(UIView *)self.dataPathLabel];
}

- (void)setupActionButtons {
    UIButton *wipeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [wipeBtn setTitle:@"مسح البيانات" forState:UIControlStateNormal];
    [wipeBtn setTitleColor:[UIColor whiteColor]
                  forState:UIControlStateNormal];
    wipeBtn.backgroundColor =
        [UIColor colorWithRed:0.85 green:0.20 blue:0.20 alpha:1.0];
    wipeBtn.layer.cornerRadius = 12.0;
    wipeBtn.titleLabel.font =
        [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    wipeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [wipeBtn addTarget:self
                action:@selector(wipeTapped)
      forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:wipeBtn];

    UIButton *backupBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [backupBtn setTitle:@"نسخ احتياطي" forState:UIControlStateNormal];
    [backupBtn setTitleColor:[UIColor whiteColor]
                    forState:UIControlStateNormal];
    backupBtn.backgroundColor =
        [UIColor colorWithRed:0.20 green:0.55 blue:0.85 alpha:1.0];
    backupBtn.layer.cornerRadius = 12.0;
    backupBtn.titleLabel.font =
        [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    backupBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [backupBtn addTarget:self
                  action:@selector(backupTapped)
        forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:backupBtn];

    UIButton *manageBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [manageBtn setTitle:@"إدارة النسخ" forState:UIControlStateNormal];
    [manageBtn setTitleColor:[UIColor whiteColor]
                    forState:UIControlStateNormal];
    manageBtn.backgroundColor =
        [UIColor colorWithRed:0.55 green:0.45 blue:0.95 alpha:1.0];
    manageBtn.layer.cornerRadius = 12.0;
    manageBtn.titleLabel.font =
        [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    manageBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [manageBtn addTarget:self
                  action:@selector(manageBackupsTapped)
        forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:manageBtn];

    UIView *lastRef = (UIView *)self.documentsPathLabel;

    [NSLayoutConstraint activateConstraints:@[
        [wipeBtn.topAnchor
            constraintEqualToAnchor:lastRef.bottomAnchor constant:20.0],
        [wipeBtn.leadingAnchor
            constraintEqualToAnchor:self.contentView.leadingAnchor
            constant:16.0],
        [wipeBtn.trailingAnchor
            constraintEqualToAnchor:self.contentView.trailingAnchor
            constant:-16.0],
        [wipeBtn.heightAnchor constraintEqualToConstant:50.0],

        [backupBtn.topAnchor
            constraintEqualToAnchor:wipeBtn.bottomAnchor constant:10.0],
        [backupBtn.leadingAnchor
            constraintEqualToAnchor:wipeBtn.leadingAnchor],
        [backupBtn.trailingAnchor
            constraintEqualToAnchor:wipeBtn.trailingAnchor],
        [backupBtn.heightAnchor constraintEqualToConstant:50.0],

        [manageBtn.topAnchor
            constraintEqualToAnchor:backupBtn.bottomAnchor constant:10.0],
        [manageBtn.leadingAnchor
            constraintEqualToAnchor:wipeBtn.leadingAnchor],
        [manageBtn.trailingAnchor
            constraintEqualToAnchor:wipeBtn.trailingAnchor],
        [manageBtn.heightAnchor constraintEqualToConstant:50.0],
        [manageBtn.bottomAnchor
            constraintEqualToAnchor:self.contentView.bottomAnchor
            constant:-30.0]
    ]];
}

- (void)setupLoadingView {
    self.loadingIndicator =
        [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:
                UIActivityIndicatorViewStyleLarge];
    self.loadingIndicator.center = self.view.center;
    self.loadingIndicator.hidesWhenStopped = YES;
    self.loadingIndicator.color =
        [UIColor colorWithRed:0.55 green:0.45 blue:0.95 alpha:1.0];
    [self.view addSubview:self.loadingIndicator];
}

#pragma mark - Data Loading

- (void)loadDataAsync {
    [self.loadingIndicator startAnimating];

    NSString *bid = self.appInfo[@"bundleID"];
    if (!bid || bid.length == 0) {
        [self.loadingIndicator stopAnimating];
        return;
    }

    dispatch_async(self.workerQueue, ^{
        @autoreleasepool {
            NSString *version = @"1.0";
            unsigned long long dataSize = 0;
            unsigned long long docsSize = 0;
            NSUInteger docsCount = 0;
            NSString *dataPath = nil;
            NSString *docsPath = nil;
            NSDate *lastBackup = nil;
            BOOL isSystem = NO;

            @try {
                version = [self.manager versionForBundleID:bid];
            } @catch (NSException *e) { }

            @try {
                dataSize = [self.manager dataSizeForBundleID:bid];
            } @catch (NSException *e) { }

            @try {
                dataPath = [self.manager dataPathForBundleID:bid];
                if (dataPath) {
                    docsPath = [dataPath
                        stringByAppendingPathComponent:@"Documents"];
                    if (![[NSFileManager defaultManager]
                            fileExistsAtPath:docsPath]) {
                        docsPath = nil;
                    }
                }
            } @catch (NSException *e) { }

            @try {
                docsCount = [self.manager documentsCountForBundleID:bid];
            } @catch (NSException *e) { }

            @try {
                docsSize = [self.manager
                    accurateDataSizeForBundleID:bid];
            } @catch (NSException *e) { }

            @try {
                lastBackup = [self.manager lastBackupDateForBundleID:bid];
            } @catch (NSException *e) { }

            @try {
                isSystem = [self.manager isSystemApp:bid];
            } @catch (NSException *e) { }

            dispatch_async(dispatch_get_main_queue(), ^{
                [self.loadingIndicator stopAnimating];

                [self updateCard:self.versionLabel
                           value:version];
                [self updateCard:self.dataSizeLabel
                           value:[self.manager formatBytes:dataSize]];
                [self updateCard:self.documentsSizeLabel
                           value:[self.manager formatBytes:docsSize]];
                [self updateCard:self.documentsCountLabel
                           value:[NSString stringWithFormat:@"%lu",
                                   (unsigned long)docsCount]];

                NSDateFormatter *df = [[NSDateFormatter alloc] init];
                [df setDateFormat:@"yyyy-MM-dd HH:mm"];
                [self updateCard:self.lastBackupLabel
                           value:lastBackup ? [df stringFromDate:lastBackup]
                                            : @"لا توجد"];
                [self updateCard:self.dataPathLabel
                           value:dataPath ?: @"غير متاح"];
                [self updateCard:self.documentsPathLabel
                           value:docsPath ?: @"غير متاح"];

                self.isSystemApp = isSystem;
            });
        }
    });
}

- (void)updateCard:(UIView *)card value:(NSString *)value {
    for (UIView *sub in card.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)sub;
            if (label.font.pointSize >= 14.0) {
                label.text = value ?: @"—";
                return;
            }
        }
    }
}

#pragma mark - Actions

- (void)wipeTapped {
    if (self.isSystemApp) {
        [self showAlert:@"لا يمكن مسح بيانات التطبيقات النظامية"];
        return;
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"تأكيد"
                                            message:@"هل أنت متأكد من مسح البيانات؟"
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"إلغاء"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"مسح"
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *action) {
            [self performWipe];
        }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performWipe {
    NSString *bid = self.appInfo[@"bundleID"];
    if (!bid) return;

    [self.loadingIndicator startAnimating];

    dispatch_async(self.workerQueue, ^{
        BOOL success = NO;
        @try {
            success = [self.manager wipeAppData:bid];
        } @catch (NSException *e) {
            success = NO;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIndicator stopAnimating];
            [self showAlert:success
                ? @"تم مسح البيانات بنجاح"
                : @"فشل مسح البيانات"];
            if (success) [self loadDataAsync];
        });
    });
}

- (void)backupTapped {
    NSString *bid = self.appInfo[@"bundleID"];
    if (!bid) return;

    [self.loadingIndicator startAnimating];

    dispatch_async(self.workerQueue, ^{
        BOOL success = NO;
        @try {
            success = [self.manager backupAppData:bid];
        } @catch (NSException *e) {
            success = NO;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIndicator stopAnimating];
            [self showAlert:success
                ? @"تم إنشاء النسخة الاحتياطية"
                : @"فشل إنشاء النسخة"];
            if (success) [self loadDataAsync];
        });
    });
}

- (void)manageBackupsTapped {
    BackupManagerViewController *vc =
        [[BackupManagerViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showAlert:(NSString *)message {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@""
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:
        [UIAlertAction actionWithTitle:@"موافق"
                                 style:UIAlertActionStyleDefault
                               handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
