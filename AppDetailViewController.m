#import "AppDetailViewController.h"
#import "AppDataManager.h"

#pragma mark - Helpers

@interface SizeBreakdown : NSObject
@property (nonatomic, assign) unsigned long long documents;
@property (nonatomic, assign) unsigned long long library;
@property (nonatomic, assign) unsigned long long caches;
@property (nonatomic, assign) unsigned long long total;
@end
@implementation SizeBreakdown
@end

#pragma mark - Segmented Bar View

@interface SegmentedBarView : UIView
@property (nonatomic, strong) NSArray<NSNumber *> *segments; // normalized 0..1
@property (nonatomic, strong) NSArray<UIColor *> *colors;
@end

@implementation SegmentedBarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
        self.layer.cornerRadius = 4;
        self.layer.masksToBounds = YES;
    }
    return self;
}

- (void)setSegments:(NSArray<NSNumber *> *)segments colors:(NSArray<UIColor *> *)colors {
    _segments = segments;
    _colors = colors;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    if (!_segments || !_colors || _segments.count == 0) return;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat x = 0;
    CGFloat h = rect.size.height;
    CGFloat w = rect.size.width;

    for (NSUInteger i = 0; i < _segments.count; i++) {
        CGFloat segW = w * [_segments[i] floatValue];
        if (segW < 1) continue;
        CGContextSetFillColorWithColor(ctx, _colors[i].CGColor);
        CGContextFillRect(ctx, CGRectMake(x, 0, segW, h));
        x += segW;
    }
}

@end

#pragma mark - Info Row (small)

@interface DetailRowView : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@end

@implementation DetailRowView

- (instancetype)initWithTitle:(NSString *)title value:(NSString *)value {
    self = [super init];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = title;
        _titleLabel.font = [UIFont systemFontOfSize:13];
        _titleLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.text = value;
        _valueLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _valueLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.numberOfLines = 1;
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_valueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_valueLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:12],
            [self.heightAnchor constraintEqualToConstant:28]
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
@property (nonatomic, strong) UILabel *bundleLabel;
@property (nonatomic, strong) UILabel *versionLabel;

// Data Size
@property (nonatomic, strong) UIView *dataCard;
@property (nonatomic, strong) UILabel *dataTitleLabel;
@property (nonatomic, strong) UILabel *dataSizeLabel;
@property (nonatomic, strong) SegmentedBarView *segmentBar;
@property (nonatomic, strong) UILabel *docsLabel;
@property (nonatomic, strong) UILabel *libLabel;
@property (nonatomic, strong) UILabel *cacheLabel;

// Backup
@property (nonatomic, strong) UIView *backupCard;
@property (nonatomic, strong) UILabel *backupStatusLabel;
@property (nonatomic, strong) UILabel *backupDateLabel;

// Actions
@property (nonatomic, strong) UIButton *backupButton;
@property (nonatomic, strong) UIButton *wipeButton;

// Technical Info (collapsible)
@property (nonatomic, strong) UIView *techCard;
@property (nonatomic, strong) UIButton *techToggleButton;
@property (nonatomic, strong) UIStackView *techStack;
@property (nonatomic, assign) BOOL techExpanded;
@property (nonatomic, strong) NSLayoutConstraint *techStackHeightConstraint;
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
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];

    [self setupNavigationBar];
    [self setupScrollView];
    [self setupHeader];
    [self setupDataCard];
    [self setupBackupCard];
    [self setupActionButtons];
    [self setupTechnicalCard];
    [self loadDataSizes];
}

#pragma mark - Setup

- (void)setupNavigationBar {
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark.circle.fill"]
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
    self.iconView.layer.cornerRadius = 22;
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
    self.nameLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    self.nameLabel.textColor = [UIColor whiteColor];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.nameLabel];

    self.bundleLabel = [[UILabel alloc] init];
    self.bundleLabel.text = bundleID;
    self.bundleLabel.font = [UIFont systemFontOfSize:12];
    self.bundleLabel.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    self.bundleLabel.textAlignment = NSTextAlignmentCenter;
    self.bundleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.bundleLabel];

    self.versionLabel = [[UILabel alloc] init];
    NSString *ver = [self.manager versionForBundleID:bundleID];
    self.versionLabel.text = [NSString stringWithFormat:@"v%@", ver];
    self.versionLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.versionLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    self.versionLabel.textAlignment = NSTextAlignmentCenter;
    self.versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.versionLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:24],
        [self.iconView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:88],
        [self.iconView.heightAnchor constraintEqualToConstant:88],

        [self.nameLabel.topAnchor constraintEqualToAnchor:self.iconView.bottomAnchor constant:14],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [self.bundleLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:4],
        [self.bundleLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.bundleLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],

        [self.versionLabel.topAnchor constraintEqualToAnchor:self.bundleLabel.bottomAnchor constant:2],
        [self.versionLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.versionLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor]
    ]];
}

