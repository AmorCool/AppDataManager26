#import "MainViewController.h"
#import "IPAFileBrowserViewController.h"
#import "IPAInstallViewController.h"
#import "Core/IPAExtractor.h"
#import "Core/Logger.h"

@interface MainViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<IPAExtractedInfo *> *ipaFiles;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ملفات IPA";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    self.ipaFiles = [NSMutableArray array];

    [self setupNavigationBar];
    [self setupTableView];
    [self setupEmptyState];
    [self setupAddButton];
    [self loadIPAFiles];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadIPAFiles];
}

- (void)setupNavigationBar {
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 40, 0);
    self.tableView.rowHeight = 80;
    [self.view addSubview:self.tableView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    [self.refreshControl addTarget:self action:@selector(refreshPulled:) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;
}

- (void)setupEmptyState {
    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.text = @"لا توجد ملفات IPA\nاضغط + لإضافة ملف";
    self.emptyLabel.textColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    self.emptyLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
}

- (void)setupAddButton {
    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                              target:self
                                                                              action:@selector(addIPATapped:)];
    addBtn.tintColor = [UIColor whiteColor];
    self.navigationItem.rightBarButtonItem = addBtn;
}

- (void)loadIPAFiles {
    [self.ipaFiles removeAllObjects];

    NSArray *directories = @[
        @"/var/mobile/Documents",
        @"/var/mobile/Downloads",
        @"/var/mobile/Media/Downloads"
    ];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in directories) {
        if (![fm fileExistsAtPath:dir]) continue;
        NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *file in contents) {
            if ([file.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
                NSString *path = [dir stringByAppendingPathComponent:file];
                IPAExtractedInfo *info = [[IPAExtractor sharedExtractor] extractInfoFromIPA:path];
                if (info) [self.ipaFiles addObject:info];
            }
        }
    }

    [self.tableView reloadData];
    self.emptyLabel.hidden = (self.ipaFiles.count > 0);
    self.emptyLabel.frame = CGRectMake(20, self.view.bounds.size.height / 2 - 40, self.view.bounds.size.width - 40, 80);
    [self.refreshControl endRefreshing];
}

- (void)refreshPulled:(UIRefreshControl *)sender {
    [self loadIPAFiles];
}

- (void)addIPATapped:(id)sender {
    // Use iOS native Files app (UIDocumentPickerViewController)
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"com.apple.itunes.ipa"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *destDir = @"/var/mobile/Documents/IPAInstaller";
    [fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:nil];

    for (NSURL *url in urls) {
        // Start accessing security-scoped resource
        [url startAccessingSecurityScopedResource];

        NSString *fileName = url.lastPathComponent;
        NSString *destPath = [destDir stringByAppendingPathComponent:fileName];

        // Copy file
        NSError *error = nil;
        if ([fm fileExistsAtPath:destPath]) {
            [fm removeItemAtPath:destPath error:nil];
        }

        // For security-scoped resources, we need to use NSFileCoordinator
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingForUploading error:&error byAccessor:^(NSURL *newURL) {
            NSError *copyError = nil;
            [fm copyItemAtPath:newURL.path toPath:destPath error:&copyError];
            if (copyError) {
                [[Logger sharedLogger] error:[NSString stringWithFormat:@"Failed to copy %@: %@", fileName, copyError.localizedDescription]];
            } else {
                [[Logger sharedLogger] info:[NSString stringWithFormat:@"Copied %@ to Documents", fileName]];
            }
        }];

        [url stopAccessingSecurityScopedResource];
    }

    [self loadIPAFiles];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    // User cancelled
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.ipaFiles.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"IPACell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:1.0];
        cell.layer.cornerRadius = 14;
        cell.layer.masksToBounds = YES;
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        cell.detailTextLabel.numberOfLines = 2;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.imageView.layer.cornerRadius = 10;
        cell.imageView.layer.masksToBounds = YES;
    }

    IPAExtractedInfo *info = self.ipaFiles[indexPath.row];
    cell.textLabel.text = info.displayName ?: info.name;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  •  %@  •  %@",
                                  info.version, info.bundleID, info.formattedSize];

    UIImage *icon = info.icon;
    if (icon) {
        CGSize size = CGSizeMake(52, 52);
        UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
        [icon drawInRect:CGRectMake(0, 0, size.width, size.height)];
        UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        cell.imageView.image = scaled;
    } else {
        cell.imageView.image = [[UIImage systemImageNamed:@"doc.zipper"] imageWithTintColor:[UIColor colorWithWhite:0.4 alpha:1.0]];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IPAExtractedInfo *info = self.ipaFiles[indexPath.row];
    IPAInstallViewController *installVC = [[IPAInstallViewController alloc] initWithIPAInfo:info];
    [self.navigationController pushViewController:installVC animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"حذف"
                                                                             handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        IPAExtractedInfo *info = self.ipaFiles[indexPath.row];
        [[NSFileManager defaultManager] removeItemAtPath:info.filePath error:nil];
        [self.ipaFiles removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        completionHandler(YES);
    }];
    deleteAction.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0];
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

@end
