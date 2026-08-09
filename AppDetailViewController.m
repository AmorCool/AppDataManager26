#import "AppDetailViewController.h"
#import "AppDataManager.h"

#pragma mark - Storage Ring View

@interface StorageRingView : UIView
@property (nonatomic, assign) CGFloat documentsRatio;
@property (nonatomic, assign) CGFloat libraryRatio;
@property (nonatomic, assign) CGFloat cachesRatio;
@property (nonatomic, strong) UILabel *centerLabel;
@end

@implementation StorageRingView

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
            [_centerLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_centerLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:8]
        ]];
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];

    CGFloat lineWidth = 12.0;
    CGFloat radius = (MIN(rect.size.width, rect.size.height) - lineWidth) / 2.0;
    CGPoint center = CGPointMake(rect.size.width / 2.0, rect.size.height / 2.0);

    // Background track
    UIBezierPath *bgPath = [UIBezierPath bezierPathWithArcCenter:center
                                                          radius:radius
                                                      startAngle:-M_PI_2
                                                        endAngle:3 * M_PI_2
                                                       clockwise:YES];
    [[UIColor colorWithWhite:0.12 alpha:1.0] setStroke];
    bgPath.lineWidth = lineWidth;
    bgPath.lineCapStyle = kCGLineCapRound;
    [bgPath stroke];

    // Segments
    NSArray<UIColor *> *colors = @[
        [UIColor colorWithRed:0.78 green:0.58 blue:0.42 alpha:1.0],  // Documents - bronze
        [UIColor colorWithRed:0.55 green:0.45 blue:0.85 alpha:1.0],  // Library - purple
        [UIColor colorWithRed:0.95 green:0.5  blue:0.3  alpha:1.0]   // Caches - orange
    ];
    NSArray<NSNumber *> *ratios = @[@(self.documentsRatio), @(self.libraryRatio), @(self.cachesRatio)];

    CGFloat startAngle = -M_PI_2;
    for (NSUInteger i = 0; i < 3; i++) {
        CGFloat ratio = [ratios[i] floatValue];
        if (ratio <= 0) continue;
        CGFloat endAngle = startAngle + (2 * M_PI * ratio);

        UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center
                                                            radius:radius
                                                        startAngle:startAngle
                                                          endAngle:endAngle
                                                         clockwise:YES];
        [colors[i] setStroke];
        path.lineWidth = lineWidth;
        path.lineCapStyle = kCGLineCapRound;
        [path stroke];

        startAngle = endAngle;
    }
}

- (void)setSizeText:(NSString *)sizeText unit:(NSString *)unit {
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] init];
    [attr appendAttributedString:[[NSAttributedString alloc] initWithString:sizeText attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:22 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: [UIColor whiteColor]
    }]];
    [attr appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\n%@", unit] attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightMedium],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:0.5 alpha:1.0]
    }]];
    self.centerLabel.attributedText = attr;
}

@end

#pragma mark - Section Header

@interface SectionHeaderView : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation SectionHeaderView

- (instancetype)initWithTitle:(NSString *)title {
    self = [super init];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = title;
        _titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _titleLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
        _titleLabel.textAlignment = NSTextAlignmentNatural;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.heightAnchor constraintEqualToConstant:20]
        ]];
    }
    return self;
}

@end

#pragma mark - Info Row (compact)

@interface CompactRowView : UIView
- (instancetype)initWithIcon:(NSString *)iconName title:(NSString *)title value:(NSString *)value;
@end

@implementation CompactRowView {
    UILabel *_titleLabel;
    UILabel *_valueLabel;
}

- (instancetype)initWithIcon:(NSString *)iconName title:(NSString *)title value:(NSString *)value {
    self = [super init];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [UIColor clearColor];

        UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
        iconView.tintColor = [UIColor colorWithWhite:0.4 alpha:1.0];
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = title;
        _titleLabel.font = [UIFont systemFontOfSize:13];
        _titleLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.text = value;
        _valueLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _valueLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.numberOfLines = 1;
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_valueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [iconView.widthAnchor constraintEqualToConstant:18],
            [iconView.heightAnchor constraintEqualToConstant:18],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:10],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_valueLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:12],

            [self.heightAnchor constraintEqualToConstant:36]
        ]];
    }
    return self;
}