#pragma mark - Data Card

- (void)setupDataCard {
    self.dataCard = [self createCard];
    [self.contentView addSubview:self.dataCard];

    self.dataTitleLabel = [[UILabel alloc] init];
    self.dataTitleLabel.text = @"بيانات التطبيق";
    self.dataTitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.dataTitleLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    self.dataTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.dataTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dataCard addSubview:self.dataTitleLabel];

    self.dataSizeLabel = [[UILabel alloc] init];
    self.dataSizeLabel.text = @"—";
    self.dataSizeLabel.font = [UIFont systemFontOfSize:42 weight:UIFontWeightBold];
    self.dataSizeLabel.textColor = [UIColor whiteColor];
    self.dataSizeLabel.textAlignment = NSTextAlignmentCenter;
    self.dataSizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dataCard addSubview:self.dataSizeLabel];

    self.segmentBar = [[SegmentedBarView alloc] initWithFrame:CGRectZero];
    self.segmentBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dataCard addSubview:self.segmentBar];

    // Breakdown labels
    self.docsLabel = [self breakdownLabelWithColor:[UIColor colorWithRed:0.35 green:0.65 blue:1.0 alpha:1.0]];
    self.libLabel = [self breakdownLabelWithColor:[UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0]];
    self.cacheLabel = [self breakdownLabelWithColor:[UIColor colorWithRed:0.95 green:0.5 blue:0.3 alpha:1.0]];
    [self.dataCard addSubview:self.docsLabel];
    [self.dataCard addSubview:self.libLabel];
    [self.dataCard addSubview:self.cacheLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.dataCard.topAnchor constraintEqualToAnchor:self.versionLabel.bottomAnchor constant:28],
        [self.dataCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.dataCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

        [self.dataTitleLabel.topAnchor constraintEqualToAnchor:self.dataCard.topAnchor constant:20],
        [self.dataTitleLabel.leadingAnchor constraintEqualToAnchor:self.dataCard.leadingAnchor constant:20],
        [self.dataTitleLabel.trailingAnchor constraintEqualToAnchor:self.dataCard.trailingAnchor constant:-20],

        [self.dataSizeLabel.topAnchor constraintEqualToAnchor:self.dataTitleLabel.bottomAnchor constant:8],
        [self.dataSizeLabel.leadingAnchor constraintEqualToAnchor:self.dataCard.leadingAnchor constant:20],
        [self.dataSizeLabel.trailingAnchor constraintEqualToAnchor:self.dataCard.trailingAnchor constant:-20],

        [self.segmentBar.topAnchor constraintEqualToAnchor:self.dataSizeLabel.bottomAnchor constant:16],
        [self.segmentBar.leadingAnchor constraintEqualToAnchor:self.dataCard.leadingAnchor constant:20],
        [self.segmentBar.trailingAnchor constraintEqualToAnchor:self.dataCard.trailingAnchor constant:-20],
        [self.segmentBar.heightAnchor constraintEqualToConstant:8],

        [self.docsLabel.topAnchor constraintEqualToAnchor:self.segmentBar.bottomAnchor constant:14],
        [self.docsLabel.leadingAnchor constraintEqualToAnchor:self.dataCard.leadingAnchor constant:20],
        [self.docsLabel.trailingAnchor constraintEqualToAnchor:self.dataCard.trailingAnchor constant:-20],

        [self.libLabel.topAnchor constraintEqualToAnchor:self.docsLabel.bottomAnchor constant:4],
        [self.libLabel.leadingAnchor constraintEqualToAnchor:self.docsLabel.leadingAnchor],
        [self.libLabel.trailingAnchor constraintEqualToAnchor:self.docsLabel.trailingAnchor],

        [self.cacheLabel.topAnchor constraintEqualToAnchor:self.libLabel.bottomAnchor constant:4],
        [self.cacheLabel.leadingAnchor constraintEqualToAnchor:self.docsLabel.leadingAnchor],
        [self.cacheLabel.trailingAnchor constraintEqualToAnchor:self.docsLabel.trailingAnchor],
        [self.cacheLabel.bottomAnchor constraintEqualToAnchor:self.dataCard.bottomAnchor constant:-20]
    ]];
}

