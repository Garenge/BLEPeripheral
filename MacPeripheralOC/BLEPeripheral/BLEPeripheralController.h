#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^BLEPeripheralLogHandler)(NSString *message);

@interface BLEPeripheralController : NSObject

- (instancetype)initWithLogHandler:(BLEPeripheralLogHandler)logHandler;
- (void)start;
- (void)stop;
- (void)releaseActiveClient;

@end

NS_ASSUME_NONNULL_END
