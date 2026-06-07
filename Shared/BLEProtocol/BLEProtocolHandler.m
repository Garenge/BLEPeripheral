#import "BLEProtocolHandler.h"
#import "BLEProtocolMessage.h"
#import "BLEProtocolConstants.h"

@implementation BLEProtocolHandlerResult
@end

@implementation BLEProtocolHandler

+ (BOOL)looksLikeProtocolData:(NSData *)data {
    NSError *error = nil;
    NSDictionary *dictionary = [BLEProtocolMessage dictionaryFromData:data error:&error];
    if (!dictionary) {
        return NO;
    }
    return [BLEProtocolMessage isProtocolEnvelope:dictionary];
}

+ (BLEProtocolHandlerResult *)responseForRequestData:(NSData *)requestData
                                      peripheralName:(NSString *)peripheralName
                                         serviceUUID:(NSString *)serviceUUID
                                  characteristicUUID:(NSString *)characteristicUUID
                                           sessionID:(NSString *)sessionID
                                            pairCode:(NSString *)pairCode
                                        currentToken:(NSString *)currentToken
                                           readCount:(NSUInteger)readCount
                                          writeCount:(NSUInteger)writeCount
                                         notifyCount:(NSUInteger)notifyCount
                                          eventCount:(NSUInteger)eventCount {
    BLEProtocolHandlerResult *result = [[BLEProtocolHandlerResult alloc] init];
    NSError *parseError = nil;
    NSDictionary *request = [BLEProtocolMessage dictionaryFromData:requestData error:&parseError];
    if (!request) {
        result.responseData = [self encodedErrorWithMessageID:nil
                                                         code:BLEProtocolErrorInvalidJSON
                                                      message:parseError.localizedDescription ?: @"Invalid JSON."];
        result.logSummary = @"protocol invalid_json";
        return result;
    }

    if (![BLEProtocolMessage isProtocolEnvelope:request]) {
        result.responseData = [self encodedErrorWithMessageID:request[BLEProtocolKeyMessageID]
                                                         code:BLEProtocolErrorInvalidEnvelope
                                                      message:@"Request must include numeric v and string op."];
        result.logSummary = @"protocol invalid_envelope";
        return result;
    }

    NSNumber *version = request[BLEProtocolKeyVersion];
    if (version.integerValue != BLEProtocolVersion) {
        result.responseData = [self encodedErrorWithMessageID:request[BLEProtocolKeyMessageID]
                                                         code:BLEProtocolErrorInvalidEnvelope
                                                      message:[NSString stringWithFormat:@"Unsupported protocol version %@.", version]];
        result.logSummary = @"protocol unsupported_version";
        return result;
    }

    NSString *operation = request[BLEProtocolKeyOperation];
    NSString *messageID = [request[BLEProtocolKeyMessageID] isKindOfClass:[NSString class]] ? request[BLEProtocolKeyMessageID] : @"0";
    if (messageID.length == 0) {
        messageID = @"0";
    }

    NSDictionary *body = [request[BLEProtocolKeyBody] isKindOfClass:[NSDictionary class]] ? request[BLEProtocolKeyBody] : @{};
    NSDictionary *response = nil;
    NSString *responseToken = nil;

    if ([operation isEqualToString:BLEProtocolOpPair]) {
        response = [self pairResponseForBody:body
                                   messageID:messageID
                                   sessionID:sessionID
                                    pairCode:pairCode
                                responseToken:&responseToken];
        result.pairingSucceeded = responseToken.length > 0;
        result.sessionToken = responseToken;
    } else if ([self operationRequiresToken:operation] &&
               ![self request:request hasToken:currentToken]) {
        response = [BLEProtocolMessage errorResponseWithMessageID:messageID
                                                             code:BLEProtocolErrorUnauthorized
                                                          message:@"Pair first, then include the returned token."];
    } else if ([operation isEqualToString:BLEProtocolOpPing]) {
        response = [BLEProtocolMessage successResponseForOperation:BLEProtocolOpPong
                                                         messageID:messageID
                                                             token:currentToken
                                                              body:@{
            @"ts": @((NSInteger)[NSDate.date timeIntervalSince1970]),
            @"platform": @"macOS",
            @"session": sessionID ?: @"",
        }];
    } else if ([operation isEqualToString:BLEProtocolOpEcho]) {
        response = [self echoResponseForBody:body messageID:messageID token:currentToken];
    } else if ([operation isEqualToString:BLEProtocolOpGetInfo]) {
        response = [BLEProtocolMessage successResponseForOperation:BLEProtocolOpInfo
                                                         messageID:messageID
                                                             token:currentToken
                                                              body:@{
            @"name": peripheralName ?: @"",
            @"serviceUUID": serviceUUID ?: @"",
            @"characteristicUUID": characteristicUUID ?: @"",
            @"protocolVersion": @(BLEProtocolVersion),
            @"pairing": @"pair-code",
            @"session": sessionID ?: @"",
            @"requiresToken": @YES,
        }];
    } else if ([operation isEqualToString:BLEProtocolOpTelemetry]) {
        response = [BLEProtocolMessage successResponseForOperation:BLEProtocolOpTelemetry
                                                         messageID:messageID
                                                             token:currentToken
                                                              body:@{
            @"session": sessionID ?: @"",
            @"reads": @(readCount),
            @"writes": @(writeCount),
            @"notifies": @(notifyCount),
            @"events": @(eventCount),
            @"uptimeHint": @"session scoped",
            @"ts": @((NSInteger)[NSDate.date timeIntervalSince1970]),
        }];
    } else if ([operation isEqualToString:BLEProtocolOpCommand]) {
        response = [self commandResponseForBody:body
                                      messageID:messageID
                                          token:currentToken
                                      sessionID:sessionID
                                      eventCount:eventCount];
    } else {
        response = [BLEProtocolMessage errorResponseWithMessageID:messageID
                                                             code:BLEProtocolErrorUnknownOperation
                                                          message:[NSString stringWithFormat:@"Unknown op: %@", operation ?: @"<nil>"]];
    }

    result.logSummary = [BLEProtocolMessage summaryForDictionary:response];
    NSError *encodeError = nil;
    result.responseData = [BLEProtocolMessage dataFromDictionary:response error:&encodeError] ?: NSData.data;
    return result;
}

