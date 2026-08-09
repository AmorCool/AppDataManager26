#import "MainViewController.h"
#import "AppDataManager.h"
#import "AppDetailViewController.h"

// MARK: - Custom App Cell
@interface AppListCell : UITableViewCell
@property (nonatomic, strong) UIImageView *appIcon;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *bundleLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UIView *containerView;
@end

@implementation AppListCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _containerView = [[UIView alloc] init];
        _containerView.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
        _containerView.layer.cornerRadius = 12;
        _containerView.layer.masksToBounds = YES;
        _containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_containerView];

        _appIcon = [[UIImageView alloc] init];
        _appIcon.layer.cornerRadius = 10;
        _appIcon.layer.masksToBounds = YES;
        _appIcon.contentMode = UIViewContentModeScaleAspectFit;
        _appIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_appIcon];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _nameLabel.textColor = [UIColor whiteColor];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_nameLabel];

        _bundleLabel = [[UILabel alloc] init];
        _bundleLabel.font = [UIFont systemFontOfSize:11];
        _bundleLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        _bundleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_bundleLabel];

        _sizeLabel = [[UILabel alloc] init];
        _sizeLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        _sizeLabel.textColor = [UIColor colorWithRed:0.4 green:0.3 blue:0.9 alpha:1.0];
        _sizeLabel.textAlignment = NSTextAlignmentRight;
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_sizeLabel];

        UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        arrow.tintColor = [UIColor colorWithWhite:0.3 alpha:1.0];
        arrow.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:arrow];

        [NSLayoutConstraint activateConstraints:@[
            [_containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_containerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_containerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
            [_containerView.heightAnchor constraintEqualToConstant:72],

            [_appIcon.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:12],
            [_appIcon.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
            [_appIcon.widthAnchor constraintEqualToConstant:48],
            [_appIcon.heightAnchor constraintEqualToConstant:48],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_appIcon.trailingAnchor constant:12],
            [_nameLabel.topAnchor constraintEqualToAnchor:_containerView.topAnchor constant:14],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:_sizeLabel.leadingAnchor constant:-8],

            [_bundleLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_bundleLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:4],
            [_bundleLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],

            [_sizeLabel.trailingAnchor constraintEqualToAnchor:arrow.leadingAnchor constant:-8],
            [_sizeLabel.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
            [_sizeLabel.widthAnchor constraintEqualToConstant:80],

            [arrow.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor constant:-12],
            [arrow.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
            [arrow.widthAnchor constraintEqualToConstant:16],
            [arrow.heightAnchor constraintEqualToConstant:16]
        ]];
    }
    return self;
}

@end

