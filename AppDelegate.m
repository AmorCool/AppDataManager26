#import "AppDelegate.h"
#import "ViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:[[ViewController alloc] init]];
    navController.navigationBar.prefersLargeTitles = YES;

    self.window.rootViewController = navController;
    // Force RTL for Arabic interface
    [[UIView appearance] setSemanticContentAttribute:UISemanticContentAttributeForceRightToLeft];
    [[UITableView appearance] setSemanticContentAttribute:UISemanticContentAttributeForceRightToLeft];
    [[UINavigationBar appearance] setSemanticContentAttribute:UISemanticContentAttributeForceRightToLeft];

    [self.window makeKeyAndVisible];

    return YES;
}

@end
