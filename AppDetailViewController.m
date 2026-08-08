#import "AppDetailViewController.h"
#import "AppDataManager.h"
#import "BackupManagerViewController.h"

@interface AppDetailViewController ()
@property (nonatomic, strong) NSDictionary *app;
@property (nonatomic, strong) UIScrollView *scrollView;
@end

@implementation AppDetailViewController

- (instancetype)initWithApp:(NSDictionary *)app {
    self = [super init];
    if (self) {
        _app = app;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    self.title = self.app[@"name"];

    [self setupUI];
}

- (void)setupUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:contentView];

    [NSLayoutConstraint activateConstraints:@[
        [contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor]
    ]];

    // App icon
    UIView *iconView = [[UIView alloc] init];
    iconView.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:1.0];
    iconView.layer.cornerRadius = 20;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:iconView];

    UILabel *iconLabel = [[UILabel alloc] init];
    iconLabel.text = [self.app[@"name"] substringToIndex:1];
    iconLabel.font = [UIFont boldSystemFontOfSize:36];
    iconLabel.textColor = [UIColor whiteColor];
    iconLabel.textAlignment = NSTextAlignmentCenter;
    iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [iconView addSubview:iconLabel];

    [NSLayoutConstraint activateConstraints:@[
        [iconLabel.centerXAnchor constraintEqualToAnchor:iconView.centerXAnchor],
        [iconLabel.centerYAnchor constraintEqualToAnchor:iconView.centerYAnchor]
    ]];

    // App name
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = self.app[@"name"];
    nameLabel.font = [UIFont boldSystemFontOfSize:24];
    nameLabel.textColor = [UIColor whiteColor];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:nameLabel];

    // Bundle ID
    UILabel *bundleLabel = [[UILabel alloc] init];
    bundleLabel.text = self.app[@"bundleID"];
    bundleLabel.font = [UIFont systemFontOfSize:13];
    bundleLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    bundleLabel.textAlignment = NSTextAlignmentCenter;
    bundleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:bundleLabel];

    // Info card
    UIView *infoCard = [self createInfoCard];
    [contentView addSubview:infoCard];

    // Backup button
    UIButton *backupButton = [self createActionButtonWithTitle:@"Backup Data" 
                                                      subtitle:@"Create a backup of app data" 
                                                           icon:@"\u2601" 
                                                        bgColor:[UIColor colorWithRed:0.4 green:0.3 blue:0.9 alpha:1.0]];
    [backupButton addTarget:self action:@selector(backupTapped) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:backupButton];

    // Wipe button
    UIButton *wipeButton = [self createActionButtonWithTitle:@"Wipe Data" 
                                                    subtitle:@"Delete all app data" 
                                                         icon:@"\U0001F5D1" 
                                                      bgColor:[UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1.0]];
    [wipeButton addTarget:self action:@selector(wipeTapped) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:wipeButton];

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [iconView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:30],
        [iconView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [iconView.widthAnchor constraintEqualToConstant:80],
        [iconView.heightAnchor constraintEqualToConstant:80],

        [nameLabel.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:16],
        [nameLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [nameLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        [bundleLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:8],
        [bundleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [bundleLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        [infoCard.topAnchor constraintEqualToAnchor:bundleLabel.bottomAnchor constant:24],
        [infoCard.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:16],
        [infoCard.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-16],

        [backupButton.topAnchor constraintEqualToAnchor:infoCard.bottomAnchor constant:24],
        [backupButton.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:16],
        [backupButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-16],
        [backupButton.heightAnchor constraintEqualToConstant:70],

        [wipeButton.topAnchor constraintEqualToAnchor:backupButton.bottomAnchor constant:12],
        [wipeButton.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:16],
        [wipeButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-16],
        [wipeButton.heightAnchor constraintEqualToConstant:70],
        [wipeButton.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-40]
    ]];
}

- (UIView *)createInfoCard {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    card.layer.cornerRadius = 16;
    card.translatesAutoresizingMaskIntoConstraints = NO;

    NSArray *infos = @[
        @{@"title": @"Data Size", @"value": self.app[@"sizeString"]},
        @{@"title": @"Bundle ID", @"value": self.app[@"bundleID"]},
        @{@"title": @"Type", @"value": self.app[@"type"]}
    ];

    UIView *lastView = nil;
    for (NSDictionary *info in infos) {
        UIView *row = [[UIView alloc] init];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:row];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = info[@"title"];
        titleLabel.font = [UIFont systemFontOfSize:14];
        titleLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:titleLabel];

        UILabel *valueLabel = [[UILabel alloc] init];
        valueLabel.text = info[@"value"];
        valueLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        valueLabel.textColor = [UIColor whiteColor];
        valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:valueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
            [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
            [row.heightAnchor constraintEqualToConstant:44],

            [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [titleLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

            [valueLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [valueLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
        ]];

        if (lastView) {
            [row.topAnchor constraintEqualToAnchor:lastView.bottomAnchor].active = YES;
        } else {
            [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:8].active = YES;
        }
        lastView = row;
    }

    [lastView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-8].active = YES;

    return card;
}

- (UIButton *)createActionButtonWithTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon bgColor:(UIColor *)bgColor {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = bgColor;
    button.layer.cornerRadius = 14;
    button.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *iconLabel = [[UILabel alloc] init];
    iconLabel.text = icon;
    iconLabel.font = [UIFont systemFontOfSize:24];
    iconLabel.textColor = [UIColor whiteColor];
    iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [button addSubview:iconLabel];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [button addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = subtitle;
    subtitleLabel.font = [UIFont systemFontOfSize:12];
    subtitleLabel.textColor = [UIColor colorWithWhite:0.8 alpha:0.8];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [button addSubview:subtitleLabel];

    UILabel *arrowLabel = [[UILabel alloc] init];
    arrowLabel.text = @">";
    arrowLabel.font = [UIFont systemFontOfSize:18];
    arrowLabel.textColor = [UIColor whiteColor];
    arrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [button addSubview:arrowLabel];

    [NSLayoutConstraint activateConstraints:@[
        [iconLabel.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:16],
        [iconLabel.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconLabel.trailingAnchor constant:12],
        [titleLabel.topAnchor constraintEqualToAnchor:button.topAnchor constant:14],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2],

        [arrowLabel.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-16],
        [arrowLabel.centerYAnchor constraintEqualToAnchor:button.centerYAnchor]
    ]];

    return button;
}

- (void)backupTapped {
    NSString *bundleID = self.app[@"bundleID"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Confirm Backup"
                                                                   message:[NSString stringWithFormat:@"This will create a backup of all data for %@.", self.app[@"name"]]
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Backup" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        BOOL success = [[AppDataManager sharedManager] backupAppData:bundleID];

        NSString *message = success ? @"✅ Backup created successfully!" : @"❌ Failed to create backup!";
        UIAlertController *result = [UIAlertController alertControllerWithTitle:@"" message:message preferredStyle:UIAlertControllerStyleAlert];
        [result addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:result animated:YES completion:nil];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)wipeTapped {
    NSString *bundleID = self.app[@"bundleID"];

    if ([[AppDataManager sharedManager] isSystemApp:bundleID]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Warning"
                                                                       message:@"⚠️ Cannot wipe system apps!"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Confirm Wipe"
                                                                   message:[NSString stringWithFormat:@"This will permanently delete all data for %@. This action cannot be undone.", self.app[@"name"]]
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Wipe" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        BOOL success = [[AppDataManager sharedManager] wipeAppData:bundleID];

        NSString *message = success ? @"✅ Data wiped successfully!" : @"❌ Failed to wipe data!";
        UIAlertController *result = [UIAlertController alertControllerWithTitle:@"" message:message preferredStyle:UIAlertControllerStyleAlert];
        [result addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:result animated:YES completion:nil];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end