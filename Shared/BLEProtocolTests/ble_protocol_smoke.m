#import <Foundation/Foundation.h>
#import "../BLEProtocol/BLEProtocolConstants.h"
#import "../BLEProtocol/BLEProtocolHandler.h"
#import "../BLEProtocol/BLEProtocolMessage.h"

static NSString * const kPeripheralName = @"MacBLE-Demo";
static NSString * const kServiceUUID = @"0000FFF0-0000-1000-8000-00805F9B34FB";
static NSString * const kCharacteristicUUID = @"0000FFF1-0000-1000-8000-00805F9B34FB";
static NSString * const kSessionID = @"test-session";

static NSUInteger gFailureCount = 0;
static BOOL gVerbose = NO;

static void AssertTrue(BOOL condition, NSString *message) {
    if (condition) {
        if (gVerbose) {
            NSLog(@"PASS %@", message);
        }
    } else {
        gFailureCount += 1;
        NSLog(@"FAIL %@", message);
    }
}

static NSData *DataForRequest(NSString *operation, NSString *messageID, NSString *token, NSDictionary *body) {
    NSDictionary *request = [BLEProtocolMessage requestWithOperation:operation
                                                           messageID:messageID
                                                               token:token
                                                                body:body ?: @{}];
    NSError *error = nil;
    NSData *data = [BLEProtocolMessage dataFromDictionary:request error:&error];
    AssertTrue(data != nil, [NSString stringWithFormat:@"encode request %@", operation]);
    return data ?: NSData.data;
}

static NSDictionary *EnvelopeFromData(NSData *data) {
    NSError *error = nil;
    NSDictionary *envelope = [BLEProtocolMessage dictionaryFromData:data error:&error];
    AssertTrue(envelope != nil, @"decode response envelope");
    return envelope ?: @{};
}

static NSArray *FixturePayloads(void) {
    NSString *path = [NSProcessInfo.processInfo.environment objectForKey:@"BLE_PAYLOAD_FIXTURES"];
    AssertTrue(path.length > 0, @"fixture path environment is set");
    NSData *data = path.length > 0 ? [NSData dataWithContentsOfFile:path] : nil;
    AssertTrue(data != nil, @"fixture file loads");
    NSError *error = nil;
    NSDictionary *root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
    NSArray *payloads = [root[@"payloads"] isKindOfClass:[NSArray class]] ? root[@"payloads"] : @[];
    AssertTrue(payloads.count > 0, @"fixture payloads load");
    return payloads;
}

static NSDictionary *FixtureNamed(NSArray *payloads, NSString *name) {
    for (NSDictionary *payload in payloads) {
        if ([payload[@"name"] isEqualToString:name]) {
            return payload;
        }
    }
    AssertTrue(NO, [NSString stringWithFormat:@"fixture %@ exists", name]);
    return @{};
}

static NSData *FixtureData(NSDictionary *fixture) {
    NSString *base64 = [fixture[@"base64"] isKindOfClass:[NSString class]] ? fixture[@"base64"] : @"";
    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    AssertTrue(data != nil, [NSString stringWithFormat:@"fixture %@ base64 decodes", fixture[@"name"] ?: @"?"]);
    return data ?: NSData.data;
}

static BLEProtocolHandlerResult *HandleRequest(NSData *requestData, NSString *currentToken, NSUInteger reads, NSUInteger writes, NSUInteger notifies, NSUInteger events) {
    return [BLEProtocolHandler responseForRequestData:requestData
                                      peripheralName:kPeripheralName
                                         serviceUUID:kServiceUUID
                                  characteristicUUID:kCharacteristicUUID
                                           sessionID:kSessionID
                                            pairCode:BLEProtocolDefaultPairCode
                                        currentToken:currentToken
                                           readCount:reads
                                          writeCount:writes
                                         notifyCount:notifies
                                          eventCount:events
                                      eventRuleMode:nil];
}

static BLEProtocolHandlerResult *HandleRequestWithRule(NSData *requestData, NSString *currentToken, NSUInteger reads, NSUInteger writes, NSUInteger notifies, NSUInteger events, NSString *eventRuleMode) {
    return [BLEProtocolHandler responseForRequestData:requestData
                                      peripheralName:kPeripheralName
                                         serviceUUID:kServiceUUID
                                  characteristicUUID:kCharacteristicUUID
                                           sessionID:kSessionID
                                            pairCode:BLEProtocolDefaultPairCode
                                        currentToken:currentToken
                                           readCount:reads
                                          writeCount:writes
                                         notifyCount:notifies
                                          eventCount:events
                                      eventRuleMode:eventRuleMode];
}

