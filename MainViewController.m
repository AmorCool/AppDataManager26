#import "MainViewController.h"
#import "AppDataManager.h"
#import "AppDetailViewController.h"

#pragma mark - New visual language

static UIColor *ADMCanvas(void) { return [UIColor colorWithRed:0.025 green:0.027 blue:0.035 alpha:1.0]; }
static UIColor *ADMPanel(void) { return [UIColor colorWithRed:0.075 green:0.082 blue:0.105 alpha:1.0]; }
static UIColor *ADMPanelRaised(void) { return [UIColor colorWithRed:0.105 green:0.115 blue:0.145 alpha:1.0]; }
static UIColor *ADMInk(void) { return [UIColor colorWithRed:0.93 green:0.95 blue:0.98 alpha:1.0]; }
static UIColor *ADMMuted(void) { return [UIColor colorWithRed:0.53 green:0.57 blue:0.64 alpha:1.0]; }
static UIColor *ADMBlue(void) { return [UIColor colorWithRed:0.20 green:0.67 blue:0.96 alpha:1.0]; }
static UIColor *ADMGreen(void) { return [UIColor colorWithRed:0.24 green:0.82 blue:0.58 alpha:1.0]; }
static UIColor *ADMOrange(void) { return [UIColor colorWithRed:0.98 green:0.63 blue:0.25 alpha:1.0]; }

#pragma mark - App row

@interface AppListCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *accentRail;
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

        _cardView = [[UIView alloc] init];
        _cardView.backgroundColor = ADMPanel();
        _cardView.layer.cornerRadius = 15;
        _cardView.layer.masksToBounds = YES;
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_cardView];

        _accentRail = [[UIView alloc] init];
        _accentRail.layer.cornerRadius = 2;
        _accentRail.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_accentRail];

        _appIcon = [[UIImageView alloc] init];
        _appIcon.layer.cornerRadius = 12;
        _appIcon.layer.masksToBounds = YES;
        _appIcon.contentMode = UIViewContentModeScaleAspectFit;
        _appIcon.backgroundColor = ADMPanelRaised();
        _appIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_appIcon];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _nameLabel.textColor = ADMInk();
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_nameLabel];

        _bundleLabel = [[UILabel alloc] init];
        _bundleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
        _bundleLabel.textColor = ADMMuted();
        _bundleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _bundleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_bundleLabel];

        _sizeLabel = [[UILabel alloc] init];
        _sizeLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
        _sizeLabel.textColor = ADMBlue();
        _sizeLabel.textAlignment = NSTextAlignmentCenter;
        _sizeLabel.backgroundColor = [UIColor colorWithRed:0.08 green:0.22 blue:0.32 alpha:1.0];
        _sizeLabel.layer.cornerRadius = 9;
        _sizeLabel.layer.masksToBounds = YES;
        _sizeLabel.adjustsFontSizeToFitWidth = YES;
        _sizeLabel.minimumScaleFactor = 0.65;
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_sizeLabel];

        UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]];
        arrow.tintColor = [UIColor colorWithWhite:0.38 alpha:1.0];
        arrow.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:arrow];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5],
            [_cardView.heightAnchor constraintEqualToConstant:76],

            [_accentRail.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor],
            [_accentRail.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:16],
            [_accentRail.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-16],
            [_accentRail.widthAnchor constraintEqualToConstant:4],

            [_appIcon.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:15],
            [_appIcon.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_appIcon.widthAnchor constraintEqualToConstant:46],
            [_appIcon.heightAnchor constraintEqualToConstant:46],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_appIcon.trailingAnchor constant:13],
            [_nameLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:14],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:_sizeLabel.leadingAnchor constant:-10],

            [_bundleLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_bundleLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:4],
            [_bundleLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],

            [_sizeLabel.trailingAnchor constraintEqualToAnchor:arrow.leadingAnchor constant:-8],
            [_sizeLabel.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_sizeLabel.widthAnchor constraintEqualToConstant:74],
            [_sizeLabel.heightAnchor constraintEqualToConstant:25],

            [arrow.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-14],
            [arrow.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [arrow.widthAnchor constraintEqualToConstant:12],
            [arrow.heightAnchor constraintEqualToConstant:16]
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

#pragma mark - Section header

@interface AppSectionHeaderView : UITableViewHeaderFooterView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIView *marker;
@end

@implementation AppSectionHeaderView

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundView = [[UIView alloc] init];
        self.backgroundView.backgroundColor = ADMCanvas();
        self.contentView.backgroundColor = ADMCanvas();

        _marker = [[UIView alloc] init];
        _marker.layer.cornerRadius = 3;
        _marker.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_marker];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        _titleLabel.textColor = ADMInk();
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        _subtitleLabel.textColor = ADMMuted();
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_subtitleLabel];

        _countLabel = [[UILabel alloc] init];
        _countLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightBold];
        _countLabel.textColor = ADMInk();
        _countLabel.textAlignment = NSTextAlignmentCenter;
        _countLabel.backgroundColor = ADMPanelRaised();
        _countLabel.layer.cornerRadius = 11;
        _countLabel.layer.masksToBounds = YES;
        _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_countLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_marker.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18],
            [_marker.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_marker.widthAnchor constraintEqualToConstant:6],
            [_marker.heightAnchor constraintEqualToConstant:30],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_marker.trailingAnchor constant:10],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:1],
            [_countLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18],
            [_countLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_countLabel.widthAnchor constraintEqualToConstant:40],
            [_countLabel.heightAnchor constraintEqualToConstant:23]
        ]];
    }
    return self;
}

