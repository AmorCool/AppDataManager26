//
//  MainViewController.m
//  AppDataManager
//
//  v1.6.0 — Stable App Discovery & Size Calculation
//

#import "MainViewController.h"
#import "AppDataManager.h"
#import "AppDetailViewController.h"

#pragma mark - App List Cell

@interface AppListCell : UITableViewCell
@property (nonatomic, strong) UIImageView *appIcon;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *bundleLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, copy) NSString *representedBundleID;
@end

@implementation AppListCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
               reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _containerView = [[UIView alloc] init];
        _containerView.backgroundColor =
            [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:1.0];
        _containerView.layer.cornerRadius = 14.0;
        _containerView.layer.masksToBounds = YES;
        _containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_containerView];

        _appIcon = [[UIImageView alloc] init];
        _appIcon.layer.cornerRadius = 10.0;
        _appIcon.layer.masksToBounds = YES;
        _appIcon.contentMode = UIViewContentModeScaleAspectFit;
        _appIcon.backgroundColor =
            [UIColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:1.0];
        _appIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_appIcon];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font =
            [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
        _nameLabel.textColor = [UIColor whiteColor];
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_nameLabel];

        _bundleLabel = [[UILabel alloc] init];
        _bundleLabel.font =
            [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
        _bundleLabel.textColor = [UIColor colorWithWhite:0.40 alpha:1.0];
        _bundleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _bundleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_bundleLabel];

        _sizeLabel = [[UILabel alloc] init];
        _sizeLabel.font =
            [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
        _sizeLabel.textColor =
            [UIColor colorWithRed:0.55 green:0.45 blue:0.95 alpha:1.0];
        _sizeLabel.textAlignment = NSTextAlignmentRight;
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_sizeLabel];

        UIImageView *arrow =
            [[UIImageView alloc] initWithImage:
                [UIImage systemImageNamed:@"chevron.right"]];
        arrow.tintColor = [UIColor colorWithWhite:0.25 alpha:1.0];
        arrow.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:arrow];

        [NSLayoutConstraint activateConstraints:@[
            [_containerView.topAnchor
                constraintEqualToAnchor:self.contentView.topAnchor constant:5.0],
            [_containerView.leadingAnchor
                constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_containerView.trailingAnchor
                constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_containerView.bottomAnchor
                constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5.0],
            [_containerView.heightAnchor constraintEqualToConstant:68.0],

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
            [_nameLabel.trailingAnchor
                constraintEqualToAnchor:_sizeLabel.leadingAnchor constant:-8.0],

            [_bundleLabel.leadingAnchor
                constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_bundleLabel.topAnchor
                constraintEqualToAnchor:_nameLabel.bottomAnchor constant:3.0],
            [_bundleLabel.trailingAnchor
                constraintEqualToAnchor:_nameLabel.trailingAnchor],

            [_sizeLabel.trailingAnchor
                constraintEqualToAnchor:arrow.leadingAnchor constant:-6.0],
            [_sizeLabel.centerYAnchor
                constraintEqualToAnchor:_containerView.centerYAnchor],
            [_sizeLabel.widthAnchor constraintEqualToConstant:70.0],

            [arrow.trailingAnchor
                constraintEqualToAnchor:_containerView.trailingAnchor constant:-14.0],
            [arrow.centerYAnchor
                constraintEqualToAnchor:_containerView.centerYAnchor],
            [arrow.widthAnchor constraintEqualToConstant:14.0],
            [arrow.heightAnchor constraintEqualToConstant:14.0]
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedBundleID = nil;
    self.nameLabel.text = nil;
    self.bundleLabel.text = nil;
    self.sizeLabel.text = nil;
    self.appIcon.image = [UIImage systemImageNamed:@"app.fill"];
    self.appIcon.tintColor =
        [UIColor colorWithRed:0.55 green:0.45 blue:0.95 alpha:1.0];
}

@end

#pragma mark - Stats Header View

@interface StatsHeaderView : UIView
@property (nonatomic, strong) UILabel *appsCountLabel;
@property (nonatomic, strong) UILabel *appsTitleLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UILabel *sizeTitleLabel;
@end

@implementation StatsHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor =
            [UIColor colorWithRed:0.10 green:0.10 blue:0.14 alpha:1.0];
        self.layer.cornerRadius = 18.0;
        self.layer.masksToBounds = YES;

        UIView *appsIconBg = [[UIView alloc] init];
        appsIconBg.backgroundColor =
            [UIColor colorWithRed:0.18 green:0.15 blue:0.30 alpha:1.0];
        appsIconBg.layer.cornerRadius = 10.0;
        appsIconBg.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:appsIconBg];

        UIImageView *appsIcon =
            [[UIImageView alloc] initWithImage:
                [UIImage systemImageNamed:@"app.fill"]];
        appsIcon.tintColor =
            [UIColor colorWithRed:0.65 green:0.50 blue:0.95 alpha:1.0];
        appsIcon.contentMode = UIViewContentModeScaleAspectFit;
        appsIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [appsIconBg addSubview:appsIcon];

        _appsCountLabel = [[UILabel alloc] init];
        _appsCountLabel.font =
            [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
        _appsCountLabel.textColor = [UIColor whiteColor];
        _appsCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_appsCountLabel];

        _appsTitleLabel = [[UILabel alloc] init];
        _appsTitleLabel.font =
            [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
        _appsTitleLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
        _appsTitleLabel.text = @"التطبيقات";
        _appsTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_appsTitleLabel];

        UIView *divider = [[UIView alloc] init];
        divider.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.6];
        divider.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:divider];

        UIView *sizeIconBg = [[UIView alloc] init];
        sizeIconBg.backgroundColor =
            [UIColor colorWithRed:0.15 green:0.20 blue:0.30 alpha:1.0];
        sizeIconBg.layer.cornerRadius = 10.0;
        sizeIconBg.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:sizeIconBg];

        UIImageView *sizeIcon =
            [[UIImageView alloc] initWithImage:
                [UIImage systemImageNamed:@"externaldrive.fill"]];
        sizeIcon.tintColor =
            [UIColor colorWithRed:0.45 green:0.65 blue:0.95 alpha:1.0];
        sizeIcon.contentMode = UIViewContentModeScaleAspectFit;
        sizeIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [sizeIconBg addSubview:sizeIcon];

        _sizeLabel = [[UILabel alloc] init];
        _sizeLabel.font =
            [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
        _sizeLabel.textColor = [UIColor whiteColor];
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_sizeLabel];

        _sizeTitleLabel = [[UILabel alloc] init];
        _sizeTitleLabel.font =
            [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
        _sizeTitleLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
        _sizeTitleLabel.text = @"الحجم الكلي";
        _sizeTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_sizeTitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [appsIconBg.leadingAnchor
                constraintEqualToAnchor:self.leadingAnchor constant:20.0],
            [appsIconBg.centerYAnchor
                constraintEqualToAnchor:self.centerYAnchor],
            [appsIconBg.widthAnchor constraintEqualToConstant:36.0],
            [appsIconBg.heightAnchor constraintEqualToConstant:36.0],

            [appsIcon.centerXAnchor
                constraintEqualToAnchor:appsIconBg.centerXAnchor],
            [appsIcon.centerYAnchor
                constraintEqualToAnchor:appsIconBg.centerYAnchor],
            [appsIcon.widthAnchor constraintEqualToConstant:18.0],
            [appsIcon.heightAnchor constraintEqualToConstant:18.0],

            [_appsCountLabel.leadingAnchor
                constraintEqualToAnchor:appsIconBg.trailingAnchor constant:10.0],
            [_appsCountLabel.topAnchor
                constraintEqualToAnchor:self.topAnchor constant:18.0],

            [_appsTitleLabel.leadingAnchor
                constraintEqualToAnchor:_appsCountLabel.leadingAnchor],
            [_appsTitleLabel.topAnchor
                constraintEqualToAnchor:_appsCountLabel.bottomAnchor constant:2.0],

            [divider.centerXAnchor
                constraintEqualToAnchor:self.centerXAnchor],
            [divider.centerYAnchor
                constraintEqualToAnchor:self.centerYAnchor],
            [divider.widthAnchor constraintEqualToConstant:1.0],
            [divider.heightAnchor constraintEqualToConstant:36.0],

            [sizeIconBg.leadingAnchor
                constraintEqualToAnchor:divider.trailingAnchor constant:20.0],
            [sizeIconBg.centerYAnchor
                constraintEqualToAnchor:self.centerYAnchor],
            [sizeIconBg.widthAnchor constraintEqualToConstant:36.0],
            [sizeIconBg.heightAnchor constraintEqualToConstant:36.0],

            [sizeIcon.centerXAnchor
                constraintEqualToAnchor:sizeIconBg.centerXAnchor],
            [sizeIcon.centerYAnchor
                constraintEqualToAnchor:sizeIconBg.centerYAnchor],
            [sizeIcon.widthAnchor constraintEqualToConstant:18.0],
            [sizeIcon.heightAnchor constraintEqualToConstant:18.0],

            [_sizeLabel.leadingAnchor
                constraintEqualToAnchor:sizeIconBg.trailingAnchor constant:10.0],
            [_sizeLabel.topAnchor
                constraintEqualToAnchor:_appsCountLabel.topAnchor],

            [_sizeTitleLabel.leadingAnchor
                constraintEqualToAnchor:_sizeLabel.leadingAnchor],
            [_sizeTitleLabel.topAnchor
                constraintEqualToAnchor:_appsTitleLabel.topAnchor]
        ]];
    }
    return self;
}

