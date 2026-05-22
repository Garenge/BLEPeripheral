#import "BLEProtocolConstants.h"

NSInteger const BLEProtocolVersion = 1;

NSString * const BLEProtocolKeyVersion = @"v";
NSString * const BLEProtocolKeyOperation = @"op";
NSString * const BLEProtocolKeyMessageID = @"id";
NSString * const BLEProtocolKeyBody = @"body";
NSString * const BLEProtocolKeyOK = @"ok";
NSString * const BLEProtocolKeyError = @"err";

NSString * const BLEProtocolOpPing = @"ping";
NSString * const BLEProtocolOpPong = @"pong";
NSString * const BLEProtocolOpEcho = @"echo";
NSString * const BLEProtocolOpGetInfo = @"getInfo";
NSString * const BLEProtocolOpInfo = @"info";
NSString * const BLEProtocolOpTick = @"tick";
NSString * const BLEProtocolOpError = @"error";

NSString * const BLEProtocolErrorInvalidJSON = @"invalid_json";
NSString * const BLEProtocolErrorInvalidEnvelope = @"invalid_envelope";
NSString * const BLEProtocolErrorUnknownOperation = @"unknown_op";
NSString * const BLEProtocolErrorInvalidBody = @"invalid_body";
