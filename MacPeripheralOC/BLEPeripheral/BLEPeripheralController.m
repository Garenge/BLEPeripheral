#import "BLEPeripheralController.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "BLEProtocolConstants.h"
#import "BLEProtocolHandler.h"
#import "BLEProtocolMessage.h"

static NSString * const kDemoPeripheralName = @"MacBLE-Demo";
static NSString * const kDemoServiceUUIDString = @"0000FFF0-0000-1000-8000-00805F9B34FB";
static NSString * const kDemoCharacteristicUUIDString = @"0000FFF1-0000-1000-8000-00805F9B34FB";
static NSString * const kUnknownCentralUUIDString = @"00000000-0000-0000-0000-000000000001";
static NSString * const kEventRuleModeNormal = @"normal";
static NSString * const kEventRuleModeQuiet = @"quiet";
static NSString * const kEventRuleModeBurst = @"burst";
static NSUInteger const kNotifyChunkEnvelopeReserve = 96;
static NSUInteger const kDefaultNotifyMaxUpdateLength = 185;
static NSUInteger const kMaxNotifyChunkPartsPerStream = 256;
static NSUInteger const kMaxNotifyQueuePacketsPerCentral = 256;

static const uint8_t kEchoReplyPrefixBytes[] = { 0x00, 0xAA };

@interface BLETrackedCentral : NSObject
@property (nonatomic, copy) NSUUID *identifier;
@property (nonatomic, copy) NSString *sessionID;
@property (nonatomic, copy, nullable) NSString *sessionToken;
@property (nonatomic, copy) NSString *eventRuleMode;
@property (nonatomic, strong, nullable) CBCentral *central;
@property (nonatomic) BOOL linkSeen;
@property (nonatomic) BOOL notifyEnabled;
@property (nonatomic) NSUInteger maxUpdateLength;
@property (nonatomic) NSUInteger readCount;
@property (nonatomic) NSUInteger writeCount;
@property (nonatomic) NSUInteger notifyCount;
@property (nonatomic) NSUInteger eventCount;
@property (nonatomic, strong) NSMutableArray<NSData *> *notifyQueue;
@end

@interface BLEPeripheralController () <CBPeripheralManagerDelegate>

@property (nonatomic, copy) BLEPeripheralLogHandler logHandler;
@property (nonatomic, strong) CBPeripheralManager *peripheralManager;
@property (nonatomic, strong) CBMutableCharacteristic *demoCharacteristic;
@property (nonatomic, strong) NSMutableData *currentValue;
@property (nonatomic) BOOL hasSubscribers;
@property (nonatomic) BOOL servicesPublished;
@property (nonatomic, strong, nullable) NSUUID *activeCentralIdentifier;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, BLETrackedCentral *> *trackedCentrals;
@property (nonatomic) NSUInteger notifyStreamCounter;

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
    self.activeCentralIdentifier = nil;
    [self logEvent:@"SYS" detail:@"Peripheral stopped, advertising and GATT cleared"];
}

