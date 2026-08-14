#import <UIKit/UIKit.h>

@interface AppDetailViewController : UIViewController
@property (nonatomic, copy) NSDictionary *appInfo;
- (instancetype)initWithAppInfo:(NSDictionary *)appInfo;
@end
