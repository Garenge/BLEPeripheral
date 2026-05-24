#import "BLEPeripheralController.h"
#import <CoreBluetooth/CoreBluetooth.h>

static NSString * const kDemoPeripheralName = @"MacBLE-Demo";
static NSString * const kDemoServiceUUIDString = @"0000FFF0-0000-1000-8000-00805F9B34FB";
static NSString * const kDemoCharacteristicUUIDString = @"0000FFF1-0000-1000-8000-00805F9B34FB";
static NSString * const kUnknownCentralUUIDString = @"00000000-0000-0000-0000-000000000001";

static const uint8_t kEchoReplyPrefixBytes[] = { 0x00, 0xAA };

@interface BLETrackedCentral : NSObject
@property (nonatomic, copy) NSUUID *identifier;
@property (nonatomic) BOOL linkSeen;
@property (nonatomic) BOOL notifyEnabled;
@property (nonatomic) NSUInteger maxUpdateLength;
@end

@interface BLEPeripheralController () <CBPeripheralManagerDelegate>

@property (nonatomic, copy) BLEPeripheralLogHandler logHandler;
@property (nonatomic, strong) CBPeripheralManager *peripheralManager;
@property (nonatomic, strong) CBMutableCharacteristic *demoCharacteristic;
@property (nonatomic, strong) NSMutableData *currentValue;
@property (nonatomic) BOOL hasSubscribers;
@property (nonatomic) BOOL servicesPublished;
@property (nonatomic, strong, nullable) NSData *pendingNotifyPayload;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, BLETrackedCentral *> *trackedCentrals;

@end

@implementation BLEPeripheralController

- (instancetype)initWithLogHandler:(BLEPeripheralLogHandler)logHandler {
    self = [super init];
    if (self) {
        _logHandler = [logHandler copy];
        _currentValue = [[self echoReplyDataForIncoming:NSData.data] mutableCopy];
        _trackedCentrals = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)start {
    dispatch_queue_t queue = dispatch_get_main_queue();
    NSDictionary *options = @{ CBPeripheralManagerOptionShowPowerAlertKey: @YES };
    self.peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self
                                                                       queue:queue
                                                                     options:options];
    [self logEvent:@"SYS" detail:@"MacPeripheralOC/BLEPeripheral/BLEPeripheralController.m#start: CBPeripheralManager on main queue"];
    [self logProfileSummary];
}

- (void)stop {
    [self notifyAllCentralsDisconnectedReason:@"peripheral stopped"];
    [self.peripheralManager stopAdvertising];
    [self.peripheralManager removeAllServices];
    [self logEvent:@"SYS" detail:@"Peripheral stopped, advertising and GATT cleared"];
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

    if (self.servicesPublished) {
        [self.peripheralManager removeAllServices];
    }
    [self.peripheralManager addService:service];
    [self log:[NSString stringWithFormat:@"Registering primary service UUID=%@ (short FFF0)", serviceUUID.UUIDString]];
    [self log:[NSString stringWithFormat:@"Characteristic UUID=%@ (short FFF1) properties=%@",
               characteristicUUID.UUIDString,
               [self propertiesDescription:properties]]];
    [self log:[NSString stringWithFormat:@"Permissions: readable + writeable | initial read length=%lu bytes",
               (unsigned long)self.currentValue.length]];
}

- (void)startAdvertising {
    if (self.peripheralManager.isAdvertising) {
        [self.peripheralManager stopAdvertising];
        [self logEvent:@"SYS" detail:@"Stopped previous advertising before restart"];
    }

    // 28-byte ADV limit: 128-bit service UUID pushes name into overflow (general scanners miss it).
    // Prefer 16-bit FFF0 + local name; GATT still uses full 128-bit UUID.
    CBUUID *shortServiceUUID = [CBUUID UUIDWithString:@"FFF0"];
    NSDictionary *advertisementData = @{
        CBAdvertisementDataLocalNameKey: kDemoPeripheralName,
        CBAdvertisementDataServiceUUIDsKey: @[ shortServiceUUID ],
    };

    [self.peripheralManager startAdvertising:advertisementData];
    [self logEvent:@"SYS" detail:[NSString stringWithFormat:@"Advertising payload: localName=%@, serviceUUIDs=[FFF0 16-bit]",
                                    kDemoPeripheralName]];
    [self logEvent:@"SYS" detail:@"Third-party apps: scan ALL devices (no filter); connect then open service FFF0"];
}