- (UILabel *)breakdownLabelWithColor:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    label.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    label.translatesAutoresizingMaskIntoConstraints = NO;

    // Dot
    NSTextAttachment *dot = [[NSTextAttachment alloc] init];
    dot.bounds = CGRectMake(0, -2, 8, 8);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(8, 8), NO, 0);
    [color setFill];
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 8, 8)];
    [path fill];
    dot.image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    NSAttributedString *dotStr = [NSAttributedString attributedStringWithAttachment:dot];
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithAttributedString:dotStr];
    [attr appendAttributedString:[[NSAttributedString alloc] initWithString:@"  " attributes:@{}]];
    label.attributedText = attr;

    return label;
}

- (void)updateBreakdownLabel:(UILabel *)label text:(NSString *)text color:(UIColor *)color {
    NSTextAttachment *dot = [[NSTextAttachment alloc] init];
    dot.bounds = CGRectMake(0, -2, 8, 8);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(8, 8), NO, 0);
    [color setFill];
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 8, 8)];
    [path fill];
    dot.image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithAttributedString:[NSAttributedString attributedStringWithAttachment:dot]];
    [attr appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"  %@", text] attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:0.7 alpha:1.0]
    }]];
    label.attributedText = attr;
}

#pragma mark - Backup Card

- (void)setupBackupCard {
    self.backupCard = [self createCard];
    [self.contentView addSubview:self.backupCard];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"النسخ الاحتياطي";
    titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backupCard addSubview:titleLabel];

    self.backupStatusLabel = [[UILabel alloc] init];
    self.backupStatusLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.backupStatusLabel.textColor = [UIColor whiteColor];
    self.backupStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backupCard addSubview:self.backupStatusLabel];

    self.backupDateLabel = [[UILabel alloc] init];
    self.backupDateLabel.font = [UIFont systemFontOfSize:13];
    self.backupDateLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    self.backupDateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backupCard addSubview:self.backupDateLabel];

    [self updateBackupStatus];

    [NSLayoutConstraint activateConstraints:@[
        [self.backupCard.topAnchor constraintEqualToAnchor:self.dataCard.bottomAnchor constant:12],
        [self.backupCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.backupCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

        [titleLabel.topAnchor constraintEqualToAnchor:self.backupCard.topAnchor constant:16],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.backupCard.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.backupCard.trailingAnchor constant:-20],

        [self.backupStatusLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6],
        [self.backupStatusLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.backupStatusLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [self.backupDateLabel.topAnchor constraintEqualToAnchor:self.backupStatusLabel.bottomAnchor constant:2],
        [self.backupDateLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.backupDateLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [self.backupDateLabel.bottomAnchor constraintEqualToAnchor:self.backupCard.bottomAnchor constant:-16]
    ]];
}

- (void)updateBackupStatus {
    NSString *bundleID = self.appInfo[@"bundleID"];
    NSDate *lastBackup = [self.manager lastBackupDateForBundleID:bundleID];

    if (lastBackup) {
        self.backupStatusLabel.text = @"يوجد نسخة احتياطية";
        self.backupStatusLabel.textColor = [UIColor colorWithRed:0.3 green:0.8 blue:0.5 alpha:1.0];

        NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitDay
                                                                        fromDate:lastBackup
                                                                          toDate:[NSDate date]
                                                                         options:0];
        NSInteger days = components.day;
        if (days == 0) {
            self.backupDateLabel.text = @"منذ اليوم";
        } else if (days == 1) {
            self.backupDateLabel.text = @"منذ يوم واحد";
        } else if (days < 7) {
            self.backupDateLabel.text = [NSString stringWithFormat:@"منذ %ld أيام", (long)days];
        } else if (days < 30) {
            self.backupDateLabel.text = [NSString stringWithFormat:@"منذ %ld أسابيع", (long)(days/7)];
        } else {
            self.backupDateLabel.text = [NSString stringWithFormat:@"منذ %ld أشهر", (long)(days/30)];
        }
    } else {
        self.backupStatusLabel.text = @"لا توجد نسخة احتياطية";
        self.backupStatusLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        self.backupDateLabel.text = @"أنشئ نسخة احتياطية قبل الحذف";
    }
}