@end

#pragma mark - Breakdown Row

@interface BreakdownRowView : UIView
- (instancetype)initWithColor:(UIColor *)color title:(NSString *)title size:(NSString *)size percent:(NSString *)percent;
@end

@implementation BreakdownRowView

- (instancetype)initWithColor:(UIColor *)color title:(NSString *)title size:(NSString *)size percent:(NSString *)percent {
    self = [super init];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        UIView *dot = [[UIView alloc] init];
        dot.backgroundColor = color;
        dot.layer.cornerRadius = 4;
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:dot];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = title;
        titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        titleLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:titleLabel];

        UILabel *sizeLabel = [[UILabel alloc] init];
        sizeLabel.text = size;
        sizeLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        sizeLabel.textColor = [UIColor whiteColor];
        sizeLabel.textAlignment = NSTextAlignmentRight;
        sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:sizeLabel];

        UILabel *pctLabel = [[UILabel alloc] init];
        pctLabel.text = percent;
        pctLabel.font = [UIFont systemFontOfSize:11];
        pctLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
        pctLabel.textAlignment = NSTextAlignmentRight;
        pctLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:pctLabel];

        [NSLayoutConstraint activateConstraints:@[
            [dot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [dot.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [dot.widthAnchor constraintEqualToConstant:8],
            [dot.heightAnchor constraintEqualToConstant:8],

            [titleLabel.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:8],
            [titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [pctLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [pctLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [pctLabel.widthAnchor constraintEqualToConstant:40],

            [sizeLabel.trailingAnchor constraintEqualToAnchor:pctLabel.leadingAnchor constant:-8],
            [sizeLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [self.heightAnchor constraintEqualToConstant:30]
        ]];
    }
    return self;
}

@end

#pragma mark - AppDetailViewController

@interface AppDetailViewController ()
@property (nonatomic, strong) NSDictionary *appInfo;
@property (nonatomic, strong) AppDataManager *manager;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

// Header
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *developerLabel;
@property (nonatomic, strong) UILabel *metaLabel;

// Data Dashboard
@property (nonatomic, strong) UIView *dataCard;
@property (nonatomic, strong) StorageRingView *ringView;
@property (nonatomic, strong) UILabel *dataSizeLabel;
@property (nonatomic, strong) UILabel *dataUnitLabel;
@property (nonatomic, strong) BreakdownRowView *docsRow;
@property (nonatomic, strong) BreakdownRowView *libRow;
@property (nonatomic, strong) BreakdownRowView *cacheRow;

// Backup
@property (nonatomic, strong) UIView *backupCard;
@property (nonatomic, strong) UILabel *backupStatusLabel;
@property (nonatomic, strong) UILabel *backupSubLabel;
@property (nonatomic, strong) UIButton *backupActionBtn;

// Actions
@property (nonatomic, strong) UIView *actionsCard;
@property (nonatomic, strong) UIButton *wipeBtn;

// Technical Details (collapsible)
@property (nonatomic, strong) UIView *techCard;
@property (nonatomic, strong) UIButton *techToggleBtn;
@property (nonatomic, strong) UIView *techContentView;
@property (nonatomic, assign) BOOL techExpanded;
@property (nonatomic, strong) NSLayoutConstraint *techContentHeightConstraint;
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
    self.view.backgroundColor = [UIColor colorWithRed:0.03 green:0.03 blue:0.05 alpha:1.0];

    [self setupNavigation];
    [self setupScrollView];
    [self setupHeader];
    [self setupDataDashboard];
    [self setupBackupSection];
    [self setupActionsSection];
    [self setupTechnicalSection];
    [self loadData];
}

#pragma mark - Setup

- (void)setupNavigation {
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                               style:UIBarButtonItemStylePlain
                                                                              target:self
                                                                              action:@selector(closeTapped)];
}

- (void)closeTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)setupScrollView {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.alwaysBounceVertical = YES;
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

#pragma mark - Header

- (void)setupHeader {
    NSString *bundleID = self.appInfo[@"bundleID"];

    self.iconView = [[UIImageView alloc] init];
    self.iconView.layer.cornerRadius = 16;
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
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.nameLabel];

    self.developerLabel = [[UILabel alloc] init];
    self.developerLabel.text = @""; // Will be set if available
    self.developerLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.developerLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    self.developerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.developerLabel];

    self.metaLabel = [[UILabel alloc] init];
    NSString *ver = [self.manager versionForBundleID:bundleID];
    self.metaLabel.text = [NSString stringWithFormat:@"v%@  ·  %@", ver, bundleID];
    self.metaLabel.font = [UIFont systemFontOfSize:11];
    self.metaLabel.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    self.metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.metaLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [self.iconView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.iconView.widthAnchor constraintEqualToConstant:64],
        [self.iconView.heightAnchor constraintEqualToConstant:64],

        [self.nameLabel.topAnchor constraintEqualToAnchor:self.iconView.topAnchor constant:4],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:14],
        [self.nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [self.developerLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2],
        [self.developerLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.developerLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],

        [self.metaLabel.topAnchor constraintEqualToAnchor:self.developerLabel.bottomAnchor constant:4],
        [self.metaLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.metaLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor]
    ]];
}

