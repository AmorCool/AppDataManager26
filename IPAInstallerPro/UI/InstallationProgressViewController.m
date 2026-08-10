#import "InstallationProgressViewController.h"
#import "Core/InstallationEngine.h"
#import "Core/Logger.h"

@interface InstallationProgressViewController ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *stageLabel;
@property (nonatomic, strong) UIButton *doneButton;
@property (nonatomic, strong) UIView *spinnerView;
@property (nonatomic, assign) BOOL isDone;
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

    // Title
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, h / 2 - 140, w - 40, 30)];
    self.titleLabel.text = self.ipaName ?: @"تثبيت التطبيق";
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.titleLabel];

    // Stage label
    self.stageLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, h / 2 - 80, w - 40, 22)];
    self.stageLabel.text = @"جاري التجهيز...";
    self.stageLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    self.stageLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.stageLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.stageLabel];

    // Progress
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.frame = CGRectMake(40, h / 2 - 30, w - 80, 4);
    self.progressView.progressTintColor = [UIColor colorWithRed:0.55 green:0.45 blue:0.95 alpha:1.0];
    self.progressView.trackTintColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.progressView.layer.cornerRadius = 2;
    self.progressView.clipsToBounds = YES;
    [self.view addSubview:self.progressView];

    // Status
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, h / 2 + 10, w - 40, 22)];
    self.statusLabel.text = @"في الانتظار...";
    self.statusLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    self.statusLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.statusLabel];

    // Spinner
    self.spinnerView = [[UIView alloc] initWithFrame:CGRectMake((w - 40) / 2, h / 2 + 60, 40, 40)];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.color = [UIColor colorWithWhite:0.6 alpha:1.0];
    spinner.center = CGPointMake(20, 20);
    [spinner startAnimating];
    [self.spinnerView addSubview:spinner];
    [self.view addSubview:self.spinnerView];

    // Done button (hidden initially)
    self.doneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.doneButton.frame = CGRectMake(40, h / 2 + 120, w - 80, 52);
    [self.doneButton setTitle:@"تم" forState:UIControlStateNormal];
    [self.doneButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.doneButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.doneButton.backgroundColor = [UIColor colorWithRed:0.55 green:0.45 blue:0.95 alpha:1.0];
    self.doneButton.layer.cornerRadius = 14;
    self.doneButton.hidden = YES;
    [self.doneButton addTarget:self action:@selector(doneTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.doneButton];
}

- (void)startInstallation {
    if (!self.ipaPath) {
        [self showError:@"مسار IPA غير صالح"];
        return;
    }

    [[InstallationEngine sharedEngine] installIPA:self.ipaPath
      progressBlock:^(InstallationStage stage, NSString *statusMessage, float progress) {
          self.stageLabel.text = statusMessage;
          self.statusLabel.text = [NSString stringWithFormat:@"%@", [[InstallationEngine sharedEngine] stageDescription:stage]];
          [self.progressView setProgress:progress animated:YES];

          if (stage == InstallationStageCompleted) {
              [self showSuccess];
          } else if (stage == InstallationStageFailed) {
              [self showError:statusMessage];
          }
      }
       completion:^(InstallationResult *result) {
           self.isDone = YES;
           if (result.success) {
               [self showSuccess];
           } else {
               [self showError:result.message];
           }
       }];
}

- (void)showSuccess {
    self.stageLabel.text = @"تم التثبيت بنجاح ✓";
    self.stageLabel.textColor = [UIColor colorWithRed:0.3 green:0.7 blue:0.5 alpha:1.0];
    self.statusLabel.text = @"يمكنك الآن فتح التطبيق من الشاشة الرئيسية";
    self.spinnerView.hidden = YES;
    self.doneButton.hidden = NO;
    [self.progressView setProgress:1.0 animated:YES];
}

- (void)showError:(NSString *)message {
    self.stageLabel.text = @"فشل التثبيت ✗";
    self.stageLabel.textColor = [UIColor colorWithRed:0.9 green:0.4 blue:0.3 alpha:1.0];
    self.statusLabel.text = message ?: @"حدث خطأ غير متوقع";
    self.spinnerView.hidden = YES;
    self.doneButton.hidden = NO;
    [self.doneButton setTitle:@"إغلاق" forState:UIControlStateNormal];
    self.doneButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.3 blue:0.3 alpha:1.0];
}

- (void)doneTapped:(UIButton *)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
