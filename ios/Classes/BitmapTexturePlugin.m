#import "BitmapTexturePlugin.h"
#import "Render.h"

@interface BitmapTexturePlugin ()

@property (nonatomic) NSObject<FlutterTextureRegistry> *textures;
// objc multi-threads
// reference: [https://blog.csdn.net/qq_27740983/article/details/50072985]
@property (nonatomic) NSThread *thread;

@property (atomic) NSMutableDictionary<NSNumber *, Render *> *renders;  // You need [atomic] to make sure it is safe to add in main thread, and run in kid thread.

@end

@implementation BitmapTexturePlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel = [FlutterMethodChannel
      methodChannelWithName:@"bitmap"
      binaryMessenger:[registrar messenger]];
  BitmapTexturePlugin *instance = [[BitmapTexturePlugin alloc] initWithTexture:[registrar textures]];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithTexture:(NSObject<FlutterTextureRegistry> *)textures {
  self = [super init];
  if (self) {
    _textures = textures;
    _thread = nil;  // The thread will not created when the app loaded.
    _renders = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (void)renderLoop {
  @autoreleasepool {  // Avoid memory leak.
    while ([[NSThread currentThread] isCancelled] == NO) {
      CFTimeInterval t1 = CACurrentMediaTime();
      
      for (Render *render in [_renders allValues]) {
        [render doRender];
      }

      CFTimeInterval t2 = CACurrentMediaTime();
      CFTimeInterval wait = 0.016 - (t2 - t1);
      if (wait > 0) {
        [NSThread sleepForTimeInterval:wait];
      }
    }
  }
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([@"it" isEqualToString:call.method]) {  // init thread
    [self createThread];
  }
  else if ([@"dt" isEqualToString:call.method]) {  // dispose thread
    [_thread cancel];
    _thread = nil;
  }
  else if ([@"i" isEqualToString:call.method]) {  // create render and no do render
    [self createThread];
    
    int width  = [call.arguments[@"width"]  intValue];
    int height = [call.arguments[@"height"] intValue];

    NSNumber *textureId = [self createRender:width height:height];
    result(textureId);
  }
  else if ([@"r" isEqualToString:call.method]) {  // render
    [self createThread];
    
    NSNumber *textureId =  call.arguments[@"textureId"];
    NSString *path      =  call.arguments[@"path"];
    int width           = [call.arguments[@"width"]     intValue];
    int height          = [call.arguments[@"height"]    intValue];
    int srcWidth        = [call.arguments[@"srcWidth"]  intValue];
    int srcHeight       = [call.arguments[@"srcHeight"] intValue];
    int fit             = [call.arguments[@"fit"]       intValue];
    NSString *bitmap    =  call.arguments[@"bitmap"];
    bool findCache      = [call.arguments[@"findCache"] boolValue];
        
    if ([textureId intValue] == -1) {
      textureId = [self createRender:width height:height];
    }
    
    Render *render = _renders[textureId];
    [render r:result path:path width:width height:height srcWidth:srcWidth srcHeight:srcHeight fit:fit bitmap:bitmap findCache:findCache];
  }
  else if ([@"dl" isEqualToString:call.method]) {  // dispose list
    NSArray<NSNumber *> *textureIds = call.arguments[@"textureIds"];
    for (NSNumber *textureId in textureIds) {
      Render *render = _renders[textureId];
      [render d];
      [_renders removeObjectForKey:textureId];
      [_textures unregisterTexture:[textureId longValue]];
    }
    result(nil);
  }
}

- (void)createThread {
  if (_thread == nil) {
    _thread = [[NSThread alloc] initWithTarget:self selector:@selector(renderLoop) object:nil];
    [_thread start];
  }
}

- (NSNumber *)createRender:(int)width height:(int)height {
  NSInteger __block textureId = 0;
  Render *render = [[Render alloc] initWithCallback:^() {
    [self.textures textureFrameAvailable:textureId];
  } width:width height:height];
  textureId = (NSInteger) [_textures registerTexture:render];
  [render si:textureId];  // si: set textureId
  _renders[@(textureId)] = render;
  return @(textureId);
}

@end
