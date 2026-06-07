#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BLEProtocolMessage : NSObject

+ (BOOL)isProtocolEnvelope:(NSDictionary *)dictionary;
+ (nullable NSDictionary *)dictionaryFromData:(NSData *)data error:(NSError * _Nullable * _Nullable)error;
+ (nullable NSData *)dataFromDictionary:(NSDictionary *)dictionary error:(NSError * _Nullable * _Nullable)error;

+ (NSDictionary *)requestWithOperation:(NSString *)operation
                            messageID:(NSString *)messageID
                                 body:(NSDictionary *)body;

+ (NSDictionary *)requestWithOperation:(NSString *)operation
                            messageID:(NSString *)messageID
                                 token:(nullable NSString *)token
                                  body:(NSDictionary *)body;

+ (NSDictionary *)successResponseForOperation:(NSString *)operation
                                    messageID:(NSString *)messageID
                                         body:(NSDictionary *)body;

+ (NSDictionary *)successResponseForOperation:(NSString *)operation
                                    messageID:(NSString *)messageID
                                         token:(nullable NSString *)token
                                          body:(NSDictionary *)body;

+ (NSDictionary *)errorResponseWithMessageID:(nullable NSString *)messageID
                                        code:(NSString *)code
                                     message:(NSString *)message;

+ (NSDictionary *)eventWithType:(NSString *)type
                       sequence:(NSUInteger)sequence
                        session:(nullable NSString *)session
                           body:(NSDictionary *)body;

+ (NSDictionary *)chunkWithStreamID:(NSString *)streamID
                            index:(NSUInteger)index
                            count:(NSUInteger)count
                             data:(NSData *)data;

+ (BOOL)isChunkEnvelope:(NSDictionary *)dictionary;
+ (nullable NSData *)chunkPayloadFromEnvelope:(NSDictionary *)dictionary
                                     streamID:(NSString * _Nullable * _Nullable)streamID
                                        index:(NSUInteger * _Nullable)index
                                        count:(NSUInteger * _Nullable)count;

+ (NSString *)summaryForDictionary:(NSDictionary *)dictionary;
+ (NSString *)capabilitySummaryForInfoBody:(NSDictionary *)body;
+ (nullable NSString *)eventRuleModeFromBody:(NSDictionary *)body;
+ (NSArray<NSString *> *)eventRuleModesFromInfoBody:(NSDictionary *)body;

@end

NS_ASSUME_NONNULL_END
