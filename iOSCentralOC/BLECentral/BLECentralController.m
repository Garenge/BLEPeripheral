#import "BLECentralController.h"
#import "BLEProtocolConstants.h"
#import "BLEProtocolMessage.h"

static NSString * const kTargetPeripheralName = @"MacBLE-Demo";
static NSString * const kServiceUUIDString = @"0000FFF0-0000-1000-8000-00805F9B34FB";
static NSString * const kCharacteristicUUIDString = @"0000FFF1-0000-1000-8000-00805F9B34FB";

@interface BLECentralController () <CBCentralManagerDelegate, CBPeripheralDelegate>

@property (nonatomic, copy) BLECentralLogHandler logHandler;
@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic, strong, nullable) CBPeripheral *connectedPeripheral;
@property (nonatomic, strong, nullable) CBCharacteristic *demoCharacteristic;
@property (nonatomic, strong) NSMutableArray<CBPeripheral *> *mutableDiscoveredPeripherals;
@property (nonatomic, strong) NSMutableSet<NSUUID *> *discoveredIDs;
@property (nonatomic) NSUInteger protocolSequence;
@property (nonatomic, copy, nullable) NSString *sessionToken;
@property (nonatomic) BOOL scanning;
@property (nonatomic) BOOL connected;
@property (nonatomic) BOOL notifying;

@end

@implementation BLECentralController

- (instancetype)initWithLogHandler:(BLECentralLogHandler)logHandler {
    self = [super init];
    if (self) {
        _logHandler = [logHandler copy];
        _mutableDiscoveredPeripherals = [NSMutableArray array];
        _discoveredIDs = [NSMutableSet set];
        _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    }
    return self;
}

- (NSArray<CBPeripheral *> *)discoveredPeripherals {
    return self.mutableDiscoveredPeripherals.copy;
}

- (BOOL)isScanning {
    return self.scanning;
}

- (BOOL)isConnected {
    return self.connected;
}

- (BOOL)isNotifying {
    return self.notifying;
}

- (void)startScan {
    if (self.centralManager.state != CBManagerStatePoweredOn) {
        [self log:@"Cannot scan: Bluetooth is not powered on."];
        return;
    }

    [self.mutableDiscoveredPeripherals removeAllObjects];
    [self.discoveredIDs removeAllObjects];

    CBUUID *serviceUUID = [CBUUID UUIDWithString:kServiceUUIDString];
    [self.centralManager scanForPeripheralsWithServices:@[serviceUUID] options:@{ CBCentralManagerScanOptionAllowDuplicatesKey: @NO }];
    self.scanning = YES;
    [self log:@"Scanning for service FFF0..."];
}

- (void)stopScan {
    [self.centralManager stopScan];
    self.scanning = NO;
    [self log:@"Scan stopped."];
}

- (void)connectPeripheral:(CBPeripheral *)peripheral {
    if (self.connectedPeripheral) {
        [self disconnect];
    }
    [self stopScan];
    self.connectedPeripheral = peripheral;
    peripheral.delegate = self;
    [self.centralManager connectPeripheral:peripheral options:nil];
    [self log:[NSString stringWithFormat:@"Connecting to %@...", peripheral.name ?: peripheral.identifier.UUIDString]];
}

- (void)disconnect {
    if (!self.connectedPeripheral) {
        return;
    }
    [self.centralManager cancelPeripheralConnection:self.connectedPeripheral];
}

- (void)readCharacteristic {
    if (!self.demoCharacteristic || !self.connectedPeripheral) {
        [self log:@"Read skipped: not connected or characteristic missing."];
        return;
    }
    [self.connectedPeripheral readValueForCharacteristic:self.demoCharacteristic];
    [self log:@"Read requested."];
}

- (void)subscribeNotifications:(BOOL)subscribe {
    if (!self.demoCharacteristic || !self.connectedPeripheral) {
        [self log:@"Subscribe skipped: not connected or characteristic missing."];
        return;
    }
    [self.connectedPeripheral setNotifyValue:subscribe forCharacteristic:self.demoCharacteristic];
    [self log:subscribe ? @"Subscribing to notifications..." : @"Unsubscribing from notifications..."];
}

- (void)sendProtocolPairCode:(NSString *)code {
    [self sendProtocolOperation:BLEProtocolOpPair body:@{ @"code": code ?: @"" } includeToken:NO];
}

- (void)sendProtocolPing {
    [self sendProtocolOperation:BLEProtocolOpPing body:@{} includeToken:NO];
}

- (void)sendProtocolGetInfo {
    [self sendProtocolOperation:BLEProtocolOpGetInfo body:@{} includeToken:NO];
}

