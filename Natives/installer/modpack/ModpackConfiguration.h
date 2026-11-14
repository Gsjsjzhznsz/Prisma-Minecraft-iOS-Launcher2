//
//  ModpackConfiguration.h
//  Amethyst
//
//  Created by iFlow on 2024/11/29.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - ★Task428：整合包格式探测（工作项一 2.2）

/// 按特征文件判定的整合包格式种类（解压前只读 zip 目录，不解包）
typedef NS_ENUM(NSInteger, ModpackFormatKind) {
    ModpackFormatKindUnknown = 0,
    ModpackFormatKindModrinth,     // modrinth.index.json
    ModpackFormatKindCurseForge,   // manifest.json（MCBBS addons 变体由既有服务链细分）
    ModpackFormatKindMultiMC,      // mmc-pack.json（instance.cfg 可选，缺失时包名回退文件名）
    ModpackFormatKindTechnic,      // modpack.cfg（.ini 风格）
    ModpackFormatKindFTB,          // webmanifest.json
    ModpackFormatKindPlainZip,     // 无签名文件，顶层 .minecraft 目录结构兜底
};

@interface ModpackFileInformation : NSObject
@property (nonatomic, strong) NSString *path;
@property (nonatomic, strong) NSString *fileHash;
@property (nonatomic, strong) NSString *downloadURL;
@property (nonatomic, assign) NSUInteger fileSize;

- (instancetype)initWithPath:(NSString *)path fileHash:(NSString *)fileHash downloadURL:(NSString *)downloadURL fileSize:(NSUInteger)fileSize;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (BOOL)validate;
@end

@interface ModpackConfiguration : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *version;
@property (nonatomic, strong) NSString *gameVersion;
@property (nonatomic, strong, nullable) NSString *author;
@property (nonatomic, strong, nullable) NSString *packDescription;
@property (nonatomic, strong) NSArray<ModpackFileInformation *> *files;
@property (nonatomic, strong) NSDictionary *dependencies;

- (instancetype)initWithName:(NSString *)name version:(NSString *)version gameVersion:(NSString *)gameVersion;
- (void)saveToFile:(NSString *)filePath error:(NSError **)error;
- (nullable instancetype)initWithContentsOfFile:(NSString *)filePath error:(NSError **)error;
- (BOOL)validate;

#pragma mark - ★Task428：格式探测前置层 + 新格式归一化（工作项一 2.2）

/// 解压前按特征文件探测格式（判定顺序与 ModpackImportService.parseModpackAtURL
/// 既有顺序保持一致：modrinth.index.json > mmc-pack.json > manifest.json >
/// modpack.cfg > webmanifest.json > 顶层 .minecraft 结构兜底 > 不识别）。
/// 只读 zip 单条目，不解包；任何异常返回 ModpackFormatKindUnknown（不抛错）。
+ (ModpackFormatKind)ame428_probeFormatAtURL:(NSURL *)fileURL;

/// 探测结果 → 既有安装链（ModpackImportService.importModpack:）消费的
/// modpackInfo 字典。归一路径：特征文件 → ModpackConfiguration 中间表示
/// （name/version/gameVersion/dependencies/files）→ 安装链字典。
/// 仅服务新格式（Technic/FTB）；Modrinth/CurseForge/MultiMC/PlainZip 仍走
/// ModpackImportService 既有解析（MultiMC 已具备 components→loader 映射 +
/// instance.cfg 包名 + .minecraft overrides 语义，不重复实现）。
/// 归一失败返回 nil 并通过 error 给出明确文案（不再笼统「无效整合包」）。
+ (nullable NSDictionary *)ame428_modpackInfoForURL:(NSURL *)fileURL
                                               kind:(ModpackFormatKind)kind
                                              error:(NSError **)error;

/// 不识别/损坏整合包的明确错误（供分发层在既有解析失败时替换笼统文案）
+ (NSError *)ame428_unrecognizedFormatError:(nullable NSError *)originalError;

@end

NS_ASSUME_NONNULL_END