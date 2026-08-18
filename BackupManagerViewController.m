//
//  BackupManagerViewController.m
//  AppDataManager
//
//  v1.6.5 — Crash-Resilient Backup Manager
//

#import "BackupManagerViewController.h"
#import "AppDataManager.h"

#pragma mark - Pie Chart View

@interface PieChartView : UIView
@property (nonatomic, strong) NSArray<NSDictionary *> *segments;
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
        _centerLabel.adjustsFontSizeToFitWidth = YES;
        _centerLabel.minimumScaleFactor = 0.7;
        _centerLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:_centerLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_centerLabel.centerXAnchor
                constraintEqualToAnchor:self.centerXAnchor],

            [_centerLabel.centerYAnchor
                constraintEqualToAnchor:self.centerYAnchor],

            [_centerLabel.leadingAnchor
                constraintGreaterThanOrEqualToAnchor:self.leadingAnchor
                constant:8.0],

            [_centerLabel.trailingAnchor
                constraintLessThanOrEqualToAnchor:self.trailingAnchor
                constant:-8.0]
        ]];
    }

    return self;
}

- (void)setSegments:(NSArray<NSDictionary *> *)segments {
    _segments = [segments copy];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];

    NSArray *segments = self.segments;

    if (![segments isKindOfClass:[NSArray class]] ||
        segments.count == 0) {
        return;
    }

    CGFloat total = 0.0;

    for (NSDictionary *segment in segments) {
        if (![segment isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSNumber *value = segment[@"value"];

        if (![value isKindOfClass:[NSNumber class]]) {
            continue;
        }

        CGFloat amount = [value doubleValue];

        if (!isfinite(amount) || amount <= 0.0) {
            continue;
        }

        total += amount;
    }

    if (!isfinite(total) || total <= 0.0) {
        return;
    }

    CGPoint center = CGPointMake(CGRectGetMidX(rect),
                                 CGRectGetMidY(rect));

    CGFloat radius =
        MIN(CGRectGetWidth(rect), CGRectGetHeight(rect)) / 2.0 - 8.0;

    if (radius <= 2.0) {
        return;
    }

    CGFloat innerRadius = radius * 0.64;
    CGFloat startAngle = -M_PI_2;

    for (NSDictionary *segment in segments) {
        NSNumber *number = segment[@"value"];
        UIColor *color = segment[@"color"];

        if (![number isKindOfClass:[NSNumber class]] ||
            ![color isKindOfClass:[UIColor class]]) {
            continue;
        }

        CGFloat value = [number doubleValue];

        if (!isfinite(value) || value <= 0.0) {
            continue;
        }

        CGFloat angle = (value / total) * (CGFloat)(2.0 * M_PI);

        if (!isfinite(angle) || angle <= 0.0) {
            continue;
        }

        CGFloat endAngle = startAngle + angle;

        UIBezierPath *path =
            [UIBezierPath bezierPathWithArcCenter:center
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

    if (innerRadius > 1.0) {
        UIBezierPath *centerPath =
            [UIBezierPath bezierPathWithArcCenter:center
                                           radius:innerRadius - 1.0
                                       startAngle:0.0
                                         endAngle:(CGFloat)(2.0 * M_PI)
                                        clockwise:YES];

        [[UIColor colorWithRed:0.06
                          green:0.06
                           blue:0.10
                          alpha:1.0] setFill];

        [centerPath fill];
    }
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

/*
 * Used to verify that an asynchronously loaded icon still belongs
 * to the same backup represented by this reused cell.
 */
@property (nonatomic, copy) NSString *representedBundleID;
@property (nonatomic, copy) NSString *representedBackupPath;

@end

@implementation BackupCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier {

    self = [super initWithStyle:style
                 reuseIdentifier:reuseIdentifier];

    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _containerView = [[UIView alloc] init];
        _containerView.backgroundColor =
            [UIColor colorWithRed:0.08
                            green:0.08
                             blue:0.12
                            alpha:1.0];

        _containerView.layer.cornerRadius = 12.0;
        _containerView.layer.masksToBounds = YES;
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
            [UIFont systemFontOfSize:15.0
                               weight:UIFontWeightSemibold];
        _nameLabel.textColor = [UIColor whiteColor];
        _nameLabel.numberOfLines = 1;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [_containerView addSubview:_nameLabel];

        _dateLabel = [[UILabel alloc] init];
        _dateLabel.font =
            [UIFont systemFontOfSize:12.0
                               weight:UIFontWeightRegular];
        _dateLabel.textColor =
            [UIColor colorWithWhite:0.45 alpha:1.0];
        _dateLabel.numberOfLines = 1;
        _dateLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [_containerView addSubview:_dateLabel];

        _sizeLabel = [[UILabel alloc] init];
        _sizeLabel.font =
            [UIFont systemFontOfSize:12.0
                               weight:UIFontWeightMedium];
        _sizeLabel.textColor =
            [UIColor colorWithWhite:0.60 alpha:1.0];
        _sizeLabel.numberOfLines = 1;
        _sizeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [_containerView addSubview:_sizeLabel];

        _restoreButton =
            [UIButton buttonWithType:UIButtonTypeSystem];

        UIImage *restoreImage =
            [UIImage systemImageNamed:@"arrow.counterclockwise"];

        if (restoreImage) {
            [_restoreButton setImage:restoreImage
                             forState:UIControlStateNormal];
        }

        _restoreButton.tintColor =
            [UIColor colorWithRed:0.30
                            green:0.60
                             blue:0.90
                            alpha:1.0];

        _restoreButton.backgroundColor =
            [UIColor colorWithRed:0.08
                            green:0.12
                             blue:0.20
                            alpha:1.0];

        _restoreButton.layer.cornerRadius = 8.0;
        _restoreButton.translatesAutoresizingMaskIntoConstraints = NO;

        [_restoreButton addTarget:self
                           action:@selector(restoreButtonTapped)
                 forControlEvents:UIControlEventTouchUpInside];

        [_containerView addSubview:_restoreButton];

        _deleteButton =
            [UIButton buttonWithType:UIButtonTypeSystem];

        UIImage *deleteImage =
            [UIImage systemImageNamed:@"trash.fill"];

        if (deleteImage) {
            [_deleteButton setImage:deleteImage
                            forState:UIControlStateNormal];
        }

        _deleteButton.tintColor =
            [UIColor colorWithRed:0.90
                            green:0.30
                             blue:0.30
                            alpha:1.0];

        _deleteButton.backgroundColor =
            [UIColor colorWithRed:0.20
                            green:0.08
                             blue:0.08
                            alpha:1.0];

        _deleteButton.layer.cornerRadius = 8.0;
        _deleteButton.translatesAutoresizingMaskIntoConstraints = NO;

        [_deleteButton addTarget:self
                          action:@selector(deleteButtonTapped)
                forControlEvents:UIControlEventTouchUpInside];

        [_containerView addSubview:_deleteButton];

        [NSLayoutConstraint activateConstraints:@[
            [_containerView.topAnchor
                constraintEqualToAnchor:self.contentView.topAnchor
                constant:4.0],

            [_containerView.leadingAnchor
                constraintEqualToAnchor:self.contentView.leadingAnchor
                constant:16.0],

            [_containerView.trailingAnchor
                constraintEqualToAnchor:self.contentView.trailingAnchor
                constant:-16.0],

            [_containerView.bottomAnchor
                constraintEqualToAnchor:self.contentView.bottomAnchor
                constant:-4.0],

            [_containerView.heightAnchor
                constraintEqualToConstant:72.0],

            [_appIcon.leadingAnchor
                constraintEqualToAnchor:_containerView.leadingAnchor
                constant:12.0],

            [_appIcon.centerYAnchor
                constraintEqualToAnchor:_containerView.centerYAnchor],

            [_appIcon.widthAnchor
                constraintEqualToConstant:44.0],

            [_appIcon.heightAnchor
                constraintEqualToConstant:44.0],

            [_deleteButton.trailingAnchor
                constraintEqualToAnchor:_containerView.trailingAnchor
                constant:-12.0],

            [_deleteButton.centerYAnchor
                constraintEqualToAnchor:_containerView.centerYAnchor],

            [_deleteButton.widthAnchor
                constraintEqualToConstant:36.0],

            [_deleteButton.heightAnchor
                constraintEqualToConstant:36.0],

            [_restoreButton.trailingAnchor
                constraintEqualToAnchor:_deleteButton.leadingAnchor
                constant:-8.0],

            [_restoreButton.centerYAnchor
                constraintEqualToAnchor:_containerView.centerYAnchor],

            [_restoreButton.widthAnchor
                constraintEqualToConstant:36.0],

            [_restoreButton.heightAnchor
                constraintEqualToConstant:36.0],

            [_nameLabel.leadingAnchor
                constraintEqualToAnchor:_appIcon.trailingAnchor
                constant:12.0],

            [_nameLabel.topAnchor
                constraintEqualToAnchor:_containerView.topAnchor
                constant:11.0],

            [_nameLabel.trailingAnchor
                constraintLessThanOrEqualToAnchor:_restoreButton.leadingAnchor
                constant:-10.0],

            [_dateLabel.leadingAnchor
                constraintEqualToAnchor:_nameLabel.leadingAnchor],

            [_dateLabel.topAnchor
                constraintEqualToAnchor:_nameLabel.bottomAnchor
                constant:3.0],

            [_dateLabel.trailingAnchor
                constraintLessThanOrEqualToAnchor:_restoreButton.leadingAnchor
                constant:-10.0],

            [_sizeLabel.leadingAnchor
                constraintEqualToAnchor:_nameLabel.leadingAnchor],

            [_sizeLabel.topAnchor
                constraintEqualToAnchor:_dateLabel.bottomAnchor
                constant:2.0],

            [_sizeLabel.trailingAnchor
                constraintLessThanOrEqualToAnchor:_restoreButton.leadingAnchor
                constant:-10.0]
        ]];
    }

    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];

    self.restoreAction = nil;
    self.deleteAction = nil;

    self.representedBundleID = nil;
    self.representedBackupPath = nil;

    self.appIcon.image = nil;
    self.appIcon.tintColor = nil;

    self.nameLabel.text = nil;
    self.dateLabel.text = nil;
    self.sizeLabel.text = nil;
}

- (void)restoreButtonTapped {
    void (^action)(void) = self.restoreAction;

    if (action) {
        action();
    }
}

- (void)deleteButtonTapped {
    void (^action)(void) = self.deleteAction;

    if (action) {
        action();
    }
}

@end

#pragma mark - BackupManagerViewController

@interface BackupManagerViewController () <
    UITableViewDelegate,
    UITableViewDataSource
>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *backups;

@property (nonatomic, strong) AppDataManager *manager;

@property (nonatomic, strong) PieChartView *pieChart;
@property (nonatomic, strong) UIView *statsContainer;

@property (nonatomic, strong) UILabel *backupsValueLabel;
@property (nonatomic, strong) UILabel *appsValueLabel;
@property (nonatomic, strong) UILabel *freeValueLabel;

@property (nonatomic, strong) dispatch_queue_t workerQueue;

@property (nonatomic, strong) UIActivityIndicatorView *spinner;

/*
 * Prevents stale asynchronous loads from replacing newer data.
 */
@property (nonatomic, assign) NSUInteger loadGeneration;

@end

@implementation BackupManagerViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"النسخ الاحتياطية";

    self.view.backgroundColor =
        [UIColor colorWithRed:0.02
                        green:0.02
                         blue:0.04
                        alpha:1.0];

    self.manager = [AppDataManager sharedManager];

    self.workerQueue =
        dispatch_queue_create(
            "com.appdatamanager.backupworker",
            DISPATCH_QUEUE_SERIAL);

    self.loadGeneration = 0;

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
    UINavigationBar *bar =
        self.navigationController.navigationBar;

    bar.prefersLargeTitles = YES;

    self.navigationItem.largeTitleDisplayMode =
        UINavigationItemLargeTitleDisplayModeAlways;

    [bar setTitleTextAttributes:@{
        NSForegroundColorAttributeName:
            [UIColor whiteColor]
    }];

    [bar setLargeTitleTextAttributes:@{
        NSForegroundColorAttributeName:
            [UIColor whiteColor]
    }];

    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance =
            [[UINavigationBarAppearance alloc] init];

        [appearance configureWithOpaqueBackground];

        appearance.backgroundColor =
            [UIColor colorWithRed:0.02
                            green:0.02
                             blue:0.04
                            alpha:1.0];

        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName:
                [UIColor whiteColor]
        };

        appearance.largeTitleTextAttributes = @{
            NSForegroundColorAttributeName:
                [UIColor whiteColor]
        };

        bar.standardAppearance = appearance;
        bar.scrollEdgeAppearance = appearance;
    } else {
        bar.barTintColor =
            [UIColor colorWithRed:0.02
                            green:0.02
                             blue:0.04
                            alpha:1.0];
    }

    UIImage *plusImage =
        [UIImage systemImageNamed:@"plus"];

    UIBarButtonItem *addButton =
        [[UIBarButtonItem alloc]
            initWithImage:plusImage
                    style:UIBarButtonItemStylePlain
                   target:self
                   action:@selector(addBackupTapped)];

    addButton.tintColor =
        [UIColor colorWithRed:0.60
                        green:0.40
                         blue:1.0
                        alpha:1.0];

    self.navigationItem.rightBarButtonItem = addButton;
}