@end

#pragma mark - Dashboard header

@interface StatsHeaderView : UIView
@property (nonatomic, strong) UILabel *eyebrowLabel;
@property (nonatomic, strong) UILabel *headlineLabel;
@property (nonatomic, strong) UILabel *appsValueLabel;
@property (nonatomic, strong) UILabel *sizeValueLabel;
@property (nonatomic, strong) UIView *appsTile;
@property (nonatomic, strong) UIView *sizeTile;
@end

@implementation StatsHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = ADMPanel();
        self.layer.cornerRadius = 20;
        self.layer.masksToBounds = YES;

        UIView *topLine = [[UIView alloc] init];
        topLine.backgroundColor = ADMBlue();
        topLine.layer.cornerRadius = 2;
        topLine.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:topLine];

        _eyebrowLabel = [[UILabel alloc] init];
        _eyebrowLabel.text = @"APP DATA MANAGER  /  OVERVIEW";
        _eyebrowLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightSemibold];
        _eyebrowLabel.textColor = ADMBlue();
        _eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_eyebrowLabel];

        _headlineLabel = [[UILabel alloc] init];
        _headlineLabel.text = @"مساحة التطبيقات";
        _headlineLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
        _headlineLabel.textColor = ADMInk();
        _headlineLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_headlineLabel];

        _appsTile = [self makeTileWithColor:ADMGreen() icon:@"square.grid.2x2.fill"];
        [self addSubview:_appsTile];
        _sizeTile = [self makeTileWithColor:ADMOrange() icon:@"internaldrive.fill"];
        [self addSubview:_sizeTile];

        _appsValueLabel = (UILabel *)[_appsTile viewWithTag:101];
        _sizeValueLabel = (UILabel *)[_sizeTile viewWithTag:101];

        UILabel *appsCaption = (UILabel *)[_appsTile viewWithTag:102];
        appsCaption.text = @"تطبيقاً مثبتاً";
        UILabel *sizeCaption = (UILabel *)[_sizeTile viewWithTag:102];
        sizeCaption.text = @"حجم البيانات";

        [NSLayoutConstraint activateConstraints:@[
            [topLine.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
            [topLine.topAnchor constraintEqualToAnchor:self.topAnchor constant:18],
            [topLine.widthAnchor constraintEqualToConstant:28],
            [topLine.heightAnchor constraintEqualToConstant:4],
            [_eyebrowLabel.leadingAnchor constraintEqualToAnchor:topLine.trailingAnchor constant:8],
            [_eyebrowLabel.centerYAnchor constraintEqualToAnchor:topLine.centerYAnchor],
            [_headlineLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
            [_headlineLabel.topAnchor constraintEqualToAnchor:_eyebrowLabel.bottomAnchor constant:7],
            [_appsTile.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_appsTile.topAnchor constraintEqualToAnchor:_headlineLabel.bottomAnchor constant:12],
            [_appsTile.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.5 constant:-21],
            [_appsTile.heightAnchor constraintEqualToConstant:60],
            [_sizeTile.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [_sizeTile.topAnchor constraintEqualToAnchor:_appsTile.topAnchor],
            [_sizeTile.widthAnchor constraintEqualToAnchor:_appsTile.widthAnchor],
            [_sizeTile.heightAnchor constraintEqualToAnchor:_appsTile.heightAnchor]
        ]];
    }
    return self;
}

- (UIView *)makeTileWithColor:(UIColor *)color icon:(NSString *)iconName {
    UIView *tile = [[UIView alloc] init];
    tile.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.55];
    tile.layer.cornerRadius = 13;
    tile.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    icon.tintColor = color;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [tile addSubview:icon];

    UILabel *value = [[UILabel alloc] init];
    value.tag = 101;
    value.text = @"—";
    value.font = [UIFont monospacedDigitSystemFontOfSize:19 weight:UIFontWeightBold];
    value.textColor = ADMInk();
    value.translatesAutoresizingMaskIntoConstraints = NO;
    [tile addSubview:value];

    UILabel *caption = [[UILabel alloc] init];
    caption.tag = 102;
    caption.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    caption.textColor = ADMMuted();
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    [tile addSubview:caption];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:12],
        [icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:20],
        [icon.heightAnchor constraintEqualToConstant:20],
        [value.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:9],
        [value.topAnchor constraintEqualToAnchor:tile.topAnchor constant:10],
        [value.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-8],
        [caption.leadingAnchor constraintEqualToAnchor:value.leadingAnchor],
        [caption.topAnchor constraintEqualToAnchor:value.bottomAnchor constant:1],
        [caption.trailingAnchor constraintEqualToAnchor:value.trailingAnchor]
    ]];
    return tile;
}

