#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BLEProtocolHandlerResult : NSObject

@property (nonatomic, strong) NSData *responseData;
@property (nonatomic, copy) NSString *logSummary;
@property (nonatomic, copy, nullable) NSString *sessionToken;
@property (nonatomic, copy, nullable) NSString *commandName;
@property (nonatomic) BOOL pairingSucceeded;
@property (nonatomic) BOOL commandAccepted;
@property (nonatomic) BOOL shouldResetCounters;

@end

@interface BLEProtocolHandler : NSObject

+ (BOOL)looksLikeProtocolData:(NSData *)data;

+ (BLEProtocolHandlerResult *)responseForRequestData:(NSData *)requestData
                                      peripheralName:(NSString *)peripheralName
                                         serviceUUID:(NSString *)serviceUUID
                                  characteristicUUID:(NSString *)characteristicUUID
                                           sessionID:(NSString *)sessionID
                                            pairCode:(NSString *)pairCode
                                        currentToken:(nullable NSString *)currentToken
                                           readCount:(NSUInteger)readCount
                                          writeCount:(NSUInteger)writeCount
                                         notifyCount:(NSUInteger)notifyCount
                                          eventCount:(NSUInteger)eventCount;

+ (nullable NSData *)responseDataForRequestData:(NSData *)requestData
                                 peripheralName:(NSString *)peripheralName
                                    serviceUUID:(NSString *)serviceUUID
                             characteristicUUID:(NSString *)characteristicUUID
                                   logSummaryOut:(NSString * _Nullable * _Nullable)logSummaryOut;

+ (nullable NSData *)tickNotificationDataWithSequence:(NSUInteger)sequence;
+ (nullable NSData *)eventNotificationDataWithType:(NSString *)type
                                          sequence:(NSUInteger)sequence
                                           session:(nullable NSString *)session
                                              body:(NSDictionary *)body;

@end

NS_ASSUME_NONNULL_END
