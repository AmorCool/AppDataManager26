#import "IPAFileBrowserViewController.h"
#import "Core/Logger.h"

@interface IPAFileBrowserViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *filteredItems;
@end

@implementation IPAFileBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"اختر ملف IPA";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    if (!self.currentPath) self.currentPath = @"/var/mobile";
    self.items = [NSMutableArray array];
    self.filteredItems = [NSMutableArray array];

    [self setupNavigationBar];
    [self setupTableView];
    [self setupSearchController];
    [self loadDirectory];
}

- (void)setupNavigationBar {
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"إلغاء" style:UIBarButtonItemStylePlain target:self action:@selector(cancelTapped:)];
    self.navigationItem.leftBarButtonItem.tintColor = [UIColor whiteColor];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 56;
    [self.view addSubview:self.tableView];
}

- (void)setupSearchController {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"بحث...";
    self.searchController.searchBar.tintColor = [UIColor whiteColor];
    self.searchController.searchBar.searchTextField.textColor = [UIColor whiteColor];
    self.searchController.searchBar.searchTextField.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
}

- (void)loadDirectory {
    [self.items removeAllObjects];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm contentsOfDirectoryAtPath:self.currentPath error:nil];

    for (NSString *item in contents) {
        if ([item hasPrefix:@"."]) continue;
        NSString *fullPath = [self.currentPath stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        [fm fileExistsAtPath:fullPath isDirectory:&isDir];

        if (isDir) {
            [self.items addObject:@{@"name": item, @"path": fullPath, @"isDir": @YES, @"size": @0}];
        } else if ([item.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
            NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
            NSNumber *size = attrs[@"NSFileSize"] ?: @0;
            [self.items addObject:@{@"name": item, @"path": fullPath, @"isDir": @NO, @"size": size}];
        }
    }

    [self.items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if ([a[@"isDir"] boolValue] && ![b[@"isDir"] boolValue]) return NSOrderedAscending;
        if (![a[@"isDir"] boolValue] && [b[@"isDir"] boolValue]) return NSOrderedDescending;
        return [a[@"name"] compare:b[@"name"] options:NSCaseInsensitiveSearch];
    }];

    self.filteredItems = [self.items mutableCopy];
    [self.tableView reloadData];
}

- (void)cancelTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSString *)formatSize:(long long)bytes {
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
    return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
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
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.13 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    }

    NSDictionary *item = self.filteredItems[indexPath.row];
    BOOL isDir = [item[@"isDir"] boolValue];

    cell.textLabel.text = item[@"name"];
    if (isDir) {
        cell.imageView.image = [[UIImage systemImageNamed:@"folder.fill"] imageWithTintColor:[UIColor colorWithRed:0.4 green:0.5 blue:0.9 alpha:1.0]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.detailTextLabel.text = @"";
    } else {
        cell.imageView.image = [[UIImage systemImageNamed:@"doc.zipper"] imageWithTintColor:[UIColor colorWithRed:0.3 green:0.7 blue:0.5 alpha:1.0]];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.detailTextLabel.text = [self formatSize:[item[@"size"] longLongValue]];
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

@end
