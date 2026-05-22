#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BLEProtocolHandler : NSObject

+ (BOOL)looksLikeProtocolData:(NSData *)data;

+ (nullable NSData *)responseDataForRequestData:(NSData *)requestData
                                 peripheralName:(NSString *)peripheralName
                                    serviceUUID:(NSString *)serviceUUID
                             characteristicUUID:(NSString *)characteristicUUID
                                   logSummaryOut:(NSString * _Nullable * _Nullable)logSummaryOut;

+ (nullable NSData *)tickNotificationDataWithSequence:(NSUInteger)sequence;

@end

NS_ASSUME_NONNULL_END
