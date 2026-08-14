//
//  BackupManagerViewController.m
//  AppDataManager
//
//  v1.6.0 — Crash-Resilient Backup Manager
//

#import "BackupManagerViewController.h"
#import "AppDataManager.h"

#pragma mark - Pie Chart View

@interface PieChartView : UIView
@property (nonatomic, strong) NSArray *segments;
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
            [_centerLabel.centerXAnchor
                constraintEqualToAnchor:self.centerXAnchor],
            [_centerLabel.centerYAnchor
                constraintEqualToAnchor:self.centerYAnchor]
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

    CGPoint center = CGPointMake(rect.size.width / 2.0,
                                  rect.size.height / 2.0);
    CGFloat radius = MIN(rect.size.width, rect.size.height) / 2.0 - 10;
    CGFloat innerRadius = radius * 0.65;
    CGFloat startAngle = -M_PI_2;

    for (NSDictionary *seg in self.segments) {
        CGFloat value = [seg[@"value"] floatValue];
        CGFloat angle = (value / total) * 2 * M_PI;
        CGFloat endAngle = startAngle + angle;
        UIColor *color = seg[@"color"];

        UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center
                                                            radius:radius
                                                        startAngle:startAngle
                                                          endAngle:endAngle
                                                         clockwise:YES];
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

    UIBezierPath *centerPath = [UIBezierPath bezierPathWithArcCenter:center
                                                              radius:innerRadius - 2
                                                          startAngle:0
                                                            endAngle:2 * M_PI
                                                           clockwise:YES];
    [[UIColor colorWithRed:0.06 green:0.06 blue:0.10 alpha:1.0] setFill];
    [centerPath fill];
}

@end

#pragma mark - Backup Cell

@interface BackupCell : UITableViewCell
@property (nonatomic, strong) UIImageView *appIcon;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UIButton *restoreButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, copy) void (^restoreAction)(void);
@property (nonatomic, copy) void (^deleteAction)(void);
@end