- (void)releaseActiveClient {
    if (!self.activeCentralIdentifier) {
        [self logEvent:@"LINK" detail:@"release requested: no active single-client owner"];
        [self resumeAdvertisingIfAvailableWithReason:@"manual release with no owner"];
        return;
    }
    NSString *owner = self.activeCentralIdentifier.UUIDString;
    [self.trackedCentrals removeObjectForKey:self.activeCentralIdentifier];
    self.activeCentralIdentifier = nil;
    self.hasSubscribers = [self anyCentralNotifyEnabled];
    [self logEvent:@"LINK-" detail:[NSString stringWithFormat:@"single-client manually released: central=%@", owner]];
    [self resumeAdvertisingIfAvailableWithReason:@"manual single-client release"];
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
    if (self.activeCentralIdentifier) {
        [self logEvent:@"SYS" detail:[NSString stringWithFormat:@"Advertising skipped: occupied by %@", self.activeCentralIdentifier.UUIDString]];
        return;
    }
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
    if (self.activeCentralIdentifier) {
        [self logEvent:@"SYS" detail:[NSString stringWithFormat:@"Name-only advertising skipped: occupied by %@", self.activeCentralIdentifier.UUIDString]];
        return;
    }
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

- (NSData *)responseDataForIncoming:(NSData *)incoming
                             central:(nullable CBCentral *)central
                       protocolResult:(BLEProtocolHandlerResult * _Nullable * _Nullable)protocolResult {
    if (![BLEProtocolHandler looksLikeProtocolData:incoming] &&
        ![self looksLikeProtocolCandidateData:incoming]) {
        if (protocolResult) {
            *protocolResult = nil;
        }
        return [self echoReplyDataForIncoming:incoming];
    }

    BLETrackedCentral *tracked = [self trackedCentralForCentral:central createIfNeeded:YES];
    BLEProtocolHandlerResult *result = [BLEProtocolHandler responseForRequestData:incoming
                                                                   peripheralName:kDemoPeripheralName
                                                                      serviceUUID:kDemoServiceUUIDString
                                                               characteristicUUID:kDemoCharacteristicUUIDString
                                                                        sessionID:tracked.sessionID
                                                                         pairCode:BLEProtocolDefaultPairCode
                                                                     currentToken:tracked.sessionToken
                                                                       readCount:tracked.readCount
                                                                      writeCount:tracked.writeCount
                                                                     notifyCount:tracked.notifyCount
                                                                       eventCount:tracked.eventCount
                                                                   eventRuleMode:tracked.eventRuleMode];
    if (result.sessionToken.length > 0) {
        tracked.sessionToken = result.sessionToken;
    }
    if (protocolResult) {
        *protocolResult = result;
    }
    return result.responseData ?: NSData.data;
}

- (void)pushSessionEventForCentral:(nullable CBCentral *)central
                              type:(NSString *)type
                              body:(NSDictionary *)body
                        peripheral:(CBPeripheralManager *)peripheral {
    BLETrackedCentral *tracked = [self trackedCentralForCentral:central createIfNeeded:YES];
    if (!tracked.notifyEnabled) {
        [self logEvent:@"TX" detail:[NSString stringWithFormat:@"event skipped: session=%@ notify OFF type=%@", tracked.sessionID, type]];
        return;
    }

    tracked.eventCount += 1;
    NSMutableDictionary *eventBody = body ? [body mutableCopy] : [NSMutableDictionary dictionary];
    eventBody[@"eventRuleMode"] = tracked.eventRuleMode ?: kEventRuleModeNormal;
    NSData *eventData = [BLEProtocolHandler eventNotificationDataWithType:type
                                                                 sequence:tracked.eventCount
                                                                  session:tracked.sessionID
                                                                     body:eventBody.copy];
    CBCentral *deliveryCentral = [self deliveryCentralForCentral:central tracked:tracked];
    [self enqueueNotifyPayload:eventData
                    forCentral:deliveryCentral
                        tracked:tracked
                        channel:@"notify/event"
                          extra:[NSString stringWithFormat:@"type=%@", type]];
    [self flushNotifyQueueForCentral:deliveryCentral tracked:tracked peripheral:peripheral];
}

- (void)applyProtocolResult:(BLEProtocolHandlerResult *)protocolResult
                 forCentral:(nullable CBCentral *)central
                 peripheral:(CBPeripheralManager *)peripheral {
    BLETrackedCentral *tracked = [self trackedCentralForCentral:central createIfNeeded:YES];
    if (!protocolResult.commandAccepted) {
        return;
    }

    NSDictionary *eventBody = [self commandEventBodyForName:protocolResult.commandName trackedCentral:tracked];
    if (protocolResult.shouldSetEventRuleMode) {
        NSString *oldMode = tracked.eventRuleMode ?: kEventRuleModeNormal;
        tracked.eventRuleMode = protocolResult.requestedEventRuleMode ?: kEventRuleModeNormal;
        [self pushSessionEventForCentral:central
                                    type:@"event.ruleChanged"
                                    body:@{
            @"name": protocolResult.commandName ?: @"setEventRule",
            @"previous": oldMode,
            @"mode": tracked.eventRuleMode,
        }
                              peripheral:peripheral];
        return;
    }
    if (protocolResult.shouldResetCounters) {
        tracked.readCount = 0;
        tracked.writeCount = 0;
        tracked.notifyCount = 0;
        tracked.eventCount = 0;
    }
    [self pushSessionEventForCentral:central
                                type:[NSString stringWithFormat:@"command.%@", protocolResult.commandName ?: @"unknown"]
                                body:eventBody
                          peripheral:peripheral];
    [self pushBurstDetailIfNeededForProtocolResult:protocolResult
                                           central:central
                                           tracked:tracked
                                        peripheral:peripheral];
}

- (NSDictionary *)commandEventBodyForName:(NSString *)name trackedCentral:(BLETrackedCentral *)tracked {
    if ([name isEqualToString:@"identify"]) {
        return @{
            @"name": name,
            @"peripheralName": kDemoPeripheralName,
            @"service": @"FFF0",
            @"characteristic": @"FFF1",
            @"session": tracked.sessionID ?: @"",
        };
    }
    if ([name isEqualToString:@"sample"]) {
        NSUInteger base = tracked.writeCount + tracked.readCount + tracked.notifyCount + tracked.eventCount;
        return @{
            @"name": name,
            @"battery": @(80 + (base % 15)),
            @"rssiHint": @(-45 - (NSInteger)(base % 20)),
            @"temperatureC": @(24 + (base % 5)),
        };
    }
    if ([name isEqualToString:@"resetCounters"]) {
        return @{
            @"name": name,
            @"before": @{
                @"reads": @(tracked.readCount),
                @"writes": @(tracked.writeCount),
                @"notifies": @(tracked.notifyCount),
                @"events": @(tracked.eventCount),
            },
            @"after": @{
                @"reads": @0,
                @"writes": @0,
                @"notifies": @0,
                @"events": @0,
            },
        };
    }
    return @{ @"name": name ?: @"unknown" };
}

- (void)pushBurstDetailIfNeededForProtocolResult:(BLEProtocolHandlerResult *)protocolResult
                                         central:(nullable CBCentral *)central
                                         tracked:(BLETrackedCentral *)tracked
                                      peripheral:(CBPeripheralManager *)peripheral {
    if (![tracked.eventRuleMode isEqualToString:kEventRuleModeBurst] ||
        ![protocolResult.commandName isEqualToString:@"sample"]) {
        return;
    }

    [self pushSessionEventForCentral:central
                                type:@"command.sample.detail"
                                body:@{
        @"name": @"sample",
        @"rule": kEventRuleModeBurst,
        @"samples": @[
            @{ @"metric": @"battery", @"unit": @"percent" },
            @{ @"metric": @"rssiHint", @"unit": @"dBm" },
            @{ @"metric": @"temperatureC", @"unit": @"celsius" },
        ],
    }
                          peripheral:peripheral];
}

- (BOOL)pushAutoNotifyReply:(CBPeripheralManager *)peripheral {
    if (![self anyCentralNotifyEnabled]) {
        [self logEvent:@"TX" detail:@"auto-push skipped — phone has NOT enabled Notify on FFF1 (must open Notify/CCCD, not Read)"];
        return NO;
    }

    NSUInteger sentCount = 0;
    for (BLETrackedCentral *tracked in self.trackedCentrals.allValues) {
        if (!tracked.notifyEnabled) {
            continue;
        }
        CBCentral *central = [self centralForTrackedCentral:tracked];
        [self enqueueNotifyPayload:self.currentValue
                        forCentral:central
                            tracked:tracked
                            channel:@"notify/reply"
                              extra:@"auto-push latest value"];
        if ([self flushNotifyQueueForCentral:central tracked:tracked peripheral:peripheral]) {
            sentCount += 1;
        }
    }
    return sentCount > 0;
}

- (BOOL)pushReply:(NSData *)payload
        toCentral:(nullable CBCentral *)central
       peripheral:(CBPeripheralManager *)peripheral {
    BLETrackedCentral *tracked = [self trackedCentralForCentral:central createIfNeeded:YES];
    CBCentral *deliveryCentral = [self deliveryCentralForCentral:central tracked:tracked];
    if (!tracked.notifyEnabled) {
        [self enqueueNotifyPayload:payload
                        forCentral:deliveryCentral
                            tracked:tracked
                            channel:@"notify/reply"
                              extra:@"notify OFF; queued for subscribe"];
        [self logEvent:@"TX" detail:[NSString stringWithFormat:@"reply stored: session=%@ notify OFF, use Read FFF1", tracked.sessionID]];
        return NO;
    }

    [self enqueueNotifyPayload:payload
                    forCentral:deliveryCentral
                        tracked:tracked
                        channel:@"notify/reply"
                          extra:@"targeted"];
    return [self flushNotifyQueueForCentral:deliveryCentral tracked:tracked peripheral:peripheral];
}

- (void)storeReplyAndAutoPush:(NSData *)responseData
                      peripheral:(CBPeripheralManager *)peripheral {
    [self.currentValue setData:responseData ?: NSData.data];
    [self pushAutoNotifyReply:peripheral];
}

- (void)enqueueNotifyPayload:(NSData *)payload
                  forCentral:(nullable CBCentral *)central
                      tracked:(BLETrackedCentral *)tracked
                      channel:(NSString *)channel
                        extra:(NSString *)extra {
    NSArray<NSData *> *packets = [self notifyPacketsForPayload:payload ?: NSData.data trackedCentral:tracked];
    [tracked.notifyQueue addObjectsFromArray:packets];
    NSUInteger droppedPackets = [self trimNotifyQueueForTrackedCentral:tracked];
    if (droppedPackets > 0) {
        [self logEvent:@"TX" detail:[NSString stringWithFormat:@"notify queue trimmed: session=%@ dropped=%lu kept=%lu",
                                      tracked.sessionID,
                                      (unsigned long)droppedPackets,
                                      (unsigned long)tracked.notifyQueue.count]];
    }
    [self logEvent:@"TX" detail:[NSString stringWithFormat:@"queued %@ packet(s): session=%@ channel=%@ bytes=%lu %@",
                                  @(packets.count),
                                  tracked.sessionID,
                                  channel,
                                  (unsigned long)(payload ?: NSData.data).length,
                                  extra.length > 0 ? extra : @""]];
}

- (BOOL)flushNotifyQueueForCentral:(nullable CBCentral *)central
                            tracked:(BLETrackedCentral *)tracked
                         peripheral:(CBPeripheralManager *)peripheral {
    BOOL sentAny = NO;
    while (tracked.notifyEnabled && tracked.notifyQueue.count > 0) {
        if (self.activeCentralIdentifier && !central) {
            [self logEvent:@"TX" detail:[NSString stringWithFormat:@"notify flush skipped: session=%@ no CBCentral object for occupied single-client session",
                                          tracked.sessionID]];
            return sentAny;
        }
        NSData *packet = tracked.notifyQueue.firstObject;
        BOOL didSend = [peripheral updateValue:packet
                             forCharacteristic:self.demoCharacteristic
                          onSubscribedCentrals:central ? @[ central ] : nil];
        if (!didSend) {
            [self logEvent:@"TX" detail:[NSString stringWithFormat:@"notify back-pressure: session=%@ queued=%lu",
                                          tracked.sessionID,
                                          (unsigned long)tracked.notifyQueue.count]];
            return sentAny;
        }
        [tracked.notifyQueue removeObjectAtIndex:0];
        tracked.notifyCount += 1;
        sentAny = YES;
        [self logTX:central
            channel:@"notify/packet"
               data:packet
              extra:[NSString stringWithFormat:@"queued=%lu", (unsigned long)tracked.notifyQueue.count]];
    }
    return sentAny;
}

- (NSUInteger)trimNotifyQueueForTrackedCentral:(BLETrackedCentral *)tracked {
    if (tracked.notifyQueue.count <= kMaxNotifyQueuePacketsPerCentral) {
        return 0;
    }
    NSUInteger droppedCount = tracked.notifyQueue.count - kMaxNotifyQueuePacketsPerCentral;
    [tracked.notifyQueue removeObjectsInRange:NSMakeRange(0, droppedCount)];
    return droppedCount;
}

- (NSArray<NSData *> *)notifyPacketsForPayload:(NSData *)payload trackedCentral:(BLETrackedCentral *)tracked {
    NSUInteger maxLength = tracked.maxUpdateLength > 0 ? tracked.maxUpdateLength : kDefaultNotifyMaxUpdateLength;
    if (payload.length <= maxLength) {
        return @[ payload ];
    }

    NSString *streamID = [self nextNotifyStreamIDForTrackedCentral:tracked];
    NSUInteger rawChunkLength = [self fittedRawChunkLengthForPayload:payload
                                                              stream:streamID
                                                           maxLength:maxLength];
    if (rawChunkLength == 0) {
        [self logEvent:@"TX" detail:[NSString stringWithFormat:@"payload chunk failed: session=%@ bytes=%lu maxUpdate=%lu",
                                      tracked.sessionID,
                                      (unsigned long)payload.length,
                                      (unsigned long)maxLength]];
        return @[];
    }

    NSUInteger chunkCount = (payload.length + rawChunkLength - 1) / rawChunkLength;
    NSMutableArray<NSData *> *packets = [NSMutableArray arrayWithCapacity:chunkCount];
    for (NSUInteger index = 0; index < chunkCount; index++) {
        NSUInteger offset = index * rawChunkLength;
        NSUInteger length = MIN(rawChunkLength, payload.length - offset);
        NSData *packet = [self chunkPacketForPayload:payload
                                              stream:streamID
                                               index:index
                                               count:chunkCount
                                              offset:offset
                                              length:length
                                           maxLength:maxLength];
        if (packet.length > 0) {
            [packets addObject:packet];
        }
    }
    [self logEvent:@"TX" detail:[NSString stringWithFormat:@"payload chunked: session=%@ stream=%@ bytes=%lu chunks=%lu maxUpdate=%lu",
                                  tracked.sessionID,
                                  streamID,
                                  (unsigned long)payload.length,
                                  (unsigned long)chunkCount,
                                  (unsigned long)maxLength]];
    return packets.copy;
}

- (nullable NSData *)chunkPacketForPayload:(NSData *)payload
                                    stream:(NSString *)streamID
                                     index:(NSUInteger)index
                                     count:(NSUInteger)count
                                    offset:(NSUInteger)offset
                                    length:(NSUInteger)length
                                 maxLength:(NSUInteger)maxLength {
    NSData *chunkData = [payload subdataWithRange:NSMakeRange(offset, length)];
    return [self chunkPacketForData:chunkData
                             stream:streamID
                              index:index
                              count:count
                          maxLength:maxLength];
}

- (nullable NSData *)chunkPacketForData:(NSData *)chunkData
                                 stream:(NSString *)streamID
                                  index:(NSUInteger)index
                                  count:(NSUInteger)count
                              maxLength:(NSUInteger)maxLength {
    NSDictionary *chunk = [BLEProtocolMessage chunkWithStreamID:streamID
                                                          index:index
                                                          count:count
                                                           data:chunkData];
    NSData *packet = [BLEProtocolMessage dataFromDictionary:chunk error:nil];
    if (packet.length > 0 && packet.length <= maxLength) {
        return packet;
    }
    return nil;
}

- (NSUInteger)fittedRawChunkLengthForPayload:(NSData *)payload
                                      stream:(NSString *)streamID
                                   maxLength:(NSUInteger)maxLength {
    NSUInteger rawChunkLength = MIN(payload.length, [self rawChunkLengthForMaxUpdateLength:maxLength]);
    while (rawChunkLength > 0) {
        NSUInteger chunkCount = (payload.length + rawChunkLength - 1) / rawChunkLength;
        if (chunkCount <= kMaxNotifyChunkPartsPerStream &&
            [self chunkPacketFitsForStream:streamID
                                     index:chunkCount - 1
                                     count:chunkCount
                                    length:rawChunkLength
                                 maxLength:maxLength]) {
            return rawChunkLength;
        }
        rawChunkLength -= 1;
    }
    return 0;
}

- (BOOL)chunkPacketFitsForStream:(NSString *)streamID
                           index:(NSUInteger)index
                           count:(NSUInteger)count
                          length:(NSUInteger)length
                       maxLength:(NSUInteger)maxLength {
    NSData *probeData = [NSMutableData dataWithLength:length];
    NSData *packet = [self chunkPacketForData:probeData
                                       stream:streamID
                                        index:index
                                        count:count
                                    maxLength:maxLength];
    return packet.length > 0;
}

- (NSUInteger)rawChunkLengthForMaxUpdateLength:(NSUInteger)maxLength {
    if (maxLength <= kNotifyChunkEnvelopeReserve + 16) {
        return MAX((NSUInteger)1, maxLength / 4);
    }
    NSUInteger budget = maxLength - kNotifyChunkEnvelopeReserve;
    return MAX((NSUInteger)1, (budget * 3) / 4);
}

- (NSString *)nextNotifyStreamIDForTrackedCentral:(BLETrackedCentral *)tracked {
    self.notifyStreamCounter += 1;
    return [NSString stringWithFormat:@"%@-%lu",
            tracked.sessionID ?: @"stream",
            (unsigned long)self.notifyStreamCounter];
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
        tracked.sessionID = [self shortSessionIDForUUID:uuid];
        tracked.eventRuleMode = kEventRuleModeNormal;
        self.trackedCentrals[uuid] = tracked;
    }
    return tracked;
}

