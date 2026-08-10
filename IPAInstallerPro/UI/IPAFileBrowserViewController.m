#import "IPAFileBrowserViewController.h"
#import "Core/Logger.h"

@interface IPAFileBrowserViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSMutableArray *filteredItems;
@property (nonatomic, strong) UIToolbar *toolbar;
@property (nonatomic, strong) NSString *clipboardPath;
@property (nonatomic, assign) BOOL clipboardIsCut;
@end

@implementation IPAFileBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.currentPath.lastPathComponent ?: @"ملفات IPA";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    if (!self.currentPath) self.currentPath = @"/var/mobile";
    self.items = [NSMutableArray array];
    self.filteredItems = [NSMutableArray array];

    [self setupNavigationBar];
    [self setupToolbar];
    [self setupTableView];
    [self setupSearchController];
    [self loadDirectory];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadDirectory];
}

- (void)setupNavigationBar {
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"إلغاء" style:UIBarButtonItemStylePlain target:self action:@selector(cancelTapped:)];
    self.navigationItem.leftBarButtonItem.tintColor = [UIColor whiteColor];

    // Add "Select" button for multi-select operations
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"تحديد" style:UIBarButtonItemStylePlain target:self action:@selector(selectTapped:)];
    self.navigationItem.rightBarButtonItem.tintColor = [UIColor whiteColor];
}

- (void)setupToolbar {
    self.toolbar = [[UIToolbar alloc] init];
    self.toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    self.toolbar.barStyle = UIBarStyleBlack;
    self.toolbar.tintColor = [UIColor whiteColor];
    [self.view addSubview:self.toolbar];

    UIBarButtonItem *backBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.backward"] style:UIBarButtonItemStylePlain target:self action:@selector(goBack:)];
    UIBarButtonItem *flex1 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *newFolderBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder.badge.plus"] style:UIBarButtonItemStylePlain target:self action:@selector(createFolder:)];
    UIBarButtonItem *flex2 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *pasteBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"doc.on.clipboard"] style:UIBarButtonItemStylePlain target:self action:@selector(pasteItem:)];

    self.toolbar.items = @[backBtn, flex1, newFolderBtn, flex2, pasteBtn];

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [self.toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.toolbar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.toolbar.heightAnchor constraintEqualToConstant:44]
    ]];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 64;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.toolbar.topAnchor]
    ]];
}

- (void)setupSearchController {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"بحث في المجلد...";
    self.searchController.searchBar.tintColor = [UIColor whiteColor];
    self.searchController.searchBar.searchTextField.textColor = [UIColor whiteColor];
    self.searchController.searchBar.searchTextField.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
}

- (void)loadDirectory {
    [self.items removeAllObjects];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *contents = [fm contentsOfDirectoryAtPath:self.currentPath error:&error];

    if (error) {
        [[Logger sharedLogger] error:[NSString stringWithFormat:@"Failed to read directory %@: %@", self.currentPath, error.localizedDescription]];
    }

    for (NSString *item in contents) {
        if ([item hasPrefix:@"."] && ![item isEqualToString:@"."]) continue;
        NSString *fullPath = [self.currentPath stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        [fm fileExistsAtPath:fullPath isDirectory:&isDir];

        NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
        NSNumber *size = attrs[NSFileSize] ?: @0;
        NSDate *modDate = attrs[NSFileModificationDate] ?: [NSDate date];

        [self.items addObject:@{
            @"name": item,
            @"path": fullPath,
            @"isDir": @(isDir),
            @"size": size,
            @"date": modDate
        }];
    }

    [self.items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if ([a[@"isDir"] boolValue] && ![b[@"isDir"] boolValue]) return NSOrderedAscending;
        if (![a[@"isDir"] boolValue] && [b[@"isDir"] boolValue]) return NSOrderedDescending;
        return [a[@"name"] compare:b[@"name"] options:NSCaseInsensitiveSearch];
    }];

    self.filteredItems = [self.items mutableCopy];
    [self.tableView reloadData];

    // Update back button state
    self.toolbar.items[0].enabled = ![self.currentPath isEqualToString:@"/var/mobile"];
}

