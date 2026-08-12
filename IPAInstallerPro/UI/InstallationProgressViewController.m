//
//  InstallationProgressViewController.m
//  IPAInstallerPro
//
//  Updated v1.1.0 — Live Installation Log Viewer
//

#import "InstallationProgressViewController.h"
#import "LiveInstallationLogger.h"
#import "InstallationEngine.h"
#import <UIKit/UIKit.h>

@interface InstallationProgressViewController () <LiveInstallationLoggerDelegate>
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UIScrollView *logScrollView;
@property (nonatomic, strong) UIButton *copyLogButton;
@property (nonatomic, strong) UIButton *saveLogButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIView *phaseIndicatorView;
@property (nonatomic, strong) NSMutableArray<UIView *> *phaseDots;

@property (nonatomic, strong) NSString *ipaPath;
@property (nonatomic, strong) NSString *appName;
@property (nonatomic, strong) NSString *bundleID;
@property (nonatomic, strong) InstallationEngine *engine;
@property (nonatomic, strong) LiveInstallationLogger *logger;
@property (nonatomic, assign) BOOL isInstalling;
@end

@implementation InstallationProgressViewController

- (instancetype)initWithIPAPath:(NSString *)ipaPath appName:(NSString *)appName bundleID:(NSString *)bundleID {
    self = [super init];
    if (self) {
        _ipaPath = ipaPath;
        _appName = appName;
        _bundleID = bundleID;
        _engine = [[InstallationEngine alloc] init];
        _logger = [LiveInstallationLogger sharedLogger];
        _logger.delegate = self;
        _phaseDots = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.09 alpha:1.0];
    self.title = @"Installing...";

    [self setupUI];
    [self startInstallation];
}

#pragma mark - UI Setup

- (void)setupUI {
    CGFloat margin = 16;
    CGFloat top = 100;

    // App name label
    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, top, self.view.bounds.size.width - margin*2, 28)];
    nameLabel.text = self.appName;
    nameLabel.font = [UIFont boldSystemFontOfSize:20];
    nameLabel.textColor = [UIColor whiteColor];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:nameLabel];

    // Bundle ID label
    UILabel *bidLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, top + 32, self.view.bounds.size.width - margin*2, 18)];
    bidLabel.text = self.bundleID;
    bidLabel.font = [UIFont systemFontOfSize:12];
    bidLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    bidLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:bidLabel];

    // Progress view
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.frame = CGRectMake(margin, top + 64, self.view.bounds.size.width - margin*2, 4);
    self.progressView.progressTintColor = [UIColor colorWithRed:0.31 green:0.76 blue:0.97 alpha:1.0];
    self.progressView.trackTintColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    self.progressView.layer.cornerRadius = 2;
    self.progressView.clipsToBounds = YES;
    [self.view addSubview:self.progressView];

    // Status label
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, top + 78, self.view.bounds.size.width - margin*2, 20)];
    self.statusLabel.text = @"Preparing...";
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.textColor = [UIColor colorWithRed:0.31 green:0.76 blue:0.97 alpha:1.0];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.statusLabel];

    // Detail label
    self.detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, top + 100, self.view.bounds.size.width - margin*2, 16)];
    self.detailLabel.text = @"";
    self.detailLabel.font = [UIFont systemFontOfSize:11];
    self.detailLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    self.detailLabel.textAlignment = NSTextAlignmentCenter;
    self.detailLabel.numberOfLines = 1;
    [self.view addSubview:self.detailLabel];

    // Phase indicator dots
    self.phaseIndicatorView = [[UIView alloc] initWithFrame:CGRectMake(margin, top + 126, self.view.bounds.size.width - margin*2, 24)];
    [self setupPhaseDots];
    [self.view addSubview:self.phaseIndicatorView];

    // Live Log TextView
    CGFloat logTop = top + 160;
    CGFloat logHeight = self.view.bounds.size.height - logTop - 120;

    UIView *logContainer = [[UIView alloc] initWithFrame:CGRectMake(margin, logTop, self.view.bounds.size.width - margin*2, logHeight)];
    logContainer.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    logContainer.layer.cornerRadius = 8;
    logContainer.layer.borderColor = [UIColor colorWithWhite:0.15 alpha:1.0].CGColor;
    logContainer.layer.borderWidth = 1;
    [self.view addSubview:logContainer];

    // Log header
    UILabel *logHeader = [[UILabel alloc] initWithFrame:CGRectMake(8, 4, 200, 18)];
    logHeader.text = @"📋 Live Installation Log";
    logHeader.font = [UIFont boldSystemFontOfSize:11];
    logHeader.textColor = [UIColor colorWithRed:0.73 green:0.33 blue:0.83 alpha:1.0];
    [logContainer addSubview:logHeader];

    self.logTextView = [[UITextView alloc] initWithFrame:CGRectMake(4, 24, logContainer.bounds.size.width - 8, logContainer.bounds.size.height - 28)];
    self.logTextView.backgroundColor = [UIColor clearColor];
    self.logTextView.textColor = [UIColor colorWithRed:0.68 green:0.83 blue:0.51 alpha:1.0];
    self.logTextView.font = [UIFont fontWithName:@"Menlo" size:9];
    self.logTextView.editable = NO;
    self.logTextView.selectable = YES;
    self.logTextView.showsVerticalScrollIndicator = YES;
    self.logTextView.text = @"Waiting for installation to begin...\n";
    [logContainer addSubview:self.logTextView];

    // Buttons
    CGFloat btnY = self.view.bounds.size.height - 100;
    CGFloat btnW = (self.view.bounds.size.width - margin*2 - 16) / 3;

    self.copyLogButton = [self createButton:@"📋 Copy" frame:CGRectMake(margin, btnY, btnW, 36) action:@selector(copyLogTapped)];
    [self.view addSubview:self.copyLogButton];

    self.saveLogButton = [self createButton:@"💾 Save" frame:CGRectMake(margin + btnW + 8, btnY, btnW, 36) action:@selector(saveLogTapped)];
    [self.view addSubview:self.saveLogButton];

    self.closeButton = [self createButton:@"✕ Close" frame:CGRectMake(margin + btnW*2 + 16, btnY, btnW, 36) action:@selector(closeTapped)];
    self.closeButton.hidden = YES;
    [self.view addSubview:self.closeButton];
}

