#import "MainViewController.h"
#import "AppDataManager.h"
#import "AppDetailViewController.h"

#pragma mark - Design System

static UIColor *ADMBackgroundColor(void) { return [UIColor colorWithRed:0.035 green:0.035 blue:0.055 alpha:1.0]; }
static UIColor *ADMCardColor(void) { return [UIColor colorWithRed:0.085 green:0.085 blue:0.125 alpha:1.0]; }
static UIColor *ADMSecondaryTextColor(void) { return [UIColor colorWithWhite:0.58 alpha:1.0]; }
static UIColor *ADMPrimaryAccent(void) { return [UIColor colorWithRed:0.54 green:0.42 blue:0.98 alpha:1.0]; }
static UIColor *ADMSystemAccent(void) { return [UIColor colorWithRed:0.30 green:0.66 blue:0.96 alpha:1.0]; }

#pragma mark - App Cell

@interface AppListCell : UITableViewCell
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIImageView *appIcon;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *bundleLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@end

@implementation AppListCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(4, 16, 4, 16);

        _containerView = [[UIView alloc] init];
        _containerView.backgroundColor = ADMCardColor();
        _containerView.layer.cornerRadius = 18.0;
        _containerView.layer.masksToBounds = YES;
        _containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_containerView];

        _appIcon = [[UIImageView alloc] init];
        _appIcon.layer.cornerRadius = 13.0;
        _appIcon.layer.masksToBounds = YES;
        _appIcon.contentMode = UIViewContentModeScaleAspectFit;
        _appIcon.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1.0];
        _appIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_appIcon];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _nameLabel.textColor = UIColor.whiteColor;
        _nameLabel.numberOfLines = 1;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_nameLabel];

        _bundleLabel = [[UILabel alloc] init];
        _bundleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
        _bundleLabel.textColor = [UIColor colorWithWhite:0.42 alpha:1.0];
        _bundleLabel.numberOfLines = 1;
        _bundleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _bundleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_bundleLabel];

        _sizeLabel = [[UILabel alloc] init];
        _sizeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _sizeLabel.textColor = ADMPrimaryAccent();
        _sizeLabel.textAlignment = NSTextAlignmentRight;
        _sizeLabel.numberOfLines = 1;
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_sizeLabel];

        UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]];
        arrow.tintColor = [UIColor colorWithWhite:0.34 alpha:1.0];
        arrow.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:arrow];

        [NSLayoutConstraint activateConstraints:@[
            [_containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_containerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_containerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
            [_containerView.heightAnchor constraintEqualToConstant:74],

            [_appIcon.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:14],
            [_appIcon.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
            [_appIcon.widthAnchor constraintEqualToConstant:46],
            [_appIcon.heightAnchor constraintEqualToConstant:46],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_appIcon.trailingAnchor constant:13],
            [_nameLabel.topAnchor constraintEqualToAnchor:_containerView.topAnchor constant:14],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:_sizeLabel.leadingAnchor constant:-10],

            [_bundleLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_bundleLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:4],
            [_bundleLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],

            [_sizeLabel.trailingAnchor constraintEqualToAnchor:arrow.leadingAnchor constant:-8],
            [_sizeLabel.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
            [_sizeLabel.widthAnchor constraintEqualToConstant:76],

            [arrow.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor constant:-15],
            [arrow.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
            [arrow.widthAnchor constraintEqualToConstant:14],
            [arrow.heightAnchor constraintEqualToConstant:14]
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.nameLabel.text = nil;
    self.bundleLabel.text = nil;
    self.sizeLabel.text = nil;
    self.appIcon.image = nil;
    self.appIcon.tintColor = nil;
    self.alpha = 1.0;
    self.transform = CGAffineTransformIdentity;
}

@end

#pragma mark - Section Header

@interface AppSectionHeaderView : UITableViewHeaderFooterView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIView *accentView;
@end

@implementation AppSectionHeaderView

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundView = [[UIView alloc] init];
        self.backgroundView.backgroundColor = ADMBackgroundColor();
        self.contentView.backgroundColor = ADMBackgroundColor();

        _accentView = [[UIView alloc] init];
        _accentView.layer.cornerRadius = 3;
        _accentView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_accentView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_titleLabel];

        _countLabel = [[UILabel alloc] init];
        _countLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _countLabel.textColor = ADMSecondaryTextColor();
        _countLabel.textAlignment = NSTextAlignmentCenter;
        _countLabel.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1.0];
        _countLabel.layer.cornerRadius = 12;
        _countLabel.layer.masksToBounds = YES;
        _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_countLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_accentView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18],
            [_accentView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_accentView.widthAnchor constraintEqualToConstant:6],
            [_accentView.heightAnchor constraintEqualToConstant:22],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_accentView.trailingAnchor constant:10],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_countLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18],
            [_countLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_countLabel.widthAnchor constraintEqualToConstant:42],
            [_countLabel.heightAnchor constraintEqualToConstant:24]
        ]];
    }
    return self;
}