+ (NSData *)responseDataForRequestData:(NSData *)requestData
                        peripheralName:(NSString *)peripheralName
                           serviceUUID:(NSString *)serviceUUID
                    characteristicUUID:(NSString *)characteristicUUID
                         logSummaryOut:(NSString **)logSummaryOut {
    BLEProtocolHandlerResult *result = [self responseForRequestData:requestData
                                                     peripheralName:peripheralName
                                                        serviceUUID:serviceUUID
                                                 characteristicUUID:characteristicUUID
                                                          sessionID:@"legacy"
                                                           pairCode:BLEProtocolDefaultPairCode
                                                       currentToken:nil
                                                          readCount:0
                                                         writeCount:0
                                                        notifyCount:0
                                                         eventCount:0];
    if (logSummaryOut) {
        *logSummaryOut = result.logSummary;
    }
    return result.responseData;
}

+ (NSData *)tickNotificationDataWithSequence:(NSUInteger)sequence {
    NSString *messageID = [NSString stringWithFormat:@"tick-%lu", (unsigned long)sequence];
    NSDictionary *payload = [BLEProtocolMessage successResponseForOperation:BLEProtocolOpTick
                                                                  messageID:messageID
                                                                       body:@{
        @"n": @(sequence),
        @"ts": @((NSInteger)[NSDate.date timeIntervalSince1970]),
    }];
    NSError *error = nil;
    NSData *data = [BLEProtocolMessage dataFromDictionary:payload error:&error];
    return data;
}

+ (NSData *)eventNotificationDataWithType:(NSString *)type
                                 sequence:(NSUInteger)sequence
                                  session:(NSString *)session
                                     body:(NSDictionary *)body {
    NSDictionary *payload = [BLEProtocolMessage eventWithType:type sequence:sequence session:session body:body ?: @{}];
    NSError *error = nil;
    return [BLEProtocolMessage dataFromDictionary:payload error:&error];
}

