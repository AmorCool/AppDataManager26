//
//  AppDetailViewController.m
//  AppDataManager
//
//  v1.6.3 — Crash-Resilient App Detail
//  Fixes:
//  - Correct card/label ownership
//  - Async lifecycle safety
//  - Stale-result protection
//  - Main-thread UI isolation
//  - Correct Documents size calculation
//  - Safer destructive operations
//  - Loading-state protection
//  - Nil/error resilience
//

#import "AppDetailViewController.h"
#import "AppDataManager.h"
#import "BackupManagerViewController.h"

@interface AppDetailViewController ()

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

@property (nonatomic, strong) UIImageView *appIcon;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *bundleIDLabel;

@property (nonatomic, strong) UIView *versionCard;
@property (nonatomic, strong) UIView *dataSizeCard;
@property (nonatomic, strong) UIView *documentsSizeCard;
@property (nonatomic, strong) UIView *documentsCountCard;
@property (nonatomic, strong) UIView *lastBackupCard;
@property (nonatomic, strong) UIView *dataPathCard;
@property (nonatomic, strong) UIView *documentsPathCard;

@property (nonatomic, strong) UILabel *versionValueLabel;
@property (nonatomic, strong) UILabel *dataSizeValueLabel;
@property (nonatomic, strong) UILabel *documentsSizeValueLabel;
@property (nonatomic, strong) UILabel *documentsCountValueLabel;
@property (nonatomic, strong) UILabel *lastBackupValueLabel;
@property (nonatomic, strong) UILabel *dataPathValueLabel;
@property (nonatomic, strong) UILabel *documentsPathValueLabel;

@property (nonatomic, strong) AppDataManager *manager;

@property (nonatomic, assign) BOOL isSystemApp;
@property (nonatomic, assign) BOOL operationInProgress;

@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) dispatch_queue_t workerQueue;

/*
 * Every load receives a unique generation.
 *
 * If the user triggers another load before the previous one finishes,
 * an old result must never overwrite the new state.
 */
@property (nonatomic, assign) NSUInteger loadGeneration;

@end

@implementation AppDetailViewController

#pragma mark - Lifecycle

- (instancetype)initWithAppInfo:(NSDictionary *)appInfo
{
    self = [super init];

    if (self) {
        _appInfo = [appInfo copy];
        _manager = [AppDataManager sharedManager];

        _workerQueue = dispatch_queue_create(
            "com.appdatamanager.detailworker",
            DISPATCH_QUEUE_SERIAL
        );

        _loadGeneration = 0;
        _operationInProgress = NO;
        _isSystemApp = NO;
    }

    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"تفاصيل التطبيق";

    self.view.backgroundColor =
        [UIColor colorWithRed:0.02
                        green:0.02
                         blue:0.04
                        alpha:1.0];

    [self setupScrollView];
    [self setupHeader];
    [self setupInfoCards];
    [self setupActionButtons];
    [self setupLoadingView];

    [self loadDataAsync];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];

    /*
     * Invalidate the current load generation.
     *
     * The worker may still finish, but its result will no longer
     * be allowed to update this controller.
     */
    self.loadGeneration++;
}

#pragma mark - UI Setup

- (void)setupScrollView
{
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];

    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.directionalLockEnabled = YES;
    self.scrollView.showsVerticalScrollIndicator = YES;

    [self.view addSubview:self.scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],

        [self.scrollView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],

        [self.scrollView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],

        [self.scrollView.bottomAnchor
            constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.contentView = [[UIView alloc] initWithFrame:CGRectZero];

    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentView.backgroundColor = [UIColor clearColor];

    [self.scrollView addSubview:self.contentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.topAnchor
            constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],

        [self.contentView.leadingAnchor
            constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],

        [self.contentView.trailingAnchor
            constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],

        [self.contentView.bottomAnchor
            constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],

        [self.contentView.widthAnchor
            constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor]
    ]];
}

