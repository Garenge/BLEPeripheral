#import "BLECentralController.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "BLEProtocolConstants.h"
#import "BLEProtocolMessage.h"

static NSString * const kTargetPeripheralName = @"MacBLE-Demo";
static NSString * const kServiceUUIDString = @"0000FFF0-0000-1000-8000-00805F9B34FB";
static NSString * const kCharacteristicUUIDString = @"0000FFF1-0000-1000-8000-00805F9B34FB";

@interface BLECentralController () <CBCentralManagerDelegate, CBPeripheralDelegate>

@property (nonatomic, copy) BLECentralLogHandler logHandler;
@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic, strong) NSMutableArray<CBPeripheral *> *mutableDiscoveredPeripherals;
@property (nonatomic, strong) NSMutableSet<NSUUID *> *discoveredIDs;
@property (nonatomic, strong, nullable) CBPeripheral *connectedPeripheral;
@property (nonatomic, strong, nullable) CBCharacteristic *demoCharacteristic;
@property (nonatomic) BOOL scanning;
@property (nonatomic) BOOL connected;
@property (nonatomic) BOOL notifyEnabled;
@property (nonatomic) NSUInteger protocolSequence;
@property (nonatomic, copy, nullable) NSString *sessionToken;

@end

@implementation BLECentralController

- (instancetype)initWithLogHandler:(BLECentralLogHandler)logHandler {
    self = [super init];
    if (self) {
        _logHandler = [logHandler copy];
        _mutableDiscoveredPeripherals = [NSMutableArray array];
        _discoveredIDs = [NSMutableSet set];
        _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
        [self logEvent:@"SYS" detail:@"MacCentralOC/MacCentralOC/BLECentralController.m#init: CBCentralManager created"];
    }
    return self;
}

- (BOOL)isScanning {
    return self.scanning;
}

- (BOOL)isConnected {
    return self.connected;
}

- (BOOL)isNotifyEnabled {
    return self.notifyEnabled;
}

- (BOOL)isCharacteristicReady {
    return self.demoCharacteristic != nil;
}

- (NSArray<NSString *> *)discoveredDeviceLabels {
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (CBPeripheral *peripheral in self.mutableDiscoveredPeripherals) {
        [labels addObject:[self labelForPeripheral:peripheral]];
    }
    return labels.copy;
}

- (void)startScan {
    if (self.centralManager.state != CBManagerStatePoweredOn) {
        [self logEvent:@"SYS" detail:@"startScan: Bluetooth is not powered on"];
        return;
    }
    [self.mutableDiscoveredPeripherals removeAllObjects];
    [self.discoveredIDs removeAllObjects];
    [self notifyStateChanged];

    CBUUID *serviceUUID = [CBUUID UUIDWithString:kServiceUUIDString];
    NSDictionary *options = @{ CBCentralManagerScanOptionAllowDuplicatesKey: @NO };
    [self.centralManager scanForPeripheralsWithServices:@[ serviceUUID ] options:options];
    self.scanning = YES;
    [self logEvent:@"SCAN" detail:@"started: filtering service FFF0"];
    [self notifyStateChanged];
}

- (void)stopScan {
    [self.centralManager stopScan];
    self.scanning = NO;
    [self logEvent:@"SCAN" detail:@"stopped"];
    [self notifyStateChanged];
}

- (void)connectDeviceAtIndex:(NSUInteger)index {
    if (index >= self.mutableDiscoveredPeripherals.count) {
        [self logEvent:@"LINK" detail:@"connect skipped: selected index is out of range"];
        return;
    }
    [self disconnect];
    [self stopScan];

    CBPeripheral *peripheral = self.mutableDiscoveredPeripherals[index];
    self.connectedPeripheral = peripheral;
    peripheral.delegate = self;
    [self.centralManager connectPeripheral:peripheral options:nil];
    [self logEvent:@"LINK" detail:[NSString stringWithFormat:@"connecting: %@", [self labelForPeripheral:peripheral]]];
    [self notifyStateChanged];
}

