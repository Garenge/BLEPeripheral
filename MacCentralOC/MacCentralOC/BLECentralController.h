#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^BLECentralLogHandler)(NSString *message);
typedef void (^BLECentralStateHandler)(void);

@interface BLECentralController : NSObject

@property (nonatomic, copy, nullable) BLECentralStateHandler stateHandler;
@property (nonatomic, readonly) BOOL isScanning;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) BOOL isNotifyEnabled;
@property (nonatomic, readonly) BOOL isCharacteristicReady;
@property (nonatomic, copy, readonly) NSArray<NSString *> *discoveredDeviceLabels;

- (instancetype)initWithLogHandler:(BLECentralLogHandler)logHandler;
- (void)startScan;
- (void)stopScan;
- (void)connectDeviceAtIndex:(NSUInteger)index;
- (void)disconnect;
- (void)readValue;
- (void)setNotifyEnabled:(BOOL)enabled;
- (void)writeText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