- (void)setupStatsView {
    self.statsContainer = [[UIView alloc] init];

    self.statsContainer.backgroundColor =
        [UIColor colorWithRed:0.06
                        green:0.06
                         blue:0.10
                        alpha:1.0];

    self.statsContainer.layer.cornerRadius = 16.0;
    self.statsContainer.layer.masksToBounds = YES;
    self.statsContainer.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:self.statsContainer];

    self.pieChart = [[PieChartView alloc] init];

    self.pieChart.translatesAutoresizingMaskIntoConstraints = NO;

    [self.statsContainer addSubview:self.pieChart];

    NSArray *legendItems = @[
        @{
            @"color":
                [UIColor colorWithRed:0.42
                                green:0.31
                                 blue:0.90
                                alpha:1.0],
            @"label": @"النسخ الاحتياطية",
            @"key": @"backups"
        },

        @{
            @"color":
                [UIColor colorWithRed:0.25
                                green:0.55
                                 blue:0.90
                                alpha:1.0],
            @"label": @"بيانات التطبيقات",
            @"key": @"apps"
        },

        @{
            @"color":
                [UIColor colorWithWhite:0.25 alpha:1.0],
            @"label": @"المساحة الحرة",
            @"key": @"free"
        }
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
        label.font =
            [UIFont systemFontOfSize:12.0
                               weight:UIFontWeightRegular];
        label.textColor =
            [UIColor colorWithWhite:0.60 alpha:1.0];

        label.numberOfLines = 1;
        label.translatesAutoresizingMaskIntoConstraints = NO;

        [self.statsContainer addSubview:label];

        UILabel *valueLabel = [[UILabel alloc] init];

        valueLabel.font =
            [UIFont systemFontOfSize:12.0
                               weight:UIFontWeightSemibold];

        valueLabel.textColor = [UIColor whiteColor];
        valueLabel.textAlignment = NSTextAlignmentRight;
        valueLabel.numberOfLines = 1;
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
            [dot.widthAnchor
                constraintEqualToConstant:8.0],

            [dot.heightAnchor
                constraintEqualToConstant:8.0],

            [dot.leadingAnchor
                constraintEqualToAnchor:self.pieChart.trailingAnchor
                constant:18.0],

            [label.leadingAnchor
                constraintEqualToAnchor:dot.trailingAnchor
                constant:8.0],

            [label.centerYAnchor
                constraintEqualToAnchor:dot.centerYAnchor],

            [valueLabel.trailingAnchor
                constraintEqualToAnchor:self.statsContainer.trailingAnchor
                constant:-14.0],

            [valueLabel.centerYAnchor
                constraintEqualToAnchor:dot.centerYAnchor],

            [valueLabel.leadingAnchor
                constraintGreaterThanOrEqualToAnchor:label.trailingAnchor
                constant:6.0]
        ]];

        if (lastLegend) {
            [dot.topAnchor
                constraintEqualToAnchor:lastLegend.bottomAnchor
                constant:14.0].active = YES;
        } else {
            [dot.topAnchor
                constraintEqualToAnchor:self.pieChart.topAnchor
                constant:18.0].active = YES;
        }

        lastLegend = dot;
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.statsContainer.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
            constant:12.0],

        [self.statsContainer.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor
            constant:16.0],

        [self.statsContainer.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor
            constant:-16.0],

        [self.statsContainer.heightAnchor
            constraintEqualToConstant:180.0],

        [self.pieChart.leadingAnchor
            constraintEqualToAnchor:self.statsContainer.leadingAnchor
            constant:18.0],

        [self.pieChart.centerYAnchor
            constraintEqualToAnchor:self.statsContainer.centerYAnchor],

        [self.pieChart.widthAnchor
            constraintEqualToConstant:130.0],

        [self.pieChart.heightAnchor
            constraintEqualToConstant:130.0]
    ]];
}

