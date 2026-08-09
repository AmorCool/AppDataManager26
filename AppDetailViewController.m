#import "AppDetailViewController.h"
#import "AppDataManager.h"

// MARK: - Color Palette (هادئة ومهنية)
#define C_BG        [UIColor colorWithRed:0.039 green:0.039 blue:0.047 alpha:1.0]   // #0A0A0C
#define C_CARD      [UIColor colorWithRed:0.078 green:0.078 blue:0.086 alpha:1.0]   // #141416
#define C_ACCENT    [UIColor colorWithRed:0.769 green:0.655 blue:0.490 alpha:1.0]   // #C4A77D
#define C_DANGER    [UIColor colorWithRed:0.478 green:0.180 blue:0.180 alpha:1.0]   // #7A2E2E
#define C_TEXT_PRI  [UIColor whiteColor]
#define C_TEXT_SEC  [UIColor colorWithRed:0.549 green:0.549 blue:0.549 alpha:1.0]   // #8C8C8C
#define C_TEXT_TER  [UIColor colorWithRed:0.333 green:0.333 blue:0.333 alpha:1.0]   // #555555
#define C_DOC       [UIColor colorWithRed:0.420 green:0.557 blue:0.420 alpha:1.0]   // #6B8E6B
#define C_LIB       [UIColor colorWithRed:0.490 green:0.490 blue:0.702 alpha:1.0]   // #7D7DB3
#define C_CACHE     [UIColor colorWithRed:0.702 green:0.545 blue:0.420 alpha:1.0]   // #B38B6B

// MARK: - Storage Ring (دائرة التخزين)
@interface StorageRingView : UIView
@property (nonatomic, assign) CGFloat docRatio;
@property (nonatomic, assign) CGFloat libRatio;
@property (nonatomic, assign) CGFloat cacheRatio;
@end

@implementation StorageRingView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    CGFloat lw = 10.0;
    CGFloat r = (MIN(rect.size.width, rect.size.height) - lw) / 2.0;
    CGPoint c = CGPointMake(rect.size.width / 2.0, rect.size.height / 2.0);

    // Track
    UIBezierPath *bg = [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:-M_PI_2 endAngle:3*M_PI_2 clockwise:YES];
    [[UIColor colorWithWhite:0.10 alpha:1.0] setStroke];
    bg.lineWidth = lw; bg.lineCapStyle = kCGLineCapRound; [bg stroke];

    NSArray *colors = @[C_DOC, C_LIB, C_CACHE];
    NSArray *ratios = @[@(self.docRatio), @(self.libRatio), @(self.cacheRatio)];
    CGFloat start = -M_PI_2;
    for (NSUInteger i = 0; i < 3; i++) {
        CGFloat ratio = [ratios[i] floatValue];
        if (ratio <= 0.005) continue;
        CGFloat end = start + (2 * M_PI * ratio);
        UIBezierPath *p = [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:start endAngle:end clockwise:YES];
        [colors[i] setStroke]; p.lineWidth = lw; p.lineCapStyle = kCGLineCapRound; [p stroke];
        start = end;
    }
}

@end

// MARK: - Info Row (صف معلومات)
@interface InfoRow : UIView
- (instancetype)initWithIcon:(NSString *)icon title:(NSString *)title value:(NSString *)value;
@end

@implementation InfoRow