// MARK: - Stats Header View
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
        self.backgroundColor = [UIColor colorWithRed:0.08 green:0.06 blue:0.18 alpha:1.0];
        self.layer.cornerRadius = 16;
        self.layer.masksToBounds = YES;

        UIView *iconContainer = [[UIView alloc] init];
        iconContainer.backgroundColor = [UIColor colorWithRed:0.15 green:0.1 blue:0.3 alpha:1.0];
        iconContainer.layer.cornerRadius = 14;
        iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:iconContainer];

        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"square.stack.3d.up.fill"]];
        icon.tintColor = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [iconContainer addSubview:icon];

        _appsCountLabel = [[UILabel alloc] init];
        _appsCountLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
        _appsCountLabel.textColor = [UIColor whiteColor];
        _appsCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_appsCountLabel];

        _appsTitleLabel = [[UILabel alloc] init];
        _appsTitleLabel.font = [UIFont systemFontOfSize:12];
        _appsTitleLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        _appsTitleLabel.text = @"Total Apps";
        _appsTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_appsTitleLabel];

        UIView *divider = [[UIView alloc] init];
        divider.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        divider.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:divider];

        _sizeLabel = [[UILabel alloc] init];
        _sizeLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
        _sizeLabel.textColor = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_sizeLabel];

        _sizeTitleLabel = [[UILabel alloc] init];
        _sizeTitleLabel.font = [UIFont systemFontOfSize:12];
        _sizeTitleLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        _sizeTitleLabel.text = @"Total Size";
        _sizeTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_sizeTitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [iconContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [iconContainer.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [iconContainer.widthAnchor constraintEqualToConstant:52],
            [iconContainer.heightAnchor constraintEqualToConstant:52],

            [icon.centerXAnchor constraintEqualToAnchor:iconContainer.centerXAnchor],
            [icon.centerYAnchor constraintEqualToAnchor:iconContainer.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:26],
            [icon.heightAnchor constraintEqualToConstant:26],

            [_appsCountLabel.leadingAnchor constraintEqualToAnchor:iconContainer.trailingAnchor constant:16],
            [_appsCountLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:18],

            [_appsTitleLabel.leadingAnchor constraintEqualToAnchor:_appsCountLabel.leadingAnchor],
            [_appsTitleLabel.topAnchor constraintEqualToAnchor:_appsCountLabel.bottomAnchor constant:2],

            [divider.leadingAnchor constraintEqualToAnchor:_appsCountLabel.trailingAnchor constant:20],
            [divider.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [divider.widthAnchor constraintEqualToConstant:1],
            [divider.heightAnchor constraintEqualToConstant:40],

            [_sizeLabel.leadingAnchor constraintEqualToAnchor:divider.trailingAnchor constant:20],
            [_sizeLabel.topAnchor constraintEqualToAnchor:_appsCountLabel.topAnchor],

            [_sizeTitleLabel.leadingAnchor constraintEqualToAnchor:_sizeLabel.leadingAnchor],
            [_sizeTitleLabel.topAnchor constraintEqualToAnchor:_appsTitleLabel.topAnchor]
        ]];
    }
    return self;
}

@end

// MARK: - MainViewController
@interface MainViewController () <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSArray *allApps;
@property (nonatomic, strong) NSArray *filteredApps;
@property (nonatomic, strong) AppDataManager *manager;
@property (nonatomic, strong) StatsHeaderView *statsView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) BOOL isCalculatingSizes;
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AppData Manager";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    self.manager = [AppDataManager sharedManager];

    [self setupNavigationBar];
    [self setupSearchController];
    [self setupTableView];
    [self setupLoadingView];
    [self loadApps];
}

- (void)setupNavigationBar {
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    [self.navigationController.navigationBar setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}];
    [self.navigationController.navigationBar setLargeTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    self.navigationController.navigationBar.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
}

- (void)setupSearchController {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search apps...";
    self.searchController.searchBar.searchTextField.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.searchController.searchBar.searchTextField.textColor = [UIColor whiteColor];
    self.searchController.searchBar.tintColor = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];
    self.searchController.searchBar.barTintColor = [UIColor clearColor];
    self.searchController.searchBar.backgroundImage = [[UIImage alloc] init];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 20, 0);
    [self.view addSubview:self.tableView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];
    [self.refreshControl addTarget:self action:@selector(loadApps) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;

    // Header with stats
    UIView *headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 110)];
    headerContainer.backgroundColor = [UIColor clearColor];

    self.statsView = [[StatsHeaderView alloc] initWithFrame:CGRectMake(16, 8, self.view.bounds.size.width - 32, 90)];
    self.statsView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [headerContainer addSubview:self.statsView];

    self.tableView.tableHeaderView = headerContainer;
}

- (void)setupLoadingView {
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.loadingIndicator.center = self.view.center;
    self.loadingIndicator.hidesWhenStopped = YES;
    self.loadingIndicator.color = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];
    [self.view addSubview:self.loadingIndicator];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, self.view.bounds.size.width - 40, 30)];
    self.statusLabel.center = CGPointMake(self.view.center.x, self.view.center.y + 40);
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.hidden = YES;
    [self.view addSubview:self.statusLabel];
}