#pragma mark - Action Buttons

- (void)setupActionButtons {
    self.backupButton = [self createActionButtonWithTitle:@"إنشاء نسخة احتياطية"
                                                     color:[UIColor colorWithRed:0.35 green:0.25 blue:0.85 alpha:1.0]
                                                     icon:@"arrow.up.circle.fill"];
    [self.backupButton addTarget:self action:@selector(backupTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.backupButton];

    self.wipeButton = [self createActionButtonWithTitle:@"حذف بيانات التطبيق"
                                                   color:[UIColor colorWithRed:0.85 green:0.25 blue:0.25 alpha:1.0]
                                                   icon:@"trash.fill"];
    [self.wipeButton addTarget:self action:@selector(wipeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.wipeButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.backupButton.topAnchor constraintEqualToAnchor:self.backupCard.bottomAnchor constant:20],
        [self.backupButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.backupButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.backupButton.heightAnchor constraintEqualToConstant:54],

        [self.wipeButton.topAnchor constraintEqualToAnchor:self.backupButton.bottomAnchor constant:10],
        [self.wipeButton.leadingAnchor constraintEqualToAnchor:self.backupButton.leadingAnchor],
        [self.wipeButton.trailingAnchor constraintEqualToAnchor:self.backupButton.trailingAnchor],
        [self.wipeButton.heightAnchor constraintEqualToConstant:54]
    ]];
}

- (UIButton *)createActionButtonWithTitle:(NSString *)title color:(UIColor *)color icon:(NSString *)iconName {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = color;
    btn.layer.cornerRadius = 14;
    btn.layer.masksToBounds = YES;
    btn.tintColor = [UIColor whiteColor];

    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] init];
    NSTextAttachment *attach = [[NSTextAttachment alloc] init];
    attach.image = [[UIImage systemImageNamed:iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    attach.bounds = CGRectMake(0, -3, 18, 18);
    [attr appendAttributedString:[NSAttributedString attributedStringWithAttachment:attach]];
    [attr appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"  %@", title] attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: [UIColor whiteColor]
    }]];
    [btn setAttributedTitle:attr forState:UIControlStateNormal];

    return btn;
}

#pragma mark - Technical Info (Collapsible)

- (void)setupTechnicalCard {
    self.techCard = [self createCard];
    [self.contentView addSubview:self.techCard];

    self.techToggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.techToggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.techToggleButton.backgroundColor = [UIColor clearColor];
    [self.techToggleButton addTarget:self action:@selector(toggleTechSection) forControlEvents:UIControlEventTouchUpInside];
    [self.techCard addSubview:self.techToggleButton];

    UILabel *techTitle = [[UILabel alloc] init];
    techTitle.text = @"معلومات التطبيق";
    techTitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    techTitle.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    techTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.techToggleButton addSubview:techTitle];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]];
    chevron.tintColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tag = 100;
    [self.techToggleButton addSubview:chevron];

    self.techStack = [[UIStackView alloc] init];
    self.techStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.techStack.axis = UILayoutConstraintAxisVertical;
    self.techStack.spacing = 0;
    self.techStack.alpha = 0;
    [self.techCard addSubview:self.techStack];

    NSString *bundleID = self.appInfo[@"bundleID"];
    NSString *dataPath = [self.manager dataPathForBundleID:bundleID];

    [self.techStack addArrangedSubview:[[DetailRowView alloc] initWithTitle:@"Bundle ID" value:bundleID]];
    [self.techStack addArrangedSubview:[[DetailRowView alloc] initWithTitle:@"Version" value:[self.manager versionForBundleID:bundleID]]];
    [self.techStack addArrangedSubview:[[DetailRowView alloc] initWithTitle:@"Data Path" value:dataPath ?: @"—"]];
    [self.techStack addArrangedSubview:[[DetailRowView alloc] initWithTitle:@"Documents" value:[NSString stringWithFormat:@"%lu files", (unsigned long)[self.manager documentsCountForBundleID:bundleID]]]];

    self.techExpanded = NO;
    self.techStackHeightConstraint = [self.techStack.heightAnchor constraintEqualToConstant:0];
    self.techStackHeightConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [self.techCard.topAnchor constraintEqualToAnchor:self.wipeButton.bottomAnchor constant:20],
        [self.techCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.techCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.techCard.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-30],

        [self.techToggleButton.topAnchor constraintEqualToAnchor:self.techCard.topAnchor],
        [self.techToggleButton.leadingAnchor constraintEqualToAnchor:self.techCard.leadingAnchor],
        [self.techToggleButton.trailingAnchor constraintEqualToAnchor:self.techCard.trailingAnchor],
        [self.techToggleButton.heightAnchor constraintEqualToConstant:48],

        [techTitle.leadingAnchor constraintEqualToAnchor:self.techToggleButton.leadingAnchor constant:20],
        [techTitle.centerYAnchor constraintEqualToAnchor:self.techToggleButton.centerYAnchor],

        [chevron.trailingAnchor constraintEqualToAnchor:self.techToggleButton.trailingAnchor constant:-20],
        [chevron.centerYAnchor constraintEqualToAnchor:self.techToggleButton.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:16],
        [chevron.heightAnchor constraintEqualToConstant:16],

        [self.techStack.topAnchor constraintEqualToAnchor:self.techToggleButton.bottomAnchor],
        [self.techStack.leadingAnchor constraintEqualToAnchor:self.techCard.leadingAnchor constant:20],
        [self.techStack.trailingAnchor constraintEqualToAnchor:self.techCard.trailingAnchor constant:-20],
        [self.techStack.bottomAnchor constraintEqualToAnchor:self.techCard.bottomAnchor constant:-12]
    ]];
}

