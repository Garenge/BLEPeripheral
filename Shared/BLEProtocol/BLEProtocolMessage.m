#import "BLEProtocolMessage.h"
#import "BLEProtocolConstants.h"

@implementation BLEProtocolMessage

+ (BOOL)isProtocolEnvelope:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    id version = dictionary[BLEProtocolKeyVersion];
    id operation = dictionary[BLEProtocolKeyOperation];
    return [version isKindOfClass:[NSNumber class]] && [operation isKindOfClass:[NSString class]];
}

+ (NSDictionary *)dictionaryFromData:(NSData *)data error:(NSError **)error {
    if (data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"BLEProtocol"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty payload."}];
        }
        return nil;
    }

    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"BLEProtocol"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"JSON root must be an object."}];
        }
        return nil;
    }

    return object;
}

+ (NSData *)dataFromDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    return [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:error];
}

+ (NSDictionary *)requestWithOperation:(NSString *)operation
                            messageID:(NSString *)messageID
                                 body:(NSDictionary *)body {
    return [self requestWithOperation:operation messageID:messageID token:nil body:body];
}

+ (NSDictionary *)requestWithOperation:(NSString *)operation
                            messageID:(NSString *)messageID
                                 token:(NSString *)token
                                  body:(NSDictionary *)body {
    NSMutableDictionary *request = [@{
        BLEProtocolKeyVersion: @(BLEProtocolVersion),
        BLEProtocolKeyOperation: operation,
        BLEProtocolKeyMessageID: messageID,
        BLEProtocolKeyBody: body ?: @{},
    } mutableCopy];
    if (token.length > 0) {
        request[BLEProtocolKeyToken] = token;
    }
    return request.copy;
}

+ (NSDictionary *)successResponseForOperation:(NSString *)operation
                                    messageID:(NSString *)messageID
                                         body:(NSDictionary *)body {
    return [self successResponseForOperation:operation messageID:messageID token:nil body:body];
}

+ (NSDictionary *)successResponseForOperation:(NSString *)operation
                                    messageID:(NSString *)messageID
                                         token:(NSString *)token
                                          body:(NSDictionary *)body {
    NSMutableDictionary *response = [@{
        BLEProtocolKeyVersion: @(BLEProtocolVersion),
        BLEProtocolKeyOperation: operation,
        BLEProtocolKeyMessageID: messageID,
        BLEProtocolKeyOK: @YES,
        BLEProtocolKeyBody: body ?: @{},
    } mutableCopy];
    if (token.length > 0) {
        response[BLEProtocolKeyToken] = token;
    }
    return response.copy;
}

+ (NSDictionary *)errorResponseWithMessageID:(NSString *)messageID
                                        code:(NSString *)code
                                     message:(NSString *)message {
    NSMutableDictionary *response = [@{
        BLEProtocolKeyVersion: @(BLEProtocolVersion),
        BLEProtocolKeyOperation: BLEProtocolOpError,
        BLEProtocolKeyOK: @NO,
        BLEProtocolKeyError: @{
            @"code": code,
            @"message": message,
        },
    } mutableCopy];

    if (messageID.length > 0) {
        response[BLEProtocolKeyMessageID] = messageID;
    }

    return response;
}

+ (NSDictionary *)eventWithType:(NSString *)type
                       sequence:(NSUInteger)sequence
                        session:(NSString *)session
                           body:(NSDictionary *)body {
    NSMutableDictionary *eventBody = [@{
        @"type": type ?: @"unknown",
        @"n": @(sequence),
        @"ts": @((NSInteger)[NSDate.date timeIntervalSince1970]),
    } mutableCopy];
    if (session.length > 0) {
        eventBody[@"session"] = session;
    }
    if (body.count > 0) {
        [eventBody addEntriesFromDictionary:body];
    }
    NSString *messageID = [NSString stringWithFormat:@"event-%lu", (unsigned long)sequence];
    return [self successResponseForOperation:BLEProtocolOpEvent messageID:messageID body:eventBody];
}

+ (NSString *)summaryForDictionary:(NSDictionary *)dictionary {
    NSString *operation = dictionary[BLEProtocolKeyOperation];
    id messageID = dictionary[BLEProtocolKeyMessageID];
    NSNumber *ok = dictionary[BLEProtocolKeyOK];
    NSString *token = dictionary[BLEProtocolKeyToken];

    if ([dictionary[BLEProtocolKeyError] isKindOfClass:[NSDictionary class]]) {
        NSDictionary *err = dictionary[BLEProtocolKeyError];
        return [NSString stringWithFormat:@"op=%@ id=%@ token=%@ error=%@ (%@)",
                operation ?: @"?",
                messageID ?: @"-",
                token.length > 0 ? @"yes" : @"no",
                err[@"code"] ?: @"?",
                err[@"message"] ?: @"?"];
    }

    return [NSString stringWithFormat:@"op=%@ id=%@ token=%@ ok=%@",
            operation ?: @"?",
            messageID ?: @"-",
            token.length > 0 ? @"yes" : @"no",
            ok ?: @"-"];
}

@end
