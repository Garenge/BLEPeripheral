#import "BLEPeripheralController.h"
#import <CoreBluetooth/CoreBluetooth.h>

static NSString * const kDemoPeripheralName = @"MacBLE-Demo";
static NSString * const kDemoServiceUUIDString = @"0000FFF0-0000-1000-8000-00805F9B34FB";
static NSString * const kDemoCharacteristicUUIDString = @"0000FFF1-0000-1000-8000-00805F9B34FB";

@interface BLEPeripheralController () <CBPeripheralManagerDelegate>

@property (nonatomic, copy) BLEPeripheralLogHandler logHandler;
@property (nonatomic, strong) CBPeripheralManager *peripheralManager;
@property (nonatomic, strong) CBMutableCharacteristic *demoCharacteristic;
@property (nonatomic, strong) NSMutableData *currentValue;
@property (nonatomic, strong, nullable) NSTimer *notifyTimer;
@property (nonatomic) NSUInteger notifyCount;
@property (nonatomic) BOOL hasSubscribers;

@end

@implementation BLEPeripheralController

- (instancetype)initWithLogHandler:(BLEPeripheralLogHandler)logHandler {
    self = [super init];
    if (self) {
        _logHandler = [logHandler copy];
        _currentValue = [NSMutableData dataWithData:[@"Hello from macOS BLE Peripheral" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    return self;
}

- (void)start {
    self.peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil];
    [self log:@"Initializing CBPeripheralManager..."];
}

- (void)stop {
    [self.notifyTimer invalidate];
    self.notifyTimer = nil;
    [self.peripheralManager stopAdvertising];
    [self.peripheralManager removeAllServices];
    [self log:@"Peripheral stopped."];
}

- (void)setupServiceAndAdvertise {
    CBUUID *serviceUUID = [CBUUID UUIDWithString:kDemoServiceUUIDString];
    CBUUID *characteristicUUID = [CBUUID UUIDWithString:kDemoCharacteristicUUIDString];

    CBCharacteristicProperties properties = (CBCharacteristicPropertyRead |
                                             CBCharacteristicPropertyWrite |
                                             CBCharacteristicPropertyWriteWithoutResponse |
                                             CBCharacteristicPropertyNotify);
    CBAttributePermissions permissions = (CBAttributePermissionsReadable |
                                          CBAttributePermissionsWriteable);

    self.demoCharacteristic = [[CBMutableCharacteristic alloc] initWithType:characteristicUUID
                                                                 properties:properties
                                                                      value:nil
                                                                permissions:permissions];

    CBMutableService *service = [[CBMutableService alloc] initWithType:serviceUUID primary:YES];
    service.characteristics = @[ self.demoCharacteristic ];

    [self.peripheralManager removeAllServices];
    [self.peripheralManager addService:service];
    [self log:[NSString stringWithFormat:@"Adding service %@ with characteristic %@...", serviceUUID.UUIDString, characteristicUUID.UUIDString]];
}

- (void)startAdvertising {
    NSDictionary *advertisementData = @{
        CBAdvertisementDataLocalNameKey: kDemoPeripheralName,
        CBAdvertisementDataServiceUUIDsKey: @[ [CBUUID UUIDWithString:kDemoServiceUUIDString] ],
    };
    [self.peripheralManager startAdvertising:advertisementData];
    [self log:[NSString stringWithFormat:@"Advertising as \"%@\"...", kDemoPeripheralName]];
}

- (void)startNotifyTimerIfNeeded {
    if (self.notifyTimer != nil) {
        return;
    }

    self.notifyTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                        target:self
                                                      selector:@selector(sendNotificationTick)
                                                      userInfo:nil
                                                       repeats:YES];
    [self log:@"Notify timer started. A notification will be sent every 2 seconds while subscribed."];
}

- (void)sendNotificationTick {
    if (!self.hasSubscribers) {
        return;
    }

    self.notifyCount += 1;
    NSString *payload = [NSString stringWithFormat:@"notify #%lu from Mac at %@",
                         (unsigned long)self.notifyCount,
                         [NSDateFormatter localizedStringFromDate:NSDate.date
                                                        dateStyle:NSDateFormatterNoStyle
                                                        timeStyle:NSDateFormatterMediumStyle]];
    NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
    BOOL didSend = [self.peripheralManager updateValue:data
                                     forCharacteristic:self.demoCharacteristic
                                  onSubscribedCentrals:nil];
    if (didSend) {
        [self log:[NSString stringWithFormat:@"Notify sent: %@", payload]];
    } else {
        [self log:@"Notify backpressure: CoreBluetooth asked us to retry later."];
    }
}

- (void)log:(NSString *)message {
    if (self.logHandler) {
        self.logHandler(message);
    }
}

#pragma mark - CBPeripheralManagerDelegate

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
    switch (peripheral.state) {
        case CBManagerStatePoweredOn:
            [self log:@"Bluetooth is powered on."];
            [self setupServiceAndAdvertise];
            break;
        case CBManagerStatePoweredOff:
            [self log:@"Bluetooth is powered off. Turn Bluetooth on in System Settings."];
            break;
        case CBManagerStateUnauthorized:
            [self log:@"Bluetooth is unauthorized. Check app Bluetooth permission in System Settings > Privacy & Security > Bluetooth."];
            break;
        case CBManagerStateUnsupported:
            [self log:@"Bluetooth LE peripheral mode is unsupported on this Mac."];
            break;
        case CBManagerStateResetting:
            [self log:@"Bluetooth is resetting..."];
            break;
        case CBManagerStateUnknown:
        default:
            [self log:@"Bluetooth state is unknown..."];
            break;
    }
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral didAddService:(CBService *)service error:(NSError *)error {
    if (error) {
        [self log:[NSString stringWithFormat:@"Failed to add service: %@", error.localizedDescription]];
        return;
    }

    [self log:[NSString stringWithFormat:@"Service added: %@", service.UUID.UUIDString]];
    [self startAdvertising];
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error {
    if (error) {
        [self log:[NSString stringWithFormat:@"Failed to start advertising: %@", error.localizedDescription]];
        return;
    }

    [self log:@"Advertising started. Scan from iPhone Central now."];
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral didReceiveReadRequest:(CBATTRequest *)request {
    if (![request.characteristic.UUID isEqual:self.demoCharacteristic.UUID]) {
        [peripheral respondToRequest:request withResult:CBATTErrorAttributeNotFound];
        return;
    }

    if (request.offset > self.currentValue.length) {
        [peripheral respondToRequest:request withResult:CBATTErrorInvalidOffset];
        return;
    }

    request.value = [self.currentValue subdataWithRange:NSMakeRange(request.offset, self.currentValue.length - request.offset)];
    [peripheral respondToRequest:request withResult:CBATTErrorSuccess];

    NSString *text = [[NSString alloc] initWithData:request.value encoding:NSUTF8StringEncoding] ?: request.value.description;
    [self log:[NSString stringWithFormat:@"Read request responded: %@", text]];
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral didReceiveWriteRequests:(NSArray<CBATTRequest *> *)requests {
    for (CBATTRequest *request in requests) {
        if (![request.characteristic.UUID isEqual:self.demoCharacteristic.UUID]) {
            [peripheral respondToRequest:request withResult:CBATTErrorAttributeNotFound];
            return;
        }

        [self.currentValue setData:request.value ?: NSData.data];
        NSString *text = [[NSString alloc] initWithData:self.currentValue encoding:NSUTF8StringEncoding] ?: self.currentValue.description;
        [self log:[NSString stringWithFormat:@"Write received: %@", text]];

        if (self.hasSubscribers) {
            BOOL didEcho = [peripheral updateValue:self.currentValue forCharacteristic:self.demoCharacteristic onSubscribedCentrals:nil];
            [self log:didEcho ? @"Echo notify sent for written value." : @"Echo notify queued by CoreBluetooth."];
        }
    }

    CBATTRequest *firstRequest = requests.firstObject;
    if (firstRequest) {
        [peripheral respondToRequest:firstRequest withResult:CBATTErrorSuccess];
    }
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didSubscribeToCharacteristic:(CBCharacteristic *)characteristic {
    self.hasSubscribers = YES;
    [self log:[NSString stringWithFormat:@"Central subscribed: %@, MTU: %lu", central.identifier.UUIDString, (unsigned long)central.maximumUpdateValueLength]];
    [self startNotifyTimerIfNeeded];
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic {
    self.hasSubscribers = NO;
    [self log:[NSString stringWithFormat:@"Central unsubscribed: %@", central.identifier.UUIDString]];
}

- (void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)peripheral {
    [self log:@"CoreBluetooth is ready to send more notifications."];
}

@end