static void TestPairSuccess(void) {
    NSData *request = DataForRequest(BLEProtocolOpPair, @"pair-1", nil, @{ @"code": BLEProtocolDefaultPairCode });
    BLEProtocolHandlerResult *result = HandleRequest(request, nil, 0, 0, 0, 0);
    NSDictionary *response = EnvelopeFromData(result.responseData);

    AssertTrue(result.pairingSucceeded, @"pair succeeds with default code");
    AssertTrue(result.sessionToken.length > 0, @"pair returns session token");
    AssertTrue([response[BLEProtocolKeyOperation] isEqualToString:BLEProtocolOpPaired], @"pair response op is paired");
    AssertTrue([response[BLEProtocolKeyToken] isEqualToString:result.sessionToken], @"pair response top-level token matches result");
}

static void TestProtectedOperationRequiresToken(void) {
    NSData *request = DataForRequest(BLEProtocolOpEcho, @"echo-1", nil, @{ @"text": @"hello" });
    BLEProtocolHandlerResult *result = HandleRequest(request, nil, 0, 0, 0, 0);
    NSDictionary *response = EnvelopeFromData(result.responseData);

    AssertTrue([response[BLEProtocolKeyOperation] isEqualToString:BLEProtocolOpError], @"echo without token returns error");
    NSDictionary *error = response[BLEProtocolKeyError];
    AssertTrue([error[@"code"] isEqualToString:BLEProtocolErrorUnauthorized], @"echo without token is unauthorized");
}

static void TestEchoWithToken(void) {
    NSString *token = @"tok-test";
    NSData *request = DataForRequest(BLEProtocolOpEcho, @"echo-2", token, @{ @"text": @"hello" });
    BLEProtocolHandlerResult *result = HandleRequest(request, token, 0, 1, 0, 0);
    NSDictionary *response = EnvelopeFromData(result.responseData);

    AssertTrue([response[BLEProtocolKeyOperation] isEqualToString:BLEProtocolOpEcho], @"echo with token returns echo");
    AssertTrue([response[BLEProtocolKeyToken] isEqualToString:token], @"echo response preserves token");
    AssertTrue([response[BLEProtocolKeyBody][@"text"] isEqualToString:@"hello"], @"echo response body text matches");
}

static void TestBodyTokenMustBeString(void) {
    NSString *token = @"tok-test";
    NSDictionary *request = @{
        BLEProtocolKeyVersion: @(BLEProtocolVersion),
        BLEProtocolKeyOperation: BLEProtocolOpEcho,
        BLEProtocolKeyMessageID: @"echo-bad-body-token",
        BLEProtocolKeyBody: @{
            @"text": @"hello",
            BLEProtocolKeyToken: @123,
        },
    };
    NSData *data = [BLEProtocolMessage dataFromDictionary:request error:nil];
    BLEProtocolHandlerResult *result = HandleRequest(data, token, 0, 1, 0, 0);
    NSDictionary *response = EnvelopeFromData(result.responseData);

    AssertTrue([BLEProtocolMessage tokenFromEnvelope:request] == nil, @"body token ignores non-string values");
    AssertTrue([response[BLEProtocolKeyOperation] isEqualToString:BLEProtocolOpError], @"numeric body token returns error");
    AssertTrue([response[BLEProtocolKeyError][@"code"] isEqualToString:BLEProtocolErrorUnauthorized], @"numeric body token is unauthorized");
}

static void TestUnknownOperationDoesNotRequireTokenFirst(void) {
    NSData *request = DataForRequest(@"dance", @"unknown-1", nil, @{});
    BLEProtocolHandlerResult *result = HandleRequest(request, nil, 0, 0, 0, 0);
    NSDictionary *response = EnvelopeFromData(result.responseData);

    AssertTrue([response[BLEProtocolKeyOperation] isEqualToString:BLEProtocolOpError], @"unknown op returns error");
    AssertTrue([response[BLEProtocolKeyError][@"code"] isEqualToString:BLEProtocolErrorUnknownOperation], @"unknown op is reported before auth");

    NSData *tokenRequest = DataForRequest(@"dance", @"unknown-2", @"tok-test", @{});
    BLEProtocolHandlerResult *tokenResult = HandleRequest(tokenRequest, @"tok-test", 0, 0, 0, 0);
    NSDictionary *tokenResponse = EnvelopeFromData(tokenResult.responseData);
    AssertTrue([tokenResponse[BLEProtocolKeyError][@"code"] isEqualToString:BLEProtocolErrorUnknownOperation], @"unknown op with token is also unknown_op");
}