- (void)cancelTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)selectTapped:(id)sender {
    // Toggle edit mode for multi-select
    [self.tableView setEditing:!self.tableView.isEditing animated:YES];
    self.navigationItem.rightBarButtonItem.title = self.tableView.isEditing ? @"تم" : @"تحديد";
}

- (void)goBack:(id)sender {
    NSString *parent = [self.currentPath stringByDeletingLastPathComponent];
    if ([parent length] > 0 && ![parent isEqualToString:self.currentPath]) {
        IPAFileBrowserViewController *parentVC = [[IPAFileBrowserViewController alloc] init];
        parentVC.currentPath = parent;
        parentVC.onFileSelected = self.onFileSelected;
        [self.navigationController pushViewController:parentVC animated:YES];
    }
}

- (void)createFolder:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"مجلد جديد" message:@"أدخل اسم المجلد" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"اسم المجلد";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"إنشاء" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields[0].text;
        if (name.length > 0) {
            NSString *newPath = [self.currentPath stringByAppendingPathComponent:name];
            [[NSFileManager defaultManager] createDirectoryAtPath:newPath withIntermediateDirectories:YES attributes:nil error:nil];
            [self loadDirectory];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)pasteItem:(id)sender {
    if (!self.clipboardPath) {
        [self showAlert:@"لا يوجد شيء في الحافظة"];
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *destName = self.clipboardPath.lastPathComponent;
    NSString *destPath = [self.currentPath stringByAppendingPathComponent:destName];

    if ([fm fileExistsAtPath:destPath]) {
        destPath = [self generateUniquePath:destPath];
    }

    NSError *error = nil;
    if (self.clipboardIsCut) {
        [fm moveItemAtPath:self.clipboardPath toPath:destPath error:&error];
        self.clipboardPath = nil;
    } else {
        [fm copyItemAtPath:self.clipboardPath toPath:destPath error:&error];
    }

    if (error) {
        [self showAlert:[NSString stringWithFormat:@"فشل: %@", error.localizedDescription]];
    } else {
        [self loadDirectory];
    }
}

- (NSString *)generateUniquePath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *base = [path stringByDeletingPathExtension];
    NSString *ext = path.pathExtension;
    int counter = 1;
    NSString *newPath = path;
    while ([fm fileExistsAtPath:newPath]) {
        if (ext.length > 0) {
            newPath = [NSString stringWithFormat:@"%@ (%d).%@", base, counter, ext];
        } else {
            newPath = [NSString stringWithFormat:@"%@ (%d)", base, counter];
        }
        counter++;
    }
    return newPath;
}

- (void)showAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تنبيه" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)formatSize:(long long)bytes {
    if (bytes < 1024) return [NSString stringWithFormat:@"%lld B", bytes];
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
    if (bytes < 1024 * 1024 * 1024) return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
}