@implementation BackupCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _containerView = [[UIView alloc] init];
        _containerView.backgroundColor =
            [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
        _containerView.layer.cornerRadius = 12.0;
        _containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_containerView];

        _appIcon = [[UIImageView alloc] init];
        _appIcon.layer.cornerRadius = 8.0;
        _appIcon.layer.masksToBounds = YES;
        _appIcon.contentMode = UIViewContentModeScaleAspectFit;
        _appIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_appIcon];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font =
            [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
        _nameLabel.textColor = [UIColor whiteColor];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_nameLabel];

        _dateLabel = [[UILabel alloc] init];
        _dateLabel.font = [UIFont systemFontOfSize:12.0];
        _dateLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_dateLabel];

        _sizeLabel = [[UILabel alloc] init];
        _sizeLabel.font =
            [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
        _sizeLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_sizeLabel];

        _restoreButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_restoreButton setImage:[UIImage systemImageNamed:@"arrow.counterclockwise"]
                        forState:UIControlStateNormal];
        _restoreButton.tintColor =
            [UIColor colorWithRed:0.3 green:0.6 blue:0.9 alpha:1.0];
        _restoreButton.backgroundColor =
            [UIColor colorWithRed:0.08 green:0.12 blue:0.20 alpha:1.0];
        _restoreButton.layer.cornerRadius = 8.0;
        _restoreButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_restoreButton addTarget:self
                           action:@selector(restoreButtonTapped)
                 forControlEvents:UIControlEventTouchUpInside];
        [_containerView addSubview:_restoreButton];

        _deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_deleteButton setImage:[UIImage systemImageNamed:@"trash.fill"]
                       forState:UIControlStateNormal];
        _deleteButton.tintColor =
            [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0];
        _deleteButton.backgroundColor =
            [UIColor colorWithRed:0.20 green:0.08 blue:0.08 alpha:1.0];
        _deleteButton.layer.cornerRadius = 8.0;
        _deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_deleteButton addTarget:self
                          action:@selector(deleteButtonTapped)
                forControlEvents:UIControlEventTouchUpInside];
        [_containerView addSubview:_deleteButton];

        [NSLayoutConstraint activateConstraints:@[
            [_containerView.topAnchor
                constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
            [_containerView.leadingAnchor
                constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_containerView.trailingAnchor
                constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_containerView.bottomAnchor
                constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],
            [_containerView.heightAnchor constraintEqualToConstant:72.0],

            [_appIcon.leadingAnchor
                constraintEqualToAnchor:_containerView.leadingAnchor constant:12.0],
            [_appIcon.centerYAnchor
                constraintEqualToAnchor:_containerView.centerYAnchor],
            [_appIcon.widthAnchor constraintEqualToConstant:44.0],
            [_appIcon.heightAnchor constraintEqualToConstant:44.0],

            [_nameLabel.leadingAnchor
                constraintEqualToAnchor:_appIcon.trailingAnchor constant:12.0],
            [_nameLabel.topAnchor
                constraintEqualToAnchor:_containerView.topAnchor constant:14.0],

            [_dateLabel.leadingAnchor
                constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_dateLabel.topAnchor
                constraintEqualToAnchor:_nameLabel.bottomAnchor constant:4.0],

            [_sizeLabel.leadingAnchor
                constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_sizeLabel.topAnchor
                constraintEqualToAnchor:_dateLabel.bottomAnchor constant:2.0],

            [_deleteButton.trailingAnchor
                constraintEqualToAnchor:_containerView.trailingAnchor constant:-12.0],
            [_deleteButton.centerYAnchor
                constraintEqualToAnchor:_containerView.centerYAnchor],
            [_deleteButton.widthAnchor constraintEqualToConstant:36.0],
            [_deleteButton.heightAnchor constraintEqualToConstant:36.0],

            [_restoreButton.trailingAnchor
                constraintEqualToAnchor:_deleteButton.leadingAnchor constant:-8.0],
            [_restoreButton.centerYAnchor
                constraintEqualToAnchor:_containerView.centerYAnchor],
            [_restoreButton.widthAnchor constraintEqualToConstant:36.0],
            [_restoreButton.heightAnchor constraintEqualToConstant:36.0]
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.restoreAction = nil;
    self.deleteAction = nil;
    self.appIcon.image = nil;
    self.nameLabel.text = nil;
    self.dateLabel.text = nil;
    self.sizeLabel.text = nil;
}

- (void)restoreButtonTapped {
    if (self.restoreAction) self.restoreAction();
}

- (void)deleteButtonTapped {
    if (self.deleteAction) self.deleteAction();
}

@end

#pragma mark - BackupManagerViewController

@interface BackupManagerViewController () <
    UITableViewDelegate,
    UITableViewDataSource
>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *backups;
@property (nonatomic, strong) AppDataManager *manager;
@property (nonatomic, strong) PieChartView *pieChart;
@property (nonatomic, strong) UIView *statsContainer;

@property (nonatomic, strong) UILabel *backupsValueLabel;
@property (nonatomic, strong) UILabel *appsValueLabel;
@property (nonatomic, strong) UILabel *freeValueLabel;

@property (nonatomic, strong) dispatch_queue_t workerQueue;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@end

@implementation BackupManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Backups";
    self.view.backgroundColor =
        [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    self.manager = [AppDataManager sharedManager];
    self.workerQueue = dispatch_queue_create(
        "com.appdatamanager.backupworker", DISPATCH_QUEUE_SERIAL);

    [self setupNavigationBar];
    [self setupStatsView];
    [self setupTableView];
    [self setupSpinner];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadBackups];
}

#pragma mark - UI Setup

- (void)setupNavigationBar {
    UINavigationBar *bar = self.navigationController.navigationBar;
    bar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode =
        UINavigationItemLargeTitleDisplayModeAlways;

    [bar setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor whiteColor]
    }];
    [bar setLargeTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor whiteColor]
    }];
    bar.barTintColor =
        [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];

    UIBarButtonItem *addBtn =
        [[UIBarButtonItem alloc]
            initWithImage:[UIImage systemImageNamed:@"plus"]
                      style:UIBarButtonItemStylePlain
                     target:self
                     action:@selector(addBackupTapped)];
    addBtn.tintColor =
        [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];
    self.navigationItem.rightBarButtonItem = addBtn;
}

