#import <Foundation/Foundation.h>
#import "../BLEProtocol/BLEProtocolConstants.h"
#import "../BLEProtocol/BLEProtocolHandler.h"
#import "../BLEProtocol/BLEProtocolMessage.h"

static NSString * const kPeripheralName = @"MacBLE-Demo";
static NSString * const kServiceUUID = @"0000FFF0-0000-1000-8000-00805F9B34FB";
static NSString * const kCharacteristicUUID = @"0000FFF1-0000-1000-8000-00805F9B34FB";
static NSString * const kSessionID = @"test-session";

static NSUInteger gFailureCount = 0;

static void AssertTrue(BOOL condition, NSString *message) {
    if (condition) {
        NSLog(@"PASS %@", message);
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

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"BLEProtocol smoke tests starting");
        TestPairSuccess();
        TestProtectedOperationRequiresToken();
        TestEchoWithToken();
        TestInfoCapabilityDiscovery();
        TestCommandMetadata();
        TestSetEventRuleCommand();
        TestSetEventRuleRejectsInvalidMode();
        TestCommandMissingName();
        if (gFailureCount > 0) {
            NSLog(@"BLEProtocol smoke tests failed: %lu", (unsigned long)gFailureCount);
            return 1;
        }
        NSLog(@"BLEProtocol smoke tests passed");
        return 0;
    }
}