+ (NSDictionary *)pairResponseForBody:(NSDictionary *)body
                             messageID:(NSString *)messageID
                             sessionID:(NSString *)sessionID
                              pairCode:(NSString *)pairCode
                          responseToken:(NSString **)responseToken {
    NSString *code = [body[@"code"] isKindOfClass:[NSString class]] ? body[@"code"] : @"";
    if (![code isEqualToString:pairCode ?: BLEProtocolDefaultPairCode]) {
        return [BLEProtocolMessage errorResponseWithMessageID:messageID
                                                         code:BLEProtocolErrorPairingFailed
                                                      message:@"Pair code mismatch."];
    }

    NSString *token = [self tokenForSessionID:sessionID];
    if (responseToken) {
        *responseToken = token;
    }
    return [BLEProtocolMessage successResponseForOperation:BLEProtocolOpPaired
                                                 messageID:messageID
                                                     token:token
                                                      body:@{
        @"session": sessionID ?: @"",
        @"token": token,
        @"expires": @"when BLE app restarts or session is replaced",
    }];
}

+ (NSDictionary *)echoResponseForBody:(NSDictionary *)body
                             messageID:(NSString *)messageID
                                 token:(NSString *)token {
    NSString *text = [body[@"text"] isKindOfClass:[NSString class]] ? body[@"text"] : nil;
    if (text.length == 0) {
        return [BLEProtocolMessage errorResponseWithMessageID:messageID
                                                         code:BLEProtocolErrorInvalidBody
                                                      message:@"echo requires body.text string."];
    }
    return [BLEProtocolMessage successResponseForOperation:BLEProtocolOpEcho
                                                 messageID:messageID
                                                     token:token
                                                      body:@{ @"text": text }];
}

+ (NSDictionary *)commandResponseForBody:(NSDictionary *)body
                                messageID:(NSString *)messageID
                                    token:(NSString *)token
                                sessionID:(NSString *)sessionID
                                eventCount:(NSUInteger)eventCount {
    NSString *name = [body[@"name"] isKindOfClass:[NSString class]] ? body[@"name"] : nil;
    if (name.length == 0) {
        return [BLEProtocolMessage errorResponseWithMessageID:messageID
                                                         code:BLEProtocolErrorInvalidBody
                                                      message:@"command requires body.name string."];
    }

    NSArray<NSString *> *acceptedCommands = @[ @"identify", @"sample", @"resetCounters" ];
    BOOL accepted = [acceptedCommands containsObject:name];
    return [BLEProtocolMessage successResponseForOperation:BLEProtocolOpCommandResult
                                                 messageID:messageID
                                                     token:token
                                                      body:@{
        @"name": name,
        @"accepted": @(accepted),
        @"session": sessionID ?: @"",
        @"queuedEvent": @(eventCount + 1),
        @"message": accepted ? @"Command accepted by demo peripheral." : @"Unknown demo command; logged only.",
    }];
}

+ (BOOL)operationRequiresToken:(NSString *)operation {
    NSSet<NSString *> *openOperations = [NSSet setWithObjects:
        BLEProtocolOpPair,
        BLEProtocolOpPing,
        BLEProtocolOpGetInfo,
        nil
    ];
    return ![openOperations containsObject:operation ?: @""];
}

+ (BOOL)request:(NSDictionary *)request hasToken:(NSString *)token {
    if (token.length == 0) {
        return NO;
    }
    NSString *requestToken = [request[BLEProtocolKeyToken] isKindOfClass:[NSString class]] ? request[BLEProtocolKeyToken] : nil;
    if (requestToken.length == 0 &&
        [request[BLEProtocolKeyBody] isKindOfClass:[NSDictionary class]]) {
        requestToken = request[BLEProtocolKeyBody][BLEProtocolKeyToken];
    }
    return [requestToken isEqualToString:token];
}

+ (NSString *)tokenForSessionID:(NSString *)sessionID {
    NSString *seed = [NSString stringWithFormat:@"%@|%@|%ld",
                      sessionID ?: @"session",
                      BLEProtocolDefaultPairCode,
                      (long)BLEProtocolVersion];
    NSUInteger hash = seed.hash;
    return [NSString stringWithFormat:@"tok-%08lx", (unsigned long)hash];
}

+ (NSData *)encodedErrorWithMessageID:(NSString *)messageID code:(NSString *)code message:(NSString *)message {
    NSDictionary *response = [BLEProtocolMessage errorResponseWithMessageID:messageID code:code message:message];
    NSError *error = nil;
    NSData *data = [BLEProtocolMessage dataFromDictionary:response error:&error];
    return data ?: [NSData data];
}

@end
