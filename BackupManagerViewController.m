#import "BackupManagerViewController.h"
#import "AppDataManager.h"

// MARK: - Pie Chart View
@interface PieChartView : UIView
@property (nonatomic, strong) NSArray *segments; // @[@{@"value": @0.5, @"color": UIColor}]
@property (nonatomic, strong) UILabel *centerLabel;
@end

@implementation PieChartView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        _centerLabel = [[UILabel alloc] init];
        _centerLabel.textAlignment = NSTextAlignmentCenter;
        _centerLabel.numberOfLines = 0;
        _centerLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_centerLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_centerLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_centerLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
        ]];
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    if (!self.segments || self.segments.count == 0) return;

    CGFloat total = 0;
    for (NSDictionary *seg in self.segments) {
        total += [seg[@"value"] floatValue];
    }
    if (total == 0) return;

    CGPoint center = CGPointMake(rect.size.width / 2.0, rect.size.height / 2.0);
    CGFloat radius = MIN(rect.size.width, rect.size.height) / 2.0 - 10;
    CGFloat innerRadius = radius * 0.65;
    CGFloat startAngle = -M_PI_2;

    CGContextRef ctx = UIGraphicsGetCurrentContext();

    for (NSDictionary *seg in self.segments) {
        CGFloat value = [seg[@"value"] floatValue];
        CGFloat angle = (value / total) * 2 * M_PI;
        CGFloat endAngle = startAngle + angle;
        UIColor *color = seg[@"color"];

        // Outer arc
        UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center
                                                            radius:radius
                                                        startAngle:startAngle
                                                          endAngle:endAngle
                                                         clockwise:YES];
        // Inner arc (reverse)
        [path addArcWithCenter:center
                        radius:innerRadius
                    startAngle:endAngle
                      endAngle:startAngle
                     clockwise:NO];
        [path closePath];

        [color setFill];
        [path fill];

        startAngle = endAngle;
    }

    // Cutout center
    UIBezierPath *centerPath = [UIBezierPath bezierPathWithArcCenter:center
                                                              radius:innerRadius - 2
                                                          startAngle:0
                                                            endAngle:2 * M_PI
                                                           clockwise:YES];
    [[UIColor colorWithRed:0.06 green:0.06 blue:0.10 alpha:1.0] setFill];
    [centerPath fill];
}

@end

// MARK: - Backup Cell
@interface BackupCell : UITableViewCell
@property (nonatomic, strong) UIImageView *appIcon;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UIButton *restoreButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIView *containerView;
@end

@implementation BackupCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _containerView = [[UIView alloc] init];
        _containerView.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
        _containerView.layer.cornerRadius = 12;
        _containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_containerView];

        _appIcon = [[UIImageView alloc] init];
        _appIcon.layer.cornerRadius = 8;
        _appIcon.layer.masksToBounds = YES;
        _appIcon.contentMode = UIViewContentModeScaleAspectFit;
        _appIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_appIcon];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _nameLabel.textColor = [UIColor whiteColor];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_nameLabel];

        _dateLabel = [[UILabel alloc] init];
        _dateLabel.font = [UIFont systemFontOfSize:12];
        _dateLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_dateLabel];

        _sizeLabel = [[UILabel alloc] init];
        _sizeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _sizeLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_sizeLabel];

        _restoreButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_restoreButton setImage:[UIImage systemImageNamed:@"arrow.counterclockwise"] forState:UIControlStateNormal];
        _restoreButton.tintColor = [UIColor colorWithRed:0.3 green:0.6 blue:0.9 alpha:1.0];
        _restoreButton.backgroundColor = [UIColor colorWithRed:0.08 green:0.12 blue:0.20 alpha:1.0];
        _restoreButton.layer.cornerRadius = 8;
        _restoreButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_restoreButton];

        _deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_deleteButton setImage:[UIImage systemImageNamed:@"trash.fill"] forState:UIControlStateNormal];
        _deleteButton.tintColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0];
        _deleteButton.backgroundColor = [UIColor colorWithRed:0.20 green:0.08 blue:0.08 alpha:1.0];
        _deleteButton.layer.cornerRadius = 8;
        _deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_deleteButton];

        [NSLayoutConstraint activateConstraints:@[
            [_containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_containerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_containerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
            [_containerView.heightAnchor constraintEqualToConstant:72],

            [_appIcon.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:12],
            [_appIcon.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
            [_appIcon.widthAnchor constraintEqualToConstant:44],
            [_appIcon.heightAnchor constraintEqualToConstant:44],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_appIcon.trailingAnchor constant:12],
            [_nameLabel.topAnchor constraintEqualToAnchor:_containerView.topAnchor constant:14],

            [_dateLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_dateLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:4],

            [_sizeLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_sizeLabel.topAnchor constraintEqualToAnchor:_dateLabel.bottomAnchor constant:2],

            [_deleteButton.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor constant:-12],
            [_deleteButton.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
            [_deleteButton.widthAnchor constraintEqualToConstant:36],
            [_deleteButton.heightAnchor constraintEqualToConstant:36],

            [_restoreButton.trailingAnchor constraintEqualToAnchor:_deleteButton.leadingAnchor constant:-8],
            [_restoreButton.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
            [_restoreButton.widthAnchor constraintEqualToConstant:36],
            [_restoreButton.heightAnchor constraintEqualToConstant:36]
        ]];
    }
    return self;
}

@end

// MARK: - BackupManagerViewController
@interface BackupManagerViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *backups;
@property (nonatomic, strong) AppDataManager *manager;
@property (nonatomic, strong) PieChartView *pieChart;
@property (nonatomic, strong) UIView *statsContainer;
@end

@implementation BackupManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Backups";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    self.manager = [AppDataManager sharedManager];

    [self setupNavigationBar];
    [self setupStatsView];
    [self setupTableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadBackups];
}