- (instancetype)initWithIcon:(NSString *)icon title:(NSString *)title value:(NSString *)value {
    self = [super init];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [UIColor clearColor];

        UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];
        iv.tintColor = C_TEXT_TER;
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:iv];

        UILabel *tl = [[UILabel alloc] init];
        tl.text = title;
        tl.font = [UIFont systemFontOfSize:12];
        tl.textColor = C_TEXT_SEC;
        tl.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:tl];

        UILabel *vl = [[UILabel alloc] init];
        vl.text = value;
        vl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        vl.textColor = C_TEXT_PRI;
        vl.textAlignment = NSTextAlignmentRight;
        vl.numberOfLines = 1;
        vl.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:vl];

        [NSLayoutConstraint activateConstraints:@[
            [iv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [iv.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [iv.widthAnchor constraintEqualToConstant:16],
            [iv.heightAnchor constraintEqualToConstant:16],
            [tl.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:10],
            [tl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [vl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [vl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [vl.leadingAnchor constraintGreaterThanOrEqualToAnchor:tl.trailingAnchor constant:12],
            [self.heightAnchor constraintEqualToConstant:30]
        ]];
    }
    return self;
}

@end

// MARK: - Dot Row (صف بنقطة ملونة)
@interface DotRow : UIView
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UILabel *pctLabel;
- (instancetype)initWithColor:(UIColor *)color title:(NSString *)title;
@end

@implementation DotRow

- (instancetype)initWithColor:(UIColor *)color title:(NSString *)title {
    self = [super init];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        UIView *dot = [[UIView alloc] init];
        dot.backgroundColor = color;
        dot.layer.cornerRadius = 3.5;
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:dot];

        UILabel *tl = [[UILabel alloc] init];
        tl.text = title;
        tl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        tl.textColor = C_TEXT_SEC;
        tl.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:tl];

        _sizeLabel = [[UILabel alloc] init];
        _sizeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _sizeLabel.textColor = C_TEXT_PRI;
        _sizeLabel.textAlignment = NSTextAlignmentRight;
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_sizeLabel];

        _pctLabel = [[UILabel alloc] init];
        _pctLabel.font = [UIFont systemFontOfSize:11];
        _pctLabel.textColor = C_TEXT_TER;
        _pctLabel.textAlignment = NSTextAlignmentRight;
        _pctLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_pctLabel];

        [NSLayoutConstraint activateConstraints:@[
            [dot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [dot.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [dot.widthAnchor constraintEqualToConstant:7],
            [dot.heightAnchor constraintEqualToConstant:7],
            [tl.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:8],
            [tl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_pctLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_pctLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_pctLabel.widthAnchor constraintEqualToConstant:36],
            [_sizeLabel.trailingAnchor constraintEqualToAnchor:_pctLabel.leadingAnchor constant:-8],
            [_sizeLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.heightAnchor constraintEqualToConstant:26]
        ]];
    }
    return self;
}

@end

// MARK: - AppDetailViewController
@interface AppDetailViewController ()
@property (nonatomic, strong) NSDictionary *appInfo;
@property (nonatomic, strong) AppDataManager *manager;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

// Header
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *metaLabel;

// Data Card
@property (nonatomic, strong) UIView *dataCard;
@property (nonatomic, strong) UILabel *dataTitleLabel;
@property (nonatomic, strong) UILabel *dataSizeLabel;
@property (nonatomic, strong) UILabel *dataUnitLabel;
@property (nonatomic, strong) StorageRingView *ringView;
@property (nonatomic, strong) UIView *divider;
@property (nonatomic, strong) DotRow *docsRow;
@property (nonatomic, strong) DotRow *libRow;
@property (nonatomic, strong) DotRow *cacheRow;

// Backup Card
@property (nonatomic, strong) UIView *backupCard;
@property (nonatomic, strong) UILabel *backupTitle;
@property (nonatomic, strong) UILabel *backupStatus;
@property (nonatomic, strong) UIButton *backupBtn;

// Actions Card
@property (nonatomic, strong) UIView *actionCard;
@property (nonatomic, strong) UIButton *wipeBtn;

// Technical Card
@property (nonatomic, strong) UIView *techCard;
@property (nonatomic, strong) UIButton *techToggle;
@property (nonatomic, strong) UIView *techContent;
@property (nonatomic, assign) BOOL techExpanded;
@property (nonatomic, strong) NSLayoutConstraint *techHeightConstraint;
@end

@implementation AppDetailViewController

