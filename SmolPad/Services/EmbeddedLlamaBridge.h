#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^EmbeddedLlamaChunkHandler)(NSString *text, BOOL isThinking);

@interface EmbeddedLlamaGenerationRequest : NSObject

@property (nonatomic, copy) NSString *systemPrompt;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *history;
@property (nonatomic, copy) NSString *userPrompt;
@property (nonatomic, strong, nullable) UIImage *image;
@property (nonatomic) NSInteger maxTokens;

@end

@interface EmbeddedLlamaBridge : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithModelPath:(NSString *)modelPath
                       mmprojPath:(NSString *)mmprojPath
                  modelIdentifier:(NSString *)modelIdentifier NS_DESIGNATED_INITIALIZER;

- (BOOL)prepare:(NSError * _Nullable * _Nullable)error;
- (BOOL)generate:(EmbeddedLlamaGenerationRequest *)request
         onChunk:(EmbeddedLlamaChunkHandler)onChunk
           error:(NSError * _Nullable * _Nullable)error;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
