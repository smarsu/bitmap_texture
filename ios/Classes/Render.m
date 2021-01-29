#import "GLKit/GLKit.h"
#import "OpenGLES/ES2/glext.h"

#import "Render.h"

typedef struct {
    GLKVector3 positionCoord;
    GLKVector2 textureCoord;
} SenceVertex;

@interface Render ()

@property (nonatomic) void (^callback)(void);
@property (nonatomic) int width;
@property (nonatomic) int height;
@property (nonatomic) NSInteger textureId;

@property (nonatomic) CVPixelBufferRef target;
@property (nonatomic) CVOpenGLESTextureCacheRef textureCache;
@property (nonatomic) CVOpenGLESTextureRef texture;

@property (nonatomic) GLuint depthBuffer;
@property (nonatomic) GLuint frameBuffer;
@property (nonatomic) GLuint vertexBuffer;
@property (nonatomic) SenceVertex *vertices;

@property (atomic) NSLock *lock;  // The lock of paths.
@property (atomic) bool do_r;  // Call [r] to set true, call [doRender] to set false
@property (atomic) bool do_init;  // Call [initGL] to set true, and make it atomic to avoid init twice.

@property (nonatomic) EAGLContext *context;
@property (nonatomic) GLuint program;
@property (nonatomic) GLuint vertexShader;
@property (nonatomic) GLuint fragmentShader;

@property (nonatomic) FlutterResult result;
@property (nonatomic) NSString *path;
@property (nonatomic) int srcWidth;
@property (nonatomic) int srcHeight;
@property (nonatomic) int fit;
@property (nonatomic) NSString *bitmap;
@property (nonatomic) bool findCache;

@property (nonatomic) uint8_t *colors;  // The raw rgba data of image.

@end

@implementation Render

- (instancetype)initWithCallback:(void (^)(void))callback width:(int)width height:(int)height {
  self = [super init];
  if (self) {
    _callback = callback;
    _width    = width;
    _height   = height;
    
    _target       = nil;
    _textureCache = nil;
    _texture      = nil;
    
    _vertices = NULL;
    _colors   = NULL;
    
    _lock  = [[NSLock alloc] init];
    
    _do_r    = false;
    _do_init = false;

    _path      = NULL;
    _srcWidth  = 0;
    _srcHeight = 0;
    _fit       = 0;
    _bitmap    = NULL;
    _findCache = false;
  }
  return self;
}

- (void)si:(NSInteger)textureId {
  _textureId = textureId;
}

- (void)r:(FlutterResult)result path:(NSString *)path width:(int)width height:(int)height srcWidth:(int)srcWidth srcHeight:(int)srcHeight fit:(int)fit bitmap:(NSString *)bitmap findCache:(bool)findCache {
  [self.lock lock];
  _result    = result;
  _path      = path;
  _width     = width;
  _height    = height;
  _srcWidth  = srcWidth;
  _srcHeight = srcHeight;
  _fit       = fit;
  _bitmap    = bitmap;
  _findCache = findCache;
  
  _do_r = true;
  [self.lock unlock];
}

- (void)d {
  [self dispose];
}

/// [doRender] will not called at once by two thread, so the [doInit] will be safe to be called once.
- (void)doRender {
  if (!_do_init) {
    _do_init = true;
    
    _colors = malloc(_height * _width * 4);  // To do, reuse the [_colors].
    [self doInit];
    glFinish();
  }
  
  if (_do_r) {
    [_lock lock];
    _do_r = false;  // Only here set the [_do_r] to false.
    FlutterResult result = _result;
    NSString *path       = _path;
    int width            = _width;
    int height           = _height;
    int srcWidth         = _srcWidth;
    int srcHeight        = _srcHeight;
    int fit              = _fit;
    NSString *bitmap     = _bitmap;
    bool findCache       = _findCache;
    [_lock unlock];
    
    [EAGLContext setCurrentContext:_context];

    [self makeBitMap:path width:width height:height srcWidth:srcWidth srcHeight:srcHeight fit:fit bitmap:bitmap findCache:findCache];
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, _width, _height, 0, GL_RGBA, GL_UNSIGNED_BYTE, _colors);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glFlush();
    _callback();
    result(@(_textureId));
  }
}

