//
// ZL2VersionNBT.m — 极简 NBT 读写器实现（7.0-UI-13-V）
//
// 实现备注（规格见 .h 头注释）：
//   - 大端序手写游标读取；越界一律置 overflow 失败（不假设数据良构）。
//   - zlib 经 dlsym 解析（DataTransferService.m Task224 同款判例，避免
//     改动链接脚本；libz 随 UnzipKit 加载后符号全局可见）。
//   - 解压窗口位：gzip=15+16（MC 数据文件形态），zlib=15，raw=-15，
//     按魔数自动识别；解压产物上限 32MB（防炸弹）。
//   - 写侧 gzip（deflateInit2 windowBits 15+16），与 MC 写出的
//     servers.dat/level.dat 容器一致。
//   - modified UTF-8 写侧：NUL → C0 80；UTF-16 代理对按各自 3 字节
//     编码（CESU-8，Java DataOutput.writeUTF 同款）。读侧标准 UTF-8，
//     0xC0 0x80 序列（Java NUL）解码失败时替换为 0x00 再解码。
//

#import "ZL2VersionNBT.h"

#include <dlfcn.h>
#include <zlib.h>   // 仅 z_stream 结构与常量；符号运行期 dlsym（见头注释）

NSString * const ZL2VersionNBTErrorDomain = @"ZL2VersionNBT";

static const NSUInteger ZL2V13MaxDecompressedBytes = 32ull * 1024ull * 1024ull;

#pragma mark - zlib（dlsym 判例：DataTransferService.m Task224）

typedef int (*ZL2V13_z_inflateInit2_fn)(z_streamp, int, const char *, int);
typedef int (*ZL2V13_z_inflate_fn)(z_streamp, int);
typedef int (*ZL2V13_z_inflateEnd_fn)(z_streamp);
typedef unsigned long (*ZL2V13_z_inflateBound_fn)(z_streamp, unsigned long);
typedef int (*ZL2V13_z_deflateInit2_fn)(z_streamp, int, int, int, int, int, const char *, int);
typedef int (*ZL2V13_z_deflate_fn)(z_streamp, int);
typedef int (*ZL2V13_z_deflateEnd_fn)(z_streamp);
typedef unsigned long (*ZL2V13_z_deflateBound_fn)(z_streamp, unsigned long);

static ZL2V13_z_inflateInit2_fn ZL2V13_z_inflateInit2_ = NULL;
static ZL2V13_z_inflate_fn      ZL2V13_z_inflate = NULL;
static ZL2V13_z_inflateEnd_fn   ZL2V13_z_inflateEnd = NULL;
static ZL2V13_z_inflateBound_fn ZL2V13_z_inflateBound = NULL;
static ZL2V13_z_deflateInit2_fn ZL2V13_z_deflateInit2_ = NULL;
static ZL2V13_z_deflate_fn      ZL2V13_z_deflate = NULL;
static ZL2V13_z_deflateEnd_fn   ZL2V13_z_deflateEnd = NULL;
static ZL2V13_z_deflateBound_fn ZL2V13_z_deflateBound = NULL;

static void ZL2V13_resolveZlibOnce(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *h = RTLD_DEFAULT;
        ZL2V13_z_inflateInit2_  = (ZL2V13_z_inflateInit2_fn)dlsym(h, "inflateInit2_");
        ZL2V13_z_inflate        = (ZL2V13_z_inflate_fn)dlsym(h, "inflate");
        ZL2V13_z_inflateEnd     = (ZL2V13_z_inflateEnd_fn)dlsym(h, "inflateEnd");
        ZL2V13_z_inflateBound   = (ZL2V13_z_inflateBound_fn)dlsym(h, "inflateBound");
        ZL2V13_z_deflateInit2_  = (ZL2V13_z_deflateInit2_fn)dlsym(h, "deflateInit2_");
        ZL2V13_z_deflate        = (ZL2V13_z_deflate_fn)dlsym(h, "deflate");
        ZL2V13_z_deflateEnd     = (ZL2V13_z_deflateEnd_fn)dlsym(h, "deflateEnd");
        ZL2V13_z_deflateBound   = (ZL2V13_z_deflateBound_fn)dlsym(h, "deflateBound");
        if (!ZL2V13_z_inflate || !ZL2V13_z_inflateInit2_ || !ZL2V13_z_inflateEnd ||
            !ZL2V13_z_deflate || !ZL2V13_z_deflateInit2_ || !ZL2V13_z_deflateEnd) {
            NSLog(@"[ZL2VersionNBT] zlib symbols unavailable via dlsym (libz not loaded?)");
        }
    });
}