@end

#pragma mark - Stats Header

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
        self.backgroundColor = ADMCardColor();
        self.layer.cornerRadius = 22;
        self.layer.masksToBounds = YES;

        UIView *appsIconBackground = [[UIView alloc] init];
        appsIconBackground.backgroundColor = [UIColor colorWithRed:0.20 green:0.15 blue:0.36 alpha:1.0];
        appsIconBackground.layer.cornerRadius = 14;
        appsIconBackground.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:appsIconBackground];

        UIImageView *appsIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"square.grid.2x2.fill"]];
        appsIcon.tintColor = ADMPrimaryAccent();
        appsIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [appsIconBackground addSubview:appsIcon];

        _appsCountLabel = [[UILabel alloc] init];
        _appsCountLabel.font = [UIFont systemFontOfSize:25 weight:UIFontWeightBold];
        _appsCountLabel.textColor = UIColor.whiteColor;
        _appsCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_appsCountLabel];

        _appsTitleLabel = [[UILabel alloc] init];
        _appsTitleLabel.text = @"التطبيقات المثبتة";
        _appsTitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _appsTitleLabel.textColor = ADMSecondaryTextColor();
        _appsTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_appsTitleLabel];

        UIView *divider = [[UIView alloc] init];
        divider.backgroundColor = [UIColor colorWithWhite:0.22 alpha:0.7];
        divider.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:divider];

        UIView *sizeIconBackground = [[UIView alloc] init];
        sizeIconBackground.backgroundColor = [UIColor colorWithRed:0.12 green:0.25 blue:0.38 alpha:1.0];
        sizeIconBackground.layer.cornerRadius = 14;
        sizeIconBackground.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:sizeIconBackground];

        UIImageView *sizeIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"externaldrive.fill"]];
        sizeIcon.tintColor = ADMSystemAccent();
        sizeIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [sizeIconBackground addSubview:sizeIcon];

        _sizeLabel = [[UILabel alloc] init];
        _sizeLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
        _sizeLabel.textColor = UIColor.whiteColor;
        _sizeLabel.adjustsFontSizeToFitWidth = YES;
        _sizeLabel.minimumScaleFactor = 0.72;
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_sizeLabel];

        _sizeTitleLabel = [[UILabel alloc] init];
        _sizeTitleLabel.text = @"حجم بيانات المستخدم";
        _sizeTitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _sizeTitleLabel.textColor = ADMSecondaryTextColor();
        _sizeTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_sizeTitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [appsIconBackground.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
            [appsIconBackground.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [appsIconBackground.widthAnchor constraintEqualToConstant:44],
            [appsIconBackground.heightAnchor constraintEqualToConstant:44],
            [appsIcon.centerXAnchor constraintEqualToAnchor:appsIconBackground.centerXAnchor],
            [appsIcon.centerYAnchor constraintEqualToAnchor:appsIconBackground.centerYAnchor],
            [appsIcon.widthAnchor constraintEqualToConstant:22],
            [appsIcon.heightAnchor constraintEqualToConstant:22],

            [_appsCountLabel.leadingAnchor constraintEqualToAnchor:appsIconBackground.trailingAnchor constant:11],
            [_appsCountLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:17],
            [_appsTitleLabel.leadingAnchor constraintEqualToAnchor:_appsCountLabel.leadingAnchor],
            [_appsTitleLabel.topAnchor constraintEqualToAnchor:_appsCountLabel.bottomAnchor constant:2],

            [divider.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [divider.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [divider.widthAnchor constraintEqualToConstant:1],
            [divider.heightAnchor constraintEqualToConstant:44],

            [sizeIconBackground.leadingAnchor constraintEqualToAnchor:divider.trailingAnchor constant:18],
            [sizeIconBackground.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [sizeIconBackground.widthAnchor constraintEqualToConstant:44],
            [sizeIconBackground.heightAnchor constraintEqualToConstant:44],
            [sizeIcon.centerXAnchor constraintEqualToAnchor:sizeIconBackground.centerXAnchor],
            [sizeIcon.centerYAnchor constraintEqualToAnchor:sizeIconBackground.centerYAnchor],
            [sizeIcon.widthAnchor constraintEqualToConstant:22],
            [sizeIcon.heightAnchor constraintEqualToConstant:22],

            [_sizeLabel.leadingAnchor constraintEqualToAnchor:sizeIconBackground.trailingAnchor constant:11],
            [_sizeLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [_sizeLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:19],
            [_sizeTitleLabel.leadingAnchor constraintEqualToAnchor:_sizeLabel.leadingAnchor],
            [_sizeTitleLabel.topAnchor constraintEqualToAnchor:_sizeLabel.bottomAnchor constant:2]
        ]];
    }
    return self;
}

@end

#pragma mark - Main Controller

@interface MainViewController () <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSArray *allApps;
@property (nonatomic, strong) NSArray *userApps;
@property (nonatomic, strong) NSArray *systemApps;
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
    self.title = @"التطبيقات";
    self.view.backgroundColor = ADMBackgroundColor();
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
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
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.barTintColor = ADMBackgroundColor();
    self.navigationController.navigationBar.backgroundColor = ADMBackgroundColor();
    self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    self.navigationController.navigationBar.largeTitleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor, NSFontAttributeName: [UIFont systemFontOfSize:34 weight:UIFontWeightBold]};
}

