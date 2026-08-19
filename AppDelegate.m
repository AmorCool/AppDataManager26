#import "AppDelegate.h"
#import "MainViewController.h"
#import "BackupManagerViewController.h"
#import "SettingsViewController.h"

@interface AppDelegate ()
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    UITabBarController *tabBarController = [[UITabBarController alloc] init];

    MainViewController *mainVC = [[MainViewController alloc] init];
    UINavigationController *mainNav = [[UINavigationController alloc] initWithRootViewController:mainVC];
    mainNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"التطبيقات"
        image:[UIImage systemImageNamed:@"square.grid.2x2"] selectedImage:[UIImage systemImageNamed:@"square.grid.2x2.fill"]];

    BackupManagerViewController *backupVC = [[BackupManagerViewController alloc] init];
    UINavigationController *backupNav = [[UINavigationController alloc] initWithRootViewController:backupVC];
    backupNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"النسخ"
        image:[UIImage systemImageNamed:@"clock.arrow.circlepath"] selectedImage:[UIImage systemImageNamed:@"clock.arrow.circlepath"]];

    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"الإعدادات"
        image:[UIImage systemImageNamed:@"gearshape"] selectedImage:[UIImage systemImageNamed:@"gearshape.fill"]];

    tabBarController.viewControllers = @[mainNav, backupNav, settingsNav];
    tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.55 green:0.45 blue:0.95 alpha:1.0];
    tabBarController.tabBar.barTintColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    tabBarController.tabBar.unselectedItemTintColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    tabBarController.tabBar.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:1.0];

    for (UINavigationController *nav in tabBarController.viewControllers) {
        nav.navigationBar.barTintColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
        nav.navigationBar.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
        nav.navigationBar.translucent = NO;
    }

    self.window.rootViewController = tabBarController;
    [self.window makeKeyAndVisible];
    [self showWelcomeIfNeeded];
    return YES;
}

- (void)showWelcomeIfNeeded {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"HasLaunchedBefore"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSString *message = @"AppData Manager v1.7.17\n\n"
                @"مجانية بالكامل — لا تُباع ولا تتطلب أي رسوم.\n\n"
                @"إذا حاول أي شخص بيع الأداة أو طلب مبلغ مقابل الحصول عليها، فهذا غير رسمي.\n\n"
                @"للإبلاغ عن أي حالة بيع أو استغلال للأداة:\n"
                @"X: @Zainqkvd\n\n"
                @"المطور: ZAIN";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"حول AppData Manager" message:message preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _) {
                [defaults setBool:YES forKey:@"HasLaunchedBefore"]; [defaults synchronize];
            }];
            [alert addAction:okAction];
            UIViewController *topVC = self.window.rootViewController;
            while (topVC.presentedViewController) topVC = topVC.presentedViewController;
            [topVC presentViewController:alert animated:YES completion:nil];
        });
    }
}

@end