- (void)setupHeader
{
    self.appIcon = [[UIImageView alloc] initWithFrame:CGRectZero];

    self.appIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.appIcon.layer.cornerRadius = 20.0;
    self.appIcon.layer.masksToBounds = YES;
    self.appIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.appIcon.backgroundColor =
        [UIColor colorWithRed:0.15
                        green:0.15
                         blue:0.18
                        alpha:1.0];

    [self.contentView addSubview:self.appIcon];

    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];

    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLabel.font =
        [UIFont systemFontOfSize:22.0
                           weight:UIFontWeightBold];
    self.nameLabel.textColor = [UIColor whiteColor];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.numberOfLines = 2;
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    [self.contentView addSubview:self.nameLabel];

    self.bundleIDLabel = [[UILabel alloc] initWithFrame:CGRectZero];

    self.bundleIDLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.bundleIDLabel.font =
        [UIFont systemFontOfSize:13.0
                           weight:UIFontWeightRegular];
    self.bundleIDLabel.textColor =
        [UIColor colorWithWhite:0.40 alpha:1.0];
    self.bundleIDLabel.textAlignment = NSTextAlignmentCenter;
    self.bundleIDLabel.numberOfLines = 2;
    self.bundleIDLabel.lineBreakMode =
        NSLineBreakByTruncatingMiddle;

    [self.contentView addSubview:self.bundleIDLabel];

    NSString *name = [self stringValue:self.appInfo[@"name"]
                               fallback:@"Unknown"];

    NSString *bundleID =
        [self stringValue:self.appInfo[@"bundleID"]
                  fallback:@""];

    self.nameLabel.text = name;
    self.bundleIDLabel.text = bundleID;

    [NSLayoutConstraint activateConstraints:@[
        [self.appIcon.topAnchor
            constraintEqualToAnchor:self.contentView.topAnchor
                           constant:20.0],

        [self.appIcon.centerXAnchor
            constraintEqualToAnchor:self.contentView.centerXAnchor],

        [self.appIcon.widthAnchor
            constraintEqualToConstant:80.0],

        [self.appIcon.heightAnchor
            constraintEqualToConstant:80.0],

        [self.nameLabel.topAnchor
            constraintEqualToAnchor:self.appIcon.bottomAnchor
                           constant:12.0],

        [self.nameLabel.leadingAnchor
            constraintEqualToAnchor:self.contentView.leadingAnchor
                           constant:20.0],

        [self.nameLabel.trailingAnchor
            constraintEqualToAnchor:self.contentView.trailingAnchor
                            constant:-20.0],

        [self.bundleIDLabel.topAnchor
            constraintEqualToAnchor:self.nameLabel.bottomAnchor
                           constant:4.0],

        [self.bundleIDLabel.leadingAnchor
            constraintEqualToAnchor:self.nameLabel.leadingAnchor],

        [self.bundleIDLabel.trailingAnchor
            constraintEqualToAnchor:self.nameLabel.trailingAnchor]
    ]];

    [self loadIconAsyncForBundleID:bundleID];
}