- (void)setupStatsView {
    self.statsContainer = [[UIView alloc] init];
    self.statsContainer.backgroundColor =
        [UIColor colorWithRed:0.06 green:0.06 blue:0.10 alpha:1.0];
    self.statsContainer.layer.cornerRadius = 16.0;
    self.statsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statsContainer];

    self.pieChart = [[PieChartView alloc] init];
    self.pieChart.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statsContainer addSubview:self.pieChart];

    NSArray *legendItems = @[
        @{@"color": [UIColor colorWithRed:0.42 green:0.31 blue:0.90 alpha:1.0],
          @"label": @"Backups",
          @"key": @"backups"},
        @{@"color": [UIColor colorWithRed:0.25 green:0.55 blue:0.90 alpha:1.0],
          @"label": @"Apps",
          @"key": @"apps"},
        @{@"color": [UIColor colorWithWhite:0.25 alpha:1.0],
          @"label": @"Free",
          @"key": @"free"}
    ];

    UIView *lastLegend = nil;
    for (NSDictionary *item in legendItems) {
        UIView *dot = [[UIView alloc] init];
        dot.backgroundColor = item[@"color"];
        dot.layer.cornerRadius = 4.0;
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        [self.statsContainer addSubview:dot];

        UILabel *label = [[UILabel alloc] init];
        label.text = item[@"label"];
        label.font = [UIFont systemFontOfSize:13.0];
        label.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [self.statsContainer addSubview:label];

        UILabel *valueLabel = [[UILabel alloc] init];
        valueLabel.font =
            [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        valueLabel.textColor = [UIColor whiteColor];
        valueLabel.textAlignment = NSTextAlignmentRight;
        valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.statsContainer addSubview:valueLabel];

        NSString *key = item[@"key"];
        if ([key isEqualToString:@"backups"]) {
            self.backupsValueLabel = valueLabel;
        } else if ([key isEqualToString:@"apps"]) {
            self.appsValueLabel = valueLabel;
        } else if ([key isEqualToString:@"free"]) {
            self.freeValueLabel = valueLabel;
        }

        [NSLayoutConstraint activateConstraints:@[
            [dot.widthAnchor constraintEqualToConstant:8.0],
            [dot.heightAnchor constraintEqualToConstant:8.0],
            [dot.leadingAnchor
                constraintEqualToAnchor:self.pieChart.trailingAnchor
                constant:20.0],

            [label.leadingAnchor
                constraintEqualToAnchor:dot.trailingAnchor constant:10.0],
            [label.centerYAnchor
                constraintEqualToAnchor:dot.centerYAnchor],

            [valueLabel.trailingAnchor
                constraintEqualToAnchor:self.statsContainer.trailingAnchor
                constant:-16.0],
            [valueLabel.centerYAnchor
                constraintEqualToAnchor:dot.centerYAnchor],
            [valueLabel.leadingAnchor
                constraintGreaterThanOrEqualToAnchor:label.trailingAnchor
                constant:8.0]
        ]];

        if (lastLegend) {
            [dot.topAnchor
                constraintEqualToAnchor:lastLegend.bottomAnchor
                constant:16.0].active = YES;
        } else {
            [dot.topAnchor
                constraintEqualToAnchor:self.pieChart.topAnchor
                constant:20.0].active = YES;
        }
        lastLegend = dot;
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.statsContainer.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
            constant:12.0],
        [self.statsContainer.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [self.statsContainer.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [self.statsContainer.heightAnchor constraintEqualToConstant:180.0],

        [self.pieChart.leadingAnchor
            constraintEqualToAnchor:self.statsContainer.leadingAnchor
            constant:20.0],
        [self.pieChart.centerYAnchor
            constraintEqualToAnchor:self.statsContainer.centerYAnchor],
        [self.pieChart.widthAnchor constraintEqualToConstant:130.0],
        [self.pieChart.heightAnchor constraintEqualToConstant:130.0]
    ]];
}