- (void)toggleTechSection {
    self.techExpanded = !self.techExpanded;

    UIImageView *chevron = [self.techToggleButton viewWithTag:100];
    [UIView animateWithDuration:0.25 animations:^{
        chevron.transform = self.techExpanded ? CGAffineTransformMakeRotation(M_PI) : CGAffineTransformIdentity;
        self.techStack.alpha = self.techExpanded ? 1.0 : 0.0;
    }];

    self.techStackHeightConstraint.active = NO;
    if (self.techExpanded) {
        self.techStackHeightConstraint = [self.techStack.heightAnchor constraintGreaterThanOrEqualToConstant:112];
    } else {
        self.techStackHeightConstraint = [self.techStack.heightAnchor constraintEqualToConstant:0];
    }
    self.techStackHeightConstraint.active = YES;

    [UIView animateWithDuration:0.3 animations:^{
        [self.view layoutIfNeeded];
    }];
}

#pragma mark - Data Loading

- (void)loadDataSizes {
    NSString *bundleID = self.appInfo[@"bundleID"];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SizeBreakdown *bd = [self calculateSizeBreakdownForBundleID:bundleID];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.dataSizeLabel.text = [self.manager formatBytes:bd.total];

            if (bd.total > 0) {
                CGFloat docP = (CGFloat)bd.documents / (CGFloat)bd.total;
                CGFloat libP = (CGFloat)bd.library / (CGFloat)bd.total;
                CGFloat cacheP = (CGFloat)bd.caches / (CGFloat)bd.total;

                [self.segmentBar setSegments:@[@(docP), @(libP), @(cacheP)]
                                      colors:@[[UIColor colorWithRed:0.35 green:0.65 blue:1.0 alpha:1.0],
                                               [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0],
                                               [UIColor colorWithRed:0.95 green:0.5 blue:0.3 alpha:1.0]]];

                [self updateBreakdownLabel:self.docsLabel
                                      text:[NSString stringWithFormat:@"Documents    %@", [self.manager formatBytes:bd.documents]]
                                     color:[UIColor colorWithRed:0.35 green:0.65 blue:1.0 alpha:1.0]];
                [self updateBreakdownLabel:self.libLabel
                                      text:[NSString stringWithFormat:@"Library      %@", [self.manager formatBytes:bd.library]]
                                     color:[UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0]];
                [self updateBreakdownLabel:self.cacheLabel
                                      text:[NSString stringWithFormat:@"Caches       %@", [self.manager formatBytes:bd.caches]]
                                     color:[UIColor colorWithRed:0.95 green:0.5 blue:0.3 alpha:1.0]];
            } else {
                [self.segmentBar setSegments:@[@1.0] colors:@[[UIColor colorWithWhite:0.15 alpha:1.0]]];
                self.docsLabel.attributedText = nil;
                self.docsLabel.text = @"لا توجد بيانات";
                self.docsLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
                self.libLabel.hidden = YES;
                self.cacheLabel.hidden = YES;
            }
        });
    });
}