static void TestEnvelopeRejectsInvalidVersionNumbers(void) {
    NSArray<NSDictionary *> *invalidVersions = @[
        @{
            @"name": @"boolean version",
            @"value": @YES,
        },
        @{
            @"name": @"fractional version",
            @"value": @1.5,
        },
    ];

    for (NSDictionary *version in invalidVersions) {
        NSDictionary *request = @{
            BLEProtocolKeyVersion: version[@"value"],
            BLEProtocolKeyOperation: BLEProtocolOpPing,
            BLEProtocolKeyMessageID: @"bad-version",
            BLEProtocolKeyBody: @{},
        };
        NSData *data = [BLEProtocolMessage dataFromDictionary:request error:nil];
        BLEProtocolHandlerResult *result = HandleRequest(data, nil, 0, 0, 0, 0);
        NSDictionary *response = EnvelopeFromData(result.responseData);
        AssertTrue(![BLEProtocolHandler looksLikeProtocolData:data],
                   [NSString stringWithFormat:@"protocol detector rejects %@", version[@"name"]]);
        AssertTrue([response[BLEProtocolKeyError][@"code"] isEqualToString:BLEProtocolErrorInvalidEnvelope],
                   [NSString stringWithFormat:@"handler rejects %@", version[@"name"]]);
    }
}

static void TestInfoCapabilityDiscovery(void) {
    NSData *request = DataForRequest(BLEProtocolOpGetInfo, @"info-1", nil, @{});
    BLEProtocolHandlerResult *result = HandleRequest(request, nil, 1, 2, 3, 4);
    NSDictionary *response = EnvelopeFromData(result.responseData);
    NSDictionary *body = response[BLEProtocolKeyBody];
    NSDictionary *operations = body[@"operations"];
    NSDictionary *security = body[@"security"];
    NSArray *commands = body[@"commands"];
    NSArray *events = body[@"events"];
    NSString *summary = [BLEProtocolMessage capabilitySummaryForInfoBody:body];

    AssertTrue([response[BLEProtocolKeyOperation] isEqualToString:BLEProtocolOpInfo], @"getInfo returns info");
    AssertTrue([body[@"capabilitySchema"] isEqualToString:@"ble-demo.capabilities.v1"], @"info includes capability schema");
    AssertTrue([operations[@"open"] containsObject:BLEProtocolOpGetInfo], @"info marks getInfo as open");
    AssertTrue([operations[@"protected"] containsObject:BLEProtocolOpCommand], @"info marks command as protected");
    AssertTrue([security[@"tokenAcceptedIn"] containsObject:@"body.token"], @"info documents body token fallback");
    AssertTrue(commands.count == 4, @"info lists demo commands");
    AssertTrue(events.count >= 8, @"info lists event types");
    AssertTrue([summary containsString:@"commands=identify,sample,resetCounters,setEventRule"], @"capability summary lists command names");
    AssertTrue([summary containsString:@"rules=normal,quiet,burst"], @"capability summary lists event rule modes");
    AssertTrue([[BLEProtocolMessage eventRuleModeFromBody:body] isEqualToString:@"normal"], @"info body exposes current event rule mode");
}

static void TestCommandMetadata(void) {
    NSString *token = @"tok-test";
    NSData *request = DataForRequest(BLEProtocolOpCommand, @"cmd-1", token, @{ @"name": @"resetCounters" });
    BLEProtocolHandlerResult *result = HandleRequest(request, token, 4, 5, 6, 7);
    NSDictionary *response = EnvelopeFromData(result.responseData);

    AssertTrue(result.commandAccepted, @"resetCounters command accepted");
    AssertTrue(result.shouldResetCounters, @"resetCounters marks counter reset");
    AssertTrue([result.commandName isEqualToString:@"resetCounters"], @"command name captured");
    AssertTrue([response[BLEProtocolKeyBody][@"effect"] isEqualToString:@"reset session counters"], @"command effect documented in body");
}