- (void)setupTableView {
    self.tableView =
        [[UITableView alloc]
            initWithFrame:CGRectZero
            style:UITableViewStylePlain];

    self.tableView.delegate = self;
    self.tableView.dataSource = self;

    self.tableView.backgroundColor = [UIColor clearColor];

    self.tableView.separatorStyle =
        UITableViewCellSeparatorStyleNone;

    self.tableView.contentInset =
        UIEdgeInsetsMake(0.0, 0.0, 20.0, 0.0);

    self.tableView.estimatedRowHeight = 80.0;
    self.tableView.rowHeight = 80.0;

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

    self.spinner.hidesWhenStopped = YES;

    self.spinner.color =
        [UIColor colorWithRed:0.60
                        green:0.40
                         blue:1.0
                        alpha:1.0];

    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:self.spinner];

    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.centerXAnchor
            constraintEqualToAnchor:self.view.centerXAnchor],

        [self.spinner.centerYAnchor
            constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

#pragma mark - Data Loading

- (void)loadBackups {
    self.loadGeneration += 1;

    NSUInteger generation = self.loadGeneration;

    [self.spinner startAnimating];

    dispatch_async(self.workerQueue, ^{
        @autoreleasepool {
            NSArray *apps = @[];

            @try {
                NSArray *result =
                    [self.manager allInstalledApplications];

                if ([result isKindOfClass:[NSArray class]]) {
                    apps = result;
                }
            } @catch (NSException *exception) {
                NSLog(@"[ADM] backup app discovery exception: %@",
                      exception);
            }

            NSMutableArray *allBackups =
                [NSMutableArray array];

            for (NSDictionary *app in apps) {
                @autoreleasepool {
                    if (![app isKindOfClass:[NSDictionary class]]) {
                        continue;
                    }

                    NSString *bundleID = app[@"bundleID"];

                    if (![bundleID isKindOfClass:[NSString class]] ||
                        bundleID.length == 0) {
                        continue;
                    }

                    NSArray *appBackups = @[];

                    @try {
                        NSArray *result =
                            [self.manager
                                availableBackupsForBundleID:bundleID];

                        if ([result isKindOfClass:[NSArray class]]) {
                            appBackups = result;
                        }
                    } @catch (NSException *exception) {
                        NSLog(@"[ADM] backup enumeration exception for %@: %@",
                              bundleID,
                              exception);
                        continue;
                    }

                    for (NSDictionary *backup in appBackups) {
                        @autoreleasepool {
                            if (![backup isKindOfClass:[NSDictionary class]]) {
                                continue;
                            }

                            NSString *path = backup[@"path"];

                            if (![path isKindOfClass:[NSString class]] ||
                                path.length == 0) {
                                continue;
                            }

                            NSMutableDictionary *full =
                                [backup mutableCopy];

                            full[@"appName"] =
                                [app[@"name"] isKindOfClass:[NSString class]]
                                    ? app[@"name"]
                                    : bundleID;

                            full[@"bundleID"] = bundleID;

                            /*
                             * AppDataManager v1.6 did not guarantee a
                             * sizeString field. Calculate it here safely.
                             */
                            if (![full[@"sizeString"]
                                    isKindOfClass:[NSString class]]) {

                                unsigned long long size = 0;

                                @try {
                                    size =
                                        [self directorySizeForBackupPath:path];
                                } @catch (NSException *exception) {
                                    size = 0;
                                }

                                full[@"size"] = @(size);

                                full[@"sizeString"] =
                                    [self.manager formatBytes:size];
                            }

                            [allBackups addObject:[full copy]];
                        }
                    }
                }
            }

            NSArray *sorted =
                [allBackups sortedArrayUsingComparator:
                    ^NSComparisonResult(NSDictionary *a,
                                        NSDictionary *b) {

                    NSDate *dateA = a[@"date"];
                    NSDate *dateB = b[@"date"];

                    if (![dateA isKindOfClass:[NSDate class]]) {
                        dateA = [NSDate distantPast];
                    }

                    if (![dateB isKindOfClass:[NSDate class]]) {
                        dateB = [NSDate distantPast];
                    }

                    return [dateB compare:dateA];
                }];

            /*
             * Heavy filesystem statistics are deliberately calculated
             * on the worker queue.
             */
            unsigned long long backupsSize = 0;
            unsigned long long appsSize = 0;
            unsigned long long freeSpace = 0;

            @try {
                backupsSize =
                    [self.manager totalBackupsSize];
            } @catch (NSException *exception) {
                backupsSize = 0;
            }

            @try {
                appsSize =
                    [self.manager totalAppsDataSize];
            } @catch (NSException *exception) {
                appsSize = 0;
            }

            @try {
                freeSpace =
                    [self.manager totalFreeSpace];
            } @catch (NSException *exception) {
                freeSpace = 0;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                /*
                 * Ignore results from an older load if a newer
                 * load has already started.
                 */
                if (generation != self.loadGeneration) {
                    return;
                }

                self.backups = sorted;

                [self.spinner stopAnimating];

                [self updateChartWithBackupsSize:backupsSize
                                         appsSize:appsSize
                                         freeSpace:freeSpace];

                [self.tableView reloadData];
            });
        }
    });
}

