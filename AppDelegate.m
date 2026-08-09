#import "AppDelegate.h"
#import "MainViewController.h"
#import "BackupManagerViewController.h"
#import "SettingsViewController.h"

@interface AppDelegate ()
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    // Create tab bar controller
    UITabBarController *tabBarController = [[UITabBarController alloc] init];

    // Apps tab
    MainViewController *mainVC = [[MainViewController alloc] init];
    UINavigationController *mainNav = [[UINavigationController alloc] initWithRootViewController:mainVC];
    mainNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Apps"
                                                         image:[UIImage systemImageNamed:@"square.grid.2x2"]
                                                 selectedImage:[UIImage systemImageNamed:@"square.grid.2x2.fill"]];

    // Backups tab
    BackupManagerViewController *backupVC = [[BackupManagerViewController alloc] init];
    UINavigationController *backupNav = [[UINavigationController alloc] initWithRootViewController:backupVC];
    backupNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Backups"
                                                           image:[UIImage systemImageNamed:@"clock.arrow.circlepath"]
                                                   selectedImage:[UIImage systemImageNamed:@"clock.arrow.circlepath"]];

    // Settings tab
    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings"
                                                            image:[UIImage systemImageNamed:@"gearshape"]
                                                    selectedImage:[UIImage systemImageNamed:@"gearshape.fill"]];

    tabBarController.viewControllers = @[mainNav, backupNav, settingsNav];
    tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.42 green:0.31 blue:0.90 alpha:1.0];
    tabBarController.tabBar.barTintColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    tabBarController.tabBar.unselectedItemTintColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    tabBarController.tabBar.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:1.0];

    // Style navigation bars
    for (UINavigationController *nav in tabBarController.viewControllers) {
        nav.navigationBar.barTintColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
        nav.navigationBar.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
        nav.navigationBar.translucent = NO;
    }

    self.window.rootViewController = tabBarController;
    [self.window makeKeyAndVisible];

    return YES;
}

@end