- (instancetype)initWithAppInfo:(NSDictionary *)appInfo {
    self = [super init];
    if (self) { _appInfo = appInfo; _manager = [AppDataManager sharedManager]; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"";
    self.view.backgroundColor = C_BG;
    [self setupNav];
    [self setupScroll];
    [self setupHeader];
    [self setupDataCard];
    [self setupBackupCard];
    [self setupActionCard];
    [self setupTechCard];
    [self loadData];
}

- (void)setupNav {
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.navigationController.navigationBar.tintColor = C_TEXT_PRI;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                               style:UIBarButtonItemStylePlain target:self action:@selector(close)];
}

- (void)close { [self.navigationController popViewControllerAnimated:YES]; }

- (void)setupScroll {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
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

- (UIView *)makeCard {
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = C_CARD;
    v.layer.cornerRadius = 12;
    v.layer.masksToBounds = YES;
    v.translatesAutoresizingMaskIntoConstraints = NO;
    return v;
}

#pragma mark - Header

- (void)setupHeader {
    NSString *bid = self.appInfo[@"bundleID"];

    self.iconView = [[UIImageView alloc] init];
    self.iconView.layer.cornerRadius = 14;
    self.iconView.layer.masksToBounds = YES;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *icon = [self.manager iconForBundleID:bid];
    if (icon) self.iconView.image = icon;
    else {
        self.iconView.image = [UIImage systemImageNamed:@"app.fill"];
        self.iconView.tintColor = C_ACCENT;
        self.iconView.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1.0];
    }
    [self.contentView addSubview:self.iconView];

    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.text = self.appInfo[@"name"];
    self.nameLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    self.nameLabel.textColor = C_TEXT_PRI;
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.nameLabel];

    self.metaLabel = [[UILabel alloc] init];
    NSString *ver = [self.manager versionForBundleID:bid];
    self.metaLabel.text = [NSString stringWithFormat:@"الإصدار %@  ·  %@", ver, bid];
    self.metaLabel.font = [UIFont systemFontOfSize:11];
    self.metaLabel.textColor = C_TEXT_TER;
    self.metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.metaLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [self.iconView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.iconView.widthAnchor constraintEqualToConstant:56],
        [self.iconView.heightAnchor constraintEqualToConstant:56],
        [self.nameLabel.topAnchor constraintEqualToAnchor:self.iconView.topAnchor constant:4],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:14],
        [self.nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [self.metaLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:4],
        [self.metaLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.metaLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor]
    ]];
}

#pragma mark - Data Card