#pragma mark - Statistics

- (void)updateChartWithBackupsSize:(unsigned long long)backupsSize
                          appsSize:(unsigned long long)appsSize
                         freeSpace:(unsigned long long)freeSpace {

    if (!self.pieChart) {
        return;
    }

    self.pieChart.segments = @[
        @{
            @"value": @(backupsSize),
            @"color":
                [UIColor colorWithRed:0.42
                                green:0.31
                                 blue:0.90
                                alpha:1.0]
        },

        @{
            @"value": @(appsSize),
            @"color":
                [UIColor colorWithRed:0.25
                                green:0.55
                                 blue:0.90
                                alpha:1.0]
        },

        @{
            @"value": @(freeSpace),
            @"color":
                [UIColor colorWithWhite:0.25 alpha:1.0]
        }
    ];

    unsigned long long used =
        backupsSize + appsSize;

    NSString *centerText =
        [NSString stringWithFormat:@"%@\nالمستخدم",
            [self.manager formatBytes:used]];

    self.pieChart.centerLabel.attributedText =
        [[NSAttributedString alloc]
            initWithString:centerText
                attributes:@{
                    NSFontAttributeName:
                        [UIFont systemFontOfSize:11.0
                                           weight:UIFontWeightMedium],

                    NSForegroundColorAttributeName:
                        [UIColor colorWithWhite:0.55 alpha:1.0]
                }];

    self.backupsValueLabel.text =
        [self.manager formatBytes:backupsSize];

    self.appsValueLabel.text =
        [self.manager formatBytes:appsSize];

    self.freeValueLabel.text =
        [self.manager formatBytes:freeSpace];

    [self.pieChart setNeedsDisplay];
}

