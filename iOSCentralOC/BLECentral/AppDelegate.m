#import "AppDelegate.h"
#import "BLECentralController.h"
#import "ViewController.h"

@interface AppDelegate ()

@property (nonatomic, strong) BLECentralController *centralController;
@property (nonatomic, strong) ViewController *rootViewController;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    __weak typeof(self) weakSelf = self;
    self.centralController = [[BLECentralController alloc] initWithLogHandler:^(NSString *message) {
        [weakSelf appendLog:message];
    }];

    self.rootViewController = [[ViewController alloc] initWithCentralController:self.centralController];

    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:self.rootViewController];

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = navigationController;
    [self.window makeKeyAndVisible];

    [self appendLog:@"BLE Central ready. Start Mac peripheral, then tap Scan."];
    return YES;
}

- (void)appendLog:(NSString *)message {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:NSDate.date], message];
    [self.rootViewController appendLogLine:line];
}

@end
