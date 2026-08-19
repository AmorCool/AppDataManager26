#import "BackupManagerViewController.h"
#import "AppDataManager.h"

#pragma mark - Design System

static UIColor *ADMBackupBackground(void) { return [UIColor colorWithRed:0.035 green:0.035 blue:0.055 alpha:1.0]; }
static UIColor *ADMBackupCard(void) { return [UIColor colorWithRed:0.085 green:0.085 blue:0.125 alpha:1.0]; }
static UIColor *ADMBackupAccent(void) { return [UIColor colorWithRed:0.54 green:0.42 blue:0.98 alpha:1.0]; }
static UIColor *ADMBackupBlue(void) { return [UIColor colorWithRed:0.30 green:0.66 blue:0.96 alpha:1.0]; }
static UIColor *ADMBackupTextSecondary(void) { return [UIColor colorWithWhite:0.58 alpha:1.0]; }

#pragma mark - Pie Chart

@interface PieChartView : UIView
@property (nonatomic, strong) NSArray *segments;
@property (nonatomic, strong) UILabel *centerLabel;
@end

@implementation PieChartView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        _centerLabel = [[UILabel alloc] init];
        _centerLabel.textAlignment = NSTextAlignmentCenter;
        _centerLabel.numberOfLines = 0;
        _centerLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_centerLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_centerLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_centerLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_centerLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_centerLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor]
        ]];
    }
    return self;
}

- (void)setSegments:(NSArray *)segments {
    _segments = segments;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    if (self.segments.count == 0) return;
    CGFloat total = 0;
    for (NSDictionary *segment in self.segments) total += [segment[@"value"] doubleValue];
    if (total <= 0) return;

    CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    CGFloat lineWidth = 16.0;
    CGFloat radius = MIN(rect.size.width, rect.size.height) / 2.0 - lineWidth;
    UIBezierPath *track = [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:-M_PI_2 endAngle:3 * M_PI_2 clockwise:YES];
    track.lineWidth = lineWidth;
    track.lineCapStyle = kCGLineCapRound;
    [[UIColor colorWithWhite:0.17 alpha:1.0] setStroke];
    [track stroke];

    CGFloat startAngle = -M_PI_2;
    for (NSDictionary *segment in self.segments) {
        CGFloat value = [segment[@"value"] doubleValue];
        if (value <= 0) continue;
        CGFloat endAngle = startAngle + ((value / total) * 2.0 * M_PI);
        UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:startAngle endAngle:endAngle clockwise:YES];
        path.lineWidth = lineWidth;
        path.lineCapStyle = kCGLineCapRound;
        [segment[@"color"] setStroke];
        [path stroke];
        startAngle = endAngle;
    }
}

@end

#pragma mark - Backup Cell

@interface BackupCell : UITableViewCell
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIImageView *appIcon;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UIButton *restoreButton;
@property (nonatomic, strong) UIButton *deleteButton;
@end