#pragma mark - Backup Size

- (unsigned long long)directorySizeForBackupPath:(NSString *)path {
    if (![path isKindOfClass:[NSString class]] ||
        path.length == 0) {
        return 0;
    }

    NSFileManager *fileManager =
        [NSFileManager defaultManager];

    BOOL isDirectory = NO;

    if (![fileManager fileExistsAtPath:path
                           isDirectory:&isDirectory]) {
        return 0;
    }

    if (!isDirectory) {
        NSDictionary *attributes =
            [fileManager attributesOfItemAtPath:path
                                          error:nil];

        return [attributes[NSFileSize] unsignedLongLongValue];
    }

    unsigned long long total = 0;

    @try {
        NSURL *url =
            [NSURL fileURLWithPath:path
                       isDirectory:YES];

        NSDirectoryEnumerator *enumerator =
            [fileManager
                enumeratorAtURL:url
                includingPropertiesForKeys:@[
                    NSURLFileSizeKey,
                    NSURLIsDirectoryKey,
                    NSURLIsSymbolicLinkKey
                ]
                options:NSDirectoryEnumerationSkipsHiddenFiles
                errorHandler:^BOOL(NSURL *url, NSError *error) {
                    return YES;
                }];

        for (NSURL *fileURL in enumerator) {
            @autoreleasepool {
                NSNumber *isDirectoryNumber = nil;
                NSNumber *isSymlinkNumber = nil;
                NSNumber *fileSize = nil;

                [fileURL getResourceValue:&isDirectoryNumber
                                   forKey:NSURLIsDirectoryKey
                                    error:nil];

                [fileURL getResourceValue:&isSymlinkNumber
                                   forKey:NSURLIsSymbolicLinkKey
                                    error:nil];

                if ([isSymlinkNumber boolValue]) {
                    continue;
                }

                if ([isDirectoryNumber boolValue]) {
                    continue;
                }

                [fileURL getResourceValue:&fileSize
                                   forKey:NSURLFileSizeKey
                                    error:nil];

                if ([fileSize isKindOfClass:[NSNumber class]]) {
                    unsigned long long value =
                        [fileSize unsignedLongLongValue];

                    if (ULLONG_MAX - total < value) {
                        total = ULLONG_MAX;
                    } else {
                        total += value;
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[ADM] backup size exception for %@: %@",
              path,
              exception);
    }

    return total;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {

    return (NSInteger)self.backups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    static NSString *cellIdentifier = @"BackupCell";

    BackupCell *cell =
        [tableView dequeueReusableCellWithIdentifier:cellIdentifier];

    if (!cell) {
        cell =
            [[BackupCell alloc]
                initWithStyle:UITableViewCellStyleDefault
                reuseIdentifier:cellIdentifier];
    }

    if (indexPath.row < 0 ||
        indexPath.row >= (NSInteger)self.backups.count) {
        return cell;
    }

    NSDictionary *backup =
        self.backups[indexPath.row];

    if (![backup isKindOfClass:[NSDictionary class]]) {
        return cell;
    }

    NSString *bundleID = backup[@"bundleID"];
    NSString *backupPath = backup[@"path"];

    if (![bundleID isKindOfClass:[NSString class]]) {
        bundleID = nil;
    }

    if (![backupPath isKindOfClass:[NSString class]]) {
        backupPath = nil;
    }

    /*
     * Reset cell state BEFORE starting async work.
     */
    cell.representedBundleID = bundleID;
    cell.representedBackupPath = backupPath;

    cell.nameLabel.text =
        [backup[@"appName"] isKindOfClass:[NSString class]]
            ? backup[@"appName"]
            : (bundleID ?: @"غير معروف");

    NSDate *date = backup[@"date"];

    if ([date isKindOfClass:[NSDate class]]) {
        NSDateFormatter *dateFormatter =
            [[NSDateFormatter alloc] init];

        dateFormatter.locale =
            [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

        dateFormatter.dateFormat =
            @"MMM d, yyyy 'at' h:mm a";

        cell.dateLabel.text =
            [dateFormatter stringFromDate:date];
    } else {
        cell.dateLabel.text = @"تاريخ غير متاح";
    }

    NSString *sizeString = backup[@"sizeString"];

    if ([sizeString isKindOfClass:[NSString class]] &&
        sizeString.length > 0) {
        cell.sizeLabel.text = sizeString;
    } else {
        cell.sizeLabel.text = @"الحجم غير متاح";
    }

    UIImage *placeholder =
        [UIImage systemImageNamed:@"app.fill"];

    cell.appIcon.image = placeholder;

    cell.appIcon.tintColor =
        [UIColor colorWithRed:0.60
                        green:0.40
                         blue:1.0
                        alpha:1.0];

    __weak BackupCell *weakCell = cell;
    __weak BackupManagerViewController *weakSelf = self;

    cell.restoreAction = ^{
        BackupCell *strongCell = weakCell;
        BackupManagerViewController *strongSelf = weakSelf;

        if (!strongCell || !strongSelf) {
            return;
        }

        NSString *path = strongCell.representedBackupPath;
        NSString *bid = strongCell.representedBundleID;

        if (path.length == 0 || bid.length == 0) {
            return;
        }

        NSDictionary *currentBackup = nil;

        for (NSDictionary *candidate in strongSelf.backups) {
            if (![candidate isKindOfClass:[NSDictionary class]]) {
                continue;
            }

            NSString *candidatePath = candidate[@"path"];

            if ([candidatePath isKindOfClass:[NSString class]] &&
                [candidatePath isEqualToString:path]) {
                currentBackup = candidate;
                break;
            }
        }

        if (!currentBackup) {
            return;
        }

        [strongSelf restoreBackup:currentBackup
                          bundleID:bid
                              path:path];
    };

    cell.deleteAction = ^{
        BackupCell *strongCell = weakCell;
        BackupManagerViewController *strongSelf = weakSelf;

        if (!strongCell || !strongSelf) {
            return;
        }

        NSString *path = strongCell.representedBackupPath;

        if (path.length == 0) {
            return;
        }

        NSDictionary *currentBackup = nil;

        for (NSDictionary *candidate in strongSelf.backups) {
            if (![candidate isKindOfClass:[NSDictionary class]]) {
                continue;
            }

            NSString *candidatePath = candidate[@"path"];

            if ([candidatePath isKindOfClass:[NSString class]] &&
                [candidatePath isEqualToString:path]) {
                currentBackup = candidate;
                break;
            }
        }

        if (!currentBackup) {
            return;
        }

        [strongSelf deleteBackup:currentBackup
                             path:path];
    };

    /*
     * Async icon loading.
     *
     * The cell is NOT captured strongly by the worker block.
     * Before assigning the icon we verify that the cell still
     * represents the same bundle/path.
     */
    if (bundleID.length > 0) {
        NSString *requestedBundleID = [bundleID copy];
        NSString *requestedBackupPath = [backupPath copy];

        dispatch_async(self.workerQueue, ^{
            @autoreleasepool {
                UIImage *icon = nil;

                @try {
                    icon =
                        [self.manager
                            iconForBundleID:requestedBundleID];
                } @catch (NSException *exception) {
                    icon = nil;
                }

                if (!icon) {
                    return;
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    BackupCell *currentCell = weakCell;

                    if (!currentCell) {
                        return;
                    }

                    if (![currentCell.representedBundleID
                            isEqualToString:requestedBundleID]) {
                        return;
                    }

                    if (![currentCell.representedBackupPath
                            isEqualToString:requestedBackupPath]) {
                        return;
                    }

                    currentCell.appIcon.image = icon;
                    currentCell.appIcon.tintColor = nil;
                });
            }
        });
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView
heightForRowAtIndexPath:(NSIndexPath *)indexPath {

    return 80.0;
}

- (UIView *)tableView:(UITableView *)tableView
viewForHeaderInSection:(NSInteger)section {

    UIView *header =
        [[UIView alloc] init];

    header.backgroundColor = [UIColor clearColor];

    UILabel *label =
        [[UILabel alloc] init];

    label.text = @"النسخ المتاحة";
    label.font =
        [UIFont systemFontOfSize:18.0
                           weight:UIFontWeightBold];

    label.textColor = [UIColor whiteColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;

    [header addSubview:label];

    UILabel *countLabel =
        [[UILabel alloc] init];

    countLabel.text =
        [NSString stringWithFormat:@"%lu",
            (unsigned long)self.backups.count];

    countLabel.font =
        [UIFont systemFontOfSize:16.0
                           weight:UIFontWeightSemibold];

    countLabel.textColor =
        [UIColor colorWithWhite:0.40 alpha:1.0];

    countLabel.textAlignment = NSTextAlignmentRight;
    countLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [header addSubview:countLabel];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor
            constraintEqualToAnchor:header.leadingAnchor
            constant:16.0],

        [label.centerYAnchor
            constraintEqualToAnchor:header.centerYAnchor],

        [countLabel.trailingAnchor
            constraintEqualToAnchor:header.trailingAnchor
            constant:-16.0],

        [countLabel.centerYAnchor
            constraintEqualToAnchor:header.centerYAnchor],

        [countLabel.leadingAnchor
            constraintGreaterThanOrEqualToAnchor:label.trailingAnchor
            constant:8.0]
    ]];

    return header;
}

- (CGFloat)tableView:(UITableView *)tableView
heightForHeaderInSection:(NSInteger)section {

    return 40.0;
}

#pragma mark - Restore

- (void)restoreBackup:(NSDictionary *)backup
             bundleID:(NSString *)bundleID
                 path:(NSString *)path {

    if (![bundleID isKindOfClass:[NSString class]] ||
        bundleID.length == 0 ||
        ![path isKindOfClass:[NSString class]] ||
        path.length == 0) {
        return;
    }

    NSString *appName = backup[@"appName"];

    if (![appName isKindOfClass:[NSString class]] ||
        appName.length == 0) {
        appName = bundleID;
    }

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:@"تأكيد الاستعادة"
                              message:
        [NSString stringWithFormat:
            @"سيتم استبدال بيانات %@ بالنسخة الاحتياطية المحددة. هل تريد المتابعة؟",
            appName]
                       preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"إلغاء"
                      style:UIAlertActionStyleCancel
                    handler:nil]];

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"استعادة"
                      style:UIAlertActionStyleDestructive
                    handler:^(UIAlertAction *action) {

        [self performRestore:bundleID
                         path:path];
    }]];

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

- (void)performRestore:(NSString *)bundleID
                  path:(NSString *)path {

    if (bundleID.length == 0 ||
        path.length == 0) {
        return;
    }

    [self.spinner startAnimating];

    dispatch_async(self.workerQueue, ^{
        BOOL success = NO;

        @try {
            success =
                [self.manager
                    restoreAppData:bundleID
                         fromBackup:path];
        } @catch (NSException *exception) {
            NSLog(@"[ADM] restore exception: %@",
                  exception);
            success = NO;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];

            [self showToast:
                success
                    ? @"تمت الاستعادة بنجاح"
                    : @"فشلت عملية الاستعادة"];

            if (success) {
                [self loadBackups];
            }
        });
    });
}

