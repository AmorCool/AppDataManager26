#import "MainViewController.h"
#import "AppDataManager.h"
#import "AppDetailViewController.h"

@interface MainViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray *apps;
@property (nonatomic, strong) NSArray *filteredApps;
@property (nonatomic, strong) UIView *statsCard;
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    self.title = @"AppData Manager";

    [self setupUI];
    [self loadApps];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadApps];
}

- (void)setupUI {
    // Title label
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"AppData Manager";
    titleLabel.font = [UIFont boldSystemFontOfSize:32];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = @"Manage app data, backup & restore";
    subtitleLabel.font = [UIFont systemFontOfSize:14];
    subtitleLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:subtitleLabel];

    // Stats card
    self.statsCard = [self createStatsCard];
    [self.view addSubview:self.statsCard];

    // Search bar
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.placeholder = @"Search apps...";
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.searchBar.layer.cornerRadius = 12;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    // Table view
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 80;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],

        [self.statsCard.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:20],
        [self.statsCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.statsCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.statsCard.heightAnchor constraintEqualToConstant:90],

        [self.searchBar.topAnchor constraintEqualToAnchor:self.statsCard.bottomAnchor constant:16],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.searchBar.heightAnchor constraintEqualToConstant:44],

        [self.tableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (UIView *)createStatsCard {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.15 alpha:1.0];
    card.layer.cornerRadius = 16;
    card.translatesAutoresizingMaskIntoConstraints = NO;

    // Apps count
    UILabel *appsIcon = [[UILabel alloc] init];
    appsIcon.text = @"\U0001F4E6";
    appsIcon.font = [UIFont systemFontOfSize:24];
    appsIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:appsIcon];

    UILabel *appsCount = [[UILabel alloc] init];
    appsCount.tag = 100;
    appsCount.text = @"0";
    appsCount.font = [UIFont boldSystemFontOfSize:28];
    appsCount.textColor = [UIColor whiteColor];
    appsCount.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:appsCount];

    UILabel *appsLabel = [[UILabel alloc] init];
    appsLabel.text = @"Total Apps";
    appsLabel.font = [UIFont systemFontOfSize:12];
    appsLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    appsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:appsLabel];

    // Size
    UILabel *sizeCount = [[UILabel alloc] init];
    sizeCount.tag = 101;
    sizeCount.text = @"0 B";
    sizeCount.font = [UIFont boldSystemFontOfSize:28];
    sizeCount.textColor = [UIColor colorWithRed:0.4 green:0.3 blue:0.9 alpha:1.0];
    sizeCount.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:sizeCount];

    UILabel *sizeLabel = [[UILabel alloc] init];
    sizeLabel.text = @"Total Size";
    sizeLabel.font = [UIFont systemFontOfSize:12];
    sizeLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:sizeLabel];

    [NSLayoutConstraint activateConstraints:@[
        [appsIcon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [appsIcon.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],

        [appsCount.leadingAnchor constraintEqualToAnchor:appsIcon.trailingAnchor constant:12],
        [appsCount.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],

        [appsLabel.leadingAnchor constraintEqualToAnchor:appsCount.leadingAnchor],
        [appsLabel.topAnchor constraintEqualToAnchor:appsCount.bottomAnchor constant:4],

        [sizeCount.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [sizeCount.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],

        [sizeLabel.trailingAnchor constraintEqualToAnchor:sizeCount.trailingAnchor],
        [sizeLabel.topAnchor constraintEqualToAnchor:sizeCount.bottomAnchor constant:4]
    ]];

    return card;
}

- (void)loadApps {
    self.apps = [[AppDataManager sharedManager] allInstalledApplications];
    self.filteredApps = self.apps;
    [self updateStats];
    [self.tableView reloadData];
}

- (void)updateStats {
    UILabel *appsCount = [self.statsCard viewWithTag:100];
    UILabel *sizeCount = [self.statsCard viewWithTag:101];

    appsCount.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.apps.count];

    unsigned long long totalSize = 0;
    for (NSDictionary *app in self.apps) {
        totalSize += [app[@"size"] unsignedLongLongValue];
    }
    sizeCount.text = [[AppDataManager sharedManager] formatBytes:totalSize];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"AppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    NSDictionary *app = self.filteredApps[indexPath.row];
    cell.textLabel.text = app[@"name"];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];

    cell.detailTextLabel.text = app[@"bundleID"];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];

    // Size label on right
    UILabel *sizeLabel = [[UILabel alloc] init];
    sizeLabel.text = app[@"sizeString"];
    sizeLabel.textColor = [UIColor colorWithRed:0.4 green:0.3 blue:0.9 alpha:1.0];
    sizeLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:sizeLabel];

    [NSLayoutConstraint activateConstraints:@[
        [sizeLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-20],
        [sizeLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
    ]];

    // App icon placeholder
    UIView *iconView = [[UIView alloc] initWithFrame:CGRectMake(16, 16, 48, 48)];
    iconView.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:1.0];
    iconView.layer.cornerRadius = 10;
    [cell.contentView addSubview:iconView];

    cell.imageView.image = nil;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *app = self.filteredApps[indexPath.row];
    AppDetailViewController *detailVC = [[AppDetailViewController alloc] initWithApp:app];
    [self.navigationController pushViewController:detailVC animated:YES];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.filteredApps = self.apps;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR bundleID CONTAINS[cd] %@", searchText, searchText];
        self.filteredApps = [self.apps filteredArrayUsingPredicate:predicate];
    }
    [self.tableView reloadData];
}

@end