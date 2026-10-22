//
// ZL2VersionNBT.h — 极简 NBT 读写器（7.0-UI-13-V：版本详情域专用）
//
// 定位：供 ZL2 版本详情子页读 servers.dat（服务器列表）与 level.dat
//   （存档名/上次游玩）。ZL2 安卓端 ServerListScreen 的口径是「改动即
//   全量回写」——本文件除只读解析外提供最小写入端（Compound/List/String
//   为主，全部 12 类标签可往返），供 servers.dat 编辑后重建。
//
// 范围（诚实边界）：
//   - 读：全部标签类型（1-12）解析为内存树；gzip/zlib/raw 三种压缩头
//     自动识别（MC 的 servers.dat / level.dat 是 gzip 包裹的 NBT）。
//   - 写：全部标签类型序列化；压缩固定 gzip（与 MC 生成格式一致）。
//   - 字符串编码：读侧标准 UTF-8（0xC0 0x80 失败时替换为 NUL 再解码）；
//     写侧 Java modified UTF-8（NUL → C0 80，增补平面字符按 UTF-16 代理
//     对各自 3 字节编码 = CESU-8，与 Java DataOutput.writeUTF 完全一致）。
//   - 解压上限 32MB（防解压炸弹；servers.dat/level.dat 实际 <1MB）。
//   - 不做：NBT 校验和、region/ankle 格式、写入时的子树选择性编辑——
//     调用方全量重建子树后回写（ZL2「改动即全量回写」同语义）。
//
// zlib 链接说明：本仓 libz 未直接链入（DataTransferService.m Task224
//   判例），符号经 dlsym(RTLD_DEFAULT) 解析（libz 随 UnzipKit 加载）；
//   zlib.h 仅提供 z_stream/常量，不产生链接期符号依赖。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// NBT 标签类型（Java Named Binary Tag 规范 1-12）
typedef NS_ENUM(NSInteger, ZL2NBTTagType) {
    ZL2NBTTagTypeEnd        = 0,
    ZL2NBTTagTypeByte       = 1,
    ZL2NBTTagTypeShort      = 2,
    ZL2NBTTagTypeInt        = 3,
    ZL2NBTTagTypeLong       = 4,
    ZL2NBTTagTypeFloat      = 5,
    ZL2NBTTagTypeDouble     = 6,
    ZL2NBTTagTypeByteArray  = 7,
    ZL2NBTTagTypeString     = 8,
    ZL2NBTTagTypeList       = 9,
    ZL2NBTTagTypeCompound   = 10,
    ZL2NBTTagTypeIntArray   = 11,
    ZL2NBTTagTypeLongArray  = 12,
};

/// NBT 标签内存节点。
/// value 按类型承载：
///   Byte/Short/Int/Long/Float/Double → NSNumber
///   ByteArray → NSData；IntArray/LongArray → NSArray<NSNumber *>
///   String → NSString
///   List → NSArray<ZL2NBTTag *>（条目无 name）
///   Compound → NSMutableDictionary<NSString *, ZL2NBTTag *>
@interface ZL2NBTTag : NSObject

@property (nonatomic, assign) ZL2NBTTagType type;
/// Compound 子项/具名标签的名字；List 条目为 nil
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, strong, nullable) id value;

/// Compound 取子标签（非 Compound 或无此键返回 nil）
- (nullable ZL2NBTTag *)tagForKey:(NSString *)key;
/// Compound 取 String 子标签快捷读
- (nullable NSString *)stringForKey:(NSString *)key;

@end

/// 解析/写出错误域；userInfo[NSLocalizedDescriptionKey] 可直显
FOUNDATION_EXPORT NSString * const ZL2VersionNBTErrorDomain;

@interface ZL2VersionNBT : NSObject

/// 解析 gzip/zlib/raw 包裹的 NBT 数据（servers.dat / level.dat 直读）。
/// 返回根 Compound 标签（name 保留）；失败返回 nil 并填充 error。
+ (nullable ZL2NBTTag *)parseCompressedData:(NSData *)data
                                      error:(NSError **)error;

/// 全量回写：根必须为 Compound；输出 gzip 包裹的标准 NBT
///（MC servers.dat 同格式；「改动即全量回写」ZL2 同语义）。
+ (nullable NSData *)writeCompressedRootTag:(ZL2NBTTag *)rootTag
                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