@end

#pragma mark - Empty and loading state

@interface ADMStateView : UIView
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *retryButton;
@end

@implementation ADMStateView

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.backgroundColor = ADMPanel();
        self.layer.cornerRadius = 20;
        self.layer.masksToBounds = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.color = ADMBlue();
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_spinner];

        _iconView = [[UIImageView alloc] init];
        _iconView.tintColor = ADMBlue();
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        _titleLabel.textColor = ADMInk();
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _messageLabel = [[UILabel alloc] init];
        _messageLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        _messageLabel.textColor = ADMMuted();
        _messageLabel.textAlignment = NSTextAlignmentCenter;
        _messageLabel.numberOfLines = 0;
        _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_messageLabel];

        _retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_retryButton setTitle:@"إعادة المحاولة" forState:UIControlStateNormal];
        [_retryButton setTitleColor:ADMBlue() forState:UIControlStateNormal];
        _retryButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _retryButton.backgroundColor = [UIColor colorWithRed:0.08 green:0.22 blue:0.32 alpha:1.0];
        _retryButton.layer.cornerRadius = 11;
        _retryButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_retryButton];

        [NSLayoutConstraint activateConstraints:@[
            [_spinner.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_spinner.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_iconView.topAnchor constraintEqualToAnchor:self.topAnchor constant:26],
            [_iconView.widthAnchor constraintEqualToConstant:34],
            [_iconView.heightAnchor constraintEqualToConstant:34],
            [_titleLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:12],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18],
            [_messageLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:7],
            [_messageLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:26],
            [_messageLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-26],
            [_retryButton.topAnchor constraintEqualToAnchor:_messageLabel.bottomAnchor constant:16],
            [_retryButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_retryButton.widthAnchor constraintEqualToConstant:126],
            [_retryButton.heightAnchor constraintEqualToConstant:36]
        ]];
    }
    return self;
}

@end

#pragma mark - Main controller

