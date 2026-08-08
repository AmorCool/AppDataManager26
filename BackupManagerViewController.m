#import "BackupManagerViewController.h"
#import "AppDataManager.h"
#import "AppDetailViewController.h"

@interface BackupManagerViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *backups;
@property (nonatomic, strong) UIView *statsView;
@end

@implementation BackupManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    self.title = @"Backups";

    [self setupUI];
    [self loadBackups];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadBackups];
}

- (void)setupUI {
    // Stats view (simplified pie chart representation)
    self.statsView = [self createStatsView];
    [self.view addSubview:self.statsView];

    // Table view
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 80;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.statsView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [self.statsView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.statsView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.statsView.heightAnchor constraintEqualToConstant:200],

        [self.tableView.topAnchor constraintEqualToAnchor:self.statsView.bottomAnchor constant:16],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (UIView *)createStatsView {
    UIView *view = [[UIView alloc] init];
    view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    view.layer.cornerRadius = 16;
    view.translatesAutoresizingMaskIntoConstraints = NO;

    // Circle chart placeholder
    UIView *circleView = [[UIView alloc] init];
    circleView.backgroundColor = [UIColor colorWithRed:0.15 green:0.1 blue:0.3 alpha:1.0];
    circleView.layer.cornerRadius = 60;
    circleView.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:circleView];

    UILabel *circleLabel = [[UILabel alloc] init];
    circleLabel.text = @"Backups";
    circleLabel.font = [UIFont boldSystemFontOfSize:14];
    circleLabel.textColor = [UIColor whiteColor];
    circleLabel.textAlignment = NSTextAlignmentCenter;
    circleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [circleView addSubview:circleLabel];

    // Legend
    NSArray *legendItems = @[
        @{@"color": [UIColor colorWithRed:0.4 green:0.3 blue:0.9 alpha:1.0], @"label": @"Backups"},
        @{@"color": [UIColor colorWithRed:0.2 green:0.6 blue:0.9 alpha:1.0], @"label": @"Apps"},
        @{@"color": [UIColor colorWithWhite:0.3 alpha:1.0], @"label": @"Free"}
    ];

    UIView *lastLegend = nil;
    for (NSDictionary *item in legendItems) {
        UIView *dot = [[UIView alloc] init];
        dot.backgroundColor = item[@"color"];
        dot.layer.cornerRadius = 4;
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        [view addSubview:dot];

        UILabel *label = [[UILabel alloc] init];
        label.text = item[@"label"];
        label.font = [UIFont systemFontOfSize:12];
        label.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [view addSubview:label];

        [NSLayoutConstraint activateConstraints:@[
            [dot.widthAnchor constraintEqualToConstant:8],
            [dot.heightAnchor constraintEqualToConstant:8],
            [dot.leadingAnchor constraintEqualToAnchor:circleView.trailingAnchor constant:20],

            [label.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:8],
            [label.centerYAnchor constraintEqualToAnchor:dot.centerYAnchor]
        ]];

        if (lastLegend) {
            [dot.topAnchor constraintEqualToAnchor:lastLegend.bottomAnchor constant:12].active = YES;
        } else {
            [dot.topAnchor constraintEqualToAnchor:circleView.topAnchor constant:20].active = YES;
        }
        lastLegend = dot;
    }

    [NSLayoutConstraint activateConstraints:@[
        [circleView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],
        [circleView.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
        [circleView.widthAnchor constraintEqualToConstant:120],
        [circleView.heightAnchor constraintEqualToConstant:120],

        [circleLabel.centerXAnchor constraintEqualToAnchor:circleView.centerXAnchor],
        [circleLabel.centerYAnchor constraintEqualToAnchor:circleView.centerYAnchor]
    ]];

    return view;
}

- (void)loadBackups {
    NSMutableArray *allBackups = [NSMutableArray array];
    NSArray *apps = [[AppDataManager sharedManager] allInstalledApplications];

    for (NSDictionary *app in apps) {
        NSArray *appBackups = [[AppDataManager sharedManager] availableBackupsForBundleID:app[@"bundleID"]];
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

    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.backups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"BackupCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    NSDictionary *backup = self.backups[indexPath.row];
    cell.textLabel.text = backup[@"appName"];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"MMM d, yyyy 'at' h:mm a"];
    NSString *dateStr = [formatter stringFromDate:backup[@"date"]];

    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  •  %@", dateStr, backup[@"sizeString"]];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];

    // Action buttons
    UIButton *restoreBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    restoreBtn.frame = CGRectMake(0, 0, 36, 36);
    restoreBtn.layer.cornerRadius = 18;
    restoreBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.15 blue:0.3 alpha:1.0];
    [restoreBtn setTitle:@"\u21bb" forState:UIControlStateNormal];
    [restoreBtn setTitleColor:[UIColor colorWithRed:0.4 green:0.3 blue:0.9 alpha:1.0] forState:UIControlStateNormal];
    restoreBtn.titleLabel.font = [UIFont systemFontOfSize:18];
    restoreBtn.tag = indexPath.row;
    [restoreBtn addTarget:self action:@selector(restoreTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIButton *deleteBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    deleteBtn.frame = CGRectMake(0, 0, 36, 36);
    deleteBtn.layer.cornerRadius = 18;
    deleteBtn.backgroundColor = [UIColor colorWithRed:0.3 green:0.1 blue:0.1 alpha:1.0];
    [deleteBtn setTitle:@"\u2715" forState:UIControlStateNormal];
    [deleteBtn setTitleColor:[UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0] forState:UIControlStateNormal];
    deleteBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    deleteBtn.tag = indexPath.row;
    [deleteBtn addTarget:self action:@selector(deleteTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIView *actionsView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 84, 36)];
    [actionsView addSubview:restoreBtn];
    [actionsView addSubview:deleteBtn];
    deleteBtn.frame = CGRectMake(48, 0, 36, 36);

    cell.accessoryView = actionsView;

    return cell;
}

- (void)restoreTapped:(UIButton *)sender {
    NSDictionary *backup = self.backups[sender.tag];
    NSString *bundleID = backup[@"bundleID"];
    NSString *path = backup[@"path"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Confirm Restore"
                                                                   message:[NSString stringWithFormat:@"This will replace current data with this backup for %@. Continue?", backup[@"appName"]]
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        BOOL success = [[AppDataManager sharedManager] restoreAppData:bundleID fromBackup:path];

        NSString *message = success ? @"✅ Restore completed!" : @"❌ Restore failed!";
        UIAlertController *result = [UIAlertController alertControllerWithTitle:@"" message:message preferredStyle:UIAlertControllerStyleAlert];
        [result addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:result animated:YES completion:nil];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteTapped:(UIButton *)sender {
    NSDictionary *backup = self.backups[sender.tag];
    NSString *path = backup[@"path"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Confirm Delete"
                                                                   message:@"This backup will be permanently deleted."
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        BOOL success = [[AppDataManager sharedManager] deleteBackup:path];
        if (success) {
            [self loadBackups];
        }

        NSString *message = success ? @"✅ Backup deleted!" : @"❌ Failed to delete!";
        UIAlertController *result = [UIAlertController alertControllerWithTitle:@"" message:message preferredStyle:UIAlertControllerStyleAlert];
        [result addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:result animated:YES completion:nil];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end