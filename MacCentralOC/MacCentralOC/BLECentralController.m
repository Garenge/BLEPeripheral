#import "BLECentralController.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "BLEProtocolConstants.h"
#import "BLEProtocolMessage.h"

static NSString * const kTargetPeripheralName = @"MacBLE-Demo";
static NSString * const kServiceUUIDString = @"0000FFF0-0000-1000-8000-00805F9B34FB";
static NSString * const kCharacteristicUUIDString = @"0000FFF1-0000-1000-8000-00805F9B34FB";
static NSString * const kEventRuleModeNormal = @"normal";
static NSTimeInterval const kDemoFlowStepDelay = 0.35;
static NSUInteger const kMaxChunkStreams = 8;
static NSUInteger const kMaxChunkPartsPerStream = 256;
static NSUInteger const kMaxChunkBufferedBytes = 64 * 1024;

@interface BLEDiscoveredDeviceRecord : NSObject

@property (nonatomic, strong) CBPeripheral *peripheral;
@property (nonatomic, strong) NSNumber *RSSI;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *matchReason;
@property (nonatomic, strong) NSDate *lastSeen;

@end

@interface BLECentralController () <CBCentralManagerDelegate, CBPeripheralDelegate>

@property (nonatomic, copy) BLECentralLogHandler logHandler;
@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic, strong) NSMutableArray<BLEDiscoveredDeviceRecord *> *mutableDiscoveredDevices;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, BLEDiscoveredDeviceRecord *> *discoveredRecords;
@property (nonatomic, strong, nullable) CBPeripheral *connectedPeripheral;
@property (nonatomic, strong, nullable) CBCharacteristic *demoCharacteristic;
@property (nonatomic) BOOL scanning;
@property (nonatomic) BOOL connected;
@property (nonatomic) BOOL notifyEnabled;
@property (nonatomic, getter=isDemoFlowRunning) BOOL demoFlowRunning;
@property (nonatomic) NSUInteger protocolSequence;
@property (nonatomic) NSUInteger demoFlowGeneration;
@property (nonatomic, copy, nullable) NSString *sessionToken;
@property (nonatomic, copy) NSString *eventRuleMode;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, NSData *> *> *chunkBuffers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *chunkCounts;
@property (nonatomic, strong) NSMutableArray<NSString *> *chunkStreamOrder;
@property (nonatomic) NSUInteger chunkBufferedBytes;

@end

@implementation BLECentralController

