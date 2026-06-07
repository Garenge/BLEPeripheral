#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSInteger const BLEProtocolVersion;

FOUNDATION_EXPORT NSString * const BLEProtocolKeyVersion;
FOUNDATION_EXPORT NSString * const BLEProtocolKeyOperation;
FOUNDATION_EXPORT NSString * const BLEProtocolKeyMessageID;
FOUNDATION_EXPORT NSString * const BLEProtocolKeyBody;
FOUNDATION_EXPORT NSString * const BLEProtocolKeyOK;
FOUNDATION_EXPORT NSString * const BLEProtocolKeyError;
FOUNDATION_EXPORT NSString * const BLEProtocolKeyToken;

FOUNDATION_EXPORT NSString * const BLEProtocolOpPair;
FOUNDATION_EXPORT NSString * const BLEProtocolOpPaired;
FOUNDATION_EXPORT NSString * const BLEProtocolOpPing;
FOUNDATION_EXPORT NSString * const BLEProtocolOpPong;
FOUNDATION_EXPORT NSString * const BLEProtocolOpEcho;
FOUNDATION_EXPORT NSString * const BLEProtocolOpGetInfo;
FOUNDATION_EXPORT NSString * const BLEProtocolOpInfo;
FOUNDATION_EXPORT NSString * const BLEProtocolOpTelemetry;
FOUNDATION_EXPORT NSString * const BLEProtocolOpCommand;
FOUNDATION_EXPORT NSString * const BLEProtocolOpCommandResult;
FOUNDATION_EXPORT NSString * const BLEProtocolOpEvent;
FOUNDATION_EXPORT NSString * const BLEProtocolOpTick;
FOUNDATION_EXPORT NSString * const BLEProtocolOpError;

FOUNDATION_EXPORT NSString * const BLEProtocolErrorInvalidJSON;
FOUNDATION_EXPORT NSString * const BLEProtocolErrorInvalidEnvelope;
FOUNDATION_EXPORT NSString * const BLEProtocolErrorUnknownOperation;
FOUNDATION_EXPORT NSString * const BLEProtocolErrorInvalidBody;
FOUNDATION_EXPORT NSString * const BLEProtocolErrorUnauthorized;
FOUNDATION_EXPORT NSString * const BLEProtocolErrorPairingFailed;

FOUNDATION_EXPORT NSString * const BLEProtocolDefaultPairCode;

NS_ASSUME_NONNULL_END
