#import <UIKit/UIKit.h>
#import "BLECentralController.h"

NS_ASSUME_NONNULL_BEGIN

@interface ViewController : UIViewController

- (instancetype)initWithCentralController:(BLECentralController *)centralController;

- (void)appendLogLine:(NSString *)line;

@end

NS_ASSUME_NONNULL_END
