#import <UIKit/UIKit.h>

@interface BackupManagerViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

- (instancetype)initWithBundleID:(NSString *)bundleID appName:(NSString *)appName;
- (instancetype)init;

@end