- (UIView *)makeCardWithTitle:(NSString *)title
                        value:(NSString *)value
                         icon:(NSString *)iconName
                       topRef:(UIView *)topRef
                   valueLabel:(UILabel **)outValueLabel
{
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];

    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor =
        [UIColor colorWithRed:0.10
                        green:0.10
                         blue:0.13
                        alpha:1.0];

    card.layer.cornerRadius = 14.0;
    card.layer.masksToBounds = YES;

    UIImage *iconImage = nil;

    if (iconName.length > 0) {
        iconImage = [UIImage systemImageNamed:iconName];
    }

    UIImageView *icon =
        [[UIImageView alloc] initWithImage:iconImage];

    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor =
        [UIColor colorWithRed:0.55
                        green:0.45
                         blue:0.95
                        alpha:1.0];
    icon.contentMode = UIViewContentModeScaleAspectFit;

    [card addSubview:icon];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];

    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font =
        [UIFont systemFontOfSize:12.0
                           weight:UIFontWeightMedium];
    titleLabel.textColor =
        [UIColor colorWithWhite:0.45 alpha:1.0];
    titleLabel.text = title ?: @"";
    titleLabel.numberOfLines = 1;
    titleLabel.lineBreakMode =
        NSLineBreakByTruncatingTail;

    [card addSubview:titleLabel];

    UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];

    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    valueLabel.font =
        [UIFont systemFontOfSize:15.0
                           weight:UIFontWeightSemibold];
    valueLabel.textColor = [UIColor whiteColor];
    valueLabel.text = value ?: @"—";
    valueLabel.numberOfLines = 0;
    valueLabel.lineBreakMode = NSLineBreakByCharWrapping;

    [card addSubview:valueLabel];

    if (outValueLabel) {
        *outValueLabel = valueLabel;
    }

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor
            constraintEqualToAnchor:card.leadingAnchor
                           constant:14.0],

        [icon.topAnchor
            constraintEqualToAnchor:card.topAnchor
                           constant:12.0],

        [icon.widthAnchor
            constraintEqualToConstant:22.0],

        [icon.heightAnchor
            constraintEqualToConstant:22.0],

        [titleLabel.leadingAnchor
            constraintEqualToAnchor:icon.trailingAnchor
                           constant:10.0],

        [titleLabel.topAnchor
            constraintEqualToAnchor:card.topAnchor
                           constant:12.0],

        [titleLabel.trailingAnchor
            constraintEqualToAnchor:card.trailingAnchor
                            constant:-14.0],

        [valueLabel.leadingAnchor
            constraintEqualToAnchor:titleLabel.leadingAnchor],

        [valueLabel.topAnchor
            constraintEqualToAnchor:titleLabel.bottomAnchor
                           constant:3.0],

        [valueLabel.trailingAnchor
            constraintEqualToAnchor:titleLabel.trailingAnchor],

        [valueLabel.bottomAnchor
            constraintEqualToAnchor:card.bottomAnchor
                           constant:-12.0]
    ]];

    [self.contentView addSubview:card];

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor
            constraintEqualToAnchor:self.contentView.leadingAnchor
                           constant:16.0],

        [card.trailingAnchor
            constraintEqualToAnchor:self.contentView.trailingAnchor
                            constant:-16.0],

        [card.topAnchor
            constraintEqualToAnchor:topRef.bottomAnchor
                           constant:10.0]
    ]];

    return card;
}

- (void)setupInfoCards
{
    UIView *ref = self.bundleIDLabel;

    self.versionCard =
        [self makeCardWithTitle:@"الإصدار"
                          value:@"جاري القراءة..."
                           icon:@"number"
                         topRef:ref
                     valueLabel:&_versionValueLabel];

    self.dataSizeCard =
        [self makeCardWithTitle:@"حجم البيانات"
                          value:@"جاري الحساب..."
                           icon:@"externaldrive.fill"
                         topRef:self.versionCard
                     valueLabel:&_dataSizeValueLabel];

    self.documentsSizeCard =
        [self makeCardWithTitle:@"حجم المستندات"
                          value:@"جاري الحساب..."
                           icon:@"doc.fill"
                         topRef:self.dataSizeCard
                     valueLabel:&_documentsSizeValueLabel];

    self.documentsCountCard =
        [self makeCardWithTitle:@"عدد الملفات"
                          value:@"جاري الحساب..."
                           icon:@"folder.fill"
                         topRef:self.documentsSizeCard
                     valueLabel:&_documentsCountValueLabel];

    self.lastBackupCard =
        [self makeCardWithTitle:@"آخر نسخة احتياطية"
                          value:@"جاري القراءة..."
                           icon:@"clock.fill"
                         topRef:self.documentsCountCard
                     valueLabel:&_lastBackupValueLabel];

    self.dataPathCard =
        [self makeCardWithTitle:@"مسار البيانات"
                          value:@"جاري القراءة..."
                           icon:@"arrow.right.doc.fill"
                         topRef:self.lastBackupCard
                     valueLabel:&_dataPathValueLabel];

    self.documentsPathCard =
        [self makeCardWithTitle:@"مسار المستندات"
                          value:@"جاري القراءة..."
                           icon:@"doc.text.fill"
                         topRef:self.dataPathCard
                     valueLabel:&_documentsPathValueLabel];
}

