#import "AppDetailViewController.h"
#import "AppDataManager.h"

@interface InfoRowView : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@end

@implementation InfoRowView

- (instancetype)initWithTitle:(NSString *)title value:(NSString *)value {
    self = [super init];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
        self.layer.cornerRadius = 10;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = title;
        _titleLabel.font = [UIFont systemFontOfSize:14];
        _titleLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.text = value;
        _valueLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        _valueLabel.textColor = [UIColor whiteColor];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_valueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [_valueLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:16]
        ]];
    }
    return self;
}

@end

@interface AppDetailViewController ()
@property (nonatomic, strong) NSDictionary *appInfo;
@property (nonatomic, strong) AppDataManager *manager;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UILabel *bundleLabel;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIButton *backupButton;
@property (nonatomic, strong) UIButton *wipeButton;
@end

@implementation AppDetailViewController

- (instancetype)initWithAppInfo:(NSDictionary *)appInfo {
    self = [super init];
    if (self) {
        _appInfo = appInfo;
        _manager = [AppDataManager sharedManager];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];

    [self setupNavigationBar];
    [self setupScrollView];
    [self setupHeader];
    [self setupInfoSection];
    [self setupActionButtons];
}

- (void)setupNavigationBar {
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];

    // Delete button (trash)
    UIBarButtonItem *deleteBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash.fill"]
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(deleteAppTapped)];
    deleteBtn.tintColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0];
    self.navigationItem.rightBarButtonItem = deleteBtn;
}

- (void)setupScrollView {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentView.backgroundColor = [UIColor clearColor];
    [self.scrollView addSubview:self.contentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor]
    ]];
}

- (void)setupHeader {
    NSString *bundleID = self.appInfo[@"bundleID"];

    self.iconView = [[UIImageView alloc] init];
    self.iconView.layer.cornerRadius = 20;
    self.iconView.layer.masksToBounds = YES;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *icon = [self.manager iconForBundleID:bundleID];
    if (icon) {
        self.iconView.image = icon;
    } else {
        self.iconView.image = [UIImage systemImageNamed:@"app.fill"];
        self.iconView.tintColor = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];
        self.iconView.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    }
    [self.contentView addSubview:self.iconView];

    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.text = self.appInfo[@"name"];
    self.nameLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    self.nameLabel.textColor = [UIColor whiteColor];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.nameLabel];

    self.versionLabel = [[UILabel alloc] init];
    self.versionLabel.text = [self.manager versionForBundleID:bundleID];
    self.versionLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.versionLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    self.versionLabel.textAlignment = NSTextAlignmentCenter;
    self.versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.versionLabel];

    self.bundleLabel = [[UILabel alloc] init];
    self.bundleLabel.text = bundleID;
    self.bundleLabel.font = [UIFont systemFontOfSize:12];
    self.bundleLabel.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    self.bundleLabel.textAlignment = NSTextAlignmentCenter;
    self.bundleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.bundleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:20],
        [self.iconView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:80],
        [self.iconView.heightAnchor constraintEqualToConstant:80],

        [self.nameLabel.topAnchor constraintEqualToAnchor:self.iconView.bottomAnchor constant:16],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [self.versionLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:4],
        [self.versionLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.versionLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],

        [self.bundleLabel.topAnchor constraintEqualToAnchor:self.versionLabel.bottomAnchor constant:6],
        [self.bundleLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.bundleLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor]
    ]];
}

- (void)setupInfoSection {
    NSString *bundleID = self.appInfo[@"bundleID"];

    UIView *infoContainer = [[UIView alloc] init];
    infoContainer.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.10 alpha:1.0];
    infoContainer.layer.cornerRadius = 16;
    infoContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:infoContainer];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"MMM d, yyyy 'at' h:mm a"];
    NSDate *lastBackup = [self.manager lastBackupDateForBundleID:bundleID];
    NSString *lastBackupStr = lastBackup ? [formatter stringFromDate:lastBackup] : @"Never";

    NSArray *infos = @[
        @{@"title": @"Data Size", @"value": self.appInfo[@"sizeString"]},
        @{@"title": @"Documents", @"value": [NSString stringWithFormat:@"%lu files", (unsigned long)[self.manager documentsCountForBundleID:bundleID]]},
        @{@"title": @"Last Backup", @"value": lastBackupStr},
        @{@"title": @"Bundle ID", @"value": bundleID},
        @{@"title": @"Version", @"value": [self.manager versionForBundleID:bundleID]}
    ];

    UIView *lastView = nil;
    for (NSDictionary *info in infos) {
        InfoRowView *row = [[InfoRowView alloc] initWithTitle:info[@"title"] value:info[@"value"]];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [infoContainer addSubview:row];

        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:infoContainer.leadingAnchor constant:12],
            [row.trailingAnchor constraintEqualToAnchor:infoContainer.trailingAnchor constant:-12],
            [row.heightAnchor constraintEqualToConstant:48]
        ]];

        if (lastView) {
            [row.topAnchor constraintEqualToAnchor:lastView.bottomAnchor constant:4].active = YES;
        } else {
            [row.topAnchor constraintEqualToAnchor:infoContainer.topAnchor constant:12].active = YES;
        }
        lastView = row;
    }

    [lastView.bottomAnchor constraintEqualToAnchor:infoContainer.bottomAnchor constant:-12].active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [infoContainer.topAnchor constraintEqualToAnchor:self.bundleLabel.bottomAnchor constant:24],
        [infoContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [infoContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16]
    ]];
}