- (void)setupDataCard {
    self.dataCard = [self makeCard];
    [self.contentView addSubview:self.dataCard];

    self.dataTitleLabel = [[UILabel alloc] init];
    self.dataTitleLabel.text = @"إجمالي البيانات";
    self.dataTitleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    self.dataTitleLabel.textColor = C_TEXT_TER;
    self.dataTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dataCard addSubview:self.dataTitleLabel];

    self.dataSizeLabel = [[UILabel alloc] init];
    self.dataSizeLabel.text = @"—";
    self.dataSizeLabel.textColor = C_TEXT_PRI;
    self.dataSizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dataCard addSubview:self.dataSizeLabel];

    self.ringView = [[StorageRingView alloc] initWithFrame:CGRectZero];
    self.ringView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dataCard addSubview:self.ringView];

    self.divider = [[UIView alloc] init];
    self.divider.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    self.divider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dataCard addSubview:self.divider];

    self.docsRow = [[DotRow alloc] initWithColor:C_DOC title:@"المستندات"];
    [self.dataCard addSubview:self.docsRow];
    self.libRow = [[DotRow alloc] initWithColor:C_LIB title:@"المكتبة"];
    [self.dataCard addSubview:self.libRow];
    self.cacheRow = [[DotRow alloc] initWithColor:C_CACHE title:@"التخزين المؤقت"];
    [self.dataCard addSubview:self.cacheRow];

    [NSLayoutConstraint activateConstraints:@[
        [self.dataCard.topAnchor constraintEqualToAnchor:self.metaLabel.bottomAnchor constant:24],
        [self.dataCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.dataCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

        [self.dataTitleLabel.topAnchor constraintEqualToAnchor:self.dataCard.topAnchor constant:16],
        [self.dataTitleLabel.leadingAnchor constraintEqualToAnchor:self.dataCard.leadingAnchor constant:18],

        [self.dataSizeLabel.topAnchor constraintEqualToAnchor:self.dataTitleLabel.bottomAnchor constant:4],
        [self.dataSizeLabel.leadingAnchor constraintEqualToAnchor:self.dataTitleLabel.leadingAnchor],

        [self.ringView.centerYAnchor constraintEqualToAnchor:self.dataSizeLabel.centerYAnchor constant:2],
        [self.ringView.trailingAnchor constraintEqualToAnchor:self.dataCard.trailingAnchor constant:-18],
        [self.ringView.widthAnchor constraintEqualToConstant:72],
        [self.ringView.heightAnchor constraintEqualToConstant:72],

        [self.divider.topAnchor constraintEqualToAnchor:self.dataSizeLabel.bottomAnchor constant:18],
        [self.divider.leadingAnchor constraintEqualToAnchor:self.dataCard.leadingAnchor constant:18],
        [self.divider.trailingAnchor constraintEqualToAnchor:self.dataCard.trailingAnchor constant:-18],
        [self.divider.heightAnchor constraintEqualToConstant:1],

        [self.docsRow.topAnchor constraintEqualToAnchor:self.divider.bottomAnchor constant:12],
        [self.docsRow.leadingAnchor constraintEqualToAnchor:self.dataCard.leadingAnchor constant:18],
        [self.docsRow.trailingAnchor constraintEqualToAnchor:self.dataCard.trailingAnchor constant:-18],

        [self.libRow.topAnchor constraintEqualToAnchor:self.docsRow.bottomAnchor constant:2],
        [self.libRow.leadingAnchor constraintEqualToAnchor:self.docsRow.leadingAnchor],
        [self.libRow.trailingAnchor constraintEqualToAnchor:self.docsRow.trailingAnchor],

        [self.cacheRow.topAnchor constraintEqualToAnchor:self.libRow.bottomAnchor constant:2],
        [self.cacheRow.leadingAnchor constraintEqualToAnchor:self.docsRow.leadingAnchor],
        [self.cacheRow.trailingAnchor constraintEqualToAnchor:self.docsRow.trailingAnchor],
        [self.cacheRow.bottomAnchor constraintEqualToAnchor:self.dataCard.bottomAnchor constant:-18]
    ]];
}

#pragma mark - Backup Card