- (void)setupActionButtons
{
    UIButton *wipeBtn =
        [self makeActionButtonWithTitle:@"مسح البيانات"
                                  color:[UIColor colorWithRed:0.85
                                                         green:0.20
                                                          blue:0.20
                                                         alpha:1.0]
                                 action:@selector(wipeTapped)];

    UIButton *backupBtn =
        [self makeActionButtonWithTitle:@"نسخ احتياطي"
                                  color:[UIColor colorWithRed:0.20
                                                         green:0.55
                                                          blue:0.85
                                                         alpha:1.0]
                                 action:@selector(backupTapped)];

    UIButton *manageBtn =
        [self makeActionButtonWithTitle:@"إدارة النسخ"
                                  color:[UIColor colorWithRed:0.55
                                                         green:0.45
                                                          blue:0.95
                                                         alpha:1.0]
                                 action:@selector(manageBackupsTapped)];

    [self.contentView addSubview:wipeBtn];
    [self.contentView addSubview:backupBtn];
    [self.contentView addSubview:manageBtn];

    UIView *lastRef = self.documentsPathCard;

    [NSLayoutConstraint activateConstraints:@[
        [wipeBtn.topAnchor
            constraintEqualToAnchor:lastRef.bottomAnchor
                           constant:20.0],

        [wipeBtn.leadingAnchor
            constraintEqualToAnchor:self.contentView.leadingAnchor
                           constant:16.0],

        [wipeBtn.trailingAnchor
            constraintEqualToAnchor:self.contentView.trailingAnchor
                            constant:-16.0],

        [wipeBtn.heightAnchor
            constraintEqualToConstant:50.0],

        [backupBtn.topAnchor
            constraintEqualToAnchor:wipeBtn.bottomAnchor
                           constant:10.0],

        [backupBtn.leadingAnchor
            constraintEqualToAnchor:wipeBtn.leadingAnchor],

        [backupBtn.trailingAnchor
            constraintEqualToAnchor:wipeBtn.trailingAnchor],

        [backupBtn.heightAnchor
            constraintEqualToConstant:50.0],

        [manageBtn.topAnchor
            constraintEqualToAnchor:backupBtn.bottomAnchor
                           constant:10.0],

        [manageBtn.leadingAnchor
            constraintEqualToAnchor:wipeBtn.leadingAnchor],

        [manageBtn.trailingAnchor
            constraintEqualToAnchor:wipeBtn.trailingAnchor],

        [manageBtn.heightAnchor
            constraintEqualToConstant:50.0],

        [manageBtn.bottomAnchor
            constraintEqualToAnchor:self.contentView.bottomAnchor
                           constant:-30.0]
    ]];
}

- (UIButton *)makeActionButtonWithTitle:(NSString *)title
                                  color:(UIColor *)color
                                 action:(SEL)action
{
    UIButton *button =
        [UIButton buttonWithType:UIButtonTypeSystem];

    button.translatesAutoresizingMaskIntoConstraints = NO;

    [button setTitle:title ?: @""
            forState:UIControlStateNormal];

    [button setTitleColor:[UIColor whiteColor]
                 forState:UIControlStateNormal];

    button.backgroundColor = color;

    button.layer.cornerRadius = 12.0;
    button.layer.masksToBounds = YES;

    button.titleLabel.font =
        [UIFont systemFontOfSize:16.0
                           weight:UIFontWeightSemibold];

    [button addTarget:self
               action:action
     forControlEvents:UIControlEventTouchUpInside];

    return button;
}

