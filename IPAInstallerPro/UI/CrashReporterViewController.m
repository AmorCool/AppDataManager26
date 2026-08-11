#import "CrashReporterViewController.h"
#import "../Core/CrashReporter.h"
#import "../Core/CrashLogParser.h"
#import "../Core/InstallationLogger.h"
#import <objc/runtime.h>

@interface CrashReporterViewController ()
@property (nonatomic, strong) NSArray<CrashEvent *> *events;
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@property (nonatomic, assign) NSInteger currentFilter;
@end

@implementation CrashReporterViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"📊 Diagnostic Center";
    self.view.backgroundColor = [UIColor blackColor];
    self.segmentControl = [[UISegmentedControl alloc] initWithItems:@[@"الكل", @"كراشات", @"تثبيت", @"تشغيل"]];
    self.segmentControl.selectedSegmentIndex = 0;
    [self.segmentControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.segmentControl;
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)];
    self.navigationItem.rightBarButtonItem = refresh;
    UIBarButtonItem *clear = [[UIBarButtonItem alloc] initWithTitle:@"مسح" style:UIBarButtonItemStylePlain target:self action:@selector(showClearMenu)];
    self.navigationItem.leftBarButtonItem = clear;
    [self loadData];
    [[CrashReporter sharedReporter] startMonitoring];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadData];
}

- (void)loadData {
    CrashReporter *reporter = [CrashReporter sharedReporter];
    switch (self.currentFilter) {
        case 0: self.events = [reporter allEvents]; break;
        case 1: self.events = [reporter crashEventsOnly]; break;
        case 2: self.events = [reporter installationEventsOnly]; break;
        case 3: self.events = [reporter launchEventsOnly]; break;
        default: self.events = [reporter allEvents]; break;
    }
    [self.tableView reloadData];
    NSString *title = @"📊 Diagnostic Center";
    if (self.currentFilter == 1) title = @"💥 Crashes";
    else if (self.currentFilter == 2) title = @"📦 Installations";
    else if (self.currentFilter == 3) title = @"▶️ Launches";
    self.title = [NSString stringWithFormat:@"%@ (%lu)", title, (unsigned long)self.events.count];
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    self.currentFilter = sender.selectedSegmentIndex;
    [self loadData];
}

- (void)showClearMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"مسح السجلات" message:@"اختر ما تريد مسحه" preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"مسح الكراشات فقط" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[CrashReporter sharedReporter] clearCrashEventsOnly];
        [self loadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"مسح كل السجلات" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[CrashReporter sharedReporter] clearAllEvents];
        [self loadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.events.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"CrashEventCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 0;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    CrashEvent *event = self.events[indexPath.row];
    UIColor *typeColor = [UIColor whiteColor];
    NSString *icon = @"❓";
    switch (event.eventType) {
        case CrashEventTypeInstallation: typeColor = [UIColor cyanColor]; icon = @"📦"; break;
        case CrashEventTypeSigning: typeColor = [UIColor orangeColor]; icon = @"🔏"; break;
        case CrashEventTypeLaunch: typeColor = [UIColor greenColor]; icon = @"▶️"; break;
        case CrashEventTypeNormalExit: typeColor = [UIColor colorWithWhite:0.5 alpha:1.0]; icon = @"📤"; break;
        case CrashEventTypeCrash: typeColor = [UIColor redColor]; icon = @"💥"; break;
        case CrashEventTypeWatchdog: typeColor = [UIColor redColor]; icon = @"⏱️"; break;
        case CrashEventTypeJetsam: typeColor = [UIColor yellowColor]; icon = @"🧠"; break;
        case CrashEventTypeSignal: typeColor = [UIColor redColor]; icon = @"📡"; break;
        case CrashEventTypeException: typeColor = [UIColor redColor]; icon = @"⚠️"; break;
        case CrashEventTypeForcedTermination: typeColor = [UIColor orangeColor]; icon = @"🚫"; break;
        case CrashEventTypeLaunchFailure: typeColor = [UIColor redColor]; icon = @"❌"; break;
        case CrashEventTypeUnexpectedExit: typeColor = [UIColor orangeColor]; icon = @"🚪"; break;
        default: break;
    }
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"yyyy-MM-dd HH:mm"];
    NSString *timeStr = event.timestamp ? [fmt stringFromDate:event.timestamp] : @"Unknown";
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@ (%@)", icon, event.appName, event.bundleID];
    cell.textLabel.textColor = typeColor;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ | %@", timeStr, event.eventDescription];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CrashEvent *event = self.events[indexPath.row];
    NSMutableString *message = [NSMutableString string];
    [message appendFormat:@"Event Type: %@\n", [[CrashReporter sharedReporter] stringForEventType:event.eventType]];
    [message appendFormat:@"Bundle ID: %@\n", event.bundleID];
    [message appendFormat:@"Description: %@\n\n", event.eventDescription];
    if (event.rawData && event.rawData.count > 0) {
        [message appendString:@"=== Raw Data ===\n"];
        for (NSString *key in event.rawData) {
            id value = event.rawData[key];
            if ([value isKindOfClass:[NSString class]]) [message appendFormat:@"%@: %@\n", key, value];
            else if ([value isKindOfClass:[NSNumber class]]) [message appendFormat:@"%@: %@\n", key, value];
        }
        [message appendString:@"\n"];
    }
    if (event.detailedLog && event.detailedLog.length > 0) [message appendFormat:@"=== Log ===\n%@", event.detailedLog];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:event.appName message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"نسخ التقرير" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *fullReport = [[CrashReporter sharedReporter] formatEvent:event];
        [[UIPasteboard generalPasteboard] setString:fullReport];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إغلاق" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 72; }

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        CrashEvent *event = self.events[indexPath.row];
        [[CrashReporter sharedReporter] clearEventsForBundleID:event.bundleID];
        [self loadData];
    }
}

@end
