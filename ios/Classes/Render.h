#import <Flutter/Flutter.h>

@interface Render : NSObject<FlutterTexture>

- (instancetype)initWithCallback:(void (^)(void))callback width:(int)width height:(int)height;

- (void)r:(FlutterResult)result path:(NSString *)path width:(int)width height:(int)height srcWidth:(int)srcWidth srcHeight:(int)srcHeight fit:(int)fit bitmap:(NSString *)bitmap findCache:(bool)findCache;  // set render param

- (void)d;  // dispose

- (void)doRender;  // do render

- (void)si:(NSInteger)textureId;  // si: set textureId

@end