- (void)setupLoadingView
{
    self.loadingIndicator =
        [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:
                UIActivityIndicatorViewStyleLarge];

    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.hidesWhenStopped = YES;
    self.loadingIndicator.color =
        [UIColor colorWithRed:0.55
                        green:0.45
                         blue:0.95
                        alpha:1.0];

    [self.view addSubview:self.loadingIndicator];

    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.centerXAnchor
            constraintEqualToAnchor:self.view.centerXAnchor],

        [self.loadingIndicator.centerYAnchor
            constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

#pragma mark - Icon Loading

- (void)loadIconAsyncForBundleID:(NSString *)bundleID
{
    if (bundleID.length == 0) {
        [self applyFallbackIcon];
        return;
    }

    __weak typeof(self) weakSelf = self;

    dispatch_async(self.workerQueue, ^{
        @autoreleasepool {
            __strong typeof(weakSelf) strongSelf = weakSelf;

            if (!strongSelf) return;

            UIImage *icon = nil;

            @try {
                icon = [strongSelf.manager iconForBundleID:bundleID];
            }
            @catch (NSException *exception) {
                icon = nil;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;

                if (!self) return;

                if (icon) {
                    self.appIcon.image = icon;
                    self.appIcon.tintColor = nil;
                } else {
                    [self applyFallbackIcon];
                }
            });
        }
    });
}

- (void)applyFallbackIcon
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyFallbackIcon];
        });
        return;
    }

    UIImage *image =
        [UIImage systemImageNamed:@"app.fill"];

    self.appIcon.image = image;
    self.appIcon.tintColor =
        [UIColor colorWithRed:0.55
                        green:0.45
                         blue:0.95
                        alpha:1.0];
}

#pragma mark - Data Loading