@end

#pragma mark - Main View Controller

@interface MainViewController () <
    UITableViewDelegate,
    UITableViewDataSource,
    UISearchResultsUpdating
>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;

@property (nonatomic, copy) NSArray *allApps;
@property (nonatomic, copy) NSArray *filteredApps;

@property (nonatomic, strong) AppDataManager *manager;
@property (nonatomic, strong) StatsHeaderView *statsView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, assign) BOOL isCalculatingSizes;
@property (nonatomic, assign) NSUInteger operationGeneration;

@property (nonatomic, strong) dispatch_queue_t workerQueue;

@end

@implementation MainViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"AppData Manager";
    self.view.backgroundColor =
        [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];

    self.manager = [AppDataManager sharedManager];

    self.workerQueue =
        dispatch_queue_create("com.appdatamanager.worker",
                              DISPATCH_QUEUE_SERIAL);

    self.operationGeneration = 0;
    self.isCalculatingSizes = NO;

    [self setupNavigationBar];
    [self setupSearchController];
    [self setupTableView];
    [self setupLoadingView];
    [self loadApps];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.operationGeneration += 1;
    self.isCalculatingSizes = NO;
}

#pragma mark - UI Setup

- (void)setupNavigationBar {
    UINavigationBar *bar = self.navigationController.navigationBar;
    bar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode =
        UINavigationItemLargeTitleDisplayModeAlways;

    [bar setTitleTextAttributes:@{
        NSForegroundColorAttributeName : [UIColor whiteColor]
    }];
    [bar setLargeTitleTextAttributes:@{
        NSForegroundColorAttributeName : [UIColor whiteColor]
    }];

    bar.barTintColor =
        [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    bar.backgroundColor =
        [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
}

- (void)setupSearchController {
    self.searchController =
        [[UISearchController alloc] initWithSearchResultsController:nil];

    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"ابحث عن تطبيق...";

    UITextField *field =
        self.searchController.searchBar.searchTextField;
    field.backgroundColor =
        [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:1.0];
    field.textColor = [UIColor whiteColor];
    field.attributedPlaceholder =
        [[NSAttributedString alloc]
            initWithString:@"ابحث عن تطبيق..."
            attributes:@{
                NSForegroundColorAttributeName :
                    [UIColor colorWithWhite:0.35 alpha:1.0]
            }];

    self.searchController.searchBar.tintColor =
        [UIColor colorWithRed:0.55 green:0.45 blue:0.95 alpha:1.0];
    self.searchController.searchBar.barTintColor = [UIColor clearColor];
    self.searchController.searchBar.backgroundImage = [[UIImage alloc] init];

    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
}

- (void)setupTableView {
    self.tableView =
        [[UITableView alloc] initWithFrame:self.view.bounds
                                     style:UITableViewStylePlain];

    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, 20.0, 0.0);
    [self.view addSubview:self.tableView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor =
        [UIColor colorWithRed:0.55 green:0.45 blue:0.95 alpha:1.0];
    [self.refreshControl addTarget:self
                            action:@selector(loadApps)
                  forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;

    UIView *headerContainer =
        [[UIView alloc] initWithFrame:
            CGRectMake(0.0, 0.0,
                       self.view.bounds.size.width,
                       100.0)];
    headerContainer.backgroundColor = [UIColor clearColor];

    self.statsView =
        [[StatsHeaderView alloc]
            initWithFrame:
                CGRectMake(16.0, 8.0,
                           self.view.bounds.size.width - 32.0,
                           82.0)];
    self.statsView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [headerContainer addSubview:self.statsView];

    self.tableView.tableHeaderView = headerContainer;
}

- (void)setupLoadingView {
    self.loadingIndicator =
        [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:
                UIActivityIndicatorViewStyleLarge];

    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.hidesWhenStopped = YES;
    self.loadingIndicator.color =
        [UIColor colorWithRed:0.55 green:0.45 blue:0.95 alpha:1.0];
    [self.view addSubview:self.loadingIndicator];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [UIColor colorWithWhite:0.40 alpha:1.0];
    self.statusLabel.font = [UIFont systemFontOfSize:14.0];
    self.statusLabel.hidden = YES;
    [self.view addSubview:self.statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.centerXAnchor
            constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingIndicator.centerYAnchor
            constraintEqualToAnchor:self.view.centerYAnchor
            constant:-15.0],
        [self.statusLabel.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor constant:20.0],
        [self.statusLabel.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor constant:-20.0],
        [self.statusLabel.topAnchor
            constraintEqualToAnchor:self.loadingIndicator.bottomAnchor
            constant:15.0]
    ]];
}

#pragma mark - Data Loading

- (void)loadApps {
    NSAssert([NSThread isMainThread],
             @"loadApps must run on main thread");

    self.operationGeneration += 1;
    NSUInteger generation = self.operationGeneration;
    self.isCalculatingSizes = NO;

    [self.manager clearCache];

    [self.loadingIndicator startAnimating];
    self.statusLabel.text = @"جاري تحميل التطبيقات...";
    self.statusLabel.hidden = NO;
    self.tableView.hidden = YES;
    [self.refreshControl endRefreshing];

    self.statsView.appsCountLabel.text = @"—";
    self.statsView.sizeLabel.text = @"—";

    dispatch_async(self.workerQueue, ^{
        @autoreleasepool {
            NSArray *discoveredApps = nil;

            @try {
                discoveredApps =
                    [self.manager allInstalledApplications];
            } @catch (NSException *exception) {
                NSLog(@"[AppDataManager] discovery exception: %@",
                      exception);
                discoveredApps = @[];
            }

            if (![discoveredApps isKindOfClass:[NSArray class]]) {
                discoveredApps = @[];
            }

            NSMutableArray *sanitized =
                [NSMutableArray arrayWithCapacity:discoveredApps.count];

            for (id object in discoveredApps) {
                @autoreleasepool {
                    if (![object isKindOfClass:[NSDictionary class]])
                        continue;

                    NSDictionary *app = (NSDictionary *)object;
                    id rawBundleID = app[@"bundleID"];

                    if (![rawBundleID isKindOfClass:[NSString class]])
                        continue;

                    NSString *bundleID = (NSString *)rawBundleID;
                    if (bundleID.length == 0) continue;

                    NSMutableDictionary *safeApp =
                        [NSMutableDictionary dictionaryWithDictionary:app];

                    id rawName = safeApp[@"name"];
                    if (![rawName isKindOfClass:[NSString class]] ||
                        [(NSString *)rawName length] == 0) {
                        safeApp[@"name"] = bundleID;
                    }

                    if (![safeApp[@"sizeString"]
                            isKindOfClass:[NSString class]]) {
                        safeApp[@"sizeString"] = @"—";
                    }

                    [sanitized addObject:[safeApp copy]];
                }
            }

            NSArray *snapshot = [sanitized copy];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.operationGeneration) return;

                self.allApps = snapshot;
                self.filteredApps = snapshot;

                [self.loadingIndicator stopAnimating];
                self.statusLabel.hidden = YES;
                self.tableView.hidden = NO;

                self.statsView.appsCountLabel.text =
                    [NSString stringWithFormat:@"%lu",
                        (unsigned long)snapshot.count];
                self.statsView.sizeLabel.text =
                    snapshot.count ? @"جاري الحساب..." : @"0 B";

                [self.tableView reloadData];

                if (snapshot.count > 0) {
                    [self calculateSizesForGeneration:generation
                                                  apps:snapshot];
                }
            });
        }
    });
}