#pragma mark - Delete

- (void)deleteBackup:(NSDictionary *)backup
                path:(NSString *)path {

    if (![path isKindOfClass:[NSString class]] ||
        path.length == 0) {
        return;
    }

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:@"تأكيد الحذف"
                              message:@"سيتم حذف هذه النسخة الاحتياطية نهائيًا."
                       preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"إلغاء"
                      style:UIAlertActionStyleCancel
                    handler:nil]];

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"حذف"
                      style:UIAlertActionStyleDestructive
                    handler:^(UIAlertAction *action) {

        [self performDelete:path];
    }]];

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

- (void)performDelete:(NSString *)path {
    if (![path isKindOfClass:[NSString class]] ||
        path.length == 0) {
        return;
    }

    [self.spinner startAnimating];

    dispatch_async(self.workerQueue, ^{
        BOOL success = NO;

        @try {
            success =
                [self.manager deleteBackup:path];
        } @catch (NSException *exception) {
            NSLog(@"[ADM] delete backup exception: %@",
                  exception);
            success = NO;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];

            [self showToast:
                success
                    ? @"تم حذف النسخة الاحتياطية"
                    : @"فشل حذف النسخة الاحتياطية"];

            if (success) {
                [self loadBackups];
            }
        });
    });
}

#pragma mark - Add Backup

