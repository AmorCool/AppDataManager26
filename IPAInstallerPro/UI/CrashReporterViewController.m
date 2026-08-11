#import "CrashReporterViewController.h"
#import "CrashReporter.h"
#import <objc/runtime.h>

@interface CrashReporterViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *crashLogs;
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@end

@implementation CrashReporterViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"📊 Crash Reporter";
    self.view.backgroundColor = [UIColor blackColor];

    // Segment control: All | By App
    self.segmentControl = [[UISegmentedControl alloc] initWithItems:@[@"الكل", @"حسب التطبيق"]];
    self.segmentControl.selectedSegmentIndex = 0;
    [self.segmentControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.segmentControl;

    // Refresh button
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)];
    self.navigationItem.rightBarButtonItem = refresh;

    // Clear button
    UIBarButtonItem *clear = [[UIBarButtonItem alloc] initWithTitle:@"مسح" style:UIBarButtonItemStylePlain target:self action:@selector(clearAll)];
    self.navigationItem.leftBarButtonItem = clear;

    [self loadData];
}

- (void)loadData {
    self.crashLogs = [[CrashReporter sharedReporter] allCrashLogs];
    [self.tableView reloadData];
    self.title = [NSString stringWithFormat:@"📊 Crash Reporter (%lu)", (unsigned long)self.crashLogs.count];
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    [self loadData];
}

- (void)clearAll {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تأكيد" message:@"هل تريد مسح جميع السجلات؟" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"مسح" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[CrashReporter sharedReporter] clearAllLogs];
        [self loadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View

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
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 0;
    }

    NSDictionary *log = self.crashLogs[indexPath.row];
    NSString *appName = log[@"appName"];
    NSString *bundleID = log[@"bundleID"];
    NSString *crashType = log[@"crashType"];
    NSString *crashReason = log[@"crashReason"];
    NSString *timestamp = log[@"timestamp"];
    NSString *signingMethod = log[@"signingMethod"];

    // Color code by crash type
    UIColor *typeColor = [UIColor whiteColor];
    if ([crashType containsString:@"SIGNING"]) typeColor = [UIColor orangeColor];
    else if ([crashType containsString:@"INSTALL"]) typeColor = [UIColor cyanColor];
    else if ([crashType containsString:@"CRASH"]) typeColor = [UIColor redColor];

    cell.textLabel.text = [NSString stringWithFormat:@"%@ (%@)", appName, bundleID];
    cell.textLabel.textColor = typeColor;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ | %@ | 🔏 %@", timestamp, crashReason, signingMethod];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *log = self.crashLogs[indexPath.row];
    NSString *report = [[CrashReporter sharedReporter] generateReportForBundleID:log[@"bundleID"]];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:log[@"appName"] message:report preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"نسخ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[UIPasteboard generalPasteboard] setString:report];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إغلاق" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 70;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary *log = self.crashLogs[indexPath.row];
        [[CrashReporter sharedReporter] clearLogsForBundleID:log[@"bundleID"]];
        [self loadData];
    }
}

@end