- (void)doInit {
  _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
  [EAGLContext setCurrentContext:_context];
  [self createProgram];
  
  CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_textureCache);

  CFDictionaryRef empty;
  CFMutableDictionaryRef attrs;
  empty = CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  attrs = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(attrs, kCVPixelBufferIOSurfacePropertiesKey, empty);
  CVPixelBufferCreate(kCFAllocatorDefault, (size_t) _width, (size_t) _height, kCVPixelFormatType_32BGRA, attrs, &_target);
  CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, _target, NULL, GL_TEXTURE_2D, GL_RGBA, (GLsizei) _width, (GLsizei) _height, GL_BGRA, GL_UNSIGNED_BYTE, 0, &_texture);
  
  CFRelease(empty);
  CFRelease(attrs);
  
  glBindTexture(CVOpenGLESTextureGetTarget(_texture), CVOpenGLESTextureGetName(_texture));
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (GLsizei) _width, (GLsizei) _height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
  glGenRenderbuffers(1, &_depthBuffer);
  glBindRenderbuffer(GL_RENDERBUFFER, _depthBuffer);
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, (GLsizei) _width, (GLsizei) _height);
  glGenFramebuffers(1, &_frameBuffer);
  glBindFramebuffer(GL_FRAMEBUFFER, _frameBuffer);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, CVOpenGLESTextureGetName(_texture), 0);
  glFramebufferRenderbuffer(GL_RENDERBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _depthBuffer);
  
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    NSLog(@"Can not glCheckFramebufferStatus");
  }
  
  glViewport(0, 0, (GLsizei) _width, (GLsizei) _height);
  
  glBindTexture(GL_TEXTURE_2D, 0);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glBindTexture(GL_TEXTURE_2D, 0);
  
  glUseProgram(_program);
  
  GLuint positionSlot = (GLuint) glGetAttribLocation(_program, "Position");
  GLuint textureSlot = (GLuint) glGetUniformLocation(_program, "Texture");
  GLuint textureCoordsSlot = (GLuint) glGetAttribLocation(_program, "TextureCoords");

  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, 0);
  glUniform1i(textureSlot, 0);
  
  glGenBuffers(1, &_vertexBuffer);
  glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
  GLsizeiptr bufferSizeBytes = sizeof(SenceVertex) * 4;
  _vertices = malloc(sizeof(SenceVertex) * 4);
  _vertices[0] = (SenceVertex) {{-1,   1, 0}, {0, 1}};
  _vertices[1] = (SenceVertex) {{-1,  -1, 0}, {0, 0}};
  _vertices[2] = (SenceVertex) {{ 1,   1, 0}, {1, 1}};
  _vertices[3] = (SenceVertex) {{ 1,  -1, 0}, {1, 0}};
  glBufferData(GL_ARRAY_BUFFER, bufferSizeBytes, _vertices, GL_STATIC_DRAW);

  glEnableVertexAttribArray(positionSlot);
  glVertexAttribPointer(positionSlot, 3, GL_FLOAT, GL_FALSE, sizeof(SenceVertex), NULL + offsetof(SenceVertex, positionCoord));

  glEnableVertexAttribArray(textureCoordsSlot);
  glVertexAttribPointer(textureCoordsSlot, 2, GL_FLOAT, GL_FALSE, sizeof(SenceVertex), NULL + offsetof(SenceVertex, textureCoord));
}

- (void)createProgram {
  _vertexShader = [self loadShader:GL_VERTEX_SHADER source:@"glsl"];
  _fragmentShader = [self loadShader:GL_FRAGMENT_SHADER source:@"glsl"];
  
  _program = glCreateProgram();
  glAttachShader(_program, _vertexShader);
  glAttachShader(_program, _fragmentShader);
  
  glLinkProgram(_program);
  GLint ok = 0;
  glGetProgramiv(_program, GL_LINK_STATUS, &ok);
}

- (GLuint)loadShader:(GLenum)type source:(NSString *)source {
  NSBundle *bundle = [NSBundle bundleWithPath: [
      [NSBundle bundleForClass:[self class]].resourcePath
                stringByAppendingPathComponent:@"/BitMap.bundle"]];
  NSString *shaderstr = [NSString
    stringWithContentsOfFile:[bundle pathForResource:source ofType:type == GL_VERTEX_SHADER ? @"vsh" : @"fsh"]
    encoding:NSUTF8StringEncoding
    error:NULL];
  
  GLuint shader = glCreateShader(type);
  const char *shaderutf8 = [shaderstr UTF8String];
  int len = (int) [shaderstr length];
  glShaderSource(shader, 1, &shaderutf8, &len);
  
  glCompileShader(shader);
  GLint ok = 0;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
  
  return shader;
}

- (void)makeBitMap:(NSString *)path width:(int)width height:(int)height srcWidth:(int)srcWidth srcHeight:(int)srcHeight fit:(int)fit bitmap:(NSString *)bitmap findCache:(bool)findCache {
  const char *bmp = [bitmap UTF8String];
  
  if (!findCache) {
    size_t size = srcWidth * srcHeight * 4;
    uint8_t *data = malloc(sizeof(uint8_t) * size);

    FILE *fpr = fopen(bmp, "rb");
    fread(data, 1, size, fpr);
    int x = (srcWidth - _width) / 2;
    int y = (srcHeight - _height) / 2;
    for (int i = 0; i < _height; ++i) {
      int start = y * srcWidth * 4 + x * 4 + i * srcWidth * 4;
      memcpy(_colors + i * _width * 4, data + start, sizeof(int8_t) * _width * 4);
    }
    fclose(fpr);
    
    FILE *fpw = fopen(bmp, "wb");
    fwrite(_colors, 1, _width * _height * 4, fpw);
    fclose(fpw);
    
    free(data);
  }
  else {
    int size = _width * _height * 4;
    FILE *fpr = fopen(bmp, "rb");
    fread(_colors, 1, size, fpr);
    fclose(fpr);
  }
}

- (void)dispose {
  [EAGLContext setCurrentContext:_context];
  
  if (_vertices) free(_vertices);
  if (_colors) free(_colors);
  
  glDeleteProgram(_program);
  glDeleteShader(_vertexShader);
  glDeleteShader(_fragmentShader);
  
  glFinish();
  glDeleteBuffers(1, &_vertexBuffer);
  glDeleteRenderbuffers(1, &_depthBuffer);
  glDeleteFramebuffers(1, &_frameBuffer);

  if (_texture) {
    CFRelease(_texture);
  }
  if (_target) {
    CFRelease(_target);
  }
  if (_textureCache) {
    CFRelease(_textureCache);
  }
}

#pragma mark - FlutterTexture

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
  if (_target) {
    CVBufferRetain(_target);
  }
  return _target;
}

@end