#pragma mark - Data Dashboard Card

- (void)setupDataDashboard {
    self.dataCard = [self createCard];
    [self.contentView addSubview:self.dataCard];

    // Section title
    UILabel *sectionTitle = [[UILabel alloc] init];
    sectionTitle.text = @"APP DATA";
    sectionTitle.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    sectionTitle.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    sectionTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dataCard addSubview:sectionTitle];

    // Size number
    self.dataSizeLabel = [[UILabel alloc] init];
    self.dataSizeLabel.text = @"—";
    self.dataSizeLabel.font = [UIFont systemFontOfSize:36 weight:UIFontWeightBold];
    self.dataSizeLabel.textColor = [UIColor whiteColor];
    self.dataSizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dataCard addSubview:self.dataSizeLabel];

    self.dataUnitLabel = [[UILabel alloc] init];
    self.dataUnitLabel.text = @"";
    self.dataUnitLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.dataUnitLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    self.dataUnitLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dataCard addSubview:self.dataUnitLabel];

    // Ring
    self.ringView = [[StorageRingView alloc] initWithFrame:CGRectZero];
    self.ringView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dataCard addSubview:self.ringView];

    // Divider
    UIView *divider = [[UIView alloc] init];
    divider.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dataCard addSubview:divider];

    // Breakdown rows
    self.docsRow = [[BreakdownRowView alloc] initWithColor:[UIColor colorWithRed:0.78 green:0.58 blue:0.42 alpha:1.0]
                                                     title:@"Documents"
                                                      size:@"—"
                                                   percent:@"—"];
    [self.dataCard addSubview:self.docsRow];

    self.libRow = [[BreakdownRowView alloc] initWithColor:[UIColor colorWithRed:0.55 green:0.45 blue:0.85 alpha:1.0]
                                                    title:@"Library"
                                                     size:@"—"
                                                  percent:@"—"];
    [self.dataCard addSubview:self.libRow];

    self.cacheRow = [[BreakdownRowView alloc] initWithColor:[UIColor colorWithRed:0.95 green:0.5 blue:0.3 alpha:1.0]
                                                      title:@"Caches"
                                                       size:@"—"
                                                    percent:@"—"];
    [self.dataCard addSubview:self.cacheRow];

    [NSLayoutConstraint activateConstraints:@[
        [self.dataCard.topAnchor constraintEqualToAnchor:self.metaLabel.bottomAnchor constant:24],
        [self.dataCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.dataCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

        [sectionTitle.topAnchor constraintEqualToAnchor:self.dataCard.topAnchor constant:20],
        [sectionTitle.leadingAnchor constraintEqualToAnchor:self.dataCard.leadingAnchor constant:20],

        [self.dataSizeLabel.topAnchor constraintEqualToAnchor:sectionTitle.bottomAnchor constant:8],
        [self.dataSizeLabel.leadingAnchor constraintEqualToAnchor:sectionTitle.leadingAnchor],

        [self.dataUnitLabel.leadingAnchor constraintEqualToAnchor:self.dataSizeLabel.trailingAnchor constant:6],
        [self.dataUnitLabel.bottomAnchor constraintEqualToAnchor:self.dataSizeLabel.bottomAnchor constant:-6],

        [self.ringView.centerYAnchor constraintEqualToAnchor:self.dataSizeLabel.centerYAnchor constant:10],
        [self.ringView.trailingAnchor constraintEqualToAnchor:self.dataCard.trailingAnchor constant:-20],
        [self.ringView.widthAnchor constraintEqualToConstant:100],
        [self.ringView.heightAnchor constraintEqualToConstant:100],

        [divider.topAnchor constraintEqualToAnchor:self.dataSizeLabel.bottomAnchor constant:20],
        [divider.leadingAnchor constraintEqualToAnchor:self.dataCard.leadingAnchor constant:20],
        [divider.trailingAnchor constraintEqualToAnchor:self.dataCard.trailingAnchor constant:-20],
        [divider.heightAnchor constraintEqualToConstant:1],

        [self.docsRow.topAnchor constraintEqualToAnchor:divider.bottomAnchor constant:12],
        [self.docsRow.leadingAnchor constraintEqualToAnchor:self.dataCard.leadingAnchor constant:20],
        [self.docsRow.trailingAnchor constraintEqualToAnchor:self.dataCard.trailingAnchor constant:-20],

        [self.libRow.topAnchor constraintEqualToAnchor:self.docsRow.bottomAnchor constant:2],
        [self.libRow.leadingAnchor constraintEqualToAnchor:self.docsRow.leadingAnchor],
        [self.libRow.trailingAnchor constraintEqualToAnchor:self.docsRow.trailingAnchor],

        [self.cacheRow.topAnchor constraintEqualToAnchor:self.libRow.bottomAnchor constant:2],
        [self.cacheRow.leadingAnchor constraintEqualToAnchor:self.docsRow.leadingAnchor],
        [self.cacheRow.trailingAnchor constraintEqualToAnchor:self.docsRow.trailingAnchor],
        [self.cacheRow.bottomAnchor constraintEqualToAnchor:self.dataCard.bottomAnchor constant:-20]
    ]];
}