- (void)setupBackupCard {
    self.backupCard = [self makeCard];
    [self.contentView addSubview:self.backupCard];

    self.backupTitle = [[UILabel alloc] init];
    self.backupTitle.text = @"النسخ الاحتياطي";
    self.backupTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.backupTitle.textColor = C_TEXT_TER;
    self.backupTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backupCard addSubview:self.backupTitle];

    self.backupStatus = [[UILabel alloc] init];
    self.backupStatus.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.backupStatus.textColor = C_TEXT_PRI;
    self.backupStatus.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backupCard addSubview:self.backupStatus];

    self.backupBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.backupBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.backupBtn.backgroundColor = [UIColor colorWithRed:0.769 green:0.655 blue:0.490 alpha:0.12];
    self.backupBtn.layer.cornerRadius = 8;
    self.backupBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.backupBtn setTitleColor:C_ACCENT forState:UIControlStateNormal];
    [self.backupBtn addTarget:self action:@selector(backupTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.backupCard addSubview:self.backupBtn];

    [NSLayoutConstraint activateConstraints:@[
        [self.backupCard.topAnchor constraintEqualToAnchor:self.dataCard.bottomAnchor constant:10],
        [self.backupCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.backupCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

        [self.backupTitle.topAnchor constraintEqualToAnchor:self.backupCard.topAnchor constant:16],
        [self.backupTitle.leadingAnchor constraintEqualToAnchor:self.backupCard.leadingAnchor constant:18],

        [self.backupStatus.topAnchor constraintEqualToAnchor:self.backupTitle.bottomAnchor constant:6],
        [self.backupStatus.leadingAnchor constraintEqualToAnchor:self.backupTitle.leadingAnchor],

        [self.backupBtn.topAnchor constraintEqualToAnchor:self.backupStatus.bottomAnchor constant:10],
        [self.backupBtn.leadingAnchor constraintEqualToAnchor:self.backupTitle.leadingAnchor],
        [self.backupBtn.widthAnchor constraintEqualToConstant:100],
        [self.backupBtn.heightAnchor constraintEqualToConstant:32],
        [self.backupBtn.bottomAnchor constraintEqualToAnchor:self.backupCard.bottomAnchor constant:-14]
    ]];
}

#pragma mark - Action Card

- (void)setupActionCard {
    self.actionCard = [self makeCard];
    [self.contentView addSubview:self.actionCard];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"حذف البيانات";
    title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    title.textColor = C_TEXT_PRI;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionCard addSubview:title];

    UILabel *desc = [[UILabel alloc] init];
    desc.text = @"سيتم حذف جميع بيانات التطبيق بشكل دائم.";
    desc.font = [UIFont systemFontOfSize:12];
    desc.textColor = C_TEXT_SEC;
    desc.numberOfLines = 2;
    desc.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionCard addSubview:desc];

    self.wipeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.wipeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.wipeBtn.backgroundColor = [UIColor colorWithRed:0.478 green:0.180 blue:0.180 alpha:0.15];
    self.wipeBtn.layer.cornerRadius = 8;
    self.wipeBtn.layer.borderColor = [UIColor colorWithRed:0.478 green:0.180 blue:0.180 alpha:0.35].CGColor;
    self.wipeBtn.layer.borderWidth = 1;
    self.wipeBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.wipeBtn setTitle:@"حذف" forState:UIControlStateNormal];
    [self.wipeBtn setTitleColor:[UIColor colorWithRed:0.85 green:0.45 blue:0.45 alpha:1.0] forState:UIControlStateNormal];
    [self.wipeBtn addTarget:self action:@selector(wipeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.actionCard addSubview:self.wipeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [self.actionCard.topAnchor constraintEqualToAnchor:self.backupCard.bottomAnchor constant:10],
        [self.actionCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.actionCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

        [title.topAnchor constraintEqualToAnchor:self.actionCard.topAnchor constant:16],
        [title.leadingAnchor constraintEqualToAnchor:self.actionCard.leadingAnchor constant:18],

        [desc.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [desc.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [desc.trailingAnchor constraintEqualToAnchor:self.actionCard.trailingAnchor constant:-18],

        [self.wipeBtn.topAnchor constraintEqualToAnchor:desc.bottomAnchor constant:10],
        [self.wipeBtn.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.wipeBtn.widthAnchor constraintEqualToConstant:100],
        [self.wipeBtn.heightAnchor constraintEqualToConstant:32],
        [self.wipeBtn.bottomAnchor constraintEqualToAnchor:self.actionCard.bottomAnchor constant:-14]
    ]];
}

#pragma mark - Technical Card

- (void)setupTechCard {
    self.techCard = [self makeCard];
    [self.contentView addSubview:self.techCard];

    self.techToggle = [UIButton buttonWithType:UIButtonTypeCustom];
    self.techToggle.translatesAutoresizingMaskIntoConstraints = NO;
    self.techToggle.backgroundColor = [UIColor clearColor];
    [self.techToggle addTarget:self action:@selector(toggleTech) forControlEvents:UIControlEventTouchUpInside];
    [self.techCard addSubview:self.techToggle];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"معلومات التطبيق";
    title.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    title.textColor = C_TEXT_SEC;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.techToggle addSubview:title];

    UIImageView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]];
    chev.tintColor = C_TEXT_TER;
    chev.translatesAutoresizingMaskIntoConstraints = NO;
    chev.tag = 100;
    [self.techToggle addSubview:chev];

    self.techContent = [[UIView alloc] init];
    self.techContent.translatesAutoresizingMaskIntoConstraints = NO;
    self.techContent.clipsToBounds = YES;
    [self.techCard addSubview:self.techContent];

    NSString *bid = self.appInfo[@"bundleID"];
    NSString *dp = [self.manager dataPathForBundleID:bid];
    NSString *ver = [self.manager versionForBundleID:bid];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.techContent addSubview:stack];

    [stack addArrangedSubview:[[InfoRow alloc] initWithIcon:@"number" title:@"معرف الحزمة" value:bid]];
    [stack addArrangedSubview:[[InfoRow alloc] initWithIcon:@"tag" title:@"الإصدار" value:ver]];
    [stack addArrangedSubview:[[InfoRow alloc] initWithIcon:@"folder" title:@"مسار البيانات" value:dp ?: @"—"]];
    [stack addArrangedSubview:[[InfoRow alloc] initWithIcon:@"doc" title:@"المستندات" value:[NSString stringWithFormat:@"%lu ملف", (unsigned long)[self.manager documentsCountForBundleID:bid]]]];

    self.techExpanded = NO;
    self.techHeightConstraint = [self.techContent.heightAnchor constraintEqualToConstant:0];
    self.techHeightConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [self.techCard.topAnchor constraintEqualToAnchor:self.actionCard.bottomAnchor constant:10],
        [self.techCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.techCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.techCard.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-24],

        [self.techToggle.topAnchor constraintEqualToAnchor:self.techCard.topAnchor],
        [self.techToggle.leadingAnchor constraintEqualToAnchor:self.techCard.leadingAnchor],
        [self.techToggle.trailingAnchor constraintEqualToAnchor:self.techCard.trailingAnchor],
        [self.techToggle.heightAnchor constraintEqualToConstant:44],

        [title.leadingAnchor constraintEqualToAnchor:self.techToggle.leadingAnchor constant:18],
        [title.centerYAnchor constraintEqualToAnchor:self.techToggle.centerYAnchor],

        [chev.trailingAnchor constraintEqualToAnchor:self.techToggle.trailingAnchor constant:-18],
        [chev.centerYAnchor constraintEqualToAnchor:self.techToggle.centerYAnchor],
        [chev.widthAnchor constraintEqualToConstant:13],
        [chev.heightAnchor constraintEqualToConstant:13],

        [self.techContent.topAnchor constraintEqualToAnchor:self.techToggle.bottomAnchor],
        [self.techContent.leadingAnchor constraintEqualToAnchor:self.techCard.leadingAnchor constant:18],
        [self.techContent.trailingAnchor constraintEqualToAnchor:self.techCard.trailingAnchor constant:-18],
        [self.techContent.bottomAnchor constraintEqualToAnchor:self.techCard.bottomAnchor constant:-8],

        [stack.topAnchor constraintEqualToAnchor:self.techContent.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.techContent.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.techContent.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.techContent.bottomAnchor]
    ]];
}

