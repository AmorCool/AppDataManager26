#import "InstalledAppsViewController.h"
#import "AppDetailsViewController.h"
#import "Core/ApplicationManager.h"
#import "Core/InstallationEngine.h"
#import "Core/Logger.h"

@interface InstalledAppsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *apps;
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@property (nonatomic, strong) NSArray *filteredApps;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation InstalledAppsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"التطبيقات";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    self.isLoading = NO;
    [self setupNavigationBar];
    [self setupSegmentControl];
    [self setupTableView];
    [self setupLoadingIndicator];
    [self loadApps];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Don't reload here to avoid lag
}

- (void)setupNavigationBar {
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
}

- (void)setupSegmentControl {
    self.segmentControl = [[UISegmentedControl alloc] initWithItems:@[@"الكل", @"مستخدم", @"نظام"]];
    self.segmentControl.selectedSegmentIndex = 0;
    self.segmentControl.tintColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    [self.segmentControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.segmentControl;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(10, 0, 40, 0);
    self.tableView.rowHeight = 72;
    [self.view addSubview:self.tableView];
}

- (void)setupLoadingIndicator {
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.loadingIndicator.color = [UIColor colorWithWhite:0.5 alpha:1.0];
    self.loadingIndicator.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2 - 40);
    self.loadingIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.loadingIndicator.hidden = YES;
    [self.view addSubview:self.loadingIndicator];
}

- (void)loadApps {
    if (self.isLoading) return;
    self.isLoading = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        self.loadingIndicator.hidden = NO;
        [self.loadingIndicator startAnimating];
    });

    // Run heavy LSApplicationWorkspace operations on background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSArray *allApps = [[ApplicationManager sharedManager] allInstalledApplications];

            dispatch_async(dispatch_get_main_queue(), ^{
                self.apps = allApps;
                [self applyFilter];
                [self.loadingIndicator stopAnimating];
                self.loadingIndicator.hidden = YES;
                self.isLoading = NO;
            });
        }
        @catch (NSException *exception) {
            [[Logger sharedLogger] error:[NSString stringWithFormat:@"Failed to load apps: %@", exception.reason]];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showToast:@"فشل تحميل التطبيقات"];
                [self.loadingIndicator stopAnimating];
                self.loadingIndicator.hidden = YES;
                self.isLoading = NO;
            });
        }
    });
}

- (void)applyFilter {
    switch (self.segmentControl.selectedSegmentIndex) {
        case 1:
            self.filteredApps = [[ApplicationManager sharedManager] userApplications];
            break;
        case 2:
            self.filteredApps = [[ApplicationManager sharedManager] systemApplications];
            break;
        default:
            self.filteredApps = self.apps;
            break;
    }
    [self.tableView reloadData];
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    [self applyFilter];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filteredApps.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"AppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:1.0];
        cell.layer.cornerRadius = 14;
        cell.layer.masksToBounds = YES;
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        cell.imageView.layer.cornerRadius = 10;
        cell.imageView.layer.masksToBounds = YES;
    }
    AppInfo *app = self.filteredApps[indexPath.row];
    cell.textLabel.text = app.name;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", app.bundleID, app.version];
    if (app.icon) {
        CGSize size = CGSizeMake(44, 44);
        UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
        [app.icon drawInRect:CGRectMake(0, 0, size.width, size.height)];
        UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        cell.imageView.image = scaled;
    } else {
        cell.imageView.image = [[UIImage systemImageNamed:@"app"] imageWithTintColor:[UIColor colorWithWhite:0.4 alpha:1.0]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    AppInfo *app = self.filteredApps[indexPath.row];
    AppDetailsViewController *detailsVC = [[AppDetailsViewController alloc] initWithAppInfo:app];
    [self.navigationController pushViewController:detailsVC animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    AppInfo *app = self.filteredApps[indexPath.row];
    if (app.isProtected) return nil;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"حذف"
                                                                             handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تأكيد الحذف"
                                                                         message:[NSString stringWithFormat:@"هل أنت متأكد من حذف %@؟", app.name]
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"حذف" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
            [[InstallationEngine sharedEngine] uninstallAppWithBundleID:app.bundleID completion:^(BOOL success, NSString *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (success) { [self loadApps]; } else { [self showToast:error ?: @"فشل الحذف"]; }
                });
            }];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        completionHandler(YES);
    }];
    deleteAction.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0];
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

- (void)showToast:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *toast = [[UILabel alloc] init];
        toast.text = message;
        toast.textColor = [UIColor whiteColor];
        toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
        toast.textAlignment = NSTextAlignmentCenter;
        toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        toast.layer.cornerRadius = 12;
        toast.layer.masksToBounds = YES;
        CGSize size = [message boundingRectWithSize:CGSizeMake(self.view.bounds.size.width - 60, CGFLOAT_MAX)
                                            options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: toast.font} context:nil].size;
        toast.frame = CGRectMake(0, 0, size.width + 32, size.height + 24);
        toast.center = CGPointMake(self.view.center.x, self.view.bounds.size.height - 120);
        [self.view addSubview:toast];
        [UIView animateWithDuration:0.3 delay:2.5 options:UIViewAnimationOptionCurveEaseOut animations:^{ toast.alpha = 0; }
                         completion:^(BOOL finished) { [toast removeFromSuperview]; }];
    });
}

@end