static void TestSetEventRuleCommand(void) {
    NSString *token = @"tok-test";
    NSData *request = DataForRequest(BLEProtocolOpCommand, @"rule-1", token, @{
        @"name": @"setEventRule",
        @"mode": @"burst",
    });
    BLEProtocolHandlerResult *result = HandleRequestWithRule(request, token, 0, 0, 0, 0, @"quiet");
    NSDictionary *response = EnvelopeFromData(result.responseData);

    AssertTrue(result.commandAccepted, @"setEventRule command accepted");
    AssertTrue(result.shouldSetEventRuleMode, @"setEventRule marks rule mode update");
    AssertTrue([result.requestedEventRuleMode isEqualToString:@"burst"], @"setEventRule captures requested mode");
    AssertTrue([response[BLEProtocolKeyBody][@"eventRuleMode"] isEqualToString:@"burst"], @"setEventRule response returns next mode");
}

static void TestSetEventRuleRejectsInvalidMode(void) {
    NSString *token = @"tok-test";
    NSData *request = DataForRequest(BLEProtocolOpCommand, @"rule-2", token, @{
        @"name": @"setEventRule",
        @"mode": @"loud",
    });
    BLEProtocolHandlerResult *result = HandleRequest(request, token, 0, 0, 0, 0);
    NSDictionary *response = EnvelopeFromData(result.responseData);

    AssertTrue(!result.commandAccepted, @"invalid setEventRule not accepted");
    AssertTrue(!result.shouldSetEventRuleMode, @"invalid setEventRule does not mark update");
    AssertTrue([response[BLEProtocolKeyOperation] isEqualToString:BLEProtocolOpError], @"invalid setEventRule returns error");
    AssertTrue([response[BLEProtocolKeyError][@"code"] isEqualToString:BLEProtocolErrorInvalidBody], @"invalid setEventRule is invalid_body");
}

static void TestCommandMissingName(void) {
    NSString *token = @"tok-test";
    NSData *request = DataForRequest(BLEProtocolOpCommand, @"cmd-2", token, @{});
    BLEProtocolHandlerResult *result = HandleRequest(request, token, 0, 0, 0, 0);
    NSDictionary *response = EnvelopeFromData(result.responseData);

    AssertTrue(!result.commandAccepted, @"missing command name not accepted");
    AssertTrue(!result.shouldResetCounters, @"missing command name does not reset counters");
    AssertTrue([response[BLEProtocolKeyOperation] isEqualToString:BLEProtocolOpError], @"missing command name returns error");
    AssertTrue([response[BLEProtocolKeyError][@"code"] isEqualToString:BLEProtocolErrorInvalidBody], @"missing command name is invalid_body");
}

