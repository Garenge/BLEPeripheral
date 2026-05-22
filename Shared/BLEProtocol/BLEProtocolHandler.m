#import "BLEProtocolHandler.h"
#import "BLEProtocolMessage.h"
#import "BLEProtocolConstants.h"

@implementation BLEProtocolHandler

+ (BOOL)looksLikeProtocolData:(NSData *)data {
    NSError *error = nil;
    NSDictionary *dictionary = [BLEProtocolMessage dictionaryFromData:data error:&error];
    if (!dictionary) {
        return NO;
    }
    return [BLEProtocolMessage isProtocolEnvelope:dictionary];
}

+ (NSData *)responseDataForRequestData:(NSData *)requestData
                        peripheralName:(NSString *)peripheralName
                           serviceUUID:(NSString *)serviceUUID
                    characteristicUUID:(NSString *)characteristicUUID
                         logSummaryOut:(NSString **)logSummaryOut {
    NSError *parseError = nil;
    NSDictionary *request = [BLEProtocolMessage dictionaryFromData:requestData error:&parseError];
    if (!request) {
        NSData *data = [self encodedErrorWithMessageID:nil
                                                    code:BLEProtocolErrorInvalidJSON
                                                 message:parseError.localizedDescription ?: @"Invalid JSON."];
        if (logSummaryOut) {
            *logSummaryOut = @"protocol invalid_json";
        }
        return data;
    }

    if (![BLEProtocolMessage isProtocolEnvelope:request]) {
        NSData *data = [self encodedErrorWithMessageID:request[BLEProtocolKeyMessageID]
                                                    code:BLEProtocolErrorInvalidEnvelope
                                                 message:@"Request must include numeric v and string op."];
        if (logSummaryOut) {
            *logSummaryOut = @"protocol invalid_envelope";
        }
        return data;
    }

    NSNumber *version = request[BLEProtocolKeyVersion];
    if (version.integerValue != BLEProtocolVersion) {
        NSData *data = [self encodedErrorWithMessageID:request[BLEProtocolKeyMessageID]
                                                    code:BLEProtocolErrorInvalidEnvelope
                                                 message:[NSString stringWithFormat:@"Unsupported protocol version %@.", version]];
        if (logSummaryOut) {
            *logSummaryOut = @"protocol unsupported_version";
        }
        return data;
    }

    NSString *operation = request[BLEProtocolKeyOperation];
    NSString *messageID = request[BLEProtocolKeyMessageID];
    if (![messageID isKindOfClass:[NSString class]] || messageID.length == 0) {
        messageID = @"0";
    }

    NSDictionary *body = [request[BLEProtocolKeyBody] isKindOfClass:[NSDictionary class]] ? request[BLEProtocolKeyBody] : @{};

    NSDictionary *response = nil;
    if ([operation isEqualToString:BLEProtocolOpPing]) {
        response = [BLEProtocolMessage successResponseForOperation:BLEProtocolOpPong
                                                         messageID:messageID
                                                              body:@{
            @"ts": @((NSInteger)[NSDate.date timeIntervalSince1970]),
            @"platform": @"macOS",
        }];
    } else if ([operation isEqualToString:BLEProtocolOpEcho]) {
        NSString *text = body[@"text"];
        if (![text isKindOfClass:[NSString class]] || text.length == 0) {
            response = [BLEProtocolMessage errorResponseWithMessageID:messageID
                                                                   code:BLEProtocolErrorInvalidBody
                                                                message:@"echo requires body.text string."];
        } else {
            response = [BLEProtocolMessage successResponseForOperation:BLEProtocolOpEcho
                                                               messageID:messageID
                                                                    body:@{ @"text": text }];
        }
    } else if ([operation isEqualToString:BLEProtocolOpGetInfo]) {
        response = [BLEProtocolMessage successResponseForOperation:BLEProtocolOpInfo
                                                         messageID:messageID
                                                              body:@{
            @"name": peripheralName ?: @"",
            @"serviceUUID": serviceUUID ?: @"",
            @"characteristicUUID": characteristicUUID ?: @"",
            @"protocolVersion": @(BLEProtocolVersion),
        }];
    } else {
        response = [BLEProtocolMessage errorResponseWithMessageID:messageID
                                                             code:BLEProtocolErrorUnknownOperation
                                                          message:[NSString stringWithFormat:@"Unknown op: %@", operation ?: @"<nil>"]];
    }

    if (logSummaryOut) {
        *logSummaryOut = [BLEProtocolMessage summaryForDictionary:response];
    }

    NSError *encodeError = nil;
    return [BLEProtocolMessage dataFromDictionary:response error:&encodeError];
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

+ (NSData *)encodedErrorWithMessageID:(NSString *)messageID code:(NSString *)code message:(NSString *)message {
    NSDictionary *response = [BLEProtocolMessage errorResponseWithMessageID:messageID code:code message:message];
    NSError *error = nil;
    NSData *data = [BLEProtocolMessage dataFromDictionary:response error:&error];
    return data ?: [NSData data];
}

@end