- (void)setupNavigationBar {
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    [self.navigationController.navigationBar setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}];
    [self.navigationController.navigationBar setLargeTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];

    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"]
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(addBackupTapped)];
    addBtn.tintColor = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];
    self.navigationItem.rightBarButtonItem = addBtn;
}

- (void)setupStatsView {
    self.statsContainer = [[UIView alloc] init];
    self.statsContainer.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.10 alpha:1.0];
    self.statsContainer.layer.cornerRadius = 16;
    self.statsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statsContainer];

    self.pieChart = [[PieChartView alloc] init];
    self.pieChart.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statsContainer addSubview:self.pieChart];

    // Legend
    NSArray *legendItems = @[
        @{@"color": [UIColor colorWithRed:0.42 green:0.31 blue:0.90 alpha:1.0], @"label": @"Backups"},
        @{@"color": [UIColor colorWithRed:0.25 green:0.55 blue:0.90 alpha:1.0], @"label": @"Apps"},
        @{@"color": [UIColor colorWithWhite:0.25 alpha:1.0], @"label": @"Free"}
    ];

    UIView *lastLegend = nil;
    for (NSDictionary *item in legendItems) {
        UIView *dot = [[UIView alloc] init];
        dot.backgroundColor = item[@"color"];
        dot.layer.cornerRadius = 4;
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        [self.statsContainer addSubview:dot];

        UILabel *label = [[UILabel alloc] init];
        label.text = item[@"label"];
        label.font = [UIFont systemFontOfSize:13];
        label.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [self.statsContainer addSubview:label];

        UILabel *valueLabel = [[UILabel alloc] init];
        valueLabel.tag = [item[@"label"] hash];
        valueLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        valueLabel.textColor = [UIColor whiteColor];
        valueLabel.textAlignment = NSTextAlignmentRight;
        valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.statsContainer addSubview:valueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [dot.widthAnchor constraintEqualToConstant:8],
            [dot.heightAnchor constraintEqualToConstant:8],
            [dot.leadingAnchor constraintEqualToAnchor:self.pieChart.trailingAnchor constant:20],

            [label.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:10],
            [label.centerYAnchor constraintEqualToAnchor:dot.centerYAnchor],

            [valueLabel.trailingAnchor constraintEqualToAnchor:self.statsContainer.trailingAnchor constant:-16],
            [valueLabel.centerYAnchor constraintEqualToAnchor:dot.centerYAnchor],
            [valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:8]
        ]];

        if (lastLegend) {
            [dot.topAnchor constraintEqualToAnchor:lastLegend.bottomAnchor constant:16].active = YES;
        } else {
            [dot.topAnchor constraintEqualToAnchor:self.pieChart.topAnchor constant:20].active = YES;
        }
        lastLegend = dot;
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.statsContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.statsContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.statsContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.statsContainer.heightAnchor constraintEqualToConstant:180],

        [self.pieChart.leadingAnchor constraintEqualToAnchor:self.statsContainer.leadingAnchor constant:20],
        [self.pieChart.centerYAnchor constraintEqualToAnchor:self.statsContainer.centerYAnchor],
        [self.pieChart.widthAnchor constraintEqualToConstant:130],
        [self.pieChart.heightAnchor constraintEqualToConstant:130]
    ]];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 20, 0);
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.statsContainer.bottomAnchor constant:16],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)loadBackups {
    NSMutableArray *allBackups = [NSMutableArray array];
    NSArray *apps = [self.manager allInstalledApplications];

    for (NSDictionary *app in apps) {
        NSArray *appBackups = [self.manager availableBackupsForBundleID:app[@"bundleID"]];
        for (NSDictionary *backup in appBackups) {
            NSMutableDictionary *fullBackup = [backup mutableCopy];
            fullBackup[@"appName"] = app[@"name"];
            fullBackup[@"bundleID"] = app[@"bundleID"];
            [allBackups addObject:fullBackup];
        }
    }

    self.backups = [allBackups sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"date"] compare:a[@"date"]];
    }];

    [self updateChart];
    [self.tableView reloadData];
}