#pragma mark - Fast Loading

- (void)loadApps {
    [self.loadingIndicator startAnimating];
    self.statusLabel.text = @"Loading applications...";
    self.statusLabel.hidden = NO;
    self.tableView.hidden = YES;

    // Clear cache on refresh
    [self.manager clearCache];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // FAST: Get apps WITHOUT calculating sizes
        self.allApps = [self.manager allInstalledApplications];
        self.filteredApps = self.allApps;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIndicator stopAnimating];
            self.statusLabel.hidden = YES;
            self.tableView.hidden = NO;
            [self.refreshControl endRefreshing];

            self.statsView.appsCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.allApps.count];
            self.statsView.sizeLabel.text = @"Calculating...";

            [self.tableView reloadData];

            // NOW calculate sizes in background
            [self calculateSizesInBackground];
        });
    });
}

- (void)calculateSizesInBackground {
    if (self.isCalculatingSizes) return;
    self.isCalculatingSizes = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSMutableArray *updatedApps = [NSMutableArray array];
        unsigned long long totalSize = 0;

        for (NSMutableDictionary *app in self.allApps) {
            NSString *bundleID = app[@"bundleID"];

            // Calculate size
            unsigned long long size = [self.manager dataSizeForBundleID:bundleID];
            NSString *sizeStr = [self.manager formatBytes:size];

            NSMutableDictionary *updatedApp = [app mutableCopy];
            updatedApp[@"size"] = @(size);
            updatedApp[@"sizeString"] = sizeStr;
            [updatedApps addObject:updatedApp];

            totalSize += size;

            // Update UI every 5 apps to avoid lag
            if ([updatedApps count] % 5 == 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.statsView.sizeLabel.text = [self.manager formatBytes:totalSize];
                    // Update visible cells only
                    [self updateVisibleCellSizes];
                });
            }
        }

        self.allApps = updatedApps;
        self.filteredApps = self.allApps;

        dispatch_async(dispatch_get_main_queue(), ^{
            self.statsView.sizeLabel.text = [self.manager formatBytes:totalSize];
            [self.tableView reloadData];
            self.isCalculatingSizes = NO;
        });
    });
}

- (void)updateVisibleCellSizes {
    NSArray *visiblePaths = [self.tableView indexPathsForVisibleRows];
    for (NSIndexPath *path in visiblePaths) {
        if (path.row < self.filteredApps.count) {
            NSDictionary *app = self.filteredApps[path.row];
            AppListCell *cell = [self.tableView cellForRowAtIndexPath:path];
            if ([cell isKindOfClass:[AppListCell class]]) {
                cell.sizeLabel.text = app[@"sizeString"];
            }
        }
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"AppCell";
    AppListCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[AppListCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
    }

    NSDictionary *app = self.filteredApps[indexPath.row];
    cell.nameLabel.text = app[@"name"];
    cell.bundleLabel.text = app[@"bundleID"];
    cell.sizeLabel.text = app[@"sizeString"];

    // Load icon async
    NSString *bundleID = app[@"bundleID"];
    UIImage *icon = [self.manager iconForBundleID:bundleID];
    if (icon) {
        cell.appIcon.image = icon;
    } else {
        cell.appIcon.image = [UIImage systemImageNamed:@"app.fill"];
        cell.appIcon.tintColor = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *app = self.filteredApps[indexPath.row];
    AppDetailViewController *detailVC = [[AppDetailViewController alloc] initWithAppInfo:app];
    [self.navigationController pushViewController:detailVC animated:YES];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 80;
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchText = searchController.searchBar.text;
    if (searchText.length == 0) {
        self.filteredApps = self.allApps;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[c] %@ OR bundleID CONTAINS[c] %@", searchText, searchText];
        self.filteredApps = [self.allApps filteredArrayUsingPredicate:predicate];
    }
    [self.tableView reloadData];
}

@end
