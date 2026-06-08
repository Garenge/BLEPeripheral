#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^BLECentralLogHandler)(NSString *message);
typedef void (^BLECentralDiscoveryHandler)(void);
typedef void (^BLECentralStateHandler)(void);

@interface BLECentralController : NSObject

@property (nonatomic, copy, nullable) BLECentralDiscoveryHandler discoveryHandler;
@property (nonatomic, copy, nullable) BLECentralStateHandler stateHandler;

@property (nonatomic, readonly) BOOL isScanning;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) BOOL isNotifying;
@property (nonatomic, readonly) BOOL isCharacteristicReady;
@property (nonatomic, readonly) BOOL isDemoFlowRunning;
@property (nonatomic, readonly, copy) NSString *eventRuleMode;
@property (nonatomic, readonly, copy) NSArray<CBPeripheral *> *discoveredPeripherals;

- (instancetype)initWithLogHandler:(BLECentralLogHandler)logHandler;
- (void)startScan;
- (void)stopScan;
- (void)connectPeripheral:(CBPeripheral *)peripheral;
- (NSString *)detailForDiscoveredPeripheralAtIndex:(NSUInteger)index;
- (void)disconnect;
- (void)readCharacteristic;
- (void)subscribeNotifications:(BOOL)subscribe;
- (void)sendProtocolPairCode:(NSString *)code;
- (void)sendProtocolPing;
- (void)sendProtocolGetInfo;
- (void)sendProtocolEcho:(NSString *)text;
- (void)sendProtocolTelemetry;
- (void)sendProtocolCommand:(NSString *)name;
- (void)sendProtocolEventRuleMode:(NSString *)mode;
- (void)sendLegacyText:(NSString *)text;
- (void)runDemoFlow;

@end

NS_ASSUME_NONNULL_END