static void TestChunkEnvelopeRoundTrip(void) {
    NSData *payload = [@"hello chunk" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *chunk = [BLEProtocolMessage chunkWithStreamID:@"stream-1" index:1 count:3 data:payload];
    NSError *error = nil;
    NSData *data = [BLEProtocolMessage dataFromDictionary:chunk error:&error];
    NSDictionary *decoded = [BLEProtocolMessage dictionaryFromData:data error:&error];
    NSString *streamID = nil;
    NSUInteger index = 0;
    NSUInteger count = 0;
    NSData *decodedPayload = [BLEProtocolMessage chunkPayloadFromEnvelope:decoded
                                                                  streamID:&streamID
                                                                     index:&index
                                                                     count:&count];

    AssertTrue([BLEProtocolMessage isChunkEnvelope:decoded], @"chunk envelope recognized");
    AssertTrue([streamID isEqualToString:@"stream-1"], @"chunk stream decoded");
    AssertTrue(index == 1, @"chunk index decoded");
    AssertTrue(count == 3, @"chunk count decoded");
    AssertTrue([decodedPayload isEqualToData:payload], @"chunk payload round trips");
}

static void TestChunkRejectsInvalidNumericFields(void) {
    NSData *payload = [@"hello chunk" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [payload base64EncodedStringWithOptions:0];
    NSArray<NSDictionary *> *invalidChunks = @[
        @{
            @"name": @"negative index",
            @"body": @{
                @"stream": @"stream-1",
                @"index": @(-1),
                @"count": @2,
                @"encoding": @"base64",
                @"data": encoded,
            },
        },
        @{
            @"name": @"negative count",
            @"body": @{
                @"stream": @"stream-1",
                @"index": @0,
                @"count": @(-2),
                @"encoding": @"base64",
                @"data": encoded,
            },
        },
        @{
            @"name": @"fractional index",
            @"body": @{
                @"stream": @"stream-1",
                @"index": @1.5,
                @"count": @2,
                @"encoding": @"base64",
                @"data": encoded,
            },
        },
        @{
            @"name": @"boolean index",
            @"body": @{
                @"stream": @"stream-1",
                @"index": @YES,
                @"count": @2,
                @"encoding": @"base64",
                @"data": encoded,
            },
        },
    ];

    for (NSDictionary *invalidChunk in invalidChunks) {
        NSDictionary *envelope = [BLEProtocolMessage successResponseForOperation:BLEProtocolOpChunk
                                                                       messageID:@"chunk-invalid"
                                                                            body:invalidChunk[@"body"]];
        NSData *decodedPayload = [BLEProtocolMessage chunkPayloadFromEnvelope:envelope
                                                                     streamID:nil
                                                                        index:nil
                                                                        count:nil];
        AssertTrue(decodedPayload == nil,
                   [NSString stringWithFormat:@"chunk rejects %@", invalidChunk[@"name"]]);
    }
}

static void TestRecordedPayloadFixtures(void) {
    NSArray *payloads = FixturePayloads();
    NSDictionary *legacyFixture = FixtureNamed(payloads, @"legacy_echo");
    NSData *legacyData = FixtureData(legacyFixture);
    AssertTrue(legacyData.length >= 2, @"legacy fixture has prefix bytes");
    const uint8_t *legacyBytes = legacyData.bytes;
    AssertTrue(legacyBytes[0] == 0x00 && legacyBytes[1] == 0xAA, @"legacy fixture prefix is 00AA");

    NSDictionary *paired = EnvelopeFromData(FixtureData(FixtureNamed(payloads, @"paired_response")));
    AssertTrue([paired[BLEProtocolKeyOperation] isEqualToString:BLEProtocolOpPaired], @"paired fixture operation");
    AssertTrue([paired[BLEProtocolKeyToken] isEqualToString:@"tok-fixture"], @"paired fixture token");

    NSDictionary *echo = EnvelopeFromData(FixtureData(FixtureNamed(payloads, @"echo_response")));
    AssertTrue([echo[BLEProtocolKeyOperation] isEqualToString:BLEProtocolOpEcho], @"echo fixture operation");
    AssertTrue([echo[BLEProtocolKeyBody][@"text"] isEqualToString:@"hello chunk fixture"], @"echo fixture text");

    NSDictionary *chunk0 = EnvelopeFromData(FixtureData(FixtureNamed(payloads, @"echo_chunk_0")));
    NSDictionary *chunk1 = EnvelopeFromData(FixtureData(FixtureNamed(payloads, @"echo_chunk_1")));
    NSString *stream0 = nil;
    NSString *stream1 = nil;
    NSUInteger index0 = 0;
    NSUInteger index1 = 0;
    NSUInteger count0 = 0;
    NSUInteger count1 = 0;
    NSData *part0 = [BLEProtocolMessage chunkPayloadFromEnvelope:chunk0 streamID:&stream0 index:&index0 count:&count0];
    NSData *part1 = [BLEProtocolMessage chunkPayloadFromEnvelope:chunk1 streamID:&stream1 index:&index1 count:&count1];
    NSMutableData *complete = [NSMutableData dataWithData:part0 ?: NSData.data];
    [complete appendData:part1 ?: NSData.data];
    AssertTrue([stream0 isEqualToString:stream1], @"chunk fixtures share stream");
    AssertTrue(index0 == 0 && index1 == 1 && count0 == 2 && count1 == 2, @"chunk fixture indexes and count");
    AssertTrue([complete isEqualToData:FixtureData(FixtureNamed(payloads, @"echo_response"))], @"chunk fixtures reassemble echo fixture");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        gVerbose = [NSProcessInfo.processInfo.environment[@"BLE_PROTOCOL_SMOKE_VERBOSE"] boolValue];
        NSLog(@"BLEProtocol smoke tests starting");
        TestPairSuccess();
        TestProtectedOperationRequiresToken();
        TestEchoWithToken();
        TestUnknownOperationDoesNotRequireTokenFirst();
        TestEnvelopeRejectsInvalidVersionNumbers();
        TestInfoCapabilityDiscovery();
        TestCommandMetadata();
        TestSetEventRuleCommand();
        TestSetEventRuleRejectsInvalidMode();
        TestCommandMissingName();
        TestBodyTokenMustBeString();
        TestChunkEnvelopeRoundTrip();
        TestChunkRejectsInvalidNumericFields();
        TestRecordedPayloadFixtures();
        if (gFailureCount > 0) {
            NSLog(@"BLEProtocol smoke tests failed: %lu", (unsigned long)gFailureCount);
            return 1;
        }
        NSLog(@"BLEProtocol smoke tests passed");
        return 0;
    }
}