@interface MainViewController () <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSArray *allApps;
@property (nonatomic, strong) NSArray *userApps;
@property (nonatomic, strong) NSArray *systemApps;
@property (nonatomic, strong) AppDataManager *manager;
@property (nonatomic, strong) StatsHeaderView *statsView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) ADMStateView *stateView;
@property (nonatomic, assign) BOOL isCalculatingSizes;
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"التطبيقات";
    self.view.backgroundColor = ADMCanvas();
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.manager = [AppDataManager sharedManager];
    self.allApps = @[];
    self.userApps = @[];
    self.systemApps = @[];
    [self setupNavigationBar];
    [self setupSearchController];
    [self setupTableView];
    [self setupStateView];
    [self loadApps];
}

- (void)setupNavigationBar {
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.tintColor = ADMInk();
    self.navigationController.navigationBar.barTintColor = ADMCanvas();
    self.navigationController.navigationBar.backgroundColor = ADMCanvas();
    self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: ADMInk()};
    self.navigationController.navigationBar.largeTitleTextAttributes = @{NSForegroundColorAttributeName: ADMInk(), NSFontAttributeName: [UIFont systemFontOfSize:34 weight:UIFontWeightBold]};
}

- (void)setupSearchController {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"ابحث بالاسم أو معرف الحزمة";
    self.searchController.searchBar.tintColor = ADMBlue();
    self.searchController.searchBar.searchTextField.textColor = ADMInk();
    self.searchController.searchBar.searchTextField.backgroundColor = ADMPanelRaised();
    self.searchController.searchBar.searchTextField.layer.cornerRadius = 12;
    self.searchController.searchBar.searchTextField.layer.masksToBounds = YES;
    self.searchController.searchBar.searchTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:self.searchController.searchBar.placeholder attributes:@{NSForegroundColorAttributeName: ADMMuted()}];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = ADMCanvas();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 30, 0);
    self.tableView.estimatedRowHeight = 86;
    self.tableView.rowHeight = 86;
    self.tableView.sectionHeaderHeight = 60;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    [self.tableView registerClass:[AppSectionHeaderView class] forHeaderFooterViewReuseIdentifier:@"AppSectionHeader"];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = ADMBlue();
    [self.refreshControl addTarget:self action:@selector(loadApps) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;

    UIView *headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 174)];
    headerContainer.backgroundColor = ADMCanvas();
    self.statsView = [[StatsHeaderView alloc] initWithFrame:CGRectMake(16, 12, self.view.bounds.size.width - 32, 150)];
    self.statsView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [headerContainer addSubview:self.statsView];
    self.tableView.tableHeaderView = headerContainer;
}

- (void)setupStateView {
    self.stateView = [[ADMStateView alloc] init];
    self.stateView.hidden = YES;
    [self.stateView.retryButton addTarget:self action:@selector(loadApps) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.stateView];
    [NSLayoutConstraint activateConstraints:@[
        [self.stateView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],
        [self.stateView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28],
        [self.stateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:28],
        [self.stateView.heightAnchor constraintEqualToConstant:210]
    ]];
}

#pragma mark - Loading

- (void)loadApps {
    [self.stateView.spinner startAnimating];
    self.stateView.hidden = NO;
    self.stateView.iconView.hidden = YES;
    self.stateView.titleLabel.text = @"جاري قراءة التطبيقات";
    self.stateView.messageLabel.text = @"يتم جلب القائمة من النظام…";
    self.stateView.retryButton.hidden = YES;
    self.tableView.alpha = self.allApps.count > 0 ? 1.0 : 0.35;
    [self.manager clearCache];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *apps = [self.manager allInstalledApplications];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allApps = apps ?: @[];
            [self rebuildSectionsForSearchText:self.searchController.searchBar.text];
            [self.refreshControl endRefreshing];
            [self.stateView.spinner stopAnimating];
            [self updateStateAfterLoad];
            self.statsView.appsValueLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.allApps.count];
            self.statsView.sizeValueLabel.text = @"جارٍ الحساب";
            [self.tableView reloadData];
            [self calculateSizesInBackground];
        });
    });
}