#pragma mark - 解压 / 压缩

/// 按指定窗口位全量解压（gzip 31 / zlib 15 / raw -15）
static NSData *ZL2V13_inflateData(NSData *input, int windowBits) {
    if (!ZL2V13_z_inflateInit2_ || !ZL2V13_z_inflate || !ZL2V13_z_inflateEnd || !ZL2V13_z_inflateBound) return nil;
    if (input.length == 0) return nil;

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)(void *)input.bytes;
    stream.avail_in = (uInt)input.length;
    if (ZL2V13_z_inflateInit2_(&stream, windowBits, ZLIB_VERSION, (int)sizeof(z_stream)) != Z_OK) return nil;

    NSMutableData *output = [NSMutableData dataWithCapacity:input.length * 4];
    uint8_t buffer[65536];
    int status = Z_OK;
    BOOL ok = YES;
    while (YES) {
        stream.next_out = buffer;
        stream.avail_out = sizeof(buffer);
        status = ZL2V13_z_inflate(&stream, Z_NO_FLUSH);
        if (stream.total_out > ZL2V13MaxDecompressedBytes) { ok = NO; break; }  // 炸弹守卫
        if (status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR) {
            [output appendBytes:buffer length:(sizeof(buffer) - stream.avail_out)];
            if (status == Z_STREAM_END) break;
            if (status == Z_BUF_ERROR && stream.avail_in == 0) break;  // 输入耗尽
        } else {
            ok = NO;
            break;
        }
    }
    ZL2V13_z_inflateEnd(&stream);
    if (!ok || output.length > ZL2V13MaxDecompressedBytes) return nil;
    return output;
}

static NSData *ZL2V13_gzipCompress(NSData *input) {
    if (!ZL2V13_z_deflateInit2_ || !ZL2V13_z_deflate || !ZL2V13_z_deflateEnd || !ZL2V13_z_deflateBound) return nil;

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)(void *)input.bytes;
    stream.avail_in = (uInt)input.length;
    // windowBits 15+16 = gzip 容器（MC 数据文件同款）
    if (ZL2V13_z_deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8,
                               Z_DEFAULT_STRATEGY, ZLIB_VERSION, (int)sizeof(z_stream)) != Z_OK) return nil;

    uLong bound = ZL2V13_z_deflateBound(&stream, (unsigned long)input.length) + 64;
    NSMutableData *output = [NSMutableData dataWithCapacity:bound];
    uint8_t buffer[65536];
    int status = Z_OK;
    BOOL ok = YES;
    do {
        stream.next_out = buffer;
        stream.avail_out = sizeof(buffer);
        status = ZL2V13_z_deflate(&stream, Z_FINISH);
        [output appendBytes:buffer length:(sizeof(buffer) - stream.avail_out)];
        if (status == Z_STREAM_END) break;
        if (status != Z_OK && status != Z_BUF_ERROR) { ok = NO; break; }
    } while (stream.avail_out == 0);
    ZL2V13_z_deflateEnd(&stream);
    if (!ok) return nil;
    return output;
}

#pragma mark - 读游标

typedef struct {
    const uint8_t *bytes;
    NSUInteger length;
    NSUInteger offset;
    BOOL overflow;
} ZL2V13Reader;

static BOOL ZL2V13_readBytes(ZL2V13Reader *r, void *out, NSUInteger n) {
    if (r->overflow || n > r->length - r->offset) { r->overflow = YES; return NO; }
    memcpy(out, r->bytes + r->offset, n);
    r->offset += n;
    return YES;
}

static uint8_t ZL2V13_readU8(ZL2V13Reader *r) {
    uint8_t v = 0;
    ZL2V13_readBytes(r, &v, 1);
    return v;
}