- (void)setupActionButtons {
    UIView *lastInfoView = self.contentView.subviews[self.contentView.subviews.count - 1];

    self.backupButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.backupButton setTitle:@"  Backup Data" forState:UIControlStateNormal];
    [self.backupButton setImage:[UIImage systemImageNamed:@"icloud.and.arrow.up.fill"] forState:UIControlStateNormal];
    self.backupButton.tintColor = [UIColor whiteColor];
    self.backupButton.backgroundColor = [UIColor colorWithRed:0.42 green:0.31 blue:0.90 alpha:1.0];
    self.backupButton.layer.cornerRadius = 14;
    self.backupButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.backupButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backupButton addTarget:self action:@selector(backupTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.backupButton];

    self.wipeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.wipeButton setTitle:@"  Wipe Data" forState:UIControlStateNormal];
    [self.wipeButton setImage:[UIImage systemImageNamed:@"trash.fill"] forState:UIControlStateNormal];
    self.wipeButton.tintColor = [UIColor whiteColor];
    self.wipeButton.backgroundColor = [UIColor colorWithRed:0.90 green:0.22 blue:0.27 alpha:1.0];
    self.wipeButton.layer.cornerRadius = 14;
    self.wipeButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.wipeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.wipeButton addTarget:self action:@selector(wipeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.wipeButton];

    BOOL isSystem = [self.appInfo[@"isSystemApp"] boolValue];
    self.wipeButton.alpha = isSystem ? 0.4 : 1.0;
    self.wipeButton.enabled = !isSystem;

    [NSLayoutConstraint activateConstraints:@[
        [self.backupButton.topAnchor constraintEqualToAnchor:lastInfoView.bottomAnchor constant:20],
        [self.backupButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.backupButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.backupButton.heightAnchor constraintEqualToConstant:56],

        [self.wipeButton.topAnchor constraintEqualToAnchor:self.backupButton.bottomAnchor constant:12],
        [self.wipeButton.leadingAnchor constraintEqualToAnchor:self.backupButton.leadingAnchor],
        [self.wipeButton.trailingAnchor constraintEqualToAnchor:self.backupButton.trailingAnchor],
        [self.wipeButton.heightAnchor constraintEqualToConstant:56],
        [self.wipeButton.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-30]
    ]];
}

#pragma mark - Actions

- (void)backupTapped {
    NSString *bundleID = self.appInfo[@"bundleID"];
    NSString *name = self.appInfo[@"name"];

    [self showSpinner];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL success = [self.manager backupAppData:bundleID];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideSpinner];
            [self showToast:success ? [NSString stringWithFormat:@"✅ Backup created for %@!", name] : [NSString stringWithFormat:@"❌ Failed to backup %@", name]];
        });
    });
}

- (void)wipeTapped {
    NSString *bundleID = self.appInfo[@"bundleID"];
    NSString *name = self.appInfo[@"name"];

    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"⚠️ WARNING"
                                                                   message:[NSString stringWithFormat:@"This will permanently delete ALL data for %@. This action cannot be undone!", name]
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Wipe Data" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self showSpinner];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            BOOL success = [self.manager wipeAppData:bundleID];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideSpinner];
                [self showToast:success ? [NSString stringWithFormat:@"✅ Data wiped for %@!", name] : [NSString stringWithFormat:@"❌ Failed to wipe %@", name]];
            });
        });
    }]];

    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)deleteAppTapped {
    [self showToast:@"ℹ️ Long press to uninstall app (feature coming soon)"];
}

#pragma mark - Helpers

- (void)showSpinner {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.tag = 999;
    spinner.center = self.view.center;
    spinner.color = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];
    [self.view addSubview:spinner];
    [spinner startAnimating];
}

- (void)hideSpinner {
    UIActivityIndicatorView *spinner = [self.view viewWithTag:999];
    [spinner stopAnimating];
    [spinner removeFromSuperview];
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