- (UIButton *)createButton:(NSString *)title frame:(CGRect)frame action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = frame;
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:12];
    btn.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    btn.layer.cornerRadius = 6;
    btn.layer.borderColor = [UIColor colorWithWhite:0.2 alpha:1.0].CGColor;
    btn.layer.borderWidth = 1;
    [btn setTitleColor:[UIColor colorWithRed:0.31 green:0.76 blue:0.97 alpha:1.0] forState:UIControlStateNormal];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)setupPhaseDots {
    NSArray *phases = @[@"IPA", @"EXT", @"ID", @"COPY", @"CHMOD", @"CHOWN", @"SIGN", @"FW", @"UI", @"VER"];
    CGFloat dotW = self.phaseIndicatorView.bounds.size.width / phases.count;
    for (int i = 0; i < phases.count; i++) {
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(i * dotW + 4, 4, dotW - 8, 16)];
        dot.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        dot.layer.cornerRadius = 3;

        UILabel *lbl = [[UILabel alloc] initWithFrame:dot.bounds];
        lbl.text = phases[i];
        lbl.font = [UIFont systemFontOfSize:7];
        lbl.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        lbl.textAlignment = NSTextAlignmentCenter;
        [dot addSubview:lbl];

        [self.phaseIndicatorView addSubview:dot];
        [self.phaseDots addObject:dot];
    }
}

- (void)updatePhaseDot:(NSUInteger)index status:(NSString *)status {
    if (index >= self.phaseDots.count) return;
    UIView *dot = self.phaseDots[index];
    if ([status isEqualToString:@"RUNNING"]) {
        dot.backgroundColor = [UIColor colorWithRed:0.31 green:0.76 blue:0.97 alpha:0.3];
        ((UILabel *)dot.subviews.firstObject).textColor = [UIColor colorWithRed:0.31 green:0.76 blue:0.97 alpha:1.0];
    } else if ([status isEqualToString:@"DONE"]) {
        dot.backgroundColor = [UIColor colorWithRed:0.51 green:0.78 blue:0.51 alpha:0.3];
        ((UILabel *)dot.subviews.firstObject).textColor = [UIColor colorWithRed:0.51 green:0.78 blue:0.51 alpha:1.0];
    } else if ([status isEqualToString:@"FAILED"]) {
        dot.backgroundColor = [UIColor colorWithRed:0.94 green:0.33 blue:0.31 alpha:0.3];
        ((UILabel *)dot.subviews.firstObject).textColor = [UIColor colorWithRed:0.94 green:0.33 blue:0.31 alpha:1.0];
    }
}