- (nullable BLETrackedCentral *)trackedCentralForCentral:(nullable CBCentral *)central createIfNeeded:(BOOL)createIfNeeded {
    BLETrackedCentral *tracked = [self trackedCentralForUUID:[self uuidForCentral:central] createIfNeeded:createIfNeeded];
    if (central) {
        tracked.central = central;
        tracked.maxUpdateLength = central.maximumUpdateValueLength;
    }
    return tracked;
}

- (nullable CBCentral *)centralForTrackedCentral:(BLETrackedCentral *)tracked {
    return tracked.central;
}

- (nullable CBCentral *)deliveryCentralForCentral:(nullable CBCentral *)central tracked:(BLETrackedCentral *)tracked {
    if (central) {
        return central;
    }
    return tracked.central;
}

- (NSString *)shortSessionIDForUUID:(NSUUID *)uuid {
    NSString *raw = uuid.UUIDString ?: kUnknownCentralUUIDString;
    NSString *compact = [[raw stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
    NSUInteger length = MIN((NSUInteger)8, compact.length);
    return [NSString stringWithFormat:@"mac-%@", [compact substringToIndex:length]];
}

- (NSUUID *)uuidForCentral:(nullable CBCentral *)central {
    if (central.identifier) {
        return central.identifier;
    }
    if (self.activeCentralIdentifier) {
        return self.activeCentralIdentifier;
    }
    return [[NSUUID alloc] initWithUUIDString:kUnknownCentralUUIDString];
}

- (NSString *)centralTag:(nullable CBCentral *)central {
    if (central.identifier) {
        return central.identifier.UUIDString;
    }
    return [NSString stringWithFormat:@"unknown-central (%@)", kUnknownCentralUUIDString];
}

- (BOOL)looksLikeProtocolCandidateData:(NSData *)data {
    NSError *error = nil;
    NSDictionary *message = [BLEProtocolMessage dictionaryFromData:data error:&error];
    if (!message) {
        return NO;
    }
    return message[BLEProtocolKeyVersion] != nil || message[BLEProtocolKeyOperation] != nil;
}

- (BOOL)isSingleClientAllowedForCentral:(nullable CBCentral *)central action:(NSString *)action {
    if (!self.activeCentralIdentifier) {
        return YES;
    }
    if (!central.identifier) {
        [self logEvent:@"LINK" detail:[NSString stringWithFormat:@"central=nil allowed for %@ because CoreBluetooth did not expose requester; owner=%@",
                                       action,
                                       self.activeCentralIdentifier.UUIDString]];
        return YES;
    }
    if ([central.identifier isEqual:self.activeCentralIdentifier]) {
        return YES;
    }
    [self logEvent:@"LINK" detail:[NSString stringWithFormat:@"central=%@ | %@ REJECTED — occupied by %@",
                                   [self centralTag:central],
                                   action,
                                   self.activeCentralIdentifier.UUIDString]];
    return NO;
}

- (void)claimSingleClientIfNeededForCentral:(nullable CBCentral *)central reason:(NSString *)reason {
    if (!central.identifier) {
        [self logEvent:@"LINK" detail:[NSString stringWithFormat:@"single-client claim skipped: central=nil reason=%@", reason]];
        return;
    }
    NSUUID *uuid = central.identifier;
    if (!self.activeCentralIdentifier) {
        self.activeCentralIdentifier = uuid;
        BLETrackedCentral *tracked = [self trackedCentralForUUID:uuid createIfNeeded:YES];
        [self logEvent:@"LINK+" detail:[NSString stringWithFormat:@"single-client occupied: central=%@ session=%@ reason=%@",
                                        [self centralTag:central],
                                        tracked.sessionID,
                                        reason]];
        if (self.peripheralManager.isAdvertising) {
            [self.peripheralManager stopAdvertising];
            [self logEvent:@"SYS" detail:@"Advertising stopped: single-client session active"];
        }
        return;
    }
    if (![self.activeCentralIdentifier isEqual:uuid]) {
        [self logEvent:@"LINK" detail:[NSString stringWithFormat:@"single-client claim ignored: central=%@ reason=%@ owner=%@",
                                       [self centralTag:central],
                                       reason,
                                       self.activeCentralIdentifier.UUIDString]];
    }
}

- (void)releaseSingleClientIfNeededForCentral:(nullable CBCentral *)central reason:(NSString *)reason {
    if (!self.activeCentralIdentifier) {
        return;
    }
    if (!central.identifier) {
        [self logEvent:@"LINK" detail:[NSString stringWithFormat:@"single-client release skipped: central=nil reason=%@ owner=%@",
                                       reason,
                                       self.activeCentralIdentifier.UUIDString]];
        return;
    }
    NSUUID *uuid = central.identifier;
    if (![uuid isEqual:self.activeCentralIdentifier]) {
        return;
    }
    [self logEvent:@"LINK-" detail:[NSString stringWithFormat:@"single-client released: central=%@ reason=%@",
                                    [self centralTag:central],
                                    reason]];
    [self.trackedCentrals removeObjectForKey:uuid];
    self.activeCentralIdentifier = nil;
    self.hasSubscribers = [self anyCentralNotifyEnabled];
    [self resumeAdvertisingIfAvailableWithReason:@"single-client released"];
}

- (void)resumeAdvertisingIfAvailableWithReason:(NSString *)reason {
    if (self.activeCentralIdentifier) {
        return;
    }
    if (!self.servicesPublished || self.peripheralManager.state != CBManagerStatePoweredOn) {
        return;
    }
    if (self.peripheralManager.isAdvertising) {
        return;
    }
    [self logEvent:@"SYS" detail:[NSString stringWithFormat:@"Advertising resume: %@", reason]];
    [self startAdvertising];
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
        tracked.central = central;
        tracked.maxUpdateLength = central.maximumUpdateValueLength;
    }
    if (tracked.linkSeen) {
        [self logEvent:@"LINK" detail:[NSString stringWithFormat:@"central=%@ | %@ (already tracked, count=%lu)",
                                       [self centralTag:central], reason, (unsigned long)self.trackedCentrals.count]];
        return;
    }
    tracked.linkSeen = YES;
    [self logEvent:@"LINK+" detail:[NSString stringWithFormat:@"central=%@ session=%@ | connected — %@ | maxUpdate=%lu B | tracked=%lu",
                                    [self centralTag:central],
                                    tracked.sessionID,
                                    reason,
                                    (unsigned long)tracked.maxUpdateLength,
                                    (unsigned long)self.trackedCentrals.count]];
}

- (void)logLinkNotifySubscribed:(CBCentral *)central {
    NSUUID *uuid = [self uuidForCentral:central];
    BLETrackedCentral *tracked = [self trackedCentralForUUID:uuid createIfNeeded:YES];
    tracked.central = central;
    tracked.maxUpdateLength = central.maximumUpdateValueLength;
    tracked.notifyEnabled = YES;
    self.hasSubscribers = YES;
    [self logLinkConnectIfNeeded:central reason:@"notify subscribed on FFF1"];
    [self logEvent:@"LINK+" detail:[NSString stringWithFormat:@"central=%@ session=%@ | notify ON — push reply/event after each write",
                                    [self centralTag:central], tracked.sessionID]];
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
    self.activeCentralIdentifier = nil;
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
    BLETrackedCentral *tracked = [self trackedCentralForCentral:central createIfNeeded:YES];
    NSMutableString *detail = [NSMutableString stringWithFormat:@"central=%@ | %@",
                               [self centralTag:central], channel];
    if (tracked.sessionID.length > 0) {
        [detail appendFormat:@" | session=%@", tracked.sessionID];
    }
    if (extra.length > 0) {
        [detail appendFormat:@" | %@", extra];
    }
    [self logEvent:@"RX" detail:detail];
    [self logPayloadContent:data tag:@"RX"];
}

- (void)logTX:(nullable CBCentral *)central channel:(NSString *)channel data:(NSData *)data extra:(nullable NSString *)extra {
    BLETrackedCentral *tracked = [self trackedCentralForCentral:central createIfNeeded:NO];
    NSMutableString *detail = [NSMutableString stringWithFormat:@"central=%@ | %@",
                               [self centralTag:central], channel];
    if (tracked.sessionID.length > 0) {
        [detail appendFormat:@" | session=%@", tracked.sessionID];
    }
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
    [self log:[NSString stringWithFormat:@"Security rule: pair code %@ -> session token; protected ops include echo/telemetry/command", BLEProtocolDefaultPairCode]];
    [self log:@"Single-client rule: first identifiable Read/Write/Notify on FFF1 occupies the peripheral and stops advertising"];
    [self log:@"Message rule: JSON protocol replies over notify/read; non-protocol payload keeps 0x00 0xAA echo"];
    [self log:@"Event rule modes: normal, quiet, burst; command setEventRule switches a session"];
    [self log:@"Auto delivery: Notify pushes reply + session events after writes (phone must enable Notify on FFF1)"];
    [self log:@"Read FFF1 only if Notify is off — third-party apps can still write raw bytes for 00AA echo"];
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

    if (![self isSingleClientAllowedForCentral:central action:@"read/FFF1"]) {
        [peripheral respondToRequest:request withResult:CBATTErrorInsufficientAuthorization];
        return;
    }

    if (request.offset > self.currentValue.length) {
        [self logEvent:@"RX" detail:[NSString stringWithFormat:@"central=%@ | read REJECTED invalid offset %lu",
                                       [self centralTag:central], (unsigned long)request.offset]];
        [peripheral respondToRequest:request withResult:CBATTErrorInvalidOffset];
        return;
    }

    [self claimSingleClientIfNeededForCentral:central reason:@"read FFF1"];

    BLETrackedCentral *tracked = [self trackedCentralForCentral:central createIfNeeded:YES];
    tracked.readCount += 1;
    [self logRX:central
         channel:@"read/FFF1"
            data:self.currentValue
           extra:[NSString stringWithFormat:@"offset=%lu readCount=%lu", (unsigned long)request.offset, (unsigned long)tracked.readCount]];

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

        if (![self isSingleClientAllowedForCentral:central action:@"write/FFF1"]) {
            [peripheral respondToRequest:request withResult:CBATTErrorInsufficientAuthorization];
            continue;
        }
        [self claimSingleClientIfNeededForCentral:central reason:@"write FFF1"];

        BOOL supportsWriteWithResponse = (self.demoCharacteristic.properties & CBCharacteristicPropertyWrite) != 0;
        BOOL supportsWriteWithoutResponse = (self.demoCharacteristic.properties & CBCharacteristicPropertyWriteWithoutResponse) != 0;
        NSString *writeModeHint = [NSString stringWithFormat:@"char supports write=%@ writeNoResp=%@ (protocol: use write+notify)",
                                   supportsWriteWithResponse ? @"YES" : @"NO",
                                   supportsWriteWithoutResponse ? @"YES" : @"NO"];

        NSData *incoming = request.value ?: NSData.data;
        [self logRX:central channel:@"write/FFF1" data:incoming extra:writeModeHint];
        BLETrackedCentral *tracked = [self trackedCentralForCentral:central createIfNeeded:YES];
        tracked.writeCount += 1;

        BLEProtocolHandlerResult *protocolResult = nil;
        NSData *outgoing = [self responseDataForIncoming:incoming central:central protocolResult:&protocolResult];
        if (protocolResult) {
            [self logEvent:@"TX" detail:[NSString stringWithFormat:@"protocol rule: %@", protocolResult.logSummary ?: @"response"]];
            if (protocolResult.pairingSucceeded) {
                [self claimSingleClientIfNeededForCentral:central reason:@"pair succeeded"];
            }
        } else {
            [self logEvent:@"TX" detail:@"legacy echo rule: 00 AA + RX payload"];
        }

        // 先 ATT 应答，再 Notify 推送（部分 Central 在 write 完成后再处理 notify）。
        [peripheral respondToRequest:request withResult:CBATTErrorSuccess];
        [self logEvent:@"TX" detail:@"ATT write response=success"];

        [self.currentValue setData:outgoing ?: NSData.data];
        if (protocolResult) {
            [self pushReply:outgoing toCentral:central peripheral:peripheral];
            NSString *eventType = protocolResult.pairingSucceeded ? @"paired" : @"write";
            if ([self shouldPushWriteEventType:eventType trackedCentral:tracked protocolResult:protocolResult]) {
                [self pushSessionEventForCentral:central
                                            type:eventType
                                            body:@{
                    @"writes": @(tracked.writeCount),
                    @"reads": @(tracked.readCount),
                    @"notifies": @(tracked.notifyCount),
                }
                                      peripheral:peripheral];
            }
            [self applyProtocolResult:protocolResult forCentral:central peripheral:peripheral];
        } else {
            [self pushReply:outgoing toCentral:central peripheral:peripheral];
        }
    }
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didSubscribeToCharacteristic:(CBCharacteristic *)characteristic {
    [self logEvent:@"SYS" detail:[NSString stringWithFormat:@"didSubscribe FFF1 central=%@", [self centralTag:central]]];
    if (![self isSingleClientAllowedForCentral:central action:@"notify/FFF1"]) {
        return;
    }
    [self claimSingleClientIfNeededForCentral:central reason:@"notify subscribed"];
    [self logLinkNotifySubscribed:central];
    [self logEvent:@"SYS" detail:@"Notify ON — write replies will auto-push (no Read needed)"];

    BLETrackedCentral *tracked = [self trackedCentralForCentral:central createIfNeeded:YES];
    BOOL hadQueuedReplies = tracked.notifyQueue.count > 0;
    [self flushNotifyQueueForCentral:central tracked:tracked peripheral:peripheral];

    if (!hadQueuedReplies && self.currentValue.length > 0) {
        [self pushReply:self.currentValue toCentral:central peripheral:peripheral];
    }
    [self pushSessionEventForCentral:central
                                type:@"subscribed"
                                body:@{ @"notifyMax": @(tracked.maxUpdateLength) }
                          peripheral:peripheral];
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic {
    [self logLinkNotifyUnsubscribed:central];
    [self releaseSingleClientIfNeededForCentral:central reason:@"notify unsubscribed"];
    // CoreBluetooth peripheral role has no explicit disconnect callback; link drop is inferred when Central leaves.
    [self logEvent:@"LINK" detail:[NSString stringWithFormat:@"central=%@ | if iPhone disconnected entirely, no further RX/TX until reconnect",
                                   [self centralTag:central]]];
}

- (void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)peripheral {
    [self logEvent:@"TX" detail:@"notify queue ready — flushing subscribed central queues"];
    for (BLETrackedCentral *tracked in self.trackedCentrals.allValues) {
        if (!tracked.notifyEnabled) {
            continue;
        }
        [self flushNotifyQueueForCentral:[self centralForTrackedCentral:tracked]
                                  tracked:tracked
                               peripheral:peripheral];
    }
}

- (BOOL)shouldPushWriteEventType:(NSString *)eventType
                  trackedCentral:(BLETrackedCentral *)tracked
                  protocolResult:(BLEProtocolHandlerResult *)protocolResult {
    if ([eventType isEqualToString:@"paired"]) {
        return YES;
    }
    if (protocolResult.shouldSetEventRuleMode) {
        return NO;
    }
    if ([tracked.eventRuleMode isEqualToString:kEventRuleModeQuiet]) {
        return NO;
    }
    return YES;
}

@end

#pragma mark - BLETrackedCentral

@implementation BLETrackedCentral

- (instancetype)init {
    self = [super init];
    if (self) {
        _eventRuleMode = kEventRuleModeNormal;
        _notifyQueue = [NSMutableArray array];
    }
    return self;
}

@end