@implementation BackupCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _containerView = [[UIView alloc] init];
        _containerView.backgroundColor = ADMBackupCard();
        _containerView.layer.cornerRadius = 18.0;
        _containerView.layer.masksToBounds = YES;
        _containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_containerView];

        _appIcon = [[UIImageView alloc] init];
        _appIcon.layer.cornerRadius = 13.0;
        _appIcon.layer.masksToBounds = YES;
        _appIcon.contentMode = UIViewContentModeScaleAspectFit;
        _appIcon.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        _appIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_appIcon];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _nameLabel.textColor = UIColor.whiteColor;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_nameLabel];

        _dateLabel = [[UILabel alloc] init];
        _dateLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
        _dateLabel.textColor = ADMBackupTextSecondary();
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_dateLabel];

        _sizeLabel = [[UILabel alloc] init];
        _sizeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _sizeLabel.textColor = ADMBackupAccent();
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_sizeLabel];

        _deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_deleteButton setImage:[UIImage systemImageNamed:@"trash.fill"] forState:UIControlStateNormal];
        _deleteButton.tintColor = [UIColor colorWithRed:0.98 green:0.34 blue:0.40 alpha:1.0];
        _deleteButton.backgroundColor = [UIColor colorWithRed:0.30 green:0.08 blue:0.12 alpha:1.0];
        _deleteButton.layer.cornerRadius = 12;
        _deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_deleteButton];

        _restoreButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_restoreButton setImage:[UIImage systemImageNamed:@"arrow.counterclockwise"] forState:UIControlStateNormal];
        _restoreButton.tintColor = ADMBackupBlue();
        _restoreButton.backgroundColor = [UIColor colorWithRed:0.08 green:0.18 blue:0.30 alpha:1.0];
        _restoreButton.layer.cornerRadius = 12;
        _restoreButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:_restoreButton];

        [NSLayoutConstraint activateConstraints:@[
            [_containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
            [_containerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_containerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5],
            [_containerView.heightAnchor constraintEqualToConstant:82],

            [_appIcon.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:14],
            [_appIcon.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
            [_appIcon.widthAnchor constraintEqualToConstant:48],
            [_appIcon.heightAnchor constraintEqualToConstant:48],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_appIcon.trailingAnchor constant:13],
            [_nameLabel.topAnchor constraintEqualToAnchor:_containerView.topAnchor constant:13],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:_restoreButton.leadingAnchor constant:-10],

            [_dateLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_dateLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:5],
            [_dateLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],

            [_sizeLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_sizeLabel.topAnchor constraintEqualToAnchor:_dateLabel.bottomAnchor constant:3],

            [_deleteButton.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor constant:-13],
            [_deleteButton.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
            [_deleteButton.widthAnchor constraintEqualToConstant:40],
            [_deleteButton.heightAnchor constraintEqualToConstant:40],

            [_restoreButton.trailingAnchor constraintEqualToAnchor:_deleteButton.leadingAnchor constant:-8],
            [_restoreButton.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
            [_restoreButton.widthAnchor constraintEqualToConstant:40],
            [_restoreButton.heightAnchor constraintEqualToConstant:40]
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.nameLabel.text = nil;
    self.dateLabel.text = nil;
    self.sizeLabel.text = nil;
    self.appIcon.image = nil;
    self.alpha = 1.0;
    self.transform = CGAffineTransformIdentity;
}

@end

#pragma mark - Controller

@interface BackupManagerViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *backups;
@property (nonatomic, strong) AppDataManager *manager;
@property (nonatomic, strong) PieChartView *pieChart;
@property (nonatomic, strong) UIView *statsContainer;
@property (nonatomic, strong) UILabel *countLabel;
@end

@implementation BackupManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"النسخ الاحتياطية";
    self.view.backgroundColor = ADMBackupBackground();
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
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
    self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
    self.navigationController.navigationBar.barTintColor = ADMBackupBackground();
    self.navigationController.navigationBar.backgroundColor = ADMBackupBackground();
    self.navigationController.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    self.navigationController.navigationBar.largeTitleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor, NSFontAttributeName: [UIFont systemFontOfSize:34 weight:UIFontWeightBold]};

    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"] style:UIBarButtonItemStylePlain target:self action:@selector(addBackupTapped)];
    addButton.tintColor = ADMBackupAccent();
    self.navigationItem.rightBarButtonItem = addButton;
}

- (void)setupStatsView {
    self.statsContainer = [[UIView alloc] init];
    self.statsContainer.backgroundColor = ADMBackupCard();
    self.statsContainer.layer.cornerRadius = 22;
    self.statsContainer.layer.masksToBounds = YES;
    self.statsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statsContainer];

    self.pieChart = [[PieChartView alloc] init];
    self.pieChart.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statsContainer addSubview:self.pieChart];

    NSArray *legendItems = @[
        @{ @"color": ADMBackupAccent(), @"label": @"النسخ الاحتياطية" },
        @{ @"color": ADMBackupBlue(), @"label": @"بيانات التطبيقات" },
        @{ @"color": [UIColor colorWithWhite:0.27 alpha:1.0], @"label": @"المساحة الحرة" }
    ];
    UIView *lastDot = nil;
    for (NSDictionary *item in legendItems) {
        UIView *dot = [[UIView alloc] init];
        dot.backgroundColor = item[@"color"];
        dot.layer.cornerRadius = 4;
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        [self.statsContainer addSubview:dot];

        UILabel *label = [[UILabel alloc] init];
        label.text = item[@"label"];
        label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        label.textColor = ADMBackupTextSecondary();
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [self.statsContainer addSubview:label];

        UILabel *value = [[UILabel alloc] init];
        value.tag = [item[@"label"] hash];
        value.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
        value.textColor = UIColor.whiteColor;
        value.textAlignment = NSTextAlignmentRight;
        value.translatesAutoresizingMaskIntoConstraints = NO;
        [self.statsContainer addSubview:value];

        [NSLayoutConstraint activateConstraints:@[
            [dot.leadingAnchor constraintEqualToAnchor:self.pieChart.trailingAnchor constant:14],
            [dot.widthAnchor constraintEqualToConstant:8],
            [dot.heightAnchor constraintEqualToConstant:8],
            [label.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:8],
            [label.centerYAnchor constraintEqualToAnchor:dot.centerYAnchor],
            [value.trailingAnchor constraintEqualToAnchor:self.statsContainer.trailingAnchor constant:-16],
            [value.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:6],
            [value.centerYAnchor constraintEqualToAnchor:dot.centerYAnchor]
        ]];
        if (lastDot) [dot.topAnchor constraintEqualToAnchor:lastDot.bottomAnchor constant:15].active = YES;
        else [dot.topAnchor constraintEqualToAnchor:self.statsContainer.topAnchor constant:25].active = YES;
        lastDot = dot;
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.statsContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.statsContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.statsContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.statsContainer.heightAnchor constraintEqualToConstant:190],
        [self.pieChart.leadingAnchor constraintEqualToAnchor:self.statsContainer.leadingAnchor constant:18],
        [self.pieChart.centerYAnchor constraintEqualToAnchor:self.statsContainer.centerYAnchor],
        [self.pieChart.widthAnchor constraintEqualToConstant:136],
        [self.pieChart.heightAnchor constraintEqualToConstant:136]
    ]];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = ADMBackupBackground();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 28, 0);
    self.tableView.estimatedRowHeight = 92;
    self.tableView.rowHeight = 92;
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
    unsigned long long freeSpace = [self.manager totalFreeSpace];
    unsigned long long total = backupsSize + appsSize + freeSpace;
    if (total == 0) total = 1;

    self.pieChart.segments = @[
        @{ @"value": @(backupsSize), @"color": ADMBackupAccent() },
        @{ @"value": @(appsSize), @"color": ADMBackupBlue() },
        @{ @"value": @(freeSpace), @"color": [UIColor colorWithWhite:0.27 alpha:1.0] }
    ];
    self.pieChart.centerLabel.attributedText = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\nالمستخدم", [self.manager formatBytes:backupsSize + appsSize]] attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: ADMBackupTextSecondary()
    }];
    [self.pieChart setNeedsDisplay];

    NSDictionary *labels = @{
        @"النسخ الاحتياطية": [self.manager formatBytes:backupsSize],
        @"بيانات التطبيقات": [self.manager formatBytes:appsSize],
        @"المساحة الحرة": [self.manager formatBytes:freeSpace]
    };
    for (UIView *view in self.statsContainer.subviews) {
        if (![view isKindOfClass:[UILabel class]] || view.tag == 0) continue;
        UILabel *label = (UILabel *)view;
        for (NSString *key in labels) if (label.tag == [key hash]) label.text = labels[key];
    }
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.backups.count; }

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = ADMBackupBackground();
    UILabel *title = [[UILabel alloc] init];
    title.text = @"النسخ المتاحة";
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    title.textColor = UIColor.whiteColor;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:title];
    self.countLabel = [[UILabel alloc] init];
    self.countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.backups.count];
    self.countLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.countLabel.textColor = ADMBackupTextSecondary();
    self.countLabel.textAlignment = NSTextAlignmentCenter;
    self.countLabel.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1.0];
    self.countLabel.layer.cornerRadius = 12;
    self.countLabel.layer.masksToBounds = YES;
    self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.countLabel];
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:18],
        [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.countLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-18],
        [self.countLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.countLabel.widthAnchor constraintEqualToConstant:42],
        [self.countLabel.heightAnchor constraintEqualToConstant:24]
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 50; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"BackupCell";
    BackupCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) cell = [[BackupCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];
    NSDictionary *backup = self.backups[indexPath.row];
    cell.nameLabel.text = backup[@"appName"];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"MMM d, yyyy 'at' h:mm a"];
    cell.dateLabel.text = [formatter stringFromDate:backup[@"date"]];
    cell.sizeLabel.text = backup[@"sizeString"];
    UIImage *icon = [self.manager iconForBundleID:backup[@"bundleID"]];
    if (icon) {
        cell.appIcon.image = icon;
        cell.appIcon.tintColor = nil;
    } else {
        cell.appIcon.image = [UIImage systemImageNamed:@"app.fill"];
        cell.appIcon.tintColor = ADMBackupAccent();
    }
    cell.restoreButton.tag = indexPath.row;
    [cell.restoreButton addTarget:self action:@selector(restoreTapped:) forControlEvents:UIControlEventTouchUpInside];
    cell.deleteButton.tag = indexPath.row;
    [cell.deleteButton addTarget:self action:@selector(deleteTapped:) forControlEvents:UIControlEventTouchUpInside];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (cell.layer.presentationLayer) return;
    cell.alpha = 0.0;
    cell.transform = CGAffineTransformMakeTranslation(0, 10);
    [UIView animateWithDuration:0.28 delay:MIN(indexPath.row * 0.04, 0.20) options:UIViewAnimationOptionCurveEaseOut animations:^{
        cell.alpha = 1.0;
        cell.transform = CGAffineTransformIdentity;
    } completion:nil];
}