- (void)disconnect {
    if (!self.connectedPeripheral) {
        return;
    }
    [self logEvent:@"LINK" detail:[NSString stringWithFormat:@"disconnect requested: %@", [self labelForPeripheral:self.connectedPeripheral]]];
    [self.centralManager cancelPeripheralConnection:self.connectedPeripheral];
}

- (void)readValue {
    if (!self.demoCharacteristic || !self.connectedPeripheral) {
        [self logEvent:@"RX" detail:@"read skipped: characteristic missing"];
        return;
    }
    [self.connectedPeripheral readValueForCharacteristic:self.demoCharacteristic];
    [self logEvent:@"RX" detail:@"read requested on FFF1"];
}

- (void)setNotifyEnabled:(BOOL)enabled {
    if (!self.demoCharacteristic || !self.connectedPeripheral) {
        [self logEvent:@"LINK" detail:@"notify skipped: characteristic missing"];
        return;
    }
    [self.connectedPeripheral setNotifyValue:enabled forCharacteristic:self.demoCharacteristic];
    [self logEvent:@"LINK" detail:enabled ? @"notify ON requested" : @"notify OFF requested"];
}

- (void)writeText:(NSString *)text {
    [self sendProtocolEcho:text];
}

- (void)sendPairCode:(NSString *)code {
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

- (void)sendTelemetryRequest {
    [self sendProtocolOperation:BLEProtocolOpTelemetry body:@{} includeToken:YES];
}

- (void)sendCommandNamed:(NSString *)name {
    [self sendProtocolOperation:BLEProtocolOpCommand body:@{ @"name": name ?: @"identify" } includeToken:YES];
}

- (void)sendRawText:(NSString *)text {
    NSData *data = [(text ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    [self writeData:data label:@"raw legacy"];
}

- (void)sendProtocolOperation:(NSString *)operation body:(NSDictionary *)body includeToken:(BOOL)includeToken {
    self.protocolSequence += 1;
    NSString *messageID = [NSString stringWithFormat:@"mac-%lu", (unsigned long)self.protocolSequence];
    NSDictionary *request = [BLEProtocolMessage requestWithOperation:operation
                                                           messageID:messageID
                                                               token:includeToken ? self.sessionToken : nil
                                                                body:body];
    NSError *error = nil;
    NSData *data = [BLEProtocolMessage dataFromDictionary:request error:&error];
    if (!data) {
        [self logEvent:@"TX" detail:[NSString stringWithFormat:@"protocol encode failed: %@", error.localizedDescription]];
        return;
    }
    [self writeData:data label:[NSString stringWithFormat:@"protocol %@", operation]];
}

- (void)writeData:(NSData *)data label:(NSString *)label {
    if (!self.demoCharacteristic || !self.connectedPeripheral) {
        [self logEvent:@"TX" detail:@"write skipped: characteristic missing"];
        return;
    }
    CBCharacteristicWriteType writeType = [self writeTypeForCharacteristic:self.demoCharacteristic];
    [self.connectedPeripheral writeValue:data forCharacteristic:self.demoCharacteristic type:writeType];
    NSString *mode = writeType == CBCharacteristicWriteWithResponse ? @"withResponse" : @"withoutResponse";
    NSString *preview = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: data.description;
    [self logEvent:@"TX" detail:[NSString stringWithFormat:@"write %@ (%@): %lu B text=%@", mode, label, (unsigned long)data.length, preview]];
}

#pragma mark - CBCentralManagerDelegate

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    switch (central.state) {
        case CBManagerStatePoweredOn:
            [self logEvent:@"SYS" detail:@"Bluetooth is powered on"];
            break;
        case CBManagerStatePoweredOff:
            [self logEvent:@"SYS" detail:@"Bluetooth is powered off"];
            break;
        case CBManagerStateUnauthorized:
            [self logEvent:@"SYS" detail:@"Bluetooth is unauthorized; check Privacy & Security"];
            break;
        case CBManagerStateUnsupported:
            [self logEvent:@"SYS" detail:@"Bluetooth LE is unsupported on this Mac"];
            break;
        default:
            [self logEvent:@"SYS" detail:@"Bluetooth state changed"];
            break;
    }
    [self notifyStateChanged];
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary<NSString *,id> *)advertisementData
                  RSSI:(NSNumber *)RSSI {
    if ([self.discoveredIDs containsObject:peripheral.identifier]) {
        return;
    }

    NSString *name = peripheral.name ?: advertisementData[CBAdvertisementDataLocalNameKey];
    if (name.length > 0 && ![name isEqualToString:kTargetPeripheralName]) {
        return;
    }

    [self.discoveredIDs addObject:peripheral.identifier];
    [self.mutableDiscoveredPeripherals addObject:peripheral];
    [self logEvent:@"SCAN" detail:[NSString stringWithFormat:@"found: %@ RSSI=%@", name ?: peripheral.identifier.UUIDString, RSSI]];
    [self notifyStateChanged];
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    self.connected = YES;
    [self logEvent:@"LINK+" detail:[NSString stringWithFormat:@"connected: %@", [self labelForPeripheral:peripheral]]];
    [peripheral discoverServices:@[ [CBUUID UUIDWithString:kServiceUUIDString] ]];
    [self notifyStateChanged];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    [self logEvent:@"LINK" detail:[NSString stringWithFormat:@"connect failed: %@", error.localizedDescription]];
    [self clearConnectionState];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSString *detail = error ? [NSString stringWithFormat:@"disconnected with error: %@", error.localizedDescription] : @"disconnected";
    [self logEvent:@"LINK-" detail:detail];
    [self clearConnectionState];
}

#pragma mark - CBPeripheralDelegate

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    if (error) {
        [self logEvent:@"GATT" detail:[NSString stringWithFormat:@"service discovery failed: %@", error.localizedDescription]];
        return;
    }

    for (CBService *service in peripheral.services) {
        if ([service.UUID isEqual:[CBUUID UUIDWithString:kServiceUUIDString]]) {
            [self logEvent:@"GATT" detail:[NSString stringWithFormat:@"service discovered: %@", service.UUID.UUIDString]];
            [peripheral discoverCharacteristics:@[ [CBUUID UUIDWithString:kCharacteristicUUIDString] ] forService:service];
            return;
        }
    }
    [self logEvent:@"GATT" detail:@"service FFF0 not found"];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if (error) {
        [self logEvent:@"GATT" detail:[NSString stringWithFormat:@"characteristic discovery failed: %@", error.localizedDescription]];
        return;
    }

    for (CBCharacteristic *characteristic in service.characteristics) {
        if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:kCharacteristicUUIDString]]) {
            self.demoCharacteristic = characteristic;
            [self logEvent:@"GATT" detail:[NSString stringWithFormat:@"characteristic ready: %@ props=0x%lx", characteristic.UUID.UUIDString, (unsigned long)characteristic.properties]];
            [self setNotifyEnabled:YES];
            [self readValue];
            [self sendPairCode:BLEProtocolDefaultPairCode];
            [self notifyStateChanged];
            return;
        }
    }
    [self logEvent:@"GATT" detail:@"characteristic FFF1 not found"];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (error) {
        [self logEvent:@"RX" detail:[NSString stringWithFormat:@"value update failed: %@", error.localizedDescription]];
        return;
    }
    [self logIncomingData:characteristic.value ?: NSData.data label:@"notify/read"];
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (error) {
        [self logEvent:@"TX" detail:[NSString stringWithFormat:@"write failed: %@", error.localizedDescription]];
        return;
    }
    [self logEvent:@"TX" detail:@"write acknowledged"];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (error) {
        [self logEvent:@"LINK" detail:[NSString stringWithFormat:@"notify state failed: %@", error.localizedDescription]];
        return;
    }
    self.notifyEnabled = characteristic.isNotifying;
    [self logEvent:@"LINK" detail:characteristic.isNotifying ? @"notify ON" : @"notify OFF"];
    [self notifyStateChanged];
}