- (instancetype)initWithLogHandler:(BLECentralLogHandler)logHandler {
    self = [super init];
    if (self) {
        _logHandler = [logHandler copy];
        _mutableDiscoveredDevices = [NSMutableArray array];
        _discoveredRecords = [NSMutableDictionary dictionary];
        _eventRuleMode = kEventRuleModeNormal;
        _chunkBuffers = [NSMutableDictionary dictionary];
        _chunkCounts = [NSMutableDictionary dictionary];
        _chunkStreamOrder = [NSMutableArray array];
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
    for (BLEDiscoveredDeviceRecord *record in self.mutableDiscoveredDevices) {
        [labels addObject:[self labelForDiscoveredRecord:record]];
    }
    return labels.copy;
}

- (void)startScan {
    if (self.centralManager.state != CBManagerStatePoweredOn) {
        [self logEvent:@"SYS" detail:@"startScan: Bluetooth is not powered on"];
        return;
    }
    [self.mutableDiscoveredDevices removeAllObjects];
    [self.discoveredRecords removeAllObjects];
    [self notifyStateChanged];

    CBUUID *serviceUUID = [CBUUID UUIDWithString:kServiceUUIDString];
    NSDictionary *options = @{ CBCentralManagerScanOptionAllowDuplicatesKey: @YES };
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
    if (index >= self.mutableDiscoveredDevices.count) {
        [self logEvent:@"LINK" detail:@"connect skipped: selected index is out of range"];
        return;
    }
    [self cancelDemoFlowWithReason:@"new connection requested"];
    [self disconnect];
    [self stopScan];

    CBPeripheral *peripheral = self.mutableDiscoveredDevices[index].peripheral;
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
    [self cancelDemoFlowWithReason:@"disconnect requested"];
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

- (void)sendEventRuleMode:(NSString *)mode {
    [self sendProtocolOperation:BLEProtocolOpCommand
                           body:@{
        @"name": @"setEventRule",
        @"mode": mode ?: @"normal",
    }
                   includeToken:YES];
}

- (void)sendRawText:(NSString *)text {
    NSData *data = [(text ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    [self writeData:data label:@"raw legacy"];
}

- (void)runDemoFlow {
    if (!self.demoCharacteristic || !self.connectedPeripheral) {
        [self logEvent:@"FLOW" detail:@"demo flow skipped: characteristic missing"];
        return;
    }
    if (self.isDemoFlowRunning) {
        [self logEvent:@"FLOW" detail:@"demo flow skipped: already running"];
        return;
    }
    self.demoFlowRunning = YES;
    self.demoFlowGeneration += 1;
    NSUInteger generation = self.demoFlowGeneration;
    [self notifyStateChanged];
    [self logEvent:@"FLOW" detail:@"demo flow started: pair/info/ping/echo/telemetry/rules/commands/raw/read"];
    [self runDemoFlowSteps:[self demoFlowSteps] index:0 generation:generation];
}

- (NSArray *)demoFlowSteps {
    return @[
        [^{ [self setNotifyEnabled:YES]; } copy],
        [^{ [self sendPairCode:BLEProtocolDefaultPairCode]; } copy],
        [^{ [self sendProtocolGetInfo]; } copy],
        [^{ [self sendProtocolPing]; } copy],
        [^{ [self sendProtocolEcho:[self demoFlowLongEchoText]]; } copy],
        [^{ [self sendTelemetryRequest]; } copy],
        [^{ [self sendEventRuleMode:@"burst"]; } copy],
        [^{ [self sendCommandNamed:@"sample"]; } copy],
        [^{ [self sendEventRuleMode:@"normal"]; } copy],
        [^{ [self sendCommandNamed:@"identify"]; } copy],
        [^{ [self sendRawText:@"demo raw legacy payload"]; } copy],
        [^{ [self readValue]; } copy],
    ];
}

- (void)runDemoFlowSteps:(NSArray *)steps index:(NSUInteger)index generation:(NSUInteger)generation {
    if (![self isCurrentDemoFlowGeneration:generation]) {
        return;
    }
    if (index >= steps.count) {
        [self logEvent:@"FLOW" detail:@"demo flow queued"];
        self.demoFlowRunning = NO;
        [self notifyStateChanged];
        return;
    }
    void (^step)(void) = steps[index];
    step();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDemoFlowStepDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self runDemoFlowSteps:steps index:index + 1 generation:generation];
    });
}

- (NSString *)demoFlowLongEchoText {
    return @"demo-flow long echo payload: pair info ping telemetry rule burst sample identify raw read; "
           "this string is intentionally long enough to exercise notify queue and chunk reassembly across clients.";
}

- (BOOL)isCurrentDemoFlowGeneration:(NSUInteger)generation {
    return self.isDemoFlowRunning &&
           self.demoFlowGeneration == generation &&
           self.demoCharacteristic != nil &&
           self.connectedPeripheral != nil;
}

- (void)cancelDemoFlowWithReason:(NSString *)reason {
    self.demoFlowGeneration += 1;
    if (!self.isDemoFlowRunning) {
        return;
    }
    self.demoFlowRunning = NO;
    [self logEvent:@"FLOW" detail:[NSString stringWithFormat:@"demo flow cancelled: %@", reason]];
    [self notifyStateChanged];
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
    NSString *name = peripheral.name ?: advertisementData[CBAdvertisementDataLocalNameKey];
    if (name.length > 0 && ![name isEqualToString:kTargetPeripheralName]) {
        return;
    }

    BLEDiscoveredDeviceRecord *record = self.discoveredRecords[peripheral.identifier];
    BOOL isNew = record == nil;
    if (isNew) {
        record = [[BLEDiscoveredDeviceRecord alloc] init];
        record.peripheral = peripheral;
        [self.mutableDiscoveredDevices addObject:record];
        self.discoveredRecords[peripheral.identifier] = record;
    }
    NSInteger previousRSSI = record.RSSI.integerValue;
    [self updateDiscoveredRecord:record advertisementData:advertisementData RSSI:RSSI name:name];
    [self sortDiscoveredDevicesByRSSI];
    if (isNew || labs(previousRSSI - record.RSSI.integerValue) >= 8) {
        NSString *action = isNew ? @"found" : @"updated";
        [self logEvent:@"SCAN" detail:[NSString stringWithFormat:@"%@: %@ RSSI=%@ match=%@", action, record.displayName, record.RSSI, record.matchReason]];
    }
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
            [self sendProtocolGetInfo];
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
        if ([self handleChunkEnvelope:message label:label]) {
            return;
        }
        [self captureSessionTokenFromMessage:message];
        [self logEvent:@"RX" detail:[NSString stringWithFormat:@"%@ protocol: %@", label, [BLEProtocolMessage summaryForDictionary:message]]];
        [self logProtocolBodyForMessage:message];
        return;
    }

    [self logEvent:@"RX" detail:[NSString stringWithFormat:@"%@ raw: %lu B text=%@",
                                 label, (unsigned long)data.length, [self textOrHexForData:data]]];
}