- (void)loadDataAsync
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self loadDataAsync];
        });
        return;
    }

    NSString *bundleID =
        [self stringValue:self.appInfo[@"bundleID"]
                  fallback:@""];

    if (bundleID.length == 0) {
        [self.loadingIndicator stopAnimating];

        [self updateAllCardsForInvalidApplication];

        return;
    }

    NSUInteger generation = ++self.loadGeneration;

    [self.loadingIndicator startAnimating];

    __weak typeof(self) weakSelf = self;

    dispatch_async(self.workerQueue, ^{
        @autoreleasepool {
            __strong typeof(weakSelf) strongSelf = weakSelf;

            if (!strongSelf) return;

            NSString *version = @"1.0";
            unsigned long long dataSize = 0;
            unsigned long long documentsSize = 0;
            NSUInteger documentsCount = 0;

            NSString *dataPath = nil;
            NSString *documentsPath = nil;

            NSDate *lastBackup = nil;
            BOOL isSystem = NO;

            /*
             * Every manager call is isolated.
             * A failure in one metric must not prevent the others
             * from being collected.
             */

            @try {
                NSString *value =
                    [strongSelf.manager versionForBundleID:bundleID];

                if ([value isKindOfClass:[NSString class]] &&
                    value.length > 0) {
                    version = value;
                }
            }
            @catch (NSException *exception) {
                version = @"غير متاح";
            }

            @try {
                dataSize =
                    [strongSelf.manager
                        dataSizeForBundleID:bundleID];
            }
            @catch (NSException *exception) {
                dataSize = 0;
            }

            @try {
                dataPath =
                    [strongSelf.manager
                        dataPathForBundleID:bundleID];
            }
            @catch (NSException *exception) {
                dataPath = nil;
            }

            @try {
                documentsPath =
                    [strongSelf.manager
                        documentsPathForBundleID:bundleID];
            }
            @catch (NSException *exception) {
                documentsPath = nil;
            }

            /*
             * Documents count.
             */
            @try {
                documentsCount =
                    [strongSelf.manager
                        documentsCountForBundleID:bundleID];
            }
            @catch (NSException *exception) {
                documentsCount = 0;
            }

            /*
             * IMPORTANT:
             *
             * Do not use accurateDataSizeForBundleID here.
             * That method represents application data, not Documents.
             *
             * Documents size must be calculated from Documents itself.
             */
            if (documentsPath.length > 0) {
                documentsSize =
                    [strongSelf directorySizeAtPath:documentsPath];
            }

            @try {
                lastBackup =
                    [strongSelf.manager
                        lastBackupDateForBundleID:bundleID];
            }
            @catch (NSException *exception) {
                lastBackup = nil;
            }

            @try {
                isSystem =
                    [strongSelf.manager
                        isSystemApp:bundleID];
            }
            @catch (NSException *exception) {
                /*
                 * Fail closed for destructive UI.
                 *
                 * If classification fails, the app must not be
                 * treated as a normal user application.
                 */
                isSystem = YES;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;

                if (!self) return;

                /*
                 * Ignore stale results.
                 */
                if (generation != self.loadGeneration) {
                    return;
                }

                [self.loadingIndicator stopAnimating];

                self.isSystemApp = isSystem;

                [self updateCardValueLabel:self.versionValueLabel
                                     value:version];

                [self updateCardValueLabel:self.dataSizeValueLabel
                                     value:[self.manager
                                                formatBytes:dataSize]];

                [self updateCardValueLabel:
                          self.documentsSizeValueLabel
                                     value:[self.manager
                                                formatBytes:documentsSize]];

                [self updateCardValueLabel:
                          self.documentsCountValueLabel
                                     value:[NSString stringWithFormat:
                                                @"%lu",
                                                (unsigned long)documentsCount]];

                NSDateFormatter *formatter =
                    [[NSDateFormatter alloc] init];

                formatter.locale =
                    [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

                formatter.dateFormat =
                    @"yyyy-MM-dd HH:mm";

                NSString *backupText =
                    lastBackup
                        ? [formatter stringFromDate:lastBackup]
                        : @"لا توجد";

                [self updateCardValueLabel:
                          self.lastBackupValueLabel
                                     value:backupText];

                [self updateCardValueLabel:
                          self.dataPathValueLabel
                                     value:dataPath.length > 0
                                          ? dataPath
                                          : @"غير متاح"];

                [self updateCardValueLabel:
                          self.documentsPathValueLabel
                                     value:documentsPath.length > 0
                                          ? documentsPath
                                          : @"غير متاح"];

                /*
                 * If the app is a system application, keep the
                 * destructive button visibly disabled.
                 */
                [self updateWipeButtonState];
            });
        }
    });
}

- (void)updateAllCardsForInvalidApplication
{
    [self updateCardValueLabel:self.versionValueLabel
                         value:@"غير متاح"];

    [self updateCardValueLabel:self.dataSizeValueLabel
                         value:@"غير متاح"];

    [self updateCardValueLabel:self.documentsSizeValueLabel
                         value:@"غير متاح"];

    [self updateCardValueLabel:self.documentsCountValueLabel
                         value:@"غير متاح"];

    [self updateCardValueLabel:self.lastBackupValueLabel
                         value:@"غير متاح"];

    [self updateCardValueLabel:self.dataPathValueLabel
                         value:@"غير متاح"];

    [self updateCardValueLabel:self.documentsPathValueLabel
                         value:@"غير متاح"];
}

#pragma mark - Safe Directory Size