static uint16_t ZL2V13_readU16(ZL2V13Reader *r) {
    uint8_t b[2] = {0, 0};
    ZL2V13_readBytes(r, b, 2);
    return (uint16_t)(((uint16_t)b[0] << 8) | (uint16_t)b[1]);
}

static int32_t ZL2V13_readI32(ZL2V13Reader *r) {
    uint8_t b[4] = {0, 0, 0, 0};
    ZL2V13_readBytes(r, b, 4);
    return (int32_t)(((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) |
                     ((uint32_t)b[2] << 8) | (uint32_t)b[3]);
}

static int64_t ZL2V13_readI64(ZL2V13Reader *r) {
    uint64_t v = 0;
    uint8_t b[8] = {0};
    ZL2V13_readBytes(r, b, 8);
    for (int i = 0; i < 8; i++) v = (v << 8) | (uint64_t)b[i];
    return (int64_t)v;
}

/// Java modified UTF-8 → NSString（0xC0 0x80 = NUL 特例容错）
static NSString *ZL2V13_readString(ZL2V13Reader *r) {
    uint16_t len = ZL2V13_readU16(r);
    if (r->overflow || len == 0) return @"";
    if (len > r->length - r->offset) { r->overflow = YES; return nil; }
    NSData *raw = [NSData dataWithBytes:(r->bytes + r->offset) length:len];
    r->offset += len;
    NSString *str = [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding];
    if (str) return str;
    // Java NUL（C0 80）→ 标准 UTF-8 非法：替换为 0x00 再解码
    NSMutableData *fixed = [raw mutableCopy];
    const uint8_t *bytes = fixed.bytes;
    uint8_t *mut = (uint8_t *)fixed.mutableBytes;
    for (NSUInteger i = 0; i + 1 < fixed.length; i++) {
        if (bytes[i] == 0xC0 && bytes[i + 1] == 0x80) { mut[i] = 0x00; mut[i + 1] = 0xFF; }  // 0xFF 哨兵跳过
    }
    NSMutableData *clean = [NSMutableData data];
    const uint8_t *cb = fixed.bytes;
    for (NSUInteger i = 0; i < fixed.length; i++) {
        if (cb[i] != 0xFF) [clean appendBytes:&cb[i] length:1];
    }
    return [[NSString alloc] initWithData:clean encoding:NSUTF8StringEncoding];
}

/// 递归读单个标签 payload（不含 name 头）；compound/list 递归展开
static id ZL2V13_readPayload(ZL2V13Reader *r, ZL2NBTTagType type) {
    switch (type) {
        case ZL2NBTTagTypeByte: {
            uint8_t v = ZL2V13_readU8(r);
            return @(v);
        }
        case ZL2NBTTagTypeShort: {
            uint16_t v = ZL2V13_readU16(r);
            return @((int16_t)v);
        }
        case ZL2NBTTagTypeInt: {
            return @(ZL2V13_readI32(r));
        }
        case ZL2NBTTagTypeLong: {
            return @(ZL2V13_readI64(r));
        }
        case ZL2NBTTagTypeFloat: {
            uint32_t v = (uint32_t)ZL2V13_readI32(r);
            float f;
            memcpy(&f, &v, sizeof(f));
            return @(f);
        }
        case ZL2NBTTagTypeDouble: {
            uint64_t v = (uint64_t)ZL2V13_readI64(r);
            double d;
            memcpy(&d, &v, sizeof(d));
            return @(d);
        }
        case ZL2NBTTagTypeByteArray: {
            int32_t n = ZL2V13_readI32(r);
            if (r->overflow || n < 0) { r->overflow = YES; return nil; }
            if ((NSUInteger)n > r->length - r->offset) { r->overflow = YES; return nil; }
            NSData *data = [NSData dataWithBytes:(r->bytes + r->offset) length:(NSUInteger)n];
            r->offset += (NSUInteger)n;
            return data;
        }
        case ZL2NBTTagTypeString: {
            return ZL2V13_readString(r);
        }
        case ZL2NBTTagTypeList: {
            uint8_t elemType = ZL2V13_readU8(r);
            int32_t count = ZL2V13_readI32(r);
            if (r->overflow || count < 0) { r->overflow = YES; return nil; }
            NSMutableArray<ZL2NBTTag *> *items = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
            for (int32_t i = 0; i < count; i++) {
                ZL2NBTTag *item = [[ZL2NBTTag alloc] init];
                item.type = (ZL2NBTTagType)elemType;
                item.value = ZL2V13_readPayload(r, (ZL2NBTTagType)elemType);
                if (r->overflow) return nil;
                [items addObject:item];
            }
            return items;
        }
        case ZL2NBTTagTypeCompound: {
            NSMutableDictionary<NSString *, ZL2NBTTag *> *children = [NSMutableDictionary dictionary];
            while (YES) {
                uint8_t childType = ZL2V13_readU8(r);
                if (r->overflow) return nil;
                if (childType == (uint8_t)ZL2NBTTagTypeEnd) break;
                NSString *childName = ZL2V13_readString(r);
                if (r->overflow || childName == nil) { r->overflow = YES; return nil; }
                id payload = ZL2V13_readPayload(r, (ZL2NBTTagType)childType);
                if (r->overflow || payload == nil) { r->overflow = YES; return nil; }
                ZL2NBTTag *child = [[ZL2NBTTag alloc] init];
                child.type = (ZL2NBTTagType)childType;
                child.name = childName;
                child.value = payload;
                children[childName] = child;
            }
            return children;
        }
        case ZL2NBTTagTypeIntArray:
        case ZL2NBTTagTypeLongArray: {
            int32_t n = ZL2V13_readI32(r);
            if (r->overflow || n < 0) { r->overflow = YES; return nil; }
            NSMutableArray<NSNumber *> *arr = [NSMutableArray arrayWithCapacity:(NSUInteger)n];
            for (int32_t i = 0; i < n; i++) {
                if (type == ZL2NBTTagTypeIntArray) {
                    [arr addObject:@(ZL2V13_readI32(r))];
                } else {
                    [arr addObject:@(ZL2V13_readI64(r))];
                }
                if (r->overflow) return nil;
            }
            return arr;
        }
        case ZL2NBTTagTypeEnd:
        default:
            r->overflow = YES;
            return nil;
    }
}

#pragma mark - 写游标

@interface ZL2V13Writer : NSObject
@property (nonatomic, strong) NSMutableData *data;
@end

@implementation ZL2V13Writer

- (instancetype)init {
    self = [super init];
    if (self) _data = [NSMutableData data];
    return self;
}

- (void)writeU8:(uint8_t)v {
    [self.data appendBytes:&v length:1];
}

- (void)writeU16:(uint16_t)v {
    uint8_t b[2] = { (uint8_t)(v >> 8), (uint8_t)(v & 0xFF) };
    [self.data appendBytes:b length:2];
}

- (void)writeI32:(int32_t)v {
    uint32_t u = (uint32_t)v;
    uint8_t b[4] = { (uint8_t)(u >> 24), (uint8_t)(u >> 16), (uint8_t)(u >> 8), (uint8_t)u };
    [self.data appendBytes:b length:4];
}

- (void)writeI64:(int64_t)v {
    uint64_t u = (uint64_t)v;
    uint8_t b[8];
    for (int i = 7; i >= 0; i--) { b[i] = (uint8_t)(u & 0xFF); u >>= 8; }
    [self.data appendBytes:b length:8];
}

/// Java modified UTF-8（NUL → C0 80；代理对各自 3 字节 = CESU-8）
- (void)writeString:(NSString *)str {
    NSMutableData *encoded = [NSMutableData data];
    NSUInteger len = str.length;
    for (NSUInteger i = 0; i < len; i++) {
        unichar u = [str characterAtIndex:i];
        if (u == 0) {
            const uint8_t nul[2] = { 0xC0, 0x80 };
            [encoded appendBytes:nul length:2];
        } else if (u < 0x80) {
            uint8_t b = (uint8_t)u;
            [encoded appendBytes:&b length:1];
        } else if (u < 0x800) {
            uint8_t b[2] = { (uint8_t)(0xC0 | (u >> 6)), (uint8_t)(0x80 | (u & 0x3F)) };
            [encoded appendBytes:b length:2];
        } else {
            uint8_t b[3] = { (uint8_t)(0xE0 | (u >> 12)), (uint8_t)(0x80 | ((u >> 6) & 0x3F)), (uint8_t)(0x80 | (u & 0x3F)) };
            [encoded appendBytes:b length:3];
        }
    }
    [self writeU16:(uint16_t)encoded.length];
    [self.data appendData:encoded];
}

- (void)writePayloadOfTag:(ZL2NBTTag *)tag {
    switch (tag.type) {
        case ZL2NBTTagTypeByte:      [self writeU8:(uint8_t)[(NSNumber *)tag.value charValue]]; break;
        case ZL2NBTTagTypeShort:     [self writeU16:(uint16_t)[(NSNumber *)tag.value shortValue]]; break;
        case ZL2NBTTagTypeInt:       [self writeI32:[(NSNumber *)tag.value intValue]]; break;
        case ZL2NBTTagTypeLong:      [self writeI64:[(NSNumber *)tag.value longLongValue]]; break;
        case ZL2NBTTagTypeFloat: {
            float f = [(NSNumber *)tag.value floatValue];
            uint32_t bits;
            memcpy(&bits, &f, sizeof(bits));
            [self writeI32:(int32_t)bits];
            break;
        }
        case ZL2NBTTagTypeDouble: {
            double d = [(NSNumber *)tag.value doubleValue];
            uint64_t bits;
            memcpy(&bits, &d, sizeof(bits));
            [self writeI64:(int64_t)bits];
            break;
        }
        case ZL2NBTTagTypeByteArray: {
            NSData *bytes = (NSData *)tag.value;
            [self writeI32:(int32_t)bytes.length];
            [self.data appendData:bytes];
            break;
        }
        case ZL2NBTTagTypeString:
            [self writeString:(NSString *)tag.value];
            break;
        case ZL2NBTTagTypeList: {
            NSArray<ZL2NBTTag *> *items = (NSArray<ZL2NBTTag *> *)tag.value;
            uint8_t elemType = items.count > 0 ? (uint8_t)items.firstObject.type : (uint8_t)ZL2NBTTagTypeEnd;
            [self writeU8:elemType];
            [self writeI32:(int32_t)items.count];
            for (ZL2NBTTag *item in items) [self writePayloadOfTag:item];
            break;
        }
        case ZL2NBTTagTypeCompound: {
            NSDictionary<NSString *, ZL2NBTTag *> *children = (NSDictionary<NSString *, ZL2NBTTag *> *)tag.value;
            for (NSString *key in children) {
                ZL2NBTTag *child = children[key];
                [self writeU8:(uint8_t)child.type];
                [self writeString:key];
                [self writePayloadOfTag:child];
            }
            [self writeU8:(uint8_t)ZL2NBTTagTypeEnd];
            break;
        }
        case ZL2NBTTagTypeIntArray: {
            NSArray<NSNumber *> *arr = (NSArray<NSNumber *> *)tag.value;
            [self writeI32:(int32_t)arr.count];
            for (NSNumber *n in arr) [self writeI32:n.intValue];
            break;
        }
        case ZL2NBTTagTypeLongArray: {
            NSArray<NSNumber *> *arr = (NSArray<NSNumber *> *)tag.value;
            [self writeI32:(int32_t)arr.count];
            for (NSNumber *n in arr) [self writeI64:n.longLongValue];
            break;
        }
        case ZL2NBTTagTypeEnd:
        default:
            break;
    }
}

@end

#pragma mark - ZL2NBTTag

@implementation ZL2NBTTag

- (nullable ZL2NBTTag *)tagForKey:(NSString *)key {
    if (self.type != ZL2NBTTagTypeCompound || key.length == 0) return nil;
    NSDictionary<NSString *, ZL2NBTTag *> *children = (NSDictionary<NSString *, ZL2NBTTag *> *)self.value;
    if (![children isKindOfClass:[NSDictionary class]]) return nil;
    ZL2NBTTag *child = children[key];
    return [child isKindOfClass:[ZL2NBTTag class]] ? child : nil;
}

- (nullable NSString *)stringForKey:(NSString *)key {
    ZL2NBTTag *child = [self tagForKey:key];
    if (!child || child.type != ZL2NBTTagTypeString) return nil;
    return [child.value isKindOfClass:[NSString class]] ? (NSString *)child.value : nil;
}

@end

#pragma mark - ZL2VersionNBT

@implementation ZL2VersionNBT

+ (nullable ZL2NBTTag *)parseCompressedData:(NSData *)data error:(NSError **)error {
    if (error) *error = nil;
    if (data.length == 0) {
        if (error) *error = [NSError errorWithDomain:ZL2VersionNBTErrorDomain code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"empty input"}];
        return nil;
    }
    ZL2V13_resolveZlibOnce();

    // 魔数识别压缩容器：1F 8B = gzip；0x78 = zlib；否则按 raw deflate 兜底
    NSData *payload = nil;
    const uint8_t *head = (const uint8_t *)data.bytes;
    if (data.length >= 2 && head[0] == 0x1F && head[1] == 0x8B) {
        payload = ZL2V13_inflateData(data, 15 + 16);
    } else if (data.length >= 1 && head[0] == 0x78) {
        payload = ZL2V13_inflateData(data, 15);
    }
    if (!payload) payload = ZL2V13_inflateData(data, -15);  // raw 兜底（部分工具写出未包裹形态）
    if (!payload) {
        if (error) *error = [NSError errorWithDomain:ZL2VersionNBTErrorDomain code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"inflate failed"}];
        return nil;
    }

    ZL2V13Reader reader;
    reader.bytes = payload.bytes;
    reader.length = payload.length;
    reader.offset = 0;
    reader.overflow = NO;

    uint8_t rootType = ZL2V13_readU8(&reader);
    if (reader.overflow || rootType != (uint8_t)ZL2NBTTagTypeCompound) {
        if (error) *error = [NSError errorWithDomain:ZL2VersionNBTErrorDomain code:3
                                            userInfo:@{NSLocalizedDescriptionKey: @"root tag is not a compound"}];
        return nil;
    }
    NSString *rootName = ZL2V13_readString(&reader);
    if (reader.overflow || rootName == nil) {
        if (error) *error = [NSError errorWithDomain:ZL2VersionNBTErrorDomain code:4
                                            userInfo:@{NSLocalizedDescriptionKey: @"root name unreadable"}];
        return nil;
    }
    id rootPayload = ZL2V13_readPayload(&reader, ZL2NBTTagTypeCompound);
    if (reader.overflow || ![rootPayload isKindOfClass:[NSMutableDictionary class]]) {
        if (error) *error = [NSError errorWithDomain:ZL2VersionNBTErrorDomain code:5
                                            userInfo:@{NSLocalizedDescriptionKey: @"payload unreadable"}];
        return nil;
    }

    ZL2NBTTag *root = [[ZL2NBTTag alloc] init];
    root.type = ZL2NBTTagTypeCompound;
    root.name = rootName;
    root.value = rootPayload;
    return root;
}

