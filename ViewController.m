#import "ViewController.h"
#import "AppDataManager.h"
#import "BackupManagerViewController.h"

@interface ViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSArray<NSDictionary *> *allApps;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredApps;
@property (nonatomic, strong) AppDataManager *manager;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AppData Manager";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.manager = [AppDataManager sharedManager];

    [self setupNavigationBar];
    [self setupSearchController];
    [self setupTableView];
    [self setupLoadingView];
    [self loadApps];
}

- (void)setupNavigationBar {
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    UIBarButtonItem *backupBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"archivebox.fill"]
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(showBackupManager)];
    self.navigationItem.rightBarButtonItem = backupBtn;

    UIBarButtonItem *infoBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"]
                                                                  style:UIBarButtonItemStylePlain
                                                                 target:self
                                                                 action:@selector(showInfo)];
    self.navigationItem.leftBarButtonItem = infoBtn;
}

- (void)setupSearchController {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search apps...";
    self.searchController.searchBar.searchTextField.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    [self.view addSubview:self.tableView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(loadApps) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;
}

- (void)setupLoadingView {
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.loadingIndicator.center = self.view.center;
    self.loadingIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.loadingIndicator];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, self.view.bounds.size.width - 40, 30)];
    self.statusLabel.center = CGPointMake(self.view.center.x, self.view.center.y + 40);
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.hidden = YES;
    [self.view addSubview:self.statusLabel];
}

- (void)loadApps {
    [self.loadingIndicator startAnimating];
    self.statusLabel.text = @"Loading applications...";
    self.statusLabel.hidden = NO;
    self.tableView.hidden = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        self.allApps = [self.manager allInstalledApplications];
        self.filteredApps = self.allApps;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIndicator stopAnimating];
            self.statusLabel.hidden = YES;
            self.tableView.hidden = NO;
            [self.refreshControl endRefreshing];
            [self.tableView reloadData];

            self.title = [NSString stringWithFormat:@"AppData Manager (%lu)", (unsigned long)self.allApps.count];
        });
    });
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"AppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    NSDictionary *app = self.filteredApps[indexPath.row];
    cell.textLabel.text = app[@"name"];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];

    // تغيير لون التطبيقات النظامية
    if ([app[@"isSystemApp"] boolValue]) {
        cell.textLabel.textColor = [UIColor systemRedColor];
    } else {
        cell.textLabel.textColor = [UIColor labelColor];
    }

    NSString *detail = [NSString stringWithFormat:@"%@ • %@%@", 
                        app[@"bundleID"], 
                        app[@"sizeString"],
                        [app[@"isSystemApp"] boolValue] ? @" • SYSTEM" : @""];
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];

    if ([app[@"hasBackup"] boolValue]) {
        UIImageView *backupIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"archivebox"]];
        backupIcon.tintColor = [UIColor systemGreenColor];
        cell.accessoryView = backupIcon;
    } else {
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *app = self.filteredApps[indexPath.row];
    [self showAppActions:app];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60;
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchText = searchController.searchBar.text;
    if (searchText.length == 0) {
        self.filteredApps = self.allApps;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[c] %@ OR bundleID CONTAINS[c] %@", searchText, searchText];
        self.filteredApps = [self.allApps filteredArrayUsingPredicate:predicate];
    }
    [self.tableView reloadData];
}

#pragma mark - Actions

