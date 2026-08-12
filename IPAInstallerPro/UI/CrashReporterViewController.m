#import "CrashReporterViewController.h"
#import "../Core/DiagnosticPipeline.h"
#import "../Core/CrashIncident.h"
#import "../Core/CrashReporter.h"
#import <objc/runtime.h>

@interface CrashReporterViewController ()
@property (nonatomic, strong) NSArray<CrashIncident *> *incidents;
@property (nonatomic, strong) NSArray<CrashIncident *> *filteredIncidents;
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@property (nonatomic, assign) NSInteger currentFilter;
@property (nonatomic, strong) DiagnosticReport *lastReport;
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
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(runPipeline)];
    self.navigationItem.rightBarButtonItem = refresh;
    UIBarButtonItem *clear = [[UIBarButtonItem alloc] initWithTitle:@"مسح" style:UIBarButtonItemStylePlain target:self action:@selector(showClearMenu)];
    self.navigationItem.leftBarButtonItem = clear;
    [self runPipeline];
    [[CrashReporter sharedReporter] startMonitoring];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self runPipeline];
}

#pragma mark - Pipeline Integration

- (void)runPipeline {
    DiagnosticPipeline *pipeline = [DiagnosticPipeline sharedPipeline];
    self.lastReport = [pipeline runPipeline];
    self.incidents = self.lastReport.incidents;
    [self applyFilter];
}

- (void)applyFilter {
    switch (self.currentFilter) {
        case 0: self.filteredIncidents = self.incidents; break;
        case 1: self.filteredIncidents = [self incidentsWithSeverities:@[@(CrashSeverityCritical), @(CrashSeverityHigh)]]; break;
        case 2: self.filteredIncidents = [self incidentsWithPhase:CrashPhaseInstall]; break;
        case 3: self.filteredIncidents = [self incidentsWithPhase:CrashPhaseProcessLaunch]; break;
        default: self.filteredIncidents = self.incidents; break;
    }
    [self.tableView reloadData];
    NSString *title = @"📊 Diagnostic Center";
    if (self.currentFilter == 1) title = @"💥 Crashes";
    else if (self.currentFilter == 2) title = @"📦 Installations";
    else if (self.currentFilter == 3) title = @"▶️ Launches";
    self.title = [NSString stringWithFormat:@"%@ (%lu)", title, (unsigned long)self.filteredIncidents.count];
}

- (NSArray<CrashIncident *> *)incidentsWithSeverities:(NSArray<NSNumber *> *)severities {
    NSMutableArray *result = [NSMutableArray array];
    for (CrashIncident *i in self.incidents) {
        for (NSNumber *s in severities) {
            if (i.severity == s.integerValue) { [result addObject:i]; break; }
        }
    }
    return result;
}

- (NSArray<CrashIncident *> *)incidentsWithPhase:(CrashPhase)phase {
    NSMutableArray *result = [NSMutableArray array];
    for (CrashIncident *i in self.incidents) {
        if (i.phase == phase) [result addObject:i];
    }
    return result;
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    self.currentFilter = sender.selectedSegmentIndex;
    [self applyFilter];
}

- (void)showClearMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"مسح السجلات" message:@"اختر ما تريد مسحه" preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"مسح الكراشات فقط" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[DiagnosticPipeline sharedPipeline] reset];
        [self runPipeline];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"مسح كل السجلات" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[DiagnosticPipeline sharedPipeline] reset];
        [[CrashReporter sharedReporter] clearAllEvents];
        [self runPipeline];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filteredIncidents.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"CrashIncidentCell";
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
    CrashIncident *incident = self.filteredIncidents[indexPath.row];
    UIColor *severityColor = [UIColor whiteColor];
    NSString *icon = @"❓";
    switch (incident.severity) {
        case CrashSeverityCritical: severityColor = [UIColor redColor]; icon = @"🔴"; break;
        case CrashSeverityHigh: severityColor = [UIColor orangeColor]; icon = @"🟠"; break;
        case CrashSeverityMedium: severityColor = [UIColor yellowColor]; icon = @"🟡"; break;
        case CrashSeverityLow: severityColor = [UIColor greenColor]; icon = @"🟢"; break;
        default: severityColor = [UIColor colorWithWhite:0.5 alpha:1.0]; icon = @"⚪"; break;
    }
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@ | %@ | %@", icon, incident.crashType, incident.bundleID, [incident severityString]];
    cell.textLabel.textColor = severityColor;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ | Phase: %@ | Confidence: %@", [incident formattedTimestamp], [incident phaseString], [incident confidenceString]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CrashIncident *incident = self.filteredIncidents[indexPath.row];
    NSMutableString *message = [NSMutableString string];
    [message appendFormat:@"Type: %@\n", incident.crashType];
    [message appendFormat:@"Severity: %@\n", [incident severityString]];
    [message appendFormat:@"Phase: %@\n", [incident phaseString]];
    [message appendFormat:@"Confidence: %@\n", [incident confidenceString]];
    [message appendFormat:@"Bundle ID: %@\n", incident.bundleID];
    [message appendFormat:@"Process: %@\n\n", incident.processName];
    [message appendFormat:@"Root Cause:\n%@\n\n", incident.rootCause];
    if (incident.evidence && incident.evidence.count > 0) {
        [message appendString:@"=== Evidence ===\n"];
        for (NSString *key in incident.evidence) {
            id value = incident.evidence[key];
            if ([value isKindOfClass:[NSString class]]) [message appendFormat:@"%@: %@\n", key, value];
            else if ([value isKindOfClass:[NSNumber class]]) [message appendFormat:@"%@: %@\n", key, value];
        }
        [message appendString:@"\n"];
    }
    if (incident.humanReadableSummary && incident.humanReadableSummary.length > 0) {
        [message appendFormat:@"=== Summary ===\n%@", incident.humanReadableSummary];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:incident.processName message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"نسخ التقرير" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *fullReport = [incident dictionaryRepresentation][@"humanReadableSummary"] ?: incident.humanReadableSummary;
        [[UIPasteboard generalPasteboard] setString:fullReport];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إغلاق" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 72; }

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        CrashIncident *incident = self.filteredIncidents[indexPath.row];
        [[DiagnosticPipeline sharedPipeline] removeManagedBundleID:incident.bundleID];
        [self runPipeline];
    }
}

@end