- (BOOL)handleChunkEnvelope:(NSDictionary *)message label:(NSString *)label {
    if (![BLEProtocolMessage isChunkEnvelope:message]) {
        return NO;
    }

    NSString *streamID = nil;
    NSUInteger index = 0;
    NSUInteger count = 0;
    NSData *payload = [BLEProtocolMessage chunkPayloadFromEnvelope:message
                                                          streamID:&streamID
                                                             index:&index
                                                             count:&count];
    if (!payload) {
        [self logEvent:@"RX" detail:[NSString stringWithFormat:@"%@ chunk invalid", label]];
        return YES;
    }

    NSData *complete = [self captureChunkPayload:payload
                                          stream:streamID
                                           index:index
                                           count:count
                                           label:label];
    if (complete.length > 0) {
        [self logIncomingData:complete label:[NSString stringWithFormat:@"%@ chunk", label]];
    }
    return YES;
}

- (nullable NSData *)captureChunkPayload:(NSData *)payload
                                  stream:(NSString *)streamID
                                   index:(NSUInteger)index
                                   count:(NSUInteger)count
                                   label:(NSString *)label {
    if (count > kMaxChunkPartsPerStream) {
        [self logEvent:@"RX" detail:[NSString stringWithFormat:@"%@ chunk dropped: stream=%@ reason=part-count-limit count=%lu",
                                     label,
                                     streamID,
                                     (unsigned long)count]];
        return nil;
    }

    NSMutableDictionary<NSNumber *, NSData *> *chunks = self.chunkBuffers[streamID];
    NSNumber *expectedCount = self.chunkCounts[streamID];
    if (expectedCount && expectedCount.unsignedIntegerValue != count) {
        [self dropChunkStream:streamID];
        [self logEvent:@"RX" detail:[NSString stringWithFormat:@"%@ chunk cache trimmed: stream=%@ reason=count-changed",
                                     label,
                                     streamID]];
        chunks = nil;
    }
    if (!chunks) {
        [self trimChunkStreamsForIncomingStream:streamID label:label];
        chunks = [NSMutableDictionary dictionary];
        self.chunkBuffers[streamID] = chunks;
        self.chunkCounts[streamID] = @(count);
        [self.chunkStreamOrder addObject:streamID];
    }

    NSData *previousPayload = chunks[@(index)];
    NSUInteger previousLength = previousPayload.length;
    NSUInteger nextBufferedBytes = self.chunkBufferedBytes - previousLength + payload.length;
    if (nextBufferedBytes > kMaxChunkBufferedBytes) {
        [self dropChunkStream:streamID];
        [self logEvent:@"RX" detail:[NSString stringWithFormat:@"%@ chunk dropped: stream=%@ reason=byte-limit bytes=%lu buffered=%lu",
                                     label,
                                     streamID,
                                     (unsigned long)payload.length,
                                     (unsigned long)self.chunkBufferedBytes]];
        return nil;
    }
    chunks[@(index)] = payload;
    self.chunkBufferedBytes = nextBufferedBytes;
    [self logEvent:@"RX" detail:[NSString stringWithFormat:@"%@ chunk: stream=%@ part=%lu/%lu bytes=%lu",
                                 label,
                                 streamID,
                                 (unsigned long)(index + 1),
                                 (unsigned long)count,
                                 (unsigned long)payload.length]];
    if (chunks.count < count) {
        return nil;
    }
    return [self reassembledChunkDataForStream:streamID count:count];
}

- (nullable NSData *)reassembledChunkDataForStream:(NSString *)streamID count:(NSUInteger)count {
    NSMutableDictionary<NSNumber *, NSData *> *chunks = self.chunkBuffers[streamID];
    NSMutableData *complete = [NSMutableData data];
    for (NSUInteger index = 0; index < count; index++) {
        NSData *part = chunks[@(index)];
        if (!part) {
            return nil;
        }
        [complete appendData:part];
    }
    [self dropChunkStream:streamID];
    [self logEvent:@"RX" detail:[NSString stringWithFormat:@"chunk complete: stream=%@ bytes=%lu",
                                 streamID,
                                 (unsigned long)complete.length]];
    return complete.copy;
}

- (void)trimChunkStreamsForIncomingStream:(NSString *)streamID label:(NSString *)label {
    if (self.chunkBuffers[streamID] || self.chunkStreamOrder.count < kMaxChunkStreams) {
        return;
    }
    NSString *droppedStream = self.chunkStreamOrder.firstObject;
    [self dropChunkStream:droppedStream];
    [self logEvent:@"RX" detail:[NSString stringWithFormat:@"%@ chunk cache trimmed: stream=%@ reason=stream-limit",
                                 label,
                                 droppedStream]];
}