#pragma mark - Backup Section

- (void)setupBackupSection {
    self.backupCard = [self createCard];
    [self.contentView addSubview:self.backupCard];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"icloud.and.arrow.up"]];
    iconView.tintColor = [UIColor colorWithRed:0.78 green:0.58 blue:0.42 alpha:1.0];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backupCard addSubview:iconView];

    self.backupStatusLabel = [[UILabel alloc] init];
    self.backupStatusLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.backupStatusLabel.textColor = [UIColor whiteColor];
    self.backupStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backupCard addSubview:self.backupStatusLabel];

    self.backupSubLabel = [[UILabel alloc] init];
    self.backupSubLabel.font = [UIFont systemFontOfSize:12];
    self.backupSubLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    self.backupSubLabel.numberOfLines = 2;
    self.backupSubLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backupCard addSubview:self.backupSubLabel];

    self.backupActionBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.backupActionBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.backupActionBtn.backgroundColor = [UIColor colorWithRed:0.78 green:0.58 blue:0.42 alpha:0.15];
    self.backupActionBtn.layer.cornerRadius = 8;
    self.backupActionBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self.backupActionBtn setTitleColor:[UIColor colorWithRed:0.78 green:0.58 blue:0.42 alpha:1.0] forState:UIControlStateNormal];
    [self.backupActionBtn addTarget:self action:@selector(backupTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.backupCard addSubview:self.backupActionBtn];

    [NSLayoutConstraint activateConstraints:@[
        [self.backupCard.topAnchor constraintEqualToAnchor:self.dataCard.bottomAnchor constant:12],
        [self.backupCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.backupCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

        [iconView.leadingAnchor constraintEqualToAnchor:self.backupCard.leadingAnchor constant:20],
        [iconView.topAnchor constraintEqualToAnchor:self.backupCard.topAnchor constant:18],
        [iconView.widthAnchor constraintEqualToConstant:28],
        [iconView.heightAnchor constraintEqualToConstant:28],

        [self.backupStatusLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:12],
        [self.backupStatusLabel.topAnchor constraintEqualToAnchor:iconView.topAnchor constant:2],
        [self.backupStatusLabel.trailingAnchor constraintEqualToAnchor:self.backupCard.trailingAnchor constant:-20],

        [self.backupSubLabel.leadingAnchor constraintEqualToAnchor:self.backupStatusLabel.leadingAnchor],
        [self.backupSubLabel.topAnchor constraintEqualToAnchor:self.backupStatusLabel.bottomAnchor constant:2],
        [self.backupSubLabel.trailingAnchor constraintEqualToAnchor:self.backupStatusLabel.trailingAnchor],

        [self.backupActionBtn.topAnchor constraintEqualToAnchor:self.backupSubLabel.bottomAnchor constant:12],
        [self.backupActionBtn.leadingAnchor constraintEqualToAnchor:self.backupStatusLabel.leadingAnchor],
        [self.backupActionBtn.widthAnchor constraintEqualToConstant:110],
        [self.backupActionBtn.heightAnchor constraintEqualToConstant:34],
        [self.backupActionBtn.bottomAnchor constraintEqualToAnchor:self.backupCard.bottomAnchor constant:-16]
    ]];
}

#pragma mark - Actions Section

- (void)setupActionsSection {
    self.actionsCard = [self createCard];
    [self.contentView addSubview:self.actionsCard];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"trash"]];
    iconView.tintColor = [UIColor colorWithRed:0.9 green:0.35 blue:0.35 alpha:1.0];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionsCard addSubview:iconView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Delete App Data";
    titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionsCard addSubview:titleLabel];

    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.text = @"All app data will be permanently removed.";
    descLabel.font = [UIFont systemFontOfSize:12];
    descLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    descLabel.numberOfLines = 2;
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionsCard addSubview:descLabel];

    self.wipeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.wipeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.wipeBtn.backgroundColor = [UIColor colorWithRed:0.9 green:0.25 blue:0.25 alpha:0.12];
    self.wipeBtn.layer.cornerRadius = 8;
    self.wipeBtn.layer.borderColor = [UIColor colorWithRed:0.9 green:0.35 blue:0.35 alpha:0.3].CGColor;
    self.wipeBtn.layer.borderWidth = 1;
    self.wipeBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self.wipeBtn setTitle:@"Delete Data" forState:UIControlStateNormal];
    [self.wipeBtn setTitleColor:[UIColor colorWithRed:0.9 green:0.35 blue:0.35 alpha:1.0] forState:UIControlStateNormal];
    [self.wipeBtn addTarget:self action:@selector(wipeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.actionsCard addSubview:self.wipeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [self.actionsCard.topAnchor constraintEqualToAnchor:self.backupCard.bottomAnchor constant:12],
        [self.actionsCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.actionsCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

        [iconView.leadingAnchor constraintEqualToAnchor:self.actionsCard.leadingAnchor constant:20],
        [iconView.topAnchor constraintEqualToAnchor:self.actionsCard.topAnchor constant:18],
        [iconView.widthAnchor constraintEqualToConstant:28],
        [iconView.heightAnchor constraintEqualToConstant:28],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:12],
        [titleLabel.topAnchor constraintEqualToAnchor:iconView.topAnchor constant:2],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.actionsCard.trailingAnchor constant:-20],

        [descLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [descLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2],
        [descLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [self.wipeBtn.topAnchor constraintEqualToAnchor:descLabel.bottomAnchor constant:12],
        [self.wipeBtn.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.wipeBtn.widthAnchor constraintEqualToConstant:110],
        [self.wipeBtn.heightAnchor constraintEqualToConstant:34],
        [self.wipeBtn.bottomAnchor constraintEqualToAnchor:self.actionsCard.bottomAnchor constant:-16]
    ]];
}