#pragma mark - Helpers

- (CBCharacteristicWriteType)writeTypeForCharacteristic:(CBCharacteristic *)characteristic {
    if ((characteristic.properties & CBCharacteristicPropertyWrite) != 0) {
        return CBCharacteristicWriteWithResponse;
    }
    return CBCharacteristicWriteWithoutResponse;
}

- (void)logIncomingData:(NSData *)data label:(NSString *)label {
    if ([self isEchoReply:data]) {
        NSData *body = [data subdataWithRange:NSMakeRange(2, data.length - 2)];
        [self logEvent:@"RX" detail:[NSString stringWithFormat:@"%@ echo: prefix=00AA body=%lu B text=%@",
                                     label, (unsigned long)body.length, [self textOrHexForData:body]]];
        return;
    }

    NSError *error = nil;
    NSDictionary *message = [BLEProtocolMessage dictionaryFromData:data error:&error];
    if ([BLEProtocolMessage isProtocolEnvelope:message]) {
        [self captureSessionTokenFromMessage:message];
        [self logEvent:@"RX" detail:[NSString stringWithFormat:@"%@ protocol: %@", label, [BLEProtocolMessage summaryForDictionary:message]]];
        [self logProtocolBodyForMessage:message];
        return;
    }

    [self logEvent:@"RX" detail:[NSString stringWithFormat:@"%@ raw: %lu B text=%@",
                                 label, (unsigned long)data.length, [self textOrHexForData:data]]];
}