- (void)sendProtocolEcho:(NSString *)text {
    [self sendProtocolOperation:BLEProtocolOpEcho body:@{ @"text": text ?: @"" } includeToken:YES];
}

- (void)sendProtocolTelemetry {
    [self sendProtocolOperation:BLEProtocolOpTelemetry body:@{} includeToken:YES];
}

- (void)sendProtocolCommand:(NSString *)name {
    [self sendProtocolOperation:BLEProtocolOpCommand body:@{ @"name": name ?: @"identify" } includeToken:YES];
}

- (void)sendLegacyText:(NSString *)text {
    NSData *data = [(text ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    [self writeData:data label:@"legacy"];
}

- (void)sendProtocolOperation:(NSString *)operation body:(NSDictionary *)body includeToken:(BOOL)includeToken {
    self.protocolSequence += 1;
    NSString *messageID = [NSString stringWithFormat:@"ios-%lu", (unsigned long)self.protocolSequence];
    NSDictionary *request = [BLEProtocolMessage requestWithOperation:operation
                                                           messageID:messageID
                                                               token:includeToken ? self.sessionToken : nil
                                                                body:body];
    NSError *error = nil;
    NSData *data = [BLEProtocolMessage dataFromDictionary:request error:&error];
    if (!data) {
        [self log:[NSString stringWithFormat:@"BLECentral/BLECentralController.m#sendProtocolOperation: encode failed: %@", error.localizedDescription]];
        return;
    }
    [self writeData:data label:[NSString stringWithFormat:@"protocol %@", operation]];
}

- (void)writeData:(NSData *)data label:(NSString *)label {
    if (!self.demoCharacteristic || !self.connectedPeripheral) {
        [self log:[NSString stringWithFormat:@"Write skipped (%@): not ready.", label]];
        return;
    }

    CBCharacteristicWriteType writeType = CBCharacteristicWriteWithResponse;
    if ((self.demoCharacteristic.properties & CBCharacteristicPropertyWrite) == 0 &&
        (self.demoCharacteristic.properties & CBCharacteristicPropertyWriteWithoutResponse) != 0) {
        writeType = CBCharacteristicWriteWithoutResponse;
    }
    [self.connectedPeripheral writeValue:data forCharacteristic:self.demoCharacteristic type:writeType];
    NSString *preview = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: data.description;
    NSString *mode = (writeType == CBCharacteristicWriteWithResponse) ? @"withResponse" : @"withoutResponse";
    [self log:[NSString stringWithFormat:@"Write sent (%@, %@): %@", label, mode, preview]];
}

- (void)log:(NSString *)message {
    if (self.logHandler) {
        self.logHandler(message);
    }
}

- (void)resetConnectionState {
    self.connectedPeripheral = nil;
    self.demoCharacteristic = nil;
    self.connected = NO;
    self.notifying = NO;
}

#pragma mark - CBCentralManagerDelegate

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    switch (central.state) {
        case CBManagerStatePoweredOn:
            [self log:@"Bluetooth is powered on."];
            break;
        case CBManagerStatePoweredOff:
            [self log:@"Bluetooth is powered off."];
            break;
        case CBManagerStateUnauthorized:
            [self log:@"Bluetooth is unauthorized. Enable permission in Settings."];
            break;
        case CBManagerStateUnsupported:
            [self log:@"Bluetooth LE is unsupported on this device."];
            break;
        default:
            [self log:@"Bluetooth state changed."];
            break;
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    if ([self.discoveredIDs containsObject:peripheral.identifier]) {
        return;
    }

    NSString *name = peripheral.name ?: advertisementData[CBAdvertisementDataLocalNameKey];
    if (name.length > 0 && ![name isEqualToString:kTargetPeripheralName]) {
        return;
    }

    [self.discoveredIDs addObject:peripheral.identifier];
    [self.mutableDiscoveredPeripherals addObject:peripheral];
    [self log:[NSString stringWithFormat:@"Discovered: %@ RSSI=%@", name ?: peripheral.identifier.UUIDString, RSSI]];
    if (self.discoveryHandler) {
        self.discoveryHandler();
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    self.connected = YES;
    [self log:[NSString stringWithFormat:@"Connected: %@", peripheral.name ?: peripheral.identifier.UUIDString]];
    [peripheral discoverServices:@[[CBUUID UUIDWithString:kServiceUUIDString]]];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    [self log:[NSString stringWithFormat:@"Connect failed: %@", error.localizedDescription]];
    [self resetConnectionState];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    if (error) {
        [self log:[NSString stringWithFormat:@"Disconnected with error: %@", error.localizedDescription]];
    } else {
        [self log:@"Disconnected."];
    }
    [self resetConnectionState];
}

#pragma mark - CBPeripheralDelegate

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    if (error) {
        [self log:[NSString stringWithFormat:@"Service discovery failed: %@", error.localizedDescription]];
        return;
    }

    for (CBService *service in peripheral.services) {
        if ([service.UUID isEqual:[CBUUID UUIDWithString:kServiceUUIDString]]) {
            [peripheral discoverCharacteristics:@[[CBUUID UUIDWithString:kCharacteristicUUIDString]] forService:service];
            [self log:[NSString stringWithFormat:@"Service discovered: %@", service.UUID.UUIDString]];
            return;
        }
    }

    [self log:@"Target service FFF0 not found."];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if (error) {
        [self log:[NSString stringWithFormat:@"Characteristic discovery failed: %@", error.localizedDescription]];
        return;
    }

    for (CBCharacteristic *characteristic in service.characteristics) {
        if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:kCharacteristicUUIDString]]) {
            self.demoCharacteristic = characteristic;
            [self log:[NSString stringWithFormat:@"Characteristic ready: %@ props=0x%lx", characteristic.UUID.UUIDString, (unsigned long)characteristic.properties]];
            [self log:@"Auto: subscribe Notify, read current value, then pair with demo code."];
            [self subscribeNotifications:YES];
            return;
        }
    }

    [self log:@"Target characteristic FFF1 not found."];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (error) {
        [self log:[NSString stringWithFormat:@"Value update failed: %@", error.localizedDescription]];
        return;
    }

    NSData *data = characteristic.value ?: NSData.data;
    [self logParsedReplyData:data label:@"Notify/Read"];
}