- (void)toggleTech {
    self.techExpanded = !self.techExpanded;
    UIImageView *chev = [self.techToggle viewWithTag:100];
    [UIView animateWithDuration:0.25 animations:^{ chev.transform = self.techExpanded ? CGAffineTransformMakeRotation(M_PI) : CGAffineTransformIdentity; }];

    self.techHeightConstraint.active = NO;
    self.techHeightConstraint = self.techExpanded ? [self.techContent.heightAnchor constraintGreaterThanOrEqualToConstant:120] : [self.techContent.heightAnchor constraintEqualToConstant:0];
    self.techHeightConstraint.active = YES;

    [UIView animateWithDuration:0.3 animations:^{ [self.view layoutIfNeeded]; }];
}

#pragma mark - Data Loading

- (void)loadData {
    NSString *bid = self.appInfo[@"bundleID"];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        unsigned long long total = [self.manager dataSizeForBundleID:bid];
        NSString *totalStr = [self.manager formatBytes:total];
        NSArray *parts = [totalStr componentsSeparatedByString:@" "];
        NSString *num = parts.count > 0 ? parts[0] : totalStr;
        NSString *unit = parts.count > 1 ? parts[1] : @"";

        NSString *dp = [self.manager dataPathForBundleID:bid];
        unsigned long long docs = 0, lib = 0, cache = 0;
        if (dp) {
            docs = [self dirSize:[dp stringByAppendingPathComponent:@"Documents"]];
            lib = [self dirSize:[dp stringByAppendingPathComponent:@"Library"]];
            cache = [self dirSize:[[dp stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"Caches"]];
        }

        CGFloat dr = total > 0 ? (CGFloat)docs / (CGFloat)total : 0;
        CGFloat lr = total > 0 ? (CGFloat)lib / (CGFloat)total : 0;
        CGFloat cr = total > 0 ? (CGFloat)cache / (CGFloat)total : 0;

        NSDate *lb = [self.manager lastBackupDateForBundleID:bid];

        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableAttributedString *sizeAttr = [[NSMutableAttributedString alloc] init];
            [sizeAttr appendAttributedString:[[NSAttributedString alloc] initWithString:num attributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:26 weight:UIFontWeightSemibold],
                NSForegroundColorAttributeName: C_TEXT_PRI
            }]];
            if (unit.length > 0) {
                [sizeAttr appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" %@", unit] attributes:@{
                    NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium],
                    NSForegroundColorAttributeName: C_TEXT_SEC
                }]];
            }
            self.dataSizeLabel.attributedText = sizeAttr;
            self.ringView.docRatio = dr; self.ringView.libRatio = lr; self.ringView.cacheRatio = cr;
            [self.ringView setNeedsDisplay];

            self.docsRow.sizeLabel.text = [self.manager formatBytes:docs];
            self.docsRow.pctLabel.text = total > 0 ? [NSString stringWithFormat:@"%.0f%%", dr * 100] : @"0%";
            self.libRow.sizeLabel.text = [self.manager formatBytes:lib];
            self.libRow.pctLabel.text = total > 0 ? [NSString stringWithFormat:@"%.0f%%", lr * 100] : @"0%";
            self.cacheRow.sizeLabel.text = [self.manager formatBytes:cache];
            self.cacheRow.pctLabel.text = total > 0 ? [NSString stringWithFormat:@"%.0f%%", cr * 100] : @"0%";

            [self updateBackup:lb];
        });
    });
}