- (void)addBackupTapped {
    [self showToast:
        @"انتقل إلى قائمة التطبيقات لإنشاء نسخة احتياطية جديدة"];
}

#pragma mark - Toast

- (void)showToast:(NSString *)message {
    if (![message isKindOfClass:[NSString class]] ||
        message.length == 0 ||
        !self.view.window) {
        return;
    }

    UILabel *toast =
        [[UILabel alloc] init];

    toast.text = message;
    toast.textColor = [UIColor whiteColor];

    toast.backgroundColor =
        [UIColor colorWithWhite:0.0
                         alpha:0.88];

    toast.textAlignment = NSTextAlignmentCenter;

    toast.font =
        [UIFont systemFontOfSize:14.0
                           weight:UIFontWeightMedium];

    toast.layer.cornerRadius = 12.0;
    toast.layer.masksToBounds = YES;

    toast.numberOfLines = 0;

    CGFloat maxWidth =
        MAX(100.0,
            self.view.bounds.size.width - 60.0);

    CGSize size =
        [message boundingRectWithSize:
            CGSizeMake(maxWidth, CGFLOAT_MAX)
                               options:
            NSStringDrawingUsesLineFragmentOrigin |
            NSStringDrawingUsesFontLeading
                            attributes:@{
                                NSFontAttributeName:
                                    toast.font
                            }
                               context:nil].size;

    CGFloat width =
        MIN(maxWidth,
            ceil(size.width) + 32.0);

    CGFloat height =
        ceil(size.height) + 24.0;

    toast.frame =
        CGRectMake(0.0,
                    0.0,
                    width,
                    height);

    toast.center =
        CGPointMake(CGRectGetMidX(self.view.bounds),
                    CGRectGetHeight(self.view.bounds) - 120.0);

    toast.alpha = 0.0;

    [self.view addSubview:toast];

    [UIView animateWithDuration:0.20
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        toast.alpha = 1.0;
    } completion:^(BOOL finished) {

        [UIView animateWithDuration:0.25
                              delay:2.0
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
            toast.alpha = 0.0;
        } completion:^(BOOL finished2) {
            [toast removeFromSuperview];
        }];
    }];
}

@end