- (void)logParsedReplyData:(NSData *)data label:(NSString *)label {
    if (data.length >= 2 && ((const uint8_t *)data.bytes)[0] == 0x00 && ((const uint8_t *)data.bytes)[1] == 0xAA) {
        NSData *body = [data subdataWithRange:NSMakeRange(2, data.length - 2)];
        NSString *text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
        [self log:[NSString stringWithFormat:@"%@ echo: prefix=00AA body(%lu B) text=%@",
                   label, (unsigned long)body.length, text ?: @"(binary)"]];
        return;
    }

    NSError *error = nil;
    NSDictionary *message = [BLEProtocolMessage dictionaryFromData:data error:&error];
    if ([BLEProtocolMessage isProtocolEnvelope:message]) {
        [self captureSessionTokenFromMessage:message];
        [self log:[NSString stringWithFormat:@"%@ protocol: %@", label, [BLEProtocolMessage summaryForDictionary:message]]];
        [self logProtocolBodyForMessage:message];
        return;
    }

    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: data.description;
    [self log:[NSString stringWithFormat:@"%@ raw: %@", label, text]];
}

- (void)captureSessionTokenFromMessage:(NSDictionary *)message {
    NSString *token = [message[BLEProtocolKeyToken] isKindOfClass:[NSString class]] ? message[BLEProtocolKeyToken] : nil;
    if (token.length == 0 &&
        [message[BLEProtocolKeyBody] isKindOfClass:[NSDictionary class]]) {
        token = message[BLEProtocolKeyBody][BLEProtocolKeyToken];
    }
    if (token.length > 0 && ![token isEqualToString:self.sessionToken]) {
        self.sessionToken = token;
        [self log:[NSString stringWithFormat:@"AUTH token captured: %@", token]];
    }
}

- (void)logProtocolBodyForMessage:(NSDictionary *)message {
    NSDictionary *body = [message[BLEProtocolKeyBody] isKindOfClass:[NSDictionary class]] ? message[BLEProtocolKeyBody] : nil;
    if (body.count == 0) {
        return;
    }
    NSString *operation = message[BLEProtocolKeyOperation] ?: @"?";
    if ([operation isEqualToString:BLEProtocolOpInfo]) {
        [self log:[NSString stringWithFormat:@"CAP %@", [BLEProtocolMessage capabilitySummaryForInfoBody:body]]];
    }
    NSError *error = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&error];
    NSString *bodyText = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding] ?: @"{}";
    [self log:[NSString stringWithFormat:@"BODY %@", bodyText]];
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (error) {
        [self log:[NSString stringWithFormat:@"Write failed: %@", error.localizedDescription]];
        return;
    }
    [self log:@"Write acknowledged."];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (error) {
        [self log:[NSString stringWithFormat:@"Notify state failed: %@", error.localizedDescription]];
        return;
    }
    self.notifying = characteristic.isNotifying;
    if (characteristic.isNotifying) {
        [self log:@"Notifications enabled — protocol replies and events arrive by notify."];
        [self readCharacteristic];
        [self sendProtocolPairCode:BLEProtocolDefaultPairCode];
        [self sendProtocolGetInfo];
    } else {
        [self log:@"Notifications disabled."];
    }
}

@end