- (void)startAdvertisingNameOnly {
    if (self.peripheralManager.isAdvertising) {
        [self.peripheralManager stopAdvertising];
    }
    NSDictionary *advertisementData = @{ CBAdvertisementDataLocalNameKey: kDemoPeripheralName };
    [self.peripheralManager startAdvertising:advertisementData];
    [self logEvent:@"SYS" detail:[NSString stringWithFormat:@"Advertising fallback: localName=%@ only (max scanner visibility)",
                                    kDemoPeripheralName]];
}

- (NSData *)echoReplyDataForIncoming:(NSData *)incoming {
    NSMutableData *reply = [NSMutableData dataWithBytes:kEchoReplyPrefixBytes length:sizeof(kEchoReplyPrefixBytes)];
    if (incoming.length > 0) {
        [reply appendData:incoming];
    }
    return reply;
}

- (BOOL)pushAutoNotifyReply:(CBPeripheralManager *)peripheral {
    if (![self anyCentralNotifyEnabled]) {
        [self logEvent:@"TX" detail:@"auto-push skipped — phone has NOT enabled Notify on FFF1 (must open Notify/CCCD, not Read)"];
        return NO;
    }

    BOOL didSend = [peripheral updateValue:self.currentValue
                         forCharacteristic:self.demoCharacteristic
                      onSubscribedCentrals:nil];
    if (didSend) {
        self.pendingNotifyPayload = nil;
        [self logEvent:@"TX" detail:@"auto-push via Notify OK — phone should receive without Read"];
        [self logPayloadContent:self.currentValue tag:@"TX"];
    } else {
        self.pendingNotifyPayload = [self.currentValue copy];
        [self logEvent:@"TX" detail:@"auto-push queued — will retry when CoreBluetooth is ready"];
    }
    return didSend;
}

- (void)storeReplyAndAutoPush:(NSData *)responseData
                      peripheral:(CBPeripheralManager *)peripheral {
    [self.currentValue setData:responseData ?: NSData.data];
    [self pushAutoNotifyReply:peripheral];
}

#pragma mark - Central tracking & structured logs

- (nullable BLETrackedCentral *)trackedCentralForUUID:(NSUUID *)uuid createIfNeeded:(BOOL)createIfNeeded {
    if (!uuid) {
        return nil;
    }
    BLETrackedCentral *tracked = self.trackedCentrals[uuid];
    if (!tracked && createIfNeeded) {
        tracked = [[BLETrackedCentral alloc] init];
        tracked.identifier = uuid;
        self.trackedCentrals[uuid] = tracked;
    }
    return tracked;
}

- (NSUUID *)uuidForCentral:(nullable CBCentral *)central {
    if (central.identifier) {
        return central.identifier;
    }
    return [[NSUUID alloc] initWithUUIDString:kUnknownCentralUUIDString];
}

- (NSString *)centralTag:(nullable CBCentral *)central {
    if (central.identifier) {
        return central.identifier.UUIDString;
    }
    return [NSString stringWithFormat:@"unknown-central (%@)", kUnknownCentralUUIDString];
}

- (NSString *)hexStringForData:(NSData *)data maxBytes:(NSUInteger)maxBytes {
    if (data.length == 0) {
        return @"(empty)";
    }
    const NSUInteger length = MIN(data.length, maxBytes);
    NSMutableString *hex = [NSMutableString string];
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < length; i++) {
        [hex appendFormat:@"%02X", bytes[i]];
        if (i + 1 < length) {
            [hex appendString:@" "];
        }
    }
    if (data.length > maxBytes) {
        [hex appendFormat:@" … (+%lu B)", (unsigned long)(data.length - maxBytes)];
    }
    return hex;
}