- (void)setupTableView {
    self.tableView =
        [[UITableView alloc] initWithFrame:CGRectZero
                                     style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, 20.0, 0.0);
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor
            constraintEqualToAnchor:self.statsContainer.bottomAnchor
            constant:16.0],
        [self.tableView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor
            constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupSpinner {
    self.spinner =
        [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:
                UIActivityIndicatorViewStyleLarge];
    self.spinner.center = self.view.center;
    self.spinner.hidesWhenStopped = YES;
    self.spinner.color =
        [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];
    [self.view addSubview:self.spinner];
}

#pragma mark - Data Loading

- (void)loadBackups {
    [self.spinner startAnimating];

    dispatch_async(self.workerQueue, ^{
        @autoreleasepool {
            NSArray *apps = nil;
            @try {
                apps = [self.manager allInstalledApplications];
            } @catch (NSException *e) {
                apps = @[];
            }

            if (![apps isKindOfClass:[NSArray class]]) apps = @[];

            NSMutableArray *allBackups = [NSMutableArray array];

            for (NSDictionary *app in apps) {
                @autoreleasepool {
                    if (![app isKindOfClass:[NSDictionary class]]) continue;

                    NSString *bid = app[@"bundleID"];
                    if (![bid isKindOfClass:[NSString class]] ||
                        bid.length == 0) continue;

                    NSArray *appBackups = nil;
                    @try {
                        appBackups =
                            [self.manager availableBackupsForBundleID:bid];
                    } @catch (NSException *e) { continue; }

                    if (![appBackups isKindOfClass:[NSArray class]]) continue;

                    for (NSDictionary *backup in appBackups) {
                        if (![backup isKindOfClass:[NSDictionary class]])
                            continue;
                        NSMutableDictionary *full = [backup mutableCopy];
                        full[@"appName"] = app[@"name"] ?: bid;
                        full[@"bundleID"] = bid;
                        [allBackups addObject:[full copy]];
                    }
                }
            }

            NSArray *sorted = [allBackups sortedArrayUsingComparator:
                ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                    return [b[@"date"] compare:a[@"date"]];
                }];

            dispatch_async(dispatch_get_main_queue(), ^{
                self.backups = sorted;
                [self.spinner stopAnimating];
                [self updateChart];
                [self.tableView reloadData];
            });
        }
    });
}

- (void)updateChart {
    unsigned long long backupsSize = 0;
    unsigned long long appsSize = 0;
    unsigned long long freeSpace = 0;

    @try {
        backupsSize = [self.manager totalBackupsSize];
    } @catch (NSException *e) { }

    @try {
        appsSize = [self.manager totalAppsDataSize];
    } @catch (NSException *e) { }

    @try {
        freeSpace = [self.manager totalFreeSpace];
    } @catch (NSException *e) { }

    unsigned long long total = backupsSize + appsSize + freeSpace;
    if (total == 0) total = 1;

    self.pieChart.segments = @[
        @{@"value": @(backupsSize),
          @"color": [UIColor colorWithRed:0.42 green:0.31 blue:0.90 alpha:1.0]},
        @{@"value": @(appsSize),
          @"color": [UIColor colorWithRed:0.25 green:0.55 blue:0.90 alpha:1.0]},
        @{@"value": @(freeSpace),
          @"color": [UIColor colorWithWhite:0.25 alpha:1.0]}
    ];

    self.pieChart.centerLabel.attributedText =
        [[NSAttributedString alloc]
            initWithString:
                [NSString stringWithFormat:@"%@\n%@",
                    [self.manager formatBytes:backupsSize + appsSize],
                    @"المجموع"]
            attributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:11.0],
                NSForegroundColorAttributeName:
                    [UIColor colorWithWhite:0.5 alpha:1.0]
            }];

    [self.pieChart setNeedsDisplay];

    self.backupsValueLabel.text = [self.manager formatBytes:backupsSize];
    self.appsValueLabel.text = [self.manager formatBytes:appsSize];
    self.freeValueLabel.text = [self.manager formatBytes:freeSpace];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
    return self.backups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"BackupCell";
    BackupCell *cell =
        [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[BackupCell alloc]
            initWithStyle:UITableViewCellStyleDefault
            reuseIdentifier:cellId];
    }

    if (indexPath.row >= (NSInteger)self.backups.count) return cell;

    NSDictionary *backup = self.backups[indexPath.row];
    cell.nameLabel.text = backup[@"appName"];

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"MMM d, yyyy 'at' h:mm a"];
    cell.dateLabel.text = [df stringFromDate:backup[@"date"]];
    cell.sizeLabel.text = backup[@"sizeString"] ?: @"—";

    NSString *bundleID = backup[@"bundleID"];

    // Async icon loading
    cell.appIcon.image = [UIImage systemImageNamed:@"app.fill"];
    cell.appIcon.tintColor =
        [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];

    if ([bundleID isKindOfClass:[NSString class]] && bundleID.length > 0) {
        dispatch_async(self.workerQueue, ^{
            @autoreleasepool {
                UIImage *icon = nil;
                @try {
                    icon = [self.manager iconForBundleID:bundleID];
                } @catch (NSException *e) { }

                if (icon) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        cell.appIcon.image = icon;
                        cell.appIcon.tintColor = nil;
                    });
                }
            }
        });
    }

    // Block-based actions — no tag, no accumulation
    __weak BackupCell *weakCell = cell;
    __weak BackupManagerViewController *weakSelf = self;
    NSString *backupPath = backup[@"path"];

    cell.restoreAction = ^{
        BackupCell *strongCell = weakCell;
        BackupManagerViewController *strongSelf = weakSelf;
        if (!strongCell || !strongSelf) return;

        [strongSelf restoreBackup:backup
                         bundleID:bundleID
                             path:backupPath];
    };

    cell.deleteAction = ^{
        BackupCell *strongCell = weakCell;
        BackupManagerViewController *strongSelf = weakSelf;
        if (!strongCell || !strongSelf) return;

        [strongSelf deleteBackup:backup path:backupPath];
    };

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView
heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 80.0;
}

