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
@property (nonatomic, readonly) BOOL isDemoFlowRunning;
@property (nonatomic, copy, readonly) NSString *eventRuleMode;
@property (nonatomic, copy, readonly) NSArray<NSString *> *discoveredDeviceLabels;

- (instancetype)initWithLogHandler:(BLECentralLogHandler)logHandler;
- (void)startScan;
- (void)stopScan;
- (void)connectDeviceAtIndex:(NSUInteger)index;
- (void)disconnect;
- (void)readValue;
- (void)setNotifyEnabled:(BOOL)enabled;
- (void)writeText:(NSString *)text;
- (void)sendPairCode:(NSString *)code;
- (void)sendProtocolPing;
- (void)sendProtocolGetInfo;
- (void)sendProtocolEcho:(NSString *)text;
- (void)sendTelemetryRequest;
- (void)sendCommandNamed:(NSString *)name;
- (void)sendEventRuleMode:(NSString *)mode;
- (void)sendRawText:(NSString *)text;
- (void)runDemoFlow;

@end

NS_ASSUME_NONNULL_END