- (void)updateStateAfterLoad {
    if (self.allApps.count > 0) {
        self.stateView.hidden = YES;
        self.tableView.alpha = 1.0;
        return;
    }
    self.stateView.hidden = NO;
    self.stateView.iconView.hidden = NO;
    self.stateView.iconView.image = [UIImage systemImageNamed:@"square.grid.2x2"];
    self.stateView.titleLabel.text = @"لم يتم العثور على تطبيقات";
    self.stateView.messageLabel.text = @"لم تُرجع خدمة النظام قائمة التطبيقات. يمكنك إعادة المحاولة دون فقدان أي بيانات.";
    self.stateView.retryButton.hidden = NO;
    self.tableView.alpha = 1.0;
}

- (void)rebuildSectionsForSearchText:(NSString *)searchText {
    NSMutableArray *users = [NSMutableArray array];
    NSMutableArray *systems = [NSMutableArray array];
    NSPredicate *matches = searchText.length > 0 ? [NSPredicate predicateWithFormat:@"name CONTAINS[c] %@ OR bundleID CONTAINS[c] %@", searchText, searchText] : nil;
    for (NSDictionary *app in self.allApps) {
        if (matches && ![matches evaluateWithObject:app]) continue;
        if ([app[@"isSystemApp"] boolValue]) [systems addObject:app];
        else [users addObject:app];
    }
    self.userApps = users;
    self.systemApps = systems;
}

- (NSArray *)appsForSection:(NSInteger)section {
    return section == 0 ? (self.userApps ?: @[]) : (self.systemApps ?: @[]);
}

- (void)calculateSizesInBackground {
    if (self.isCalculatingSizes || self.allApps.count == 0) return;
    self.isCalculatingSizes = YES;
    NSArray *snapshot = [self.allApps copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSMutableArray *updated = [NSMutableArray arrayWithCapacity:snapshot.count];
        unsigned long long total = 0;
        for (NSDictionary *app in snapshot) {
            NSString *bundleID = app[@"bundleID"];
            unsigned long long size = [self.manager dataSizeForBundleID:bundleID];
            NSMutableDictionary *copy = [app mutableCopy];
            copy[@"size"] = @(size);
            copy[@"sizeString"] = [self.manager formatBytes:size];
            [updated addObject:copy];
            total += size;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allApps = updated;
            [self rebuildSectionsForSearchText:self.searchController.searchBar.text];
            self.statsView.sizeValueLabel.text = [self.manager formatBytes:total];
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
    BOOL system = section == 1;
    header.titleLabel.text = system ? @"تطبيقات النظام" : @"تطبيقات المستخدم";
    header.subtitleLabel.text = system ? @"SYSTEM APPS  /  READ ONLY" : @"USER APPS  /  DATA MANAGEMENT";
    header.countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)apps.count];
    header.marker.backgroundColor = system ? ADMBlue() : ADMGreen();
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 60; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"AppCell";
    AppListCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) cell = [[AppListCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];

    NSDictionary *app = [self appsForSection:indexPath.section][indexPath.row];
    cell.nameLabel.text = app[@"name"];
    cell.bundleLabel.text = app[@"bundleID"];
    cell.sizeLabel.text = app[@"sizeString"] ?: @"جارٍ الحساب";
    cell.accentRail.backgroundColor = indexPath.section == 0 ? ADMGreen() : ADMBlue();

    UIImage *icon = [self.manager iconForBundleID:app[@"bundleID"]];
    if (icon) {
        cell.appIcon.image = icon;
        cell.appIcon.tintColor = nil;
    } else {
        cell.appIcon.image = [UIImage systemImageNamed:@"app.fill"];
        cell.appIcon.tintColor = indexPath.section == 0 ? ADMGreen() : ADMBlue();
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.alpha = 0.0;
    cell.transform = CGAffineTransformMakeTranslation(0, 7);
    [UIView animateWithDuration:0.24 delay:MIN(indexPath.row * 0.025, 0.15) options:UIViewAnimationOptionCurveEaseOut animations:^{
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

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self rebuildSectionsForSearchText:searchController.searchBar.text];
    [self.tableView reloadData];
}

@end
