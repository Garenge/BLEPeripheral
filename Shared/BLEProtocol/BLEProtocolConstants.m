#import "BLEProtocolConstants.h"

NSInteger const BLEProtocolVersion = 1;

NSString * const BLEProtocolKeyVersion = @"v";
NSString * const BLEProtocolKeyOperation = @"op";
NSString * const BLEProtocolKeyMessageID = @"id";
NSString * const BLEProtocolKeyBody = @"body";
NSString * const BLEProtocolKeyOK = @"ok";
NSString * const BLEProtocolKeyError = @"err";
NSString * const BLEProtocolKeyToken = @"token";

NSString * const BLEProtocolOpPair = @"pair";
NSString * const BLEProtocolOpPaired = @"paired";
NSString * const BLEProtocolOpPing = @"ping";
NSString * const BLEProtocolOpPong = @"pong";
NSString * const BLEProtocolOpEcho = @"echo";
NSString * const BLEProtocolOpGetInfo = @"getInfo";
NSString * const BLEProtocolOpInfo = @"info";
NSString * const BLEProtocolOpTelemetry = @"telemetry";
NSString * const BLEProtocolOpCommand = @"command";
NSString * const BLEProtocolOpCommandResult = @"commandResult";
NSString * const BLEProtocolOpEvent = @"event";
NSString * const BLEProtocolOpTick = @"tick";
NSString * const BLEProtocolOpError = @"error";

NSString * const BLEProtocolErrorInvalidJSON = @"invalid_json";
NSString * const BLEProtocolErrorInvalidEnvelope = @"invalid_envelope";
NSString * const BLEProtocolErrorUnknownOperation = @"unknown_op";
NSString * const BLEProtocolErrorInvalidBody = @"invalid_body";
NSString * const BLEProtocolErrorUnauthorized = @"unauthorized";
NSString * const BLEProtocolErrorPairingFailed = @"pairing_failed";

NSString * const BLEProtocolDefaultPairCode = @"135790";