- (UIView *)tableView:(UITableView *)tableView
viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = [UIColor clearColor];

    UILabel *label = [[UILabel alloc] init];
    label.frame = CGRectMake(16.0, 8.0, 200.0, 24.0);
    label.text = @"Available Backups";
    label.font =
        [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    label.textColor = [UIColor whiteColor];
    [header addSubview:label];

    UILabel *countLabel = [[UILabel alloc] init];
    countLabel.frame = CGRectMake(
        self.view.bounds.size.width - 60.0, 8.0, 40.0, 24.0);
    countLabel.text =
        [NSString stringWithFormat:@"%lu",
            (unsigned long)self.backups.count];
    countLabel.font =
        [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    countLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    countLabel.textAlignment = NSTextAlignmentRight;
    [header addSubview:countLabel];

    return header;
}

- (CGFloat)tableView:(UITableView *)tableView
heightForHeaderInSection:(NSInteger)section {
    return 40.0;
}

#pragma mark - Actions

- (void)restoreBackup:(NSDictionary *)backup
             bundleID:(NSString *)bundleID
                 path:(NSString *)path {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Confirm Restore"
            message:[NSString stringWithFormat:
                @"This will replace current data with this backup for %@. Continue?",
                backup[@"appName"]]
            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"Restore"
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
            [self performRestore:bundleID path:path];
        }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performRestore:(NSString *)bundleID path:(NSString *)path {
    [self.spinner startAnimating];

    dispatch_async(self.workerQueue, ^{
        BOOL success = NO;
        @try {
            success = [self.manager restoreAppData:bundleID
                                        fromBackup:path];
        } @catch (NSException *e) {
            success = NO;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            [self showToast:success
                ? @"✅ Restore completed!"
                : @"❌ Restore failed!"];
        });
    });
}

- (void)deleteBackup:(NSDictionary *)backup path:(NSString *)path {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Confirm Delete"
            message:@"This backup will be permanently deleted."
            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"Delete"
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *action) {
            [self performDelete:path];
        }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performDelete:(NSString *)path {
    [self.spinner startAnimating];

    dispatch_async(self.workerQueue, ^{
        BOOL success = NO;
        @try {
            success = [self.manager deleteBackup:path];
        } @catch (NSException *e) {
            success = NO;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            if (success) [self loadBackups];
            [self showToast:success
                ? @"✅ Backup deleted!"
                : @"❌ Failed to delete!"];
        });
    });
}

- (void)addBackupTapped {
    [self showToast:@"ℹ️ Go to Apps tab to create a new backup"];
}

#pragma mark - Helpers

- (void)showToast:(NSString *)message {
    UILabel *toast = [[UILabel alloc] init];
    toast.text = message;
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor =
        [UIColor colorWithWhite:0.0 alpha:0.85];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font =
        [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    toast.layer.cornerRadius = 12.0;
    toast.layer.masksToBounds = YES;
    toast.numberOfLines = 0;

    CGSize size = [message boundingRectWithSize:
        CGSizeMake(self.view.bounds.size.width - 60.0, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin
        attributes:@{NSFontAttributeName: toast.font}
        context:nil].size;

    toast.frame = CGRectMake(0.0, 0.0,
                              size.width + 32.0, size.height + 24.0);
    toast.center = CGPointMake(self.view.center.x,
                                self.view.bounds.size.height - 120.0);

    [self.view addSubview:toast];

    [UIView animateWithDuration:0.3
                          delay:2.5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{ toast.alpha = 0; }
                     completion:^(BOOL finished) {
                         [toast removeFromSuperview];
                     }];
}

@end
