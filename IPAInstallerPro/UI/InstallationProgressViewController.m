#import "InstallationProgressViewController.h"
#import <objc/runtime.h>
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
    self.statusIcon = [[UIImageView alloc] initWithFrame:CGRectMake((w - 80) / 2, 80, 80, 80)];
    self.statusIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.statusIcon.tintColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    self.statusIcon.image = [[UIImage systemImageNamed:@"arrow.down.circle.fill"] imageWithTintColor:[UIColor colorWithWhite:0.3 alpha:1.0]];
    [self.view addSubview:self.statusIcon];

    // Title
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, 180, w - margin * 2, 32)];
    self.titleLabel.text = self.ipaName ?: @"تثبيت التطبيق";
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.titleLabel];

    // Provider label
    self.providerLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, 218, w - margin * 2, 20)];
    self.providerLabel.text = @"جاري اختيار أفضل طريقة تثبيت...";
    self.providerLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    self.providerLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.providerLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.providerLabel];

    // Stage label
    self.stageLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, 260, w - margin * 2, 24)];
    self.stageLabel.text = @"في الانتظار...";
    self.stageLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    self.stageLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.stageLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.stageLabel];

    // Progress bar
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.frame = CGRectMake(margin, 300, w - margin * 2, 6);
    self.progressView.progressTintColor = [UIColor colorWithRed:0.35 green:0.65 blue:0.95 alpha:1.0];
    self.progressView.trackTintColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.progressView.layer.cornerRadius = 3;
    self.progressView.clipsToBounds = YES;
    [self.view addSubview:self.progressView];

    // Status detail
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, 320, w - margin * 2, 20)];
    self.statusLabel.text = @"جاري التجهيز...";
    self.statusLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    self.statusLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.statusLabel];

    // Detail label (for error messages or extra info)
    self.detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, 360, w - margin * 2, 60)];
    self.detailLabel.text = @"";
    self.detailLabel.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    self.detailLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    self.detailLabel.textAlignment = NSTextAlignmentCenter;
    self.detailLabel.numberOfLines = 3;
    [self.view addSubview:self.detailLabel];

    // Spinner
    self.spinnerView = [[UIView alloc] initWithFrame:CGRectMake((w - 50) / 2, 440, 50, 50)];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.color = [UIColor colorWithWhite:0.5 alpha:1.0];
    spinner.center = CGPointMake(25, 25);
    [spinner startAnimating];
    [self.spinnerView addSubview:spinner];
    [self.view addSubview:self.spinnerView];

    // Done button (hidden initially)
    self.doneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.doneButton.frame = CGRectMake(margin, h - 180, w - margin * 2, 54);
    [self.doneButton setTitle:@"تم" forState:UIControlStateNormal];
    [self.doneButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.doneButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.doneButton.backgroundColor = [UIColor colorWithRed:0.35 green:0.65 blue:0.95 alpha:1.0];
    self.doneButton.layer.cornerRadius = 14;
    self.doneButton.hidden = YES;
    [self.doneButton addTarget:self action:@selector(doneTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.doneButton];

    // Open App button (hidden initially)
    self.openAppButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.openAppButton.frame = CGRectMake(margin, h - 110, w - margin * 2, 54);
    [self.openAppButton setTitle:@"فتح التطبيق" forState:UIControlStateNormal];
    [self.openAppButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.openAppButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.openAppButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.7 blue:0.5 alpha:1.0];
    self.openAppButton.layer.cornerRadius = 14;
    self.openAppButton.hidden = YES;
    [self.openAppButton addTarget:self action:@selector(openAppTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.openAppButton];
}

- (void)startInstallation {
    if (!self.ipaPath) {
        [self showError:@"مسار IPA غير صالح" detail:@"لم يتم تحديد ملف IPA للتثبيت"];
        return;
    }

    [[InstallationEngine sharedEngine] installIPA:self.ipaPath
      progressBlock:^(InstallationStage stage, NSString *statusMessage, float progress) {
          self.stageLabel.text = statusMessage;
          self.statusLabel.text = [[InstallationEngine sharedEngine] stageDescription:stage];
          [self.progressView setProgress:progress animated:YES];

          // Update provider label based on stage
          if (stage == InstallationStageInstalling) {
              self.providerLabel.text = @"جاري التثبيت...";
          } else if (stage == InstallationStageRegistering) {
              self.providerLabel.text = @"جاري تسجيل التطبيق في النظام...";
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
           } else {
               NSString *detail = result.detailedOutput ?: @"";
               if (detail.length > 200) {
                   detail = [detail substringToIndex:200];
               }
               [self showError:result.message detail:detail];
           }
       }];
}

- (void)showSuccess {
    self.stageLabel.text = @"تم التثبيت بنجاح ✓";
    self.stageLabel.textColor = [UIColor colorWithRed:0.3 green:0.8 blue:0.5 alpha:1.0];
    self.statusLabel.text = @"يمكنك الآن فتح التطبيق من الشاشة الرئيسية";
    self.providerLabel.text = @"اكتملت عملية التثبيت";
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
    self.detailLabel.text = detail;
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
            // Try using LSApplicationWorkspace to open
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