#pragma mark - Technical Section (Collapsible)

- (void)setupTechnicalSection {
    self.techCard = [self createCard];
    [self.contentView addSubview:self.techCard];

    self.techToggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.techToggleBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.techToggleBtn.backgroundColor = [UIColor clearColor];
    [self.techToggleBtn addTarget:self action:@selector(toggleTech) forControlEvents:UIControlEventTouchUpInside];
    [self.techCard addSubview:self.techToggleBtn];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Application Details";
    titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.techToggleBtn addSubview:titleLabel];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]];
    chevron.tintColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tag = 100;
    [self.techToggleBtn addSubview:chevron];

    self.techContentView = [[UIView alloc] init];
    self.techContentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.techContentView.clipsToBounds = YES;
    [self.techCard addSubview:self.techContentView];

    NSString *bundleID = self.appInfo[@"bundleID"];
    NSString *dataPath = [self.manager dataPathForBundleID:bundleID];
    NSString *ver = [self.manager versionForBundleID:bundleID];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.techContentView addSubview:stack];

    [stack addArrangedSubview:[[CompactRowView alloc] initWithIcon:@"number" title:@"Bundle ID" value:bundleID]];
    [stack addArrangedSubview:[[CompactRowView alloc] initWithIcon:@"tag" title:@"Version" value:ver]];
    [stack addArrangedSubview:[[CompactRowView alloc] initWithIcon:@"folder" title:@"Data Path" value:dataPath ?: @"—"]];
    [stack addArrangedSubview:[[CompactRowView alloc] initWithIcon:@"doc" title:@"Documents" value:[NSString stringWithFormat:@"%lu files", (unsigned long)[self.manager documentsCountForBundleID:bundleID]]]];

    self.techExpanded = NO;
    self.techContentHeightConstraint = [self.techContentView.heightAnchor constraintEqualToConstant:0];
    self.techContentHeightConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [self.techCard.topAnchor constraintEqualToAnchor:self.actionsCard.bottomAnchor constant:12],
        [self.techCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.techCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.techCard.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-30],

        [self.techToggleBtn.topAnchor constraintEqualToAnchor:self.techCard.topAnchor],
        [self.techToggleBtn.leadingAnchor constraintEqualToAnchor:self.techCard.leadingAnchor],
        [self.techToggleBtn.trailingAnchor constraintEqualToAnchor:self.techCard.trailingAnchor],
        [self.techToggleBtn.heightAnchor constraintEqualToConstant:48],

        [titleLabel.leadingAnchor constraintEqualToAnchor:self.techToggleBtn.leadingAnchor constant:20],
        [titleLabel.centerYAnchor constraintEqualToAnchor:self.techToggleBtn.centerYAnchor],

        [chevron.trailingAnchor constraintEqualToAnchor:self.techToggleBtn.trailingAnchor constant:-20],
        [chevron.centerYAnchor constraintEqualToAnchor:self.techToggleBtn.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:14],
        [chevron.heightAnchor constraintEqualToConstant:14],

        [self.techContentView.topAnchor constraintEqualToAnchor:self.techToggleBtn.bottomAnchor],
        [self.techContentView.leadingAnchor constraintEqualToAnchor:self.techCard.leadingAnchor constant:20],
        [self.techContentView.trailingAnchor constraintEqualToAnchor:self.techCard.trailingAnchor constant:-20],
        [self.techContentView.bottomAnchor constraintEqualToAnchor:self.techCard.bottomAnchor constant:-8],

        [stack.topAnchor constraintEqualToAnchor:self.techContentView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.techContentView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.techContentView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.techContentView.bottomAnchor]
    ]];
}