#pragma mark - Size Calculation

- (void)calculateSizesForGeneration:(NSUInteger)generation
                                apps:(NSArray *)apps {
    NSAssert([NSThread isMainThread],
             @"Must start from main thread");

    if (generation != self.operationGeneration) return;
    if (self.isCalculatingSizes) return;

    self.isCalculatingSizes = YES;

    dispatch_async(self.workerQueue, ^{
        @autoreleasepool {
            unsigned long long totalSize = 0;
            NSMutableArray *results =
                [NSMutableArray arrayWithCapacity:apps.count];

            __block BOOL cancelled = NO;

            for (NSDictionary *app in apps) {
                @autoreleasepool {
                    // Check generation without blocking main thread
                    if (self.operationGeneration != generation) {
                        cancelled = YES;
                        break;
                    }

                    NSString *bundleID = app[@"bundleID"];
                    if (![bundleID isKindOfClass:[NSString class]] ||
                        bundleID.length == 0) {
                        [results addObject:app];
                        continue;
                    }

                    unsigned long long size = 0;
                    NSString *sizeString = @"—";

                    @try {
                        size =
                            [self.manager dataSizeForBundleID:bundleID];

                        @try {
                            sizeString =
                                [self.manager formatBytes:size];
                        } @catch (NSException *e) {
                            sizeString = @"—";
                        }
                    } @catch (NSException *e) {
                        NSLog(@"[AppDataManager] size crash isolated "
                              @"for %@: %@", bundleID, e);
                        size = 0;
                        sizeString = @"—";
                    }

                    if (totalSize <= ULLONG_MAX - size) {
                        totalSize += size;
                    }

                    NSMutableDictionary *updated = [app mutableCopy];
                    updated[@"size"] = @(size);
                    updated[@"sizeString"] = sizeString;
                    [results addObject:[updated copy]];
                }
            }

            NSArray *finalResults = [results copy];
            unsigned long long finalTotal = totalSize;
            BOOL completed = !cancelled;

            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.operationGeneration != generation) return;

                if (!completed) {
                    self.isCalculatingSizes = NO;
                    return;
                }

                self.allApps = finalResults;

                NSString *query =
                    self.searchController.searchBar.text ?: @"";

                if (query.length == 0) {
                    self.filteredApps = self.allApps;
                } else {
                    @try {
                        NSPredicate *predicate =
                            [NSPredicate predicateWithFormat:
                                @"name CONTAINS[c] %@ OR "
                                @"bundleID CONTAINS[c] %@",
                                query, query];
                        self.filteredApps =
                            [self.allApps
                                filteredArrayUsingPredicate:predicate];
                    } @catch (NSException *e) {
                        self.filteredApps = self.allApps;
                    }
                }

                self.statsView.sizeLabel.text =
                    [self.manager formatBytes:finalTotal];

                self.isCalculatingSizes = NO;
                [self.tableView reloadData];
            });
        }
    });
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
    return self.filteredApps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"AppCell";

    AppListCell *cell =
        [tableView dequeueReusableCellWithIdentifier:cellID];

    if (!cell) {
        cell = [[AppListCell alloc]
            initWithStyle:UITableViewCellStyleDefault
            reuseIdentifier:cellID];
    }

    if (indexPath.row >= (NSInteger)self.filteredApps.count) {
        return cell;
    }

    NSDictionary *app = self.filteredApps[indexPath.row];
    NSString *bundleID = app[@"bundleID"];

    cell.representedBundleID =
        [bundleID isKindOfClass:[NSString class]] ? bundleID : nil;

    cell.nameLabel.text =
        [app[@"name"] isKindOfClass:[NSString class]]
            ? app[@"name"] : @"";

    cell.bundleLabel.text =
        [bundleID isKindOfClass:[NSString class]]
            ? bundleID : @"";

    cell.sizeLabel.text =
        [app[@"sizeString"] isKindOfClass:[NSString class]]
            ? app[@"sizeString"] : @"—";

    cell.appIcon.image =
        [UIImage systemImageNamed:@"app.fill"];
    cell.appIcon.tintColor =
        [UIColor colorWithRed:0.55 green:0.45 blue:0.95 alpha:1.0];

    if (bundleID.length > 0) {
        __weak AppListCell *weakCell = cell;
        NSUInteger generation = self.operationGeneration;

        dispatch_async(self.workerQueue, ^{
            @autoreleasepool {
                UIImage *icon = nil;
                @try {
                    icon = [self.manager iconForBundleID:bundleID];
                } @catch (NSException *e) {
                    icon = nil;
                }

                if (!icon) return;

                dispatch_async(dispatch_get_main_queue(), ^{
                    AppListCell *strongCell = weakCell;
                    if (!strongCell) return;
                    if (self.operationGeneration != generation) return;
                    if (![strongCell.representedBundleID
                            isEqualToString:bundleID]) return;

                    strongCell.appIcon.image = icon;
                    strongCell.appIcon.tintColor = nil;
                });
            }
        });
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView
didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row >= (NSInteger)self.filteredApps.count) return;

    NSDictionary *app = self.filteredApps[indexPath.row];

    @try {
        AppDetailViewController *detailVC =
            [[AppDetailViewController alloc] initWithAppInfo:app];
        if (detailVC) {
            [self.navigationController
                pushViewController:detailVC animated:YES];
        }
    } @catch (NSException *e) {
        NSLog(@"[MainViewController] detail exception: %@", e);
    }
}

- (CGFloat)tableView:(UITableView *)tableView
heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 78.0;
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:
    (UISearchController *)searchController {

    NSString *searchText =
        searchController.searchBar.text ?: @"";

    NSArray *snapshot = self.allApps ?: @[];

    if (searchText.length == 0) {
        self.filteredApps = snapshot;
    } else {
        @try {
            NSPredicate *predicate =
                [NSPredicate predicateWithFormat:
                    @"name CONTAINS[c] %@ OR bundleID CONTAINS[c] %@",
                    searchText, searchText];
            self.filteredApps =
                [snapshot filteredArrayUsingPredicate:predicate];
        } @catch (NSException *e) {
            self.filteredApps = snapshot;
        }
    }

    [self.tableView reloadData];
}

@end