#pragma mark - Existing actions preserved

- (void)restoreTapped:(UIButton *)sender {
    NSDictionary *backup = self.backups[sender.tag];
    NSString *bundleID = backup[@"bundleID"];
    NSString *path = backup[@"path"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تأكيد الاستعادة" message:[NSString stringWithFormat:@"سيتم استبدال بيانات %@ بالنسخة المحددة. هل تريد المتابعة؟", backup[@"appName"]] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"استعادة" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showSpinner];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            BOOL success = [self.manager restoreAppData:bundleID fromBackup:path];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideSpinner];
                [self showToast:success ? @"تمت الاستعادة" : @"فشلت الاستعادة"];
            });
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteTapped:(UIButton *)sender {
    NSDictionary *backup = self.backups[sender.tag];
    NSString *path = backup[@"path"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تأكيد الحذف" message:@"سيتم حذف هذه النسخة نهائياً." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"حذف" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self showSpinner];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            BOOL success = [self.manager deleteBackup:path];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideSpinner];
                if (success) [self loadBackups];
                [self showToast:success ? @"تم حذف النسخة" : @"فشل حذف النسخة"];
            });
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addBackupTapped { [self showToast:@"انتقل إلى تبويب التطبيقات لإنشاء نسخة جديدة"]; }

- (void)showSpinner {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.tag = 999;
    spinner.color = ADMBackupAccent();
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[[spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor], [spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]]];
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
    toast.textColor = UIColor.whiteColor;
    toast.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.96];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    toast.layer.cornerRadius = 15;
    toast.layer.masksToBounds = YES;
    toast.numberOfLines = 0;
    CGSize size = [message boundingRectWithSize:CGSizeMake(self.view.bounds.size.width - 64, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: toast.font} context:nil].size;
    toast.frame = CGRectMake(0, 0, size.width + 34, size.height + 24);
    toast.center = CGPointMake(self.view.center.x, self.view.bounds.size.height - 118);
    toast.alpha = 0.0;
    [self.view addSubview:toast];
    [UIView animateWithDuration:0.22 animations:^{ toast.alpha = 1.0; } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.28 delay:2.2 options:UIViewAnimationOptionCurveEaseOut animations:^{ toast.alpha = 0.0; } completion:^(BOOL done) { [toast removeFromSuperview]; }];
    }];
}

@end