- (void)toggleTech {
    self.techExpanded = !self.techExpanded;

    UIImageView *chevron = [self.techToggleBtn viewWithTag:100];
    [UIView animateWithDuration:0.25 animations:^{
        chevron.transform = self.techExpanded ? CGAffineTransformMakeRotation(M_PI) : CGAffineTransformIdentity;
    }];

    self.techContentHeightConstraint.active = NO;
    if (self.techExpanded) {
        self.techContentHeightConstraint = [self.techContentView.heightAnchor constraintGreaterThanOrEqualToConstant:144];
    } else {
        self.techContentHeightConstraint = [self.techContentView.heightAnchor constraintEqualToConstant:0];
    }
    self.techContentHeightConstraint.active = YES;

    [UIView animateWithDuration:0.3 animations:^{
        [self.view layoutIfNeeded];
    }];
}

#pragma mark - Data Loading

- (void)loadData {
    NSString *bundleID = self.appInfo[@"bundleID"];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        unsigned long long total = [self.manager dataSizeForBundleID:bundleID];
        NSString *totalStr = [self.manager formatBytes:total];

        // Parse size and unit
        NSArray *parts = [totalStr componentsSeparatedByString:@" "];
        NSString *sizeNum = parts.count > 0 ? parts[0] : totalStr;
        NSString *unit = parts.count > 1 ? parts[1] : @"";

        // Calculate breakdown
        NSString *dataPath = [self.manager dataPathForBundleID:bundleID];
        unsigned long long docs = 0, lib = 0, cache = 0;
        if (dataPath) {
            docs = [self dirSize:[dataPath stringByAppendingPathComponent:@"Documents"]];
            lib = [self dirSize:[dataPath stringByAppendingPathComponent:@"Library"]];
            cache = [self dirSize:[[dataPath stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"Caches"]];
        }

        CGFloat docP = total > 0 ? (CGFloat)docs / (CGFloat)total : 0;
        CGFloat libP = total > 0 ? (CGFloat)lib / (CGFloat)total : 0;
        CGFloat cacheP = total > 0 ? (CGFloat)cache / (CGFloat)total : 0;

        // Backup
        NSDate *lastBackup = [self.manager lastBackupDateForBundleID:bundleID];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.dataSizeLabel.text = sizeNum;
            self.dataUnitLabel.text = unit;
            [self.ringView setSizeText:sizeNum unit:unit];
            self.ringView.documentsRatio = docP;
            self.ringView.libraryRatio = libP;
            self.ringView.cachesRatio = cacheP;
            [self.ringView setNeedsDisplay];

            [self updateRow:self.docsRow size:docs percent:docP total:total];
            [self updateRow:self.libRow size:lib percent:libP total:total];
            [self updateRow:self.cacheRow size:cache percent:cacheP total:total];

            [self updateBackupUI:lastBackup];
        });
    });
}