- (unsigned long long)directorySizeAtPath:(NSString *)path
{
    if (path.length == 0) return 0;

    NSFileManager *fileManager =
        [NSFileManager defaultManager];

    if (![fileManager fileExistsAtPath:path]) {
        return 0;
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
                    NSURLIsRegularFileKey,
                    NSURLIsSymbolicLinkKey,
                    NSURLFileSizeKey
                ]
                options:0
                errorHandler:^BOOL(NSURL *url, NSError *error) {
                    /*
                     * Skip inaccessible entries and continue.
                     */
                    return YES;
                }];

        NSMutableSet *visitedInodes =
            [NSMutableSet set];

        NSUInteger processedFiles = 0;

        for (NSURL *fileURL in enumerator) {
            @autoreleasepool {
                @try {
                    NSNumber *isDirectory = nil;
                    NSNumber *isRegularFile = nil;
                    NSNumber *isSymlink = nil;

                    [fileURL getResourceValue:&isDirectory
                                       forKey:NSURLIsDirectoryKey
                                        error:nil];

                    [fileURL getResourceValue:&isRegularFile
                                       forKey:NSURLIsRegularFileKey
                                        error:nil];

                    [fileURL getResourceValue:&isSymlink
                                       forKey:NSURLIsSymbolicLinkKey
                                        error:nil];

                    if ([isSymlink boolValue]) {
                        continue;
                    }

                    if (![isRegularFile boolValue]) {
                        continue;
                    }

                    const char *filePath =
                        [fileURL.path fileSystemRepresentation];

                    if (!filePath) {
                        continue;
                    }

                    struct stat st;

                    if (lstat(filePath, &st) != 0) {
                        continue;
                    }

                    if (!S_ISREG(st.st_mode)) {
                        continue;
                    }

                    NSString *inodeKey =
                        [NSString stringWithFormat:
                           :@"%llu:%llu",
                            (unsigned long long)st.st_dev,
                            (unsigned long long)st.st_ino];

                    if ([visitedInodes containsObject:inodeKey]) {
                        continue;
                    }

                    [visitedInodes addObject:inodeKey];

                    total +=
                        (unsigned long long)st.st_size;

                    processedFiles++;

                    /*
                     * Give the system a tiny opportunity to schedule
                     * other work on very large Documents directories.
                     */
                    if ((processedFiles % 1000) == 0) {
                        [NSThread
                            sleepForTimeInterval:0.001];
                    }
                }
                @catch (NSException *exception) {
                    continue;
                }
            }
        }
    }
    @catch (NSException *exception) {
        return total;
    }

    return total;
}

#pragma mark - Card Updates

- (void)updateCardValueLabel:(UILabel *)label
                       value:(NSString *)value
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateCardValueLabel:label
                                 value:value];
        });

        return;
    }

    if (!label) return;

    label.text =
        (value.length > 0)
            ? value
            : @"—";
}

#pragma mark - Actions

- (void)wipeTapped
{
    if (self.operationInProgress) {
        return;
    }

    if (self.isSystemApp) {
        [self showAlert:@"لا يمكن مسح بيانات التطبيقات النظامية"];
        return;
    }

    NSString *bundleID =
        [self stringValue:self.appInfo[@"bundleID"]
                  fallback:@""];

    if (bundleID.length == 0) {
        [self showAlert:@"تعذر تحديد التطبيق"];
        return;
    }

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:@"تأكيد"
                             message:@"هل أنت متأكد من مسح بيانات التطبيق؟"
                      preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"إلغاء"
                      style:UIAlertActionStyleCancel
                    handler:nil]];

    __weak typeof(self) weakSelf = self;

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"مسح"
                      style:UIAlertActionStyleDestructive
                    handler:^(UIAlertAction *action) {

        __strong typeof(weakSelf) self = weakSelf;

        if (!self) return;

        [self performWipeForBundleID:bundleID];
    }]];

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

- (void)performWipeForBundleID:(NSString *)bundleID
{
    if (self.operationInProgress) {
        return;
    }

    if (bundleID.length == 0) {
        [self showAlert:@"تعذر تحديد التطبيق"];
        return;
    }

    if (self.isSystemApp) {
        [self showAlert:@"لا يمكن مسح بيانات التطبيقات النظامية"];
        return;
    }

    self.operationInProgress = YES;

    [self setLoading:YES];

    __weak typeof(self) weakSelf = self;

    dispatch_async(self.workerQueue, ^{
        @autoreleasepool {
            __strong typeof(weakSelf) strongSelf = weakSelf;

            if (!strongSelf) return;

            BOOL success = NO;

            @try {
                success =
                    [strongSelf.manager
                        wipeAppData:bundleID];
            }
            @catch (NSException *exception) {
                success = NO;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;

                if (!self) return;

                self.operationInProgress = NO;

                [self setLoading:NO];

                if (success) {
                    [self showAlert:@"تم مسح البيانات بنجاح"];

                    /*
                     * Reload after the alert has been presented.
                     * The manager's cache should already have been
                     * invalidated by the wipe operation.
                     */
                    [self loadDataAsync];
                } else {
                    [self showAlert:@"فشل مسح البيانات"];
                }
            });
        }
    });
}