#pragma mark - LiveInstallationLoggerDelegate

- (void)logger:(id)logger didAppendEntry:(NSString *)entry atIndex:(NSUInteger)index {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *current = self.logTextView.text;
        self.logTextView.text = [current stringByAppendingFormat:@"%@\n", entry];

        // Auto-scroll to bottom
        NSRange bottom = NSMakeRange(self.logTextView.text.length - 1, 1);
        [self.logTextView scrollRangeToVisible:bottom];
    });
}

- (void)logger:(id)logger didUpdatePhase:(NSString *)phase status:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = [NSString stringWithFormat:@"Phase: %@", phase];

        // Map phase to dot index
        NSDictionary *phaseMap = @{
            @"IPA_OPEN": @0, @"IPA_EXTRACT": @1, @"APP_IDENTIFY": @2,
            @"FILE_COPY": @3, @"PERMISSION_chmod": @4, @"PERMISSION_chown": @5,
            @"SIGN_signAllAt": @6, @"FRAMEWORK": @7, @"UICACHE": @8, @"VERIFY": @9
        };
        NSNumber *idx = phaseMap[phase];
        if (idx) {
            [self updatePhaseDot:[idx unsignedIntegerValue] status:status];
            // Mark previous as done
            for (NSUInteger i = 0; i < [idx unsignedIntegerValue]; i++) {
                [self updatePhaseDot:i status:@"DONE"];
            }
        }
    });
}

#pragma mark - Installation

- (void)startInstallation {
    self.isInstalling = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int result = [self.engine installIPAAtPath:self.ipaPath
                                        progress:^(float progress) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.progressView.progress = progress;
            });
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.isInstalling = NO;
            [self installationCompleted:result];
        });
    });
}

- (void)installationCompleted:(int)result {
    self.closeButton.hidden = NO;

    if (result == 0) {
        self.statusLabel.text = @"✅ Installation Complete";
        self.statusLabel.textColor = [UIColor colorWithRed:0.51 green:0.78 blue:0.51 alpha:1.0];
        self.progressView.progressTintColor = [UIColor colorWithRed:0.51 green:0.78 blue:0.51 alpha:1.0];
        self.title = @"Success";

        // Mark all phases done
        for (NSUInteger i = 0; i < self.phaseDots.count; i++) {
            [self updatePhaseDot:i status:@"DONE"];
        }
    } else {
        self.statusLabel.text = [NSString stringWithFormat:@"❌ Failed (code %d)", result];
        self.statusLabel.textColor = [UIColor colorWithRed:0.94 green:0.33 blue:0.31 alpha:1.0];
        self.progressView.progressTintColor = [UIColor colorWithRed:0.94 green:0.33 blue:0.31 alpha:1.0];
        self.title = @"Failed";

        // Mark current phase as failed
        for (NSUInteger i = 0; i < self.phaseDots.count; i++) {
            UIView *dot = self.phaseDots[i];
            if (dot.backgroundColor == [UIColor colorWithWhite:0.15 alpha:1.0]) {
                [self updatePhaseDot:i status:@"FAILED"];
                break;
            }
        }
    }

    // Add summary to log
    NSString *summary = [NSString stringWithFormat:@"\n═══════════════════════════════════════\n  FINAL RESULT: %@ (exit code %d)\n═══════════════════════════════════════",
                         result == 0 ? @"SUCCESS" : @"FAILED", result];
    NSString *current = self.logTextView.text;
    self.logTextView.text = [current stringByAppendingString:summary];
}

#pragma mark - Button Actions

- (void)copyLogTapped {
    NSString *logText = [[LiveInstallationLogger sharedLogger] fullLogText];
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    pb.string = logText;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Copied"
                                                                   message:@"Full installation log copied to clipboard"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveLogTapped {
    NSString *logText = [[LiveInstallationLogger sharedLogger] fullLogText];
    NSString *filename = [NSString stringWithFormat:@"install_%@_%@.log",
                          self.bundleID,
                          [[NSDate date] description]];
    filename = [filename stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    filename = [filename stringByReplacingOccurrencesOfString:@":" withString:@"-"];

    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    [logText writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Saved"
                                                                   message:[NSString stringWithFormat:@"Log saved to\n%@", path]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