- (void)dropChunkStream:(NSString *)streamID {
    NSMutableDictionary<NSNumber *, NSData *> *chunks = self.chunkBuffers[streamID];
    [self.chunkBuffers removeObjectForKey:streamID];
    [self.chunkCounts removeObjectForKey:streamID];
    [self.chunkStreamOrder removeObject:streamID];
    if (!chunks) {
        return;
    }
    NSUInteger droppedBytes = 0;
    for (NSData *part in chunks.allValues) {
        droppedBytes += part.length;
    }
    self.chunkBufferedBytes = droppedBytes > self.chunkBufferedBytes ? 0 : self.chunkBufferedBytes - droppedBytes;
}

- (void)clearChunkBuffers {
    [self.chunkBuffers removeAllObjects];
    [self.chunkCounts removeAllObjects];
    [self.chunkStreamOrder removeAllObjects];
    self.chunkBufferedBytes = 0;
}

- (void)captureSessionTokenFromMessage:(NSDictionary *)message {
    NSString *token = [BLEProtocolMessage tokenFromEnvelope:message];
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
    NSString *operation = message[BLEProtocolKeyOperation] ?: @"?";
    [self captureEventRuleModeFromBody:body];
    if ([operation isEqualToString:BLEProtocolOpInfo]) {
        [self logEvent:@"CAP" detail:[BLEProtocolMessage capabilitySummaryForInfoBody:body]];
    }
    NSError *error = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&error];
    NSString *bodyText = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding] ?: @"{}";
    NSString *category = [operation isEqualToString:BLEProtocolOpEvent] ? @"EVT" : @"RX";
    [self logEvent:category detail:[NSString stringWithFormat:@"body=%@", bodyText]];
}

- (void)captureEventRuleModeFromBody:(NSDictionary *)body {
    NSString *mode = [BLEProtocolMessage eventRuleModeFromBody:body];
    if (mode.length == 0 || [mode isEqualToString:self.eventRuleMode]) {
        return;
    }
    self.eventRuleMode = mode;
    [self logEvent:@"RULE" detail:[NSString stringWithFormat:@"mode=%@", mode]];
    [self notifyStateChanged];
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

- (void)updateDiscoveredRecord:(BLEDiscoveredDeviceRecord *)record
             advertisementData:(NSDictionary<NSString *, id> *)advertisementData
                          RSSI:(NSNumber *)RSSI
                          name:(NSString *)name {
    record.RSSI = RSSI ?: @(0);
    record.displayName = name.length > 0 ? name : @"(unknown)";
    record.matchReason = [self matchReasonForAdvertisementData:advertisementData name:name];
    record.lastSeen = NSDate.date;
}

- (void)sortDiscoveredDevicesByRSSI {
    [self.mutableDiscoveredDevices sortUsingComparator:^NSComparisonResult(BLEDiscoveredDeviceRecord *first, BLEDiscoveredDeviceRecord *second) {
        return [second.RSSI compare:first.RSSI];
    }];
}

- (NSString *)matchReasonForAdvertisementData:(NSDictionary<NSString *, id> *)advertisementData name:(NSString *)name {
    NSMutableArray<NSString *> *reasons = [NSMutableArray array];
    NSArray<CBUUID *> *serviceUUIDs = [advertisementData[CBAdvertisementDataServiceUUIDsKey] isKindOfClass:[NSArray class]] ? advertisementData[CBAdvertisementDataServiceUUIDsKey] : @[];
    if ([serviceUUIDs containsObject:[CBUUID UUIDWithString:kServiceUUIDString]]) {
        [reasons addObject:@"service FFF0"];
    }
    if ([name isEqualToString:kTargetPeripheralName]) {
        [reasons addObject:@"name"];
    }
    if (reasons.count == 0) {
        [reasons addObject:@"service filter"];
    }
    return [reasons componentsJoinedByString:@"+"];
}

- (NSString *)labelForDiscoveredRecord:(BLEDiscoveredDeviceRecord *)record {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    NSString *seen = [formatter stringFromDate:record.lastSeen ?: NSDate.date];
    return [NSString stringWithFormat:@"%@ | RSSI %@ | %@ | seen %@",
            record.displayName,
            record.RSSI ?: @(0),
            record.matchReason,
            seen];
}

- (void)clearConnectionState {
    [self cancelDemoFlowWithReason:@"connection cleared"];
    self.connectedPeripheral = nil;
    self.demoCharacteristic = nil;
    self.connected = NO;
    self.notifyEnabled = NO;
    self.sessionToken = nil;
    self.eventRuleMode = kEventRuleModeNormal;
    [self clearChunkBuffers];
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

@implementation BLEDiscoveredDeviceRecord
@end