- (void)updateChart {
    unsigned long long backupsSize = [self.manager totalBackupsSize];
    unsigned long long appsSize = [self.manager totalAppsDataSize];
    unsigned long long freeSpace = 50ULL * 1024 * 1024 * 1024; // Approximate 50GB free placeholder

    unsigned long long total = backupsSize + appsSize + freeSpace;
    if (total == 0) total = 1;

    self.pieChart.segments = @[
        @{@"value": @(backupsSize), @"color": [UIColor colorWithRed:0.42 green:0.31 blue:0.90 alpha:1.0]},
        @{@"value": @(appsSize), @"color": [UIColor colorWithRed:0.25 green:0.55 blue:0.90 alpha:1.0]},
        @{@"value": @(freeSpace), @"color": [UIColor colorWithWhite:0.25 alpha:1.0]}
    ];

    self.pieChart.centerLabel.attributedText = [[NSAttributedString alloc] initWithString:
        [NSString stringWithFormat:@"%@\n%@", [self.manager formatBytes:backupsSize + appsSize], @"Total"]
        attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:11],
            NSForegroundColorAttributeName: [UIColor colorWithWhite:0.5 alpha:1.0]
        }];

    [self.pieChart setNeedsDisplay];

    // Update legend values
    for (UIView *subview in self.statsContainer.subviews) {
        if ([subview isKindOfClass:[UILabel class]] && subview.tag != 0) {
            UILabel *label = (UILabel *)subview;
            if (label.tag == [@"Backups" hash]) {
                label.text = [self.manager formatBytes:backupsSize];
            } else if (label.tag == [@"Apps" hash]) {
                label.text = [self.manager formatBytes:appsSize];
            } else if (label.tag == [@"Free" hash]) {
                label.text = [self.manager formatBytes:freeSpace];
            }
        }
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.backups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"BackupCell";
    BackupCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[BackupCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
    }

    NSDictionary *backup = self.backups[indexPath.row];
    cell.nameLabel.text = backup[@"appName"];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"MMM d, yyyy 'at' h:mm a"];
    NSString *dateStr = [formatter stringFromDate:backup[@"date"]];
    cell.dateLabel.text = dateStr;
    cell.sizeLabel.text = backup[@"sizeString"];

    NSString *bundleID = backup[@"bundleID"];
    UIImage *icon = [self.manager iconForBundleID:bundleID];
    if (icon) {
        cell.appIcon.image = icon;
    } else {
        cell.appIcon.image = [UIImage systemImageNamed:@"app.fill"];
        cell.appIcon.tintColor = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];
    }

    cell.restoreButton.tag = indexPath.row;
    [cell.restoreButton addTarget:self action:@selector(restoreTapped:) forControlEvents:UIControlEventTouchUpInside];

    cell.deleteButton.tag = indexPath.row;
    [cell.deleteButton addTarget:self action:@selector(deleteTapped:) forControlEvents:UIControlEventTouchUpInside];

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 80;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = [UIColor clearColor];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, 200, 24)];
    label.text = @"Available Backups";
    label.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    label.textColor = [UIColor whiteColor];
    [header addSubview:label];

    UILabel *countLabel = [[UILabel alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 60, 8, 40, 24)];
    countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.backups.count];
    countLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    countLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    countLabel.textAlignment = NSTextAlignmentRight;
    [header addSubview:countLabel];

    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 40;
}

#pragma mark - Actions

- (void)restoreTapped:(UIButton *)sender {
    NSDictionary *backup = self.backups[sender.tag];
    NSString *bundleID = backup[@"bundleID"];
    NSString *path = backup[@"path"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Confirm Restore"
                                                                   message:[NSString stringWithFormat:@"This will replace current data with this backup for %@. Continue?", backup[@"appName"]]
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showSpinner];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            BOOL success = [self.manager restoreAppData:bundleID fromBackup:path];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideSpinner];
                [self showToast:success ? @"✅ Restore completed!" : @"❌ Restore failed!"];
            });
        });
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteTapped:(UIButton *)sender {
    NSDictionary *backup = self.backups[sender.tag];
    NSString *path = backup[@"path"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Confirm Delete"
                                                                   message:@"This backup will be permanently deleted."
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self showSpinner];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            BOOL success = [self.manager deleteBackup:path];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideSpinner];
                if (success) {
                    [self loadBackups];
                }
                [self showToast:success ? @"✅ Backup deleted!" : @"❌ Failed to delete!"];
            });
        });
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addBackupTapped {
    [self showToast:@"ℹ️ Go to Apps tab to create a new backup"];
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
