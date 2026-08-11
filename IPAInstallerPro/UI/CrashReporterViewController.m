#import "CrashReporterViewController.h"
#import "CrashReporter.h"
#import "Logger.h"

@interface CrashReporterCell : UITableViewCell
@end
@implementation CrashReporterCell
@end

@interface CrashReporterViewController ()
@property (nonatomic, strong) NSArray<CrashLog *> *crashLogs;
@property (nonatomic, strong) NSDateFormatter *formatter;
@end

@implementation CrashReporterViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"📊 Crash Reporter";
    self.view.backgroundColor = [UIColor blackColor];

    self.formatter = [[NSDateFormatter alloc] init];
    [self.formatter setDateFormat:@"yyyy-MM-dd HH:mm"];

    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.separatorColor = [UIColor darkGrayColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 120;

    // Add clear button
    UIBarButtonItem *clearBtn = [[UIBarButtonItem alloc] initWithTitle:@"مسح"
                                                                  style:UIBarButtonItemStylePlain
                                                                 target:self
                                                                 action:@selector(clearAll:)];
    self.navigationItem.rightBarButtonItem = clearBtn;

    // Add export button
    UIBarButtonItem *exportBtn = [[UIBarButtonItem alloc] initWithTitle:@"تصدير"
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(exportReport:)];
    self.navigationItem.leftBarButtonItem = exportBtn;

    [self loadData];
}

- (void)loadData {
    self.crashLogs = [[CrashReporter sharedReporter] allCrashLogs];
    [self.tableView reloadData];

    if (self.crashLogs.count == 0) {
        UILabel *emptyLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
        emptyLabel.text = @"لا توجد كراشات مسجلة\n🎉 كل شي يشتغل!";
        emptyLabel.textColor = [UIColor grayColor];
        emptyLabel.textAlignment = NSTextAlignmentCenter;
        emptyLabel.numberOfLines = 0;
        emptyLabel.font = [UIFont systemFontOfSize:18];
        self.tableView.backgroundView = emptyLabel;
    } else {
        self.tableView.backgroundView = nil;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.crashLogs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"CrashCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
        cell.detailTextLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    CrashLog *log = self.crashLogs[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ (%@)", log.appName, log.bundleID];

    NSString *timeStr = [self.formatter stringFromDate:log.timestamp];
    NSString *detail = [NSString stringWithFormat:@"🕐 %@\n💥 %@\n📋 %@\n🔏 %@", 
                        timeStr, log.crashType, log.crashReason, log.signingMethod];
    cell.detailTextLabel.text = detail;

    // Color code by crash type
    if ([log.crashType containsString:@"SIGNING"]) {
        cell.contentView.backgroundColor = [UIColor colorWithRed:0.3 green:0.1 blue:0.1 alpha:1.0];
    } else if ([log.crashType containsString:@"SUCCESS"]) {
        cell.contentView.backgroundColor = [UIColor colorWithRed:0.1 green:0.3 blue:0.1 alpha:1.0];
    } else {
        cell.contentView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    CrashLog *log = self.crashLogs[indexPath.row];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:log.appName
                                                                     message:[self formatDetail:log]
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"نسخ التقرير"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        NSString *report = [[CrashReporter sharedReporter] generateReportForBundleID:log.bundleID];
        [[UIPasteboard generalPasteboard] setString:report];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إغلاق"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)formatDetail:(CrashLog *)log {
    return [NSString stringWithFormat:@"Bundle ID: %@\nType: %@\nReason: %@\nSigning: %@\nTeam ID: %@\nPath: %@\nEntitlements: %lu keys\niOS: %@\nJailbreak: %@",
            log.bundleID, log.crashType, log.crashReason, log.signingMethod,
            log.teamID, log.executablePath, (unsigned long)log.entitlementsUsed.count,
            log.iosVersion, log.jailbreakType];
}

- (void)clearAll:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"مسح الكل"
                                                                     message:@"هل أنت متأكد من مسح كل الكراشات؟"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"مسح"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [[CrashReporter sharedReporter] clearAllLogs];
        [self loadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportReport:(id)sender {
    NSString *report = [[CrashReporter sharedReporter] generateFullReport];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[report] applicationActivities:nil];
    [self presentViewController:activity animated:YES completion:nil];
}

@end