- (void)backupTapped
{
    if (self.operationInProgress) {
        return;
    }

    NSString *bundleID =
        [self stringValue:self.appInfo[@"bundleID"]
                  fallback:@""];

    if (bundleID.length == 0) {
        [self showAlert:@"تعذر تحديد التطبيق"];
        return;
    }

    self.operationInProgress = YES;

    [self setLoading:YES];

    __weak typeof(self) weakSelf = self;

    dispatch_async(self.workerQueue, ^{
        @autoreleasepool {
            __strong typeof(weakSelf) strongSelf = weakSelf;

            if (!strongSelf) return;

            BOOL success = NO;

            @try {
                success =
                    [strongSelf.manager
                        backupAppData:bundleID];
            }
            @catch (NSException *exception) {
                success = NO;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;

                if (!self) return;

                self.operationInProgress = NO;

                [self setLoading:NO];

                if (success) {
                    [self showAlert:@"تم إنشاء النسخة الاحتياطية"];

                    [self loadDataAsync];
                } else {
                    [self showAlert:@"فشل إنشاء النسخة الاحتياطية"];
                }
            });
        }
    });
}

- (void)manageBackupsTapped
{
    if (self.operationInProgress) {
        return;
    }

    BackupManagerViewController *vc =
        [[BackupManagerViewController alloc] init];

    if (!vc) {
        [self showAlert:@"تعذر فتح إدارة النسخ"];
        return;
    }

    if (!self.navigationController) {
        [self showAlert:@"تعذر فتح إدارة النسخ"];
        return;
    }

    [self.navigationController
        pushViewController:vc
                  animated:YES];
}

#pragma mark - Loading State

- (void)setLoading:(BOOL)loading
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setLoading:loading];
        });

        return;
    }

    if (loading) {
        [self.loadingIndicator startAnimating];
    } else {
        [self.loadingIndicator stopAnimating];
    }

    [self updateWipeButtonState];
}

- (void)updateWipeButtonState
{
    /*
     * Find the first action button matching "مسح البيانات".
     */
    for (UIView *subview in self.contentView.subviews) {
        if (![subview isKindOfClass:[UIButton class]]) {
            continue;
        }

        UIButton *button = (UIButton *)subview;

        NSString *title =
            [button titleForState:UIControlStateNormal];

        if ([title isEqualToString:@"مسح البيانات"]) {
            BOOL disabled =
                self.isSystemApp ||
                self.operationInProgress;

            button.enabled = !disabled;
            button.alpha = disabled ? 0.45 : 1.0;

            break;
        }
    }
}

#pragma mark - Alerts

- (void)showAlert:(NSString *)message
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showAlert:message];
        });

        return;
    }

    if (!self.viewIfLoaded.window &&
        !self.presentedViewController) {
        /*
         * Controller is not currently visible.
         * Do not attempt to present UI into a detached hierarchy.
         */
        return;
    }

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:@""
                             message:message ?: @"حدث خطأ"
                      preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"موافق"
                      style:UIAlertActionStyleDefault
                    handler:nil]];

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

#pragma mark - Helpers

- (NSString *)stringValue:(id)value
                  fallback:(NSString *)fallback
{
    if ([value isKindOfClass:[NSString class]]) {
        NSString *string = (NSString *)value;

        if (string.length > 0) {
            return string;
        }
    }

    return fallback ?: @"";
}

@end
