#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^BLECentralLogHandler)(NSString *message);
typedef void (^BLECentralDiscoveryHandler)(void);

@interface BLECentralController : NSObject

@property (nonatomic, copy, nullable) BLECentralDiscoveryHandler discoveryHandler;

@property (nonatomic, readonly) BOOL isScanning;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) BOOL isNotifying;
@property (nonatomic, readonly, copy) NSArray<CBPeripheral *> *discoveredPeripherals;

- (instancetype)initWithLogHandler:(BLECentralLogHandler)logHandler;
- (void)startScan;
- (void)stopScan;
- (void)connectPeripheral:(CBPeripheral *)peripheral;
- (void)disconnect;
- (void)readCharacteristic;
- (void)subscribeNotifications:(BOOL)subscribe;
- (void)sendProtocolPing;
- (void)sendProtocolGetInfo;
- (void)sendProtocolEcho:(NSString *)text;
- (void)sendLegacyText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