- (void)setupSearchController {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"ابحث بالاسم أو معرف الحزمة";
    self.searchController.searchBar.tintColor = ADMPrimaryAccent();
    self.searchController.searchBar.searchTextField.textColor = UIColor.whiteColor;
    self.searchController.searchBar.searchTextField.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.searchController.searchBar.searchTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:self.searchController.searchBar.placeholder attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.42 alpha:1.0]}];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = ADMBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 28, 0);
    self.tableView.sectionHeaderHeight = 48;
    self.tableView.estimatedRowHeight = 82;
    self.tableView.rowHeight = 82;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    [self.tableView registerClass:[AppSectionHeaderView class] forHeaderFooterViewReuseIdentifier:@"AppSectionHeader"];

    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = ADMPrimaryAccent();
    [self.refreshControl addTarget:self action:@selector(loadApps) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;

    UIView *headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 124)];
    headerContainer.backgroundColor = ADMBackgroundColor();
    self.statsView = [[StatsHeaderView alloc] initWithFrame:CGRectMake(16, 12, self.view.bounds.size.width - 32, 98)];
    self.statsView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [headerContainer addSubview:self.statsView];
    self.tableView.tableHeaderView = headerContainer;
}

- (void)setupLoadingView {
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingIndicator.color = ADMPrimaryAccent();
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.loadingIndicator];
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = ADMSecondaryTextColor();
    self.statusLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.statusLabel.hidden = YES;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.loadingIndicator.bottomAnchor constant:14],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24]
    ]];
}

#pragma mark - Loading and filtering

- (void)loadApps {
    [self.loadingIndicator startAnimating];
    self.statusLabel.text = @"جاري تجهيز التطبيقات...";
    self.statusLabel.hidden = NO;
    self.tableView.hidden = YES;
    [self.manager clearCache];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *apps = [self.manager allInstalledApplications];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allApps = apps ?: @[];
            [self rebuildSectionsForSearchText:self.searchController.searchBar.text];
            [self.loadingIndicator stopAnimating];
            self.statusLabel.hidden = YES;
            self.tableView.hidden = NO;
            [self.refreshControl endRefreshing];
            self.statsView.appsCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.allApps.count];
            self.statsView.sizeLabel.text = @"جاري الحساب...";
            [self.tableView reloadData];
            [self calculateSizesInBackground];
        });
    });
}