- (NSString *)formatDate:(NSDate *)date {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ar"];
    return [formatter stringFromDate:date];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text ?: @"";
    if (query.length == 0) {
        self.filteredItems = [self.items mutableCopy];
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@", query];
        self.filteredItems = [[self.items filteredArrayUsingPredicate:predicate] mutableCopy];
    }
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filteredItems.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"BrowserCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        cell.detailTextLabel.numberOfLines = 1;
    }

    NSDictionary *item = self.filteredItems[indexPath.row];
    BOOL isDir = [item[@"isDir"] boolValue];
    long long size = [item[@"size"] longLongValue];
    NSDate *date = item[@"date"];

    cell.textLabel.text = item[@"name"];
    if (isDir) {
        cell.imageView.image = [[UIImage systemImageNamed:@"folder.fill"] imageWithTintColor:[UIColor colorWithRed:0.4 green:0.5 blue:0.9 alpha:1.0]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"📁 مجلد • %@", [self formatDate:date]];
    } else {
        NSString *ext = [item[@"name"] pathExtension].lowercaseString;
        if ([ext isEqualToString:@"ipa"]) {
            cell.imageView.image = [[UIImage systemImageNamed:@"doc.zipper"] imageWithTintColor:[UIColor colorWithRed:0.3 green:0.7 blue:0.5 alpha:1.0]];
        } else {
            cell.imageView.image = [[UIImage systemImageNamed:@"doc"] imageWithTintColor:[UIColor colorWithWhite:0.5 alpha:1.0]];
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", [self formatSize:size], [self formatDate:date]];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.filteredItems[indexPath.row];

    if ([item[@"isDir"] boolValue]) {
        IPAFileBrowserViewController *next = [[IPAFileBrowserViewController alloc] init];
        next.currentPath = item[@"path"];
        next.onFileSelected = self.onFileSelected;
        [self.navigationController pushViewController:next animated:YES];
    } else {
        if (self.onFileSelected) {
            self.onFileSelected(item[@"path"]);
        }
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - Swipe Actions (Copy, Cut, Delete, Rename)

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.filteredItems[indexPath.row];
    NSString *path = item[@"path"];

    // Copy action
    UIContextualAction *copyAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:@"نسخ"
        handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            self.clipboardPath = path;
            self.clipboardIsCut = NO;
            [self showAlert:@"تم النسخ إلى الحافظة"];
            completionHandler(YES);
        }];
    copyAction.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.9 alpha:1.0];
    copyAction.image = [UIImage systemImageNamed:@"doc.on.doc"];

    // Cut action
    UIContextualAction *cutAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:@"قص"
        handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            self.clipboardPath = path;
            self.clipboardIsCut = YES;
            [self showAlert:@"تم القص إلى الحافظة"];
            completionHandler(YES);
        }];
    cutAction.backgroundColor = [UIColor colorWithRed:0.9 green:0.6 blue:0.1 alpha:1.0];
    cutAction.image = [UIImage systemImageNamed:@"scissors"];

    // Rename action
    UIContextualAction *renameAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:@"إعادة تسمية"
        handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"إعادة تسمية" message:@"أدخل الاسم الجديد" preferredStyle:UIAlertControllerStyleAlert];
            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.text = item[@"name"];
            }];
            [alert addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                NSString *newName = alert.textFields[0].text;
                if (newName.length > 0) {
                    NSString *newPath = [self.currentPath stringByAppendingPathComponent:newName];
                    NSError *error = nil;
                    [[NSFileManager defaultManager] moveItemAtPath:path toPath:newPath error:&error];
                    if (error) {
                        [self showAlert:[NSString stringWithFormat:@"فشل: %@", error.localizedDescription]];
                    } else {
                        [self loadDirectory];
                    }
                }
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            completionHandler(YES);
        }];
    renameAction.backgroundColor = [UIColor colorWithRed:0.4 green:0.4 blue:0.9 alpha:1.0];
    renameAction.image = [UIImage systemImageNamed:@"pencil"];

    // Delete action
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"حذف"
        handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"تأكيد الحذف" message:[NSString stringWithFormat:@"هل أنت متأكد من حذف "%@"؟", item[@"name"]] preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:@"حذف" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                NSError *error = nil;
                [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
                if (error) {
                    [self showAlert:[NSString stringWithFormat:@"فشل الحذف: %@", error.localizedDescription]];
                } else {
                    [self loadDirectory];
                }
            }]];
            [confirm addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:confirm animated:YES completion:nil];
            completionHandler(YES);
        }];
    deleteAction.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0];
    deleteAction.image = [UIImage systemImageNamed:@"trash"];

    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, renameAction, cutAction, copyAction]];
}

@end