+ (nullable NSData *)writeCompressedRootTag:(ZL2NBTTag *)rootTag error:(NSError **)error {
    if (error) *error = nil;
    if (![rootTag isKindOfClass:[ZL2NBTTag class]] || rootTag.type != ZL2NBTTagTypeCompound) {
        if (error) *error = [NSError errorWithDomain:ZL2VersionNBTErrorDomain code:11
                                            userInfo:@{NSLocalizedDescriptionKey: @"root must be a compound"}];
        return nil;
    }
    ZL2V13_resolveZlibOnce();

    ZL2V13Writer *writer = [[ZL2V13Writer alloc] init];
    // 根标签 = 具名 Compound（name 保留原值；MC 的根名为空串）
    [writer writeU8:(uint8_t)ZL2NBTTagTypeCompound];
    NSString *rootName = rootTag.name;
    [writer writeString:(rootName.length > 0 ? rootName : @"")];
    [writer writePayloadOfTag:rootTag];

    NSData *gzipped = ZL2V13_gzipCompress(writer.data);
    if (!gzipped) {
        if (error) *error = [NSError errorWithDomain:ZL2VersionNBTErrorDomain code:12
                                            userInfo:@{NSLocalizedDescriptionKey: @"gzip compress failed"}];
        return nil;
    }
    return gzipped;
}

@end