- (void)logPayloadContent:(NSData *)data tag:(NSString *)tag {
    if (data.length == 0) {
        [self logEvent:tag detail:@"  payload: (empty)"];
        return;
    }
    [self logEvent:tag detail:[NSString stringWithFormat:@"  bytes: %lu", (unsigned long)data.length]];

    NSString *utf8 = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (utf8.length > 0) {
        [self logEvent:tag detail:[NSString stringWithFormat:@"  text: %@", utf8]];
    } else {
        [self logEvent:tag detail:@"  text: (not valid UTF-8)"];
    }
    [self logEvent:tag detail:[NSString stringWithFormat:@"  hex: %@", [self hexStringForData:data maxBytes:256]]];
}

- (void)logEvent:(NSString *)category detail:(NSString *)detail {
    [self log:[NSString stringWithFormat:@"[%@] %@", category, detail]];
}

- (void)logLinkConnectIfNeeded:(nullable CBCentral *)central reason:(NSString *)reason {
    NSUUID *uuid = [self uuidForCentral:central];
    BLETrackedCentral *tracked = [self trackedCentralForUUID:uuid createIfNeeded:YES];
    if (central) {
        tracked.maxUpdateLength = central.maximumUpdateValueLength;
    }
    if (tracked.linkSeen) {
        [self logEvent:@"LINK" detail:[NSString stringWithFormat:@"central=%@ | %@ (already tracked, count=%lu)",
                                       [self centralTag:central], reason, (unsigned long)self.trackedCentrals.count]];
        return;
    }
    tracked.linkSeen = YES;
    [self logEvent:@"LINK+" detail:[NSString stringWithFormat:@"central=%@ | connected — %@ | maxUpdate=%lu B | tracked=%lu",
                                    [self centralTag:central],
                                    reason,
                                    (unsigned long)tracked.maxUpdateLength,
                                    (unsigned long)self.trackedCentrals.count]];
}

- (void)logLinkNotifySubscribed:(CBCentral *)central {
    NSUUID *uuid = [self uuidForCentral:central];
    BLETrackedCentral *tracked = [self trackedCentralForUUID:uuid createIfNeeded:YES];
    tracked.maxUpdateLength = central.maximumUpdateValueLength;
    tracked.notifyEnabled = YES;
    self.hasSubscribers = YES;
    [self logLinkConnectIfNeeded:central reason:@"notify subscribed on FFF1"];
    [self logEvent:@"LINK+" detail:[NSString stringWithFormat:@"central=%@ | notify ON — push 00 AA + payload after each write",
                                    [self centralTag:central]]];
}

- (void)logLinkNotifyUnsubscribed:(CBCentral *)central {
    BLETrackedCentral *tracked = [self trackedCentralForUUID:[self uuidForCentral:central] createIfNeeded:NO];
    if (tracked) {
        tracked.notifyEnabled = NO;
    }
    self.hasSubscribers = [self anyCentralNotifyEnabled];
    [self logEvent:@"LINK-" detail:[NSString stringWithFormat:@"central=%@ | notify OFF — BLE link may still be up",
                                    [self centralTag:central]]];
}

- (void)notifyAllCentralsDisconnectedReason:(NSString *)reason {
    NSArray<BLETrackedCentral *> *snapshot = self.trackedCentrals.allValues.copy;
    for (BLETrackedCentral *tracked in snapshot) {
        if (!tracked.linkSeen) {
            continue;
        }
        [self logEvent:@"LINK-" detail:[NSString stringWithFormat:@"central=%@ | disconnected — %@",
                                        tracked.identifier.UUIDString, reason]];
    }
    [self.trackedCentrals removeAllObjects];
    self.hasSubscribers = NO;
}

- (BOOL)anyCentralNotifyEnabled {
    for (BLETrackedCentral *tracked in self.trackedCentrals.allValues) {
        if (tracked.notifyEnabled) {
            return YES;
        }
    }
    return NO;
}

- (void)logRX:(nullable CBCentral *)central channel:(NSString *)channel data:(NSData *)data extra:(nullable NSString *)extra {
    [self logLinkConnectIfNeeded:central reason:[NSString stringWithFormat:@"RX %@", channel]];
    if (!central) {
        [self logEvent:@"LINK" detail:@"central=nil on this ATT request (common on macOS read/write)"];
    }
    NSMutableString *detail = [NSMutableString stringWithFormat:@"central=%@ | %@",
                               [self centralTag:central], channel];
    if (extra.length > 0) {
        [detail appendFormat:@" | %@", extra];
    }
    [self logEvent:@"RX" detail:detail];
    [self logPayloadContent:data tag:@"RX"];
}