- (void)showAppActions:(NSDictionary *)app {
    NSString *name = app[@"name"];
    NSString *bundleID = app[@"bundleID"];
    NSString *sizeStr = app[@"sizeString"];
    BOOL isSystem = [app[@"isSystemApp"] boolValue];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:name
                                                                   message:[NSString stringWithFormat:@"Bundle ID: %@\nData Size: %@%@", bundleID, sizeStr, isSystem ? @"\n⚠️ SYSTEM APP - Wipe Disabled" : @""]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    // نسخ احتياطي (متاح للجميع)
    [alert addAction:[UIAlertAction actionWithTitle:@"📦 Backup Data" 
                                              style:UIAlertActionStyleDefault 
                                            handler:^(UIAlertAction *action) {
        [self performAction:@"Backup" forApp:bundleID name:name];
    }]];

    // استعراض النسخ الاحتياطية
    if ([app[@"hasBackup"] boolValue]) {
        [alert addAction:[UIAlertAction actionWithTitle:@"📂 View Backups" 
                                                  style:UIAlertActionStyleDefault 
                                                handler:^(UIAlertAction *action) {
            [self showBackupsForApp:bundleID name:name];
        }]];
    }

    // مسح البيانات (غير متاح للتطبيقات النظامية)
    if (!isSystem) {
        [alert addAction:[UIAlertAction actionWithTitle:@"🗑 Wipe Data" 
                                                  style:UIAlertActionStyleDestructive 
                                                handler:^(UIAlertAction *action) {
            [self confirmWipe:bundleID name:name];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[self.tableView indexPathForSelectedRow]];
        alert.popoverPresentationController.sourceView = cell;
        alert.popoverPresentationController.sourceRect = cell.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmWipe:(NSString *)bundleID name:(NSString *)name {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"⚠️ WARNING" 
                                                                     message:[NSString stringWithFormat:@"This will permanently delete ALL data for %@. This action cannot be undone!", name]
                                                              preferredStyle:UIAlertControllerStyleAlert];

    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Wipe Data" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self performAction:@"Wipe" forApp:bundleID name:name];
    }]];

    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)performAction:(NSString *)action forApp:(NSString *)bundleID name:(NSString *)name {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.center = self.view.center;
    [self.view addSubview:spinner];
    [spinner startAnimating];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL success = NO;
        NSString *message = @"";

        if ([action isEqualToString:@"Backup"]) {
            success = [self.manager backupAppData:bundleID];
            message = success ? [NSString stringWithFormat:@"✅ Backup created for %@!", name] : [NSString stringWithFormat:@"❌ Failed to backup %@", name];
        } else if ([action isEqualToString:@"Wipe"]) {
            success = [self.manager wipeAppData:bundleID];
            message = success ? [NSString stringWithFormat:@"✅ Data wiped for %@!", name] : [NSString stringWithFormat:@"❌ Failed to wipe %@", name];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [spinner stopAnimating];
            [spinner removeFromSuperview];

            if (success && [action isEqualToString:@"Wipe"]) {
                [self loadApps];
            }

            [self showToast:message];
        });
    });
}

- (void)showBackupsForApp:(NSString *)bundleID name:(NSString *)name {
    BackupManagerViewController *backupVC = [[BackupManagerViewController alloc] initWithBundleID:bundleID appName:name];
    [self.navigationController pushViewController:backupVC animated:YES];
}

- (void)showBackupManager {
    BackupManagerViewController *backupVC = [[BackupManagerViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:backupVC];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)showInfo {
    NSString *info = @"AppData Manager v1.0.0

"
                      @"A professional tool for managing app data on jailbroken iOS devices.

"
                      @"Features:
"
                      @"• Wipe app data
"
                      @"• Backup & Restore
"
                      @"• System app protection
"
                      @"• Rootless compatible
"
                      @"• Dopamine 3.0 support
"
                      @"• iOS 18 support

"
                      @"Developer: @Zainqkvd";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"About", @"About title") 
                                                                   message:info 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK button") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showToast:(NSString *)message {
    UILabel *toast = [[UILabel alloc] init];
    toast.text = message;
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    toast.layer.cornerRadius = 10;
    toast.layer.masksToBounds = YES;
    toast.numberOfLines = 0;

    CGSize size = [message boundingRectWithSize:CGSizeMake(self.view.bounds.size.width - 60, CGFLOAT_MAX)
                                         options:NSStringDrawingUsesLineFragmentOrigin
                                      attributes:@{NSFontAttributeName: toast.font}
                                         context:nil].size;
    toast.frame = CGRectMake(0, 0, size.width + 30, size.height + 20);
    toast.center = CGPointMake(self.view.center.x, self.view.bounds.size.height - 100);

    [self.view addSubview:toast];

    [UIView animateWithDuration:0.3 delay:2.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        toast.alpha = 0;
    } completion:^(BOOL finished) {
        [toast removeFromSuperview];
    }];
}

@end