- (void)rebuildSectionsForSearchText:(NSString *)searchText {
    NSPredicate *isSystem = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *app, NSDictionary *_) {
        return [app[@"isSystemApp"] boolValue];
    }];
    NSPredicate *isUser = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *app, NSDictionary *_) {
        return ![app[@"isSystemApp"] boolValue];
    }];

    NSArray *user = [self.allApps filteredArrayUsingPredicate:isUser];
    NSArray *system = [self.allApps filteredArrayUsingPredicate:isSystem];
    if (searchText.length > 0) {
        NSPredicate *matches = [NSPredicate predicateWithFormat:@"name CONTAINS[c] %@ OR bundleID CONTAINS[c] %@", searchText, searchText];
        user = [user filteredArrayUsingPredicate:matches];
        system = [system filteredArrayUsingPredicate:matches];
    }
    self.userApps = user;
    self.systemApps = system;
}

- (NSArray *)appsForSection:(NSInteger)section {
    return section == 0 ? (self.userApps ?: @[]) : (self.systemApps ?: @[]);
}

- (void)calculateSizesInBackground {
    if (self.isCalculatingSizes) return;
    self.isCalculatingSizes = YES;
    NSArray *snapshot = [self.allApps copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSMutableArray *updatedApps = [NSMutableArray arrayWithCapacity:snapshot.count];
        unsigned long long totalSize = 0;
        for (NSDictionary *app in snapshot) {
            NSString *bundleID = app[@"bundleID"];
            unsigned long long size = [self.manager dataSizeForBundleID:bundleID];
            NSMutableDictionary *updated = [app mutableCopy];
            updated[@"size"] = @(size);
            updated[@"sizeString"] = [self.manager formatBytes:size];
            [updatedApps addObject:updated];
            totalSize += size;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allApps = updatedApps;
            [self rebuildSectionsForSearchText:self.searchController.searchBar.text];
            self.statsView.sizeLabel.text = [self.manager formatBytes:totalSize];
            [self.tableView reloadData];
            self.isCalculatingSizes = NO;
        });
    });
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self appsForSection:section].count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    AppSectionHeaderView *header = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"AppSectionHeader"];
    NSArray *apps = [self appsForSection:section];
    header.titleLabel.text = section == 0 ? @"تطبيقات المستخدم" : @"تطبيقات النظام";
    header.countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)apps.count];
    header.accentView.backgroundColor = section == 0 ? ADMPrimaryAccent() : ADMSystemAccent();
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 50; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"AppCell";
    AppListCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) cell = [[AppListCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];

    NSDictionary *app = [self appsForSection:indexPath.section][indexPath.row];
    cell.nameLabel.text = app[@"name"];
    cell.bundleLabel.text = app[@"bundleID"];
    cell.sizeLabel.text = app[@"sizeString"] ?: @"جاري الحساب...";

    UIImage *icon = [self.manager iconForBundleID:app[@"bundleID"]];
    if (icon) {
        cell.appIcon.image = icon;
        cell.appIcon.tintColor = nil;
    } else {
        cell.appIcon.image = [UIImage systemImageNamed:@"app.fill"];
        cell.appIcon.tintColor = indexPath.section == 0 ? ADMPrimaryAccent() : ADMSystemAccent();
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (cell.layer.presentationLayer) return;
    cell.alpha = 0.0;
    cell.transform = CGAffineTransformMakeTranslation(0, 8);
    [UIView animateWithDuration:0.28 delay:MIN(indexPath.row * 0.025, 0.18) options:UIViewAnimationOptionCurveEaseOut animations:^{
        cell.alpha = 1.0;
        cell.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *app = [self appsForSection:indexPath.section][indexPath.row];
    AppDetailViewController *detailVC = [[AppDetailViewController alloc] initWithAppInfo:app];
    [self.navigationController pushViewController:detailVC animated:YES];
}

- (void)updateVisibleCellSizes {
    for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) {
        NSArray *apps = [self appsForSection:path.section];
        if (path.row >= apps.count) continue;
        AppListCell *cell = (AppListCell *)[self.tableView cellForRowAtIndexPath:path];
        cell.sizeLabel.text = apps[path.row][@"sizeString"];
    }
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self rebuildSectionsForSearchText:searchController.searchBar.text];
    [self.tableView reloadData];
}

@end