- (void)logTX:(nullable CBCentral *)central channel:(NSString *)channel data:(NSData *)data extra:(nullable NSString *)extra {
    NSMutableString *detail = [NSMutableString stringWithFormat:@"central=%@ | %@",
                               [self centralTag:central], channel];
    if (extra.length > 0) {
        [detail appendFormat:@" | %@", extra];
    }
    [self logEvent:@"TX" detail:detail];
    if (data.length > 0) {
        [self logPayloadContent:data tag:@"TX"];
    }
}

- (NSString *)propertiesDescription:(CBCharacteristicProperties)properties {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (properties & CBCharacteristicPropertyRead) { [parts addObject:@"read"]; }
    if (properties & CBCharacteristicPropertyWrite) { [parts addObject:@"write"]; }
    if (properties & CBCharacteristicPropertyWriteWithoutResponse) { [parts addObject:@"writeWithoutResponse"]; }
    if (properties & CBCharacteristicPropertyNotify) { [parts addObject:@"notify"]; }
    if (properties & CBCharacteristicPropertyIndicate) { [parts addObject:@"indicate"]; }
    return parts.count > 0 ? [parts componentsJoinedByString:@", "] : @"none";
}

- (void)logProfileSummary {
    [self log:@"--- Mac BLE GATT profile ---"];
    [self log:[NSString stringWithFormat:@"Peripheral name (advertised): %@", kDemoPeripheralName]];
    [self log:[NSString stringWithFormat:@"Primary service: %@ (16-bit FFF0)", kDemoServiceUUIDString]];
    [self log:[NSString stringWithFormat:@"Characteristic: %@ (16-bit FFF1)", kDemoCharacteristicUUIDString]];
    [self log:@"Characteristic properties: read, write, writeWithoutResponse, notify"];
    [self log:@"Message rule: reply = 0x00 0xAA + bytes received (any payload)"];
    [self log:@"Auto delivery: Notify push after each write (phone must enable Notify on FFF1)"];
    [self log:@"Read FFF1 only if Notify is off — third-party apps: tap Notify before Write"];
    [self log:@"--- end profile ---"];
}

- (void)log:(NSString *)message {
    NSLog(@"BLEPeripheral: %@", message);
    if (self.logHandler) {
        self.logHandler(message);
    }
}