- (void)updateRow:(BreakdownRowView *)row size:(unsigned long long)size percent:(CGFloat)pct total:(unsigned long long)total {
    NSString *sizeStr = [self.manager formatBytes:size];
    NSString *pctStr = total > 0 ? [NSString stringWithFormat:@"%.0f%%", pct * 100] : @"0%";

    // Remove old subviews and recreate
    for (UIView *sv in row.subviews) [sv removeFromSuperview];

    UIColor *color;
    if (row == self.docsRow) color = [UIColor colorWithRed:0.78 green:0.58 blue:0.42 alpha:1.0];
    else if (row == self.libRow) color = [UIColor colorWithRed:0.55 green:0.45 blue:0.85 alpha:1.0];
    else color = [UIColor colorWithRed:0.95 green:0.5 blue:0.3 alpha:1.0];

    UIView *dot = [[UIView alloc] init];
    dot.backgroundColor = color;
    dot.layer.cornerRadius = 4;
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:dot];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = row == self.docsRow ? @"Documents" : (row == self.libRow ? @"Library" : @"Caches");
    titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    titleLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:titleLabel];

    UILabel *sizeLabel = [[UILabel alloc] init];
    sizeLabel.text = sizeStr;
    sizeLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    sizeLabel.textColor = [UIColor whiteColor];
    sizeLabel.textAlignment = NSTextAlignmentRight;
    sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:sizeLabel];

    UILabel *pctLabel = [[UILabel alloc] init];
    pctLabel.text = pctStr;
    pctLabel.font = [UIFont systemFontOfSize:11];
    pctLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    pctLabel.textAlignment = NSTextAlignmentRight;
    pctLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:pctLabel];

    [NSLayoutConstraint activateConstraints:@[
        [dot.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [dot.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [dot.widthAnchor constraintEqualToConstant:8],
        [dot.heightAnchor constraintEqualToConstant:8],

        [titleLabel.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:8],
        [titleLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [pctLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [pctLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [pctLabel.widthAnchor constraintEqualToConstant:40],

        [sizeLabel.trailingAnchor constraintEqualToAnchor:pctLabel.leadingAnchor constant:-8],
        [sizeLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
    ]];
}

- (void)updateBackupUI:(NSDate *)lastBackup {
    if (lastBackup) {
        self.backupStatusLabel.text = @"Backup Available";
        self.backupStatusLabel.textColor = [UIColor colorWithRed:0.3 green:0.8 blue:0.5 alpha:1.0];

        NSDateComponents *comp = [[NSCalendar currentCalendar] components:NSCalendarUnitDay fromDate:lastBackup toDate:[NSDate date] options:0];
        NSInteger days = comp.day;
        if (days == 0) self.backupSubLabel.text = @"Last backup: Today";
        else if (days == 1) self.backupSubLabel.text = @"Last backup: Yesterday";
        else self.backupSubLabel.text = [NSString stringWithFormat:@"Last backup: %ld days ago", (long)days];

        [self.backupActionBtn setTitle:@"Restore" forState:UIControlStateNormal];
    } else {
        self.backupStatusLabel.text = @"No Backup Available";
        self.backupStatusLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        self.backupSubLabel.text = @"Create a backup before deleting app data.";
        [self.backupActionBtn setTitle:@"Backup" forState:UIControlStateNormal];
    }
}

- (unsigned long long)dirSize:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return 0;
    unsigned long long total = 0;
    NSArray *items = [fm subpathsAtPath:path];
    for (NSString *item in items) {
        @try {
            NSDictionary *attrs = [fm attributesOfItemAtPath:[path stringByAppendingPathComponent:item] error:nil];
            if (attrs) total += [attrs fileSize];
        } @catch (NSException *e) { continue; }
    }
    return total;
}

#pragma mark - Actions

- (void)backupTapped {
    NSString *bundleID = self.appInfo[@"bundleID"];
    NSDate *lastBackup = [self.manager lastBackupDateForBundleID:bundleID];

    if (lastBackup) {
        // Restore
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restore Backup"
                                                                       message:@"This will replace current app data with the backup."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSArray *backups = [self.manager availableBackupsForBundleID:bundleID];
            if (backups.count > 0) {
                BOOL ok = [self.manager restoreAppData:bundleID fromBackup:backups[0]];
                [self showToast:ok ? @"Restored successfully ✅" : @"Restore failed ❌"];
                if (ok) [self loadData];
            }
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        // Create backup
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Backup %@?", self.appInfo[@"name"]]
                                                                       message:@"A full backup of app data will be created."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Backup" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                BOOL ok = [self.manager backupAppData:bundleID];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showToast:ok ? @"Backup created ✅" : @"Backup failed ❌"];
                    if (ok) [self loadData];
                });
            });
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)wipeTapped {
    NSString *bundleID = self.appInfo[@"bundleID"];
    NSString *appName = self.appInfo[@"name"];

    if ([self.manager isSystemApp:bundleID]) {
        [self showToast:@"System apps cannot be wiped ⛔"];
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        unsigned long long docs = [self dirSize:[[self.manager dataPathForBundleID:bundleID] stringByAppendingPathComponent:@"Documents"]];
        unsigned long long lib = [self dirSize:[[self.manager dataPathForBundleID:bundleID] stringByAppendingPathComponent:@"Library"]];
        unsigned long long cache = [self dirSize:[[[self.manager dataPathForBundleID:bundleID] stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"Caches"]];
        unsigned long long total = docs + lib + cache;

        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *msg = [NSString stringWithFormat:@"This will permanently remove all data for %@:\n\nDocuments    %@\nLibrary      %@\nCaches       %@\n\nTotal: %@",
                             appName,
                             [self.manager formatBytes:docs],
                             [self.manager formatBytes:lib],
                             [self.manager formatBytes:cache],
                             [self.manager formatBytes:total]];

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete App Data"
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Delete Data" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    BOOL ok = [self.manager wipeAppData:bundleID];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self showToast:ok ? @"Data deleted ✅" : @"Delete failed ❌"];
                        if (ok) [self loadData];
                    });
                });
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    });
}

#pragma mark - Helpers

- (UIView *)createCard {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.10 alpha:1.0];
    card.layer.cornerRadius = 16;
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    return card;
}

- (void)showToast:(NSString *)message {
    UILabel *toast = [[UILabel alloc] init];
    toast.text = message;
    toast.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.2 alpha:0.95];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 10;
    toast.layer.masksToBounds = YES;
    toast.alpha = 0;
    toast.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:toast];
    [NSLayoutConstraint activateConstraints:@[
        [toast.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [toast.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-24],
        [toast.heightAnchor constraintEqualToConstant:38],
        [toast.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40]
    ]];

    [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 1.0; } completion:^(BOOL f) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 0; } completion:^(BOOL f2) { [toast removeFromSuperview]; }];
        });
    }];
}

@end