- (SizeBreakdown *)calculateSizeBreakdownForBundleID:(NSString *)bundleID {
    SizeBreakdown *bd = [[SizeBreakdown alloc] init];
    NSString *dataPath = [self.manager dataPathForBundleID:bundleID];
    if (!dataPath) {
        bd.total = 0;
        return bd;
    }

    NSFileManager *fm = [NSFileManager defaultManager];

    // Documents
    NSString *docsPath = [dataPath stringByAppendingPathComponent:@"Documents"];
    bd.documents = [self directorySize:docsPath];

    // Library
    NSString *libPath = [dataPath stringByAppendingPathComponent:@"Library"];
    bd.library = [self directorySize:libPath];

    // Caches
    NSString *cachePath = [libPath stringByAppendingPathComponent:@"Caches"];
    bd.caches = [self directorySize:cachePath];

    // Total (actual)
    bd.total = [self.manager dataSizeForBundleID:bundleID];

    return bd;
}

- (unsigned long long)directorySize:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return 0;

    unsigned long long total = 0;
    NSArray *items = [fm subpathsAtPath:path];
    for (NSString *item in items) {
        @try {
            NSString *fullPath = [path stringByAppendingPathComponent:item];
            NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
            if (attrs) total += [attrs fileSize];
        } @catch (NSException *e) { continue; }
    }
    return total;
}

#pragma mark - Actions

- (void)backupTapped {
    NSString *bundleID = self.appInfo[@"bundleID"];
    NSString *appName = self.appInfo[@"name"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"نسخ %@ احتياطياً", appName]
                                                                   message:@"سيتم إنشاء نسخة احتياطية كاملة من بيانات التطبيق."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"نسخ احتياطي" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            BOOL success = [self.manager backupAppData:bundleID];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    [self showToast:@"تم إنشاء النسخة الاحتياطية ✅"];
                    [self updateBackupStatus];
                } else {
                    [self showToast:@"فشل إنشاء النسخة الاحتياطية ❌"];
                }
            });
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)wipeTapped {
    NSString *bundleID = self.appInfo[@"bundleID"];
    NSString *appName = self.appInfo[@"name"];

    if ([self.manager isSystemApp:bundleID]) {
        [self showToast:@"لا يمكن حذف بيانات تطبيق النظام ⛔"];
        return;
    }

    // حساب ما سيتم حذفه
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SizeBreakdown *bd = [self calculateSizeBreakdownForBundleID:bundleID];

        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *msg = [NSString stringWithFormat:@"سيتم حذف بيانات %@ بشكل دائم:\n\nDocuments    %@\nLibrary      %@\nCaches       %@\n\nإجمالي البيانات\n%@",
                             appName,
                             [self.manager formatBytes:bd.documents],
                             [self.manager formatBytes:bd.library],
                             [self.manager formatBytes:bd.caches],
                             [self.manager formatBytes:bd.total]];

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"حذف بيانات التطبيق"
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];

            UIAlertAction *wipeAction = [UIAlertAction actionWithTitle:@"حذف البيانات" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    BOOL success = [self.manager wipeAppData:bundleID];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (success) {
                            [self showToast:@"تم حذف البيانات ✅"];
                            [self loadDataSizes];
                        } else {
                            [self showToast:@"فشل الحذف ❌"];
                        }
                    });
                });
            }];
            [alert addAction:wipeAction];
            [self presentViewController:alert animated:YES completion:nil];
        });
    });
}

- (void)deleteAppTapped {
    [self wipeTapped];
}

#pragma mark - Helpers

- (UIView *)createCard {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.11 alpha:1.0];
    card.layer.cornerRadius = 16;
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    return card;
}

- (void)showToast:(NSString *)message {
    UILabel *toast = [[UILabel alloc] init];
    toast.text = message;
    toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
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
        [toast.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-30],
        [toast.heightAnchor constraintEqualToConstant:40],
        [toast.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40]
    ]];

    [UIView animateWithDuration:0.3 animations:^{
        toast.alpha = 1.0;
    } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                toast.alpha = 0;
            } completion:^(BOOL finished) {
                [toast removeFromSuperview];
            }];
        });
    }];
}

@end