#pragma mark - CBPeripheralManagerDelegate

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
    switch (peripheral.state) {
        case CBManagerStatePoweredOn:
            [self log:@"Bluetooth state: powered on"];
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

    self.servicesPublished = YES;
    [self logEvent:@"SYS" detail:[NSString stringWithFormat:@"GATT service published: %@ (connect后可见)", service.UUID.UUIDString]];
    [self startAdvertising];
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error {
    if (error) {
        [self logEvent:@"SYS" detail:[NSString stringWithFormat:@"Advertising failed: %@ — retry name-only",
                                        error.localizedDescription]];
        [self startAdvertisingNameOnly];
        return;
    }

    [self logEvent:@"SYS" detail:[NSString stringWithFormat:@"Advertising active (isAdvertising=YES) name=%@",
                                    kDemoPeripheralName]];
    [self logEvent:@"SYS" detail:@"iPhone 三方扫描: 选「扫描全部 / 无过滤」; 找 MacBLE-Demo 或 Unknown 后连接"];
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral didReceiveReadRequest:(CBATTRequest *)request {
    CBCentral *central = request.central;
    [self logEvent:@"SYS" detail:[NSString stringWithFormat:@"didReceiveReadRequest central=%@", [self centralTag:central]]];

    if (![request.characteristic.UUID isEqual:self.demoCharacteristic.UUID]) {
        [self logEvent:@"RX" detail:[NSString stringWithFormat:@"central=%@ | read REJECTED unknown UUID %@",
                                       [self centralTag:central], request.characteristic.UUID.UUIDString]];
        [peripheral respondToRequest:request withResult:CBATTErrorAttributeNotFound];
        return;
    }

    if (request.offset > self.currentValue.length) {
        [self logEvent:@"RX" detail:[NSString stringWithFormat:@"central=%@ | read REJECTED invalid offset %lu",
                                       [self centralTag:central], (unsigned long)request.offset]];
        [peripheral respondToRequest:request withResult:CBATTErrorInvalidOffset];
        return;
    }

    [self logRX:central
         channel:@"read/FFF1"
            data:self.currentValue
           extra:[NSString stringWithFormat:@"offset=%lu", (unsigned long)request.offset]];

    request.value = [self.currentValue subdataWithRange:NSMakeRange(request.offset, self.currentValue.length - request.offset)];
    [peripheral respondToRequest:request withResult:CBATTErrorSuccess];

    [self logTX:central
       channel:@"read-response/FFF1"
          data:request.value
         extra:@"ATT success"];
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral didReceiveWriteRequests:(NSArray<CBATTRequest *> *)requests {
    [self logEvent:@"SYS" detail:[NSString stringWithFormat:@"didReceiveWriteRequests count=%lu", (unsigned long)requests.count]];

    for (CBATTRequest *request in requests) {
        CBCentral *central = request.central;

        if (![request.characteristic.UUID isEqual:self.demoCharacteristic.UUID]) {
            [self logEvent:@"RX" detail:[NSString stringWithFormat:@"write REJECTED — got UUID %@, expected FFF1",
                                           request.characteristic.UUID.UUIDString]];
            [peripheral respondToRequest:request withResult:CBATTErrorAttributeNotFound];
            continue;
        }

        BOOL supportsWriteWithResponse = (self.demoCharacteristic.properties & CBCharacteristicPropertyWrite) != 0;
        BOOL supportsWriteWithoutResponse = (self.demoCharacteristic.properties & CBCharacteristicPropertyWriteWithoutResponse) != 0;
        NSString *writeModeHint = [NSString stringWithFormat:@"char supports write=%@ writeNoResp=%@ (protocol: use write+notify)",
                                   supportsWriteWithResponse ? @"YES" : @"NO",
                                   supportsWriteWithoutResponse ? @"YES" : @"NO"];

        NSData *incoming = request.value ?: NSData.data;
        [self logRX:central channel:@"write/FFF1" data:incoming extra:writeModeHint];
        NSData *outgoing = [self echoReplyDataForIncoming:incoming];
        [self logEvent:@"TX" detail:@"echo rule: 00 AA + RX payload"];

        // 先 ATT 应答，再 Notify 推送（部分 Central 在 write 完成后再处理 notify）。
        [peripheral respondToRequest:request withResult:CBATTErrorSuccess];
        [self logEvent:@"TX" detail:@"ATT write response=success"];

        [self storeReplyAndAutoPush:outgoing peripheral:peripheral];
    }
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didSubscribeToCharacteristic:(CBCharacteristic *)characteristic {
    [self logEvent:@"SYS" detail:[NSString stringWithFormat:@"didSubscribe FFF1 central=%@", [self centralTag:central]]];
    [self logLinkNotifySubscribed:central];
    [self logEvent:@"SYS" detail:@"Notify ON — write replies will auto-push (no Read needed)"];

    if (self.currentValue.length > 0) {
        [self pushAutoNotifyReply:peripheral];
    }
    if (self.pendingNotifyPayload.length > 0) {
        [self.currentValue setData:self.pendingNotifyPayload];
        [self pushAutoNotifyReply:peripheral];
    }
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic {
    [self logLinkNotifyUnsubscribed:central];
    // CoreBluetooth peripheral role has no explicit disconnect callback; link drop is inferred when Central leaves.
    [self logEvent:@"LINK" detail:[NSString stringWithFormat:@"central=%@ | if iPhone disconnected entirely, no further RX/TX until reconnect",
                                   [self centralTag:central]]];
}

- (void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)peripheral {
    [self logEvent:@"TX" detail:@"notify queue ready — flushing pending auto-push"];
    if (self.pendingNotifyPayload.length > 0) {
        [self.currentValue setData:self.pendingNotifyPayload];
    }
    [self pushAutoNotifyReply:peripheral];
}

@end

#pragma mark - BLETrackedCentral

@implementation BLETrackedCentral
@end