- (void)updateBackup:(NSDate *)lastBackup {
    if (lastBackup) {
        self.backupStatus.text = @"يوجد نسخة احتياطية";
        self.backupStatus.textColor = [UIColor colorWithRed:0.4 green:0.7 blue:0.5 alpha:1.0];
        [self.backupBtn setTitle:@"استعادة" forState:UIControlStateNormal];
    } else {
        self.backupStatus.text = @"لا توجد نسخة احتياطية";
        self.backupStatus.textColor = C_TEXT_SEC;
        [self.backupBtn setTitle:@"نسخ" forState:UIControlStateNormal];
    }
}

- (unsigned long long)dirSize:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return 0;
    unsigned long long t = 0;
    for (NSString *item in [fm subpathsAtPath:path]) {
        @try {
            NSDictionary *a = [fm attributesOfItemAtPath:[path stringByAppendingPathComponent:item] error:nil];
            if (a) t += [a fileSize];
        } @catch (NSException *e) { continue; }
    }
    return t;
}

#pragma mark - Actions

- (void)backupTapped {
    NSString *bid = self.appInfo[@"bundleID"];
    NSDate *lb = [self.manager lastBackupDateForBundleID:bid];

    if (lb) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"استعادة النسخة الاحتياطية"
                                                                    message:@"سيتم استبدال بيانات التطبيق الحالية بالنسخة الاحتياطية."
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"استعادة" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            NSArray *b = [self.manager availableBackupsForBundleID:bid];
            if (b.count > 0) {
                BOOL ok = [self.manager restoreAppData:bid fromBackup:b[0]];
                [self toast:ok ? @"تمت الاستعادة ✅" : @"فشلت الاستعادة ❌"];
                if (ok) [self loadData];
            }
        }]];
        [self presentViewController:a animated:YES completion:nil];
    } else {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"نسخ %@ احتياطياً", self.appInfo[@"name"]]
                                                                    message:@"سيتم إنشاء نسخة احتياطية كاملة من بيانات التطبيق."
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"نسخ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                BOOL ok = [self.manager backupAppData:bid];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self toast:ok ? @"تم إنشاء النسخة ✅" : @"فشل إنشاء النسخة ❌"];
                    if (ok) [self loadData];
                });
            });
        }]];
        [self presentViewController:a animated:YES completion:nil];
    }
}

