#import "BackupManagerViewController.h"
#import "AppDataManager.h"

@interface BackupManagerViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *backups;
@property (nonatomic, strong) AppDataManager *manager;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, assign) BOOL showAllBackups;
@end

@implementation BackupManagerViewController

- (instancetype)initWithBundleID:(NSString *)bundleID appName:(NSString *)appName {
    self = [super init];
    if (self) {
        self.bundleID = bundleID;
        self.appName = appName;
        self.showAllBackups = NO;
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.bundleID = nil;
        self.appName = NSLocalizedString(@"All Backups", @"All backups title");
        self.showAllBackups = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.showAllBackups ? NSLocalizedString(@"Backup Manager", @"Backup manager title") : self.appName;
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.manager = [AppDataManager sharedManager];

    if (self.showAllBackups) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone 
                                                                                              target:self 
                                                                                              action:@selector(dismissModal)];
    }

    [self setupTableView];
    [self loadBackups];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self.view addSubview:self.tableView];

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(loadBackups) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = refresh;
}

- (void)loadBackups {
    [self.tableView.refreshControl beginRefreshing];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (self.showAllBackups) {
            // جمع كل النسخ الاحتياطية
            NSMutableArray *allBackups = [NSMutableArray array];
            NSArray *apps = [self.manager allInstalledApplications];
            for (NSDictionary *app in apps) {
                NSArray *appBackups = [self.manager availableBackupsForBundleID:app[@"bundleID"]];
                [allBackups addObjectsFromArray:appBackups];
            }
            self.backups = [allBackups sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                return [b[@"date"] compare:a[@"date"]];
            }];
        } else {
            self.backups = [self.manager availableBackupsForBundleID:self.bundleID];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView.refreshControl endRefreshing];
            [self.tableView reloadData];

            if (self.backups.count == 0) {
                [self showEmptyState];
            }
        });
    });
}

- (void)showEmptyState {
    UILabel *label = [[UILabel alloc] init];
    label.text = NSLocalizedString(@"No backups found", @"No backups message");
    label.textColor = [UIColor secondaryLabelColor];
    label.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.frame = CGRectMake(0, 0, self.view.bounds.size.width, 50);
    label.center = self.view.center;
    [self.view addSubview:label];
}

- (void)dismissModal {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.backups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"BackupCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }

    NSDictionary *backup = self.backups[indexPath.row];
    cell.textLabel.text = backup[@"name"];
    cell.textLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 2;

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm"];
    NSString *dateStr = [formatter stringFromDate:backup[@"date"]];

    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", dateStr, backup[@"sizeString"]];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *backup = self.backups[indexPath.row];
    [self showBackupActions:backup];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 65;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary *backup = self.backups[indexPath.row];
        [self confirmDeleteBackup:backup atIndexPath:indexPath];
    }
}

- (void)showBackupActions:(NSDictionary *)backup {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Backup Options", @"Backup options title") 
                                                                   message:backup[@"name"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    // استعادة
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"🔄 Restore", @"Restore button") 
                                              style:UIAlertActionStyleDefault 
                                            handler:^(UIAlertAction *action) {
        [self confirmRestore:backup];
    }]];

    // حذف
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"🗑 Delete", @"Delete button") 
                                              style:UIAlertActionStyleDestructive 
                                            handler:^(UIAlertAction *action) {
        [self deleteBackup:backup[@"path"]];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel button") style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[self.tableView indexPathForSelectedRow]];
        alert.popoverPresentationController.sourceView = cell;
        alert.popoverPresentationController.sourceRect = cell.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmRestore:(NSDictionary *)backup {
    NSString *bundleID = [[backup[@"name"] componentsSeparatedByString:@"_"] firstObject];

    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"🔄 Restore Backup", @"Restore backup action") 
                                                                     message:[NSString stringWithFormat:NSLocalizedString(@"This will replace current data with this backup for %@. Continue?", @"Restore confirmation message"), bundleID]
                                                              preferredStyle:UIAlertControllerStyleAlert];

    [confirm addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel button") style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self restoreBackup:backup forBundleID:bundleID];
    }]];

    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)restoreBackup:(NSDictionary *)backup forBundleID:(NSString *)bundleID {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.center = self.view.center;
    [self.view addSubview:spinner];
    [spinner startAnimating];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL success = [self.manager restoreAppData:bundleID fromBackup:backup[@"path"]];

        dispatch_async(dispatch_get_main_queue(), ^{
            [spinner stopAnimating];
            [spinner removeFromSuperview];

            NSString *msg = success ? NSLocalizedString(@"✅ Restore completed!", @"Restore success") : NSLocalizedString(@"❌ Restore failed!", @"Restore failure");
            [self showToast:msg];
        });
    });
}

- (void)confirmDeleteBackup:(NSDictionary *)backup atIndexPath:(NSIndexPath *)indexPath {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"🗑 Delete Backup", @"Delete backup action") 
                                                                     message:NSLocalizedString(@"This backup will be permanently deleted.", @"Delete confirmation message") 
                                                              preferredStyle:UIAlertControllerStyleAlert];

    [confirm addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel button") style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self deleteBackup:backup[@"path"]];
    }]];

    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)deleteBackup:(NSString *)path {
    BOOL success = [self.manager deleteBackup:path];
    if (success) {
        [self loadBackups];
        [self showToast:NSLocalizedString(@"✅ Backup deleted!", @"Delete success")];
    } else {
        [self showToast:NSLocalizedString(@"❌ Failed to delete!", @"Delete failure")];
    }
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
