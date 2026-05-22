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
    return @{
        BLEProtocolKeyVersion: @(BLEProtocolVersion),
        BLEProtocolKeyOperation: operation,
        BLEProtocolKeyMessageID: messageID,
        BLEProtocolKeyBody: body ?: @{},
    };
}

+ (NSDictionary *)successResponseForOperation:(NSString *)operation
                                    messageID:(NSString *)messageID
                                         body:(NSDictionary *)body {
    return @{
        BLEProtocolKeyVersion: @(BLEProtocolVersion),
        BLEProtocolKeyOperation: operation,
        BLEProtocolKeyMessageID: messageID,
        BLEProtocolKeyOK: @YES,
        BLEProtocolKeyBody: body ?: @{},
    };
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

+ (NSString *)summaryForDictionary:(NSDictionary *)dictionary {
    NSString *operation = dictionary[BLEProtocolKeyOperation];
    id messageID = dictionary[BLEProtocolKeyMessageID];
    NSNumber *ok = dictionary[BLEProtocolKeyOK];

    if ([dictionary[BLEProtocolKeyError] isKindOfClass:[NSDictionary class]]) {
        NSDictionary *err = dictionary[BLEProtocolKeyError];
        return [NSString stringWithFormat:@"op=%@ id=%@ error=%@ (%@)",
                operation ?: @"?",
                messageID ?: @"-",
                err[@"code"] ?: @"?",
                err[@"message"] ?: @"?"];
    }

    return [NSString stringWithFormat:@"op=%@ id=%@ ok=%@",
            operation ?: @"?",
            messageID ?: @"-",
            ok ?: @"-"];
}

@end