- (void)wipeTapped {
    NSString *bid = self.appInfo[@"bundleID"];
    NSString *name = self.appInfo[@"name"];

    if ([self.manager isSystemApp:bid]) {
        [self toast:@"لا يمكن حذف بيانات تطبيق النظام ⛔"];
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        unsigned long long d = [self dirSize:[[self.manager dataPathForBundleID:bid] stringByAppendingPathComponent:@"Documents"]];
        unsigned long long l = [self dirSize:[[self.manager dataPathForBundleID:bid] stringByAppendingPathComponent:@"Library"]];
        unsigned long long c = [self dirSize:[[[self.manager dataPathForBundleID:bid] stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"Caches"]];
        unsigned long long t = d + l + c;

        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *msg = [NSString stringWithFormat:@"سيتم حذف بيانات %@ بشكل دائم:\n\nالمستندات        %@\nالمكتبة          %@\nالتخزين المؤقت   %@\n\nالإجمالي: %@",
                             name, [self.manager formatBytes:d], [self.manager formatBytes:l],
                             [self.manager formatBytes:c], [self.manager formatBytes:t]];

            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"حذف بيانات التطبيق"
                                                                        message:msg
                                                                 preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
            [a addAction:[UIAlertAction actionWithTitle:@"حذف" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    BOOL ok = [self.manager wipeAppData:bid];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self toast:ok ? @"تم الحذف ✅" : @"فشل الحذف ❌"];
                        if (ok) [self loadData];
                    });
                });
            }]];
            [self presentViewController:a animated:YES completion:nil];
        });
    });
}

- (void)toast:(NSString *)msg {
    UILabel *t = [[UILabel alloc] init];
    t.text = msg;
    t.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    t.textColor = C_TEXT_PRI;
    t.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.16 alpha:0.95];
    t.textAlignment = NSTextAlignmentCenter;
    t.layer.cornerRadius = 8;
    t.layer.masksToBounds = YES;
    t.alpha = 0;
    t.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:t];

    [NSLayoutConstraint activateConstraints:@[
        [t.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [t.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [t.heightAnchor constraintEqualToConstant:34],
        [t.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40]
    ]];

    [UIView animateWithDuration:0.3 animations:^{ t.alpha = 1.0; } completion:^(BOOL f) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{ t.alpha = 0; } completion:^(BOOL f2) { [t removeFromSuperview]; }];
        });
    }];
}

@end
