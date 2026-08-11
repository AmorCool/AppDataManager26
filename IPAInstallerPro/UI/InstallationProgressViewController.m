#import "InstallationProgressViewController.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import "Core/InstallationEngine.h"
#import "Core/Logger.h"

@interface InstallationProgressViewController ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *stageLabel;
@property (nonatomic, strong) UILabel *providerLabel;
@property (nonatomic, strong) UIButton *doneButton;
@property (nonatomic, strong) UIButton *openAppButton;
@property (nonatomic, strong) UIView *spinnerView;
@property (nonatomic, strong) UIImageView *statusIcon;
@property (nonatomic, assign) BOOL isDone;
@property (nonatomic, strong) NSString *installedBundleID;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UIView *logContainer;
@end

@implementation InstallationProgressViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    self.isDone = NO;

    [self setupViews];
    [self startInstallation];
}

- (void)setupViews {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat margin = 24;

    // Status icon (center top)
    self.statusIcon = [[UIImageView alloc] initWithFrame:CGRectMake((w - 70) / 2, 60, 70, 70)];
    self.statusIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.statusIcon.tintColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    self.statusIcon.image = [[UIImage systemImageNamed:@"arrow.down.circle.fill"] imageWithTintColor:[UIColor colorWithWhite:0.3 alpha:1.0]];
    [self.view addSubview:self.statusIcon];

    // Title
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, 145, w - margin * 2, 30)];
    self.titleLabel.text = self.ipaName ?: @"تثبيت التطبيق";
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.titleLabel];

    // Provider label
    self.providerLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, 180, w - margin * 2, 18)];
    self.providerLabel.text = @"جاري اختيار أفضل طريقة تثبيت...";
    self.providerLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    self.providerLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.providerLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.providerLabel];

    // Stage label
    self.stageLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, 210, w - margin * 2, 22)];
    self.stageLabel.text = @"في الانتظار...";
    self.stageLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    self.stageLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.stageLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.stageLabel];

    // Progress bar
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.frame = CGRectMake(margin, 245, w - margin * 2, 4);
    self.progressView.progressTintColor = [UIColor colorWithRed:0.35 green:0.65 blue:0.95 alpha:1.0];
    self.progressView.trackTintColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.progressView.layer.cornerRadius = 2;
    self.progressView.clipsToBounds = YES;
    [self.view addSubview:self.progressView];

    // Status detail
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, 260, w - margin * 2, 18)];
    self.statusLabel.text = @"جاري التجهيز...";
    self.statusLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    self.statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.statusLabel];

    // Detail label (for short error messages)
    self.detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, 285, w - margin * 2, 40)];
    self.detailLabel.text = @"";
    self.detailLabel.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    self.detailLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    self.detailLabel.textAlignment = NSTextAlignmentCenter;
    self.detailLabel.numberOfLines = 2;
    [self.view addSubview:self.detailLabel];

    // === LOGS CONTAINER ===
    CGFloat logTop = 340;
    CGFloat logHeight = h - logTop - 160;

    self.logContainer = [[UIView alloc] initWithFrame:CGRectMake(margin, logTop, w - margin * 2, logHeight)];
    self.logContainer.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.09 alpha:1.0];
    self.logContainer.layer.cornerRadius = 14;
    self.logContainer.layer.masksToBounds = YES;
    self.logContainer.layer.borderWidth = 1;
    self.logContainer.layer.borderColor = [UIColor colorWithWhite:0.1 alpha:1.0].CGColor;
    [self.view addSubview:self.logContainer];

    // Log header
    UILabel *logHeader = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, 200, 18)];
    logHeader.text = @"📋 سجل العملية";
    logHeader.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    logHeader.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    [self.logContainer addSubview:logHeader];

    // Log text view
    self.logTextView = [[UITextView alloc] initWithFrame:CGRectMake(8, 28, self.logContainer.bounds.size.width - 16, self.logContainer.bounds.size.height - 36)];
    self.logTextView.backgroundColor = [UIColor clearColor];
    self.logTextView.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    self.logTextView.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    self.logTextView.editable = NO;
    self.logTextView.selectable = YES;
    self.logTextView.showsVerticalScrollIndicator = YES;
    self.logTextView.textAlignment = NSTextAlignmentRight; // RTL for Arabic
    self.logTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.logContainer addSubview:self.logTextView];

    // Spinner
    self.spinnerView = [[UIView alloc] initWithFrame:CGRectMake((w - 40) / 2, logTop + logHeight + 10, 40, 40)];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.color = [UIColor colorWithWhite:0.5 alpha:1.0];
    spinner.center = CGPointMake(20, 20);
    [spinner startAnimating];
    [self.spinnerView addSubview:spinner];
    [self.view addSubview:self.spinnerView];

    // Done button (hidden initially)
    self.doneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.doneButton.frame = CGRectMake(margin, h - 100, w - margin * 2, 50);
    [self.doneButton setTitle:@"تم" forState:UIControlStateNormal];
    [self.doneButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.doneButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.doneButton.backgroundColor = [UIColor colorWithRed:0.35 green:0.65 blue:0.95 alpha:1.0];
    self.doneButton.layer.cornerRadius = 14;
    self.doneButton.hidden = YES;
    [self.doneButton addTarget:self action:@selector(doneTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.doneButton];

    // Open App button (hidden initially)
    self.openAppButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.openAppButton.frame = CGRectMake(margin, h - 160, w - margin * 2, 50);
    [self.openAppButton setTitle:@"فتح التطبيق" forState:UIControlStateNormal];
    [self.openAppButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.openAppButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.openAppButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.7 blue:0.5 alpha:1.0];
    self.openAppButton.layer.cornerRadius = 14;
    self.openAppButton.hidden = YES;
    [self.openAppButton addTarget:self action:@selector(openAppTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.openAppButton];
}

- (void)appendLog:(NSString *)text {
    if (!text || text.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *current = self.logTextView.text ?: @"";
        self.logTextView.text = [current stringByAppendingFormat:@"%@\n", text];
        // Auto-scroll to bottom
        if (self.logTextView.text.length > 0) {
            NSRange bottom = NSMakeRange(self.logTextView.text.length - 1, 1);
            [self.logTextView scrollRangeToVisible:bottom];
        }
    });
}

- (void)startInstallation {
    if (!self.ipaPath) {
        [self showError:@"مسار IPA غير صالح" detail:@"لم يتم تحديد ملف IPA للتثبيت"];
        return;
    }

    [self appendLog:@"🚀 بدء عملية التثبيت..."];

    [[InstallationEngine sharedEngine] installIPA:self.ipaPath
     progressBlock:^(InstallationStage stage, NSString *statusMessage, float progress) {
        self.stageLabel.text = statusMessage;
        self.statusLabel.text = [[InstallationEngine sharedEngine] stageDescription:stage];
        [self.progressView setProgress:progress animated:YES];

        if (stage == InstallationStageInstalling) {
            self.providerLabel.text = @"جاري التثبيت...";
            [self appendLog:[NSString stringWithFormat:@"⏳ %@", statusMessage]];
        } else if (stage == InstallationStageRegistering) {
            self.providerLabel.text = @"جاري تسجيل التطبيق...";
            [self appendLog:[NSString stringWithFormat:@"📝 %@", statusMessage]];
        } else if (stage == InstallationStageValidating) {
            [self appendLog:[NSString stringWithFormat:@"🔍 %@", statusMessage]];
        } else if (stage == InstallationStagePreparing) {
            [self appendLog:[NSString stringWithFormat:@"📦 %@", statusMessage]];
        }

        if (stage == InstallationStageCompleted) {
            [self showSuccess];
        } else if (stage == InstallationStageFailed) {
            [self showError:statusMessage detail:@""];
        }
    }
     completion:^(InstallationResult *result) {
        self.isDone = YES;
        if (result.success) {
            self.installedBundleID = result.bundleID;
            [self showSuccess];
            [self appendLog:@"✅ تم التثبيت بنجاح!"];
        } else {
            NSString *detail = result.detailedOutput ?: @"";
            if (detail.length > 0) {
                [self appendLog:@"---"];
                [self appendLog:detail];
            }
            [self showError:result.message detail:detail];
        }
    }];
}

- (void)showSuccess {
    self.stageLabel.text = @"تم التثبيت بنجاح ✓";
    self.stageLabel.textColor = [UIColor colorWithRed:0.3 green:0.8 blue:0.5 alpha:1.0];
    self.statusLabel.text = @"يمكنك الآن فتح التطبيق";
    self.providerLabel.text = @"اكتملت العملية";
    self.spinnerView.hidden = YES;
    self.doneButton.hidden = NO;
    self.openAppButton.hidden = (self.installedBundleID.length == 0);
    [self.progressView setProgress:1.0 animated:YES];

    self.statusIcon.image = [[UIImage systemImageNamed:@"checkmark.circle.fill"] imageWithTintColor:[UIColor colorWithRed:0.3 green:0.8 blue:0.5 alpha:1.0]];
}

- (void)showError:(NSString *)message detail:(NSString *)detail {
    self.stageLabel.text = @"فشل التثبيت ✗";
    self.stageLabel.textColor = [UIColor colorWithRed:0.9 green:0.35 blue:0.3 alpha:1.0];
    self.statusLabel.text = message ?: @"حدث خطأ غير متوقع";
    self.providerLabel.text = @"لم يكتمل التثبيت";
    self.detailLabel.text = detail.length > 100 ? [detail substringToIndex:100] : detail;
    self.spinnerView.hidden = YES;
    self.doneButton.hidden = NO;
    self.openAppButton.hidden = YES;
    [self.doneButton setTitle:@"إغلاق" forState:UIControlStateNormal];
    self.doneButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.3 blue:0.3 alpha:1.0];
    [self.progressView setProgress:1.0 animated:YES];

    self.statusIcon.image = [[UIImage systemImageNamed:@"xmark.circle.fill"] imageWithTintColor:[UIColor colorWithRed:0.9 green:0.35 blue:0.3 alpha:1.0]];
}

- (void)doneTapped:(UIButton *)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)openAppTapped:(UIButton *)sender {
    if (self.installedBundleID.length > 0) {
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", self.installedBundleID]];
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        } else {
            Class LSApplicationWorkspace_class = objc_getClass("LSApplicationWorkspace");
            if (LSApplicationWorkspace_class) {
                id workspace = [LSApplicationWorkspace_class performSelector:@selector(defaultWorkspace)];
                if ([workspace respondsToSelector:@selector(openApplicationWithBundleID:)]) {
                    [workspace performSelector:@selector(openApplicationWithBundleID:) withObject:self.installedBundleID];
                }
            }
        }
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