- (void)captureSessionTokenFromMessage:(NSDictionary *)message {
    NSString *token = [message[BLEProtocolKeyToken] isKindOfClass:[NSString class]] ? message[BLEProtocolKeyToken] : nil;
    if (token.length == 0 &&
        [message[BLEProtocolKeyBody] isKindOfClass:[NSDictionary class]]) {
        token = message[BLEProtocolKeyBody][BLEProtocolKeyToken];
    }
    if (token.length > 0 && ![token isEqualToString:self.sessionToken]) {
        self.sessionToken = token;
        [self logEvent:@"AUTH" detail:[NSString stringWithFormat:@"session token captured: %@", token]];
    }
}

- (void)logProtocolBodyForMessage:(NSDictionary *)message {
    NSDictionary *body = [message[BLEProtocolKeyBody] isKindOfClass:[NSDictionary class]] ? message[BLEProtocolKeyBody] : nil;
    if (body.count == 0) {
        return;
    }
    NSError *error = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&error];
    NSString *bodyText = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding] ?: @"{}";
    NSString *operation = message[BLEProtocolKeyOperation] ?: @"?";
    NSString *category = [operation isEqualToString:BLEProtocolOpEvent] ? @"EVT" : @"RX";
    [self logEvent:category detail:[NSString stringWithFormat:@"body=%@", bodyText]];
}

- (BOOL)isEchoReply:(NSData *)data {
    if (data.length < 2) {
        return NO;
    }
    const uint8_t *bytes = data.bytes;
    return bytes[0] == 0x00 && bytes[1] == 0xAA;
}

- (NSString *)textOrHexForData:(NSData *)data {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text.length > 0) {
        return text;
    }
    const uint8_t *bytes = data.bytes;
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:data.length];
    for (NSUInteger index = 0; index < data.length; index++) {
        [parts addObject:[NSString stringWithFormat:@"%02X", bytes[index]]];
    }
    return [parts componentsJoinedByString:@" "];
}

- (NSString *)labelForPeripheral:(CBPeripheral *)peripheral {
    NSString *name = peripheral.name.length > 0 ? peripheral.name : @"(unknown)";
    return [NSString stringWithFormat:@"%@ | %@", name, peripheral.identifier.UUIDString];
}

- (void)clearConnectionState {
    self.connectedPeripheral = nil;
    self.demoCharacteristic = nil;
    self.connected = NO;
    self.notifyEnabled = NO;
    self.sessionToken = nil;
    [self notifyStateChanged];
}

- (void)notifyStateChanged {
    if (self.stateHandler) {
        self.stateHandler();
    }
}

- (void)logEvent:(NSString *)category detail:(NSString *)detail {
    if (self.logHandler) {
        self.logHandler([NSString stringWithFormat:@"[%@] %@", category, detail]);
    }
}

@end
