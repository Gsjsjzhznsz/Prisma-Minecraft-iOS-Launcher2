//
// ZL2VersionPages.m — ZL2 版本详情八子页实现（7.0-UI-13-V）
//
// 页面 ↔ ZL2 映射与能力口径（全部子页枚举走容器解析链产物的 ameV13_gameDir）：
//
//  ① 概览  VersionOverViewScreen：信息卡（同容器头）+ FlowRow 管理按钮组
//          （outlined：radiusS 描边 outlineVariant 1pt / fontLabelLarge /
//          padding 12×8）。重命名 = PLProfiles 注册表键换名（Task162
//          actionDone 链 1:1：删旧键建新键 + selected 同步 + save +
//          SelectedProfileChanged；游戏目录实体不做 rename——旧链同口径，
//          versions/<id> 以 lastVersionId 为键且可能被多实例引用）；编辑
//          摘要写 profile[@"versionSummary"]（ZL2 versions_overview_edit_
//          version_summary 对应字段，空值删键）；删除版本 = 旧 VC
//          deleteProfile: 全链 1:1（至少保留一个实例守卫 + 二次确认 +
//          注册表删除 + 选中回退 + Task255 实体目录连带删除引用计数守卫 +
//          @"ReloadProfileList"）；打开游戏目录 = UIDocumentPicker
//          （目录 Open 模式，iOS14 能力上限内的「呈现该目录」等价物）。
//  ② 模组  ModsManagerScreen：mods/ 仅文件；行卡 48pt 图标占位 + 文件名 +
//          大小 + ZL2M3Switch（禁用=追加 .disabled 后缀 / 启用=剥后缀，
//          ModService.toggleEnableForMod 同语义；目标同名预检 Task217）+
//          删除（M3Dialog 确认）；顶部导入（多选 zip/jar 复制进 mods/）+
//          计数徽章；空态卡。
//  ③ 存档  SavesManagerScreen：saves/ 仅目录；行 42pt icon.png（降采样
//          NSCache）+ 存档名（level.dat LevelName 优先）+ 上次游玩
//          （LastPlayed ms；解析失败显示文件名不炸）；删除/重命名；导入
//          zip = UnzipKit 真解压（WorldService.m extractWorldZipAt: 同款
//          链路：顶层目录检测 + extractFilesTo + level.dat 校验日志）。
//          ★ 任务预案「zip 原样落盘提示手动解压」未采用：本仓已随包链接
//          UnzipKit（WorldService/ModService/DataTransferService 在用），
//          具备真解压能力，按 ZL2 语义 1:1 落地；UZK 失败路径兜底
//          「导入失败」弹窗（诚实降级点：不掩盖失败，不做半截落盘）。
//  ④ 资源包 ResourcePackManageScreen：resourcepacks/ 目录+zip；行=名称+
//          大小+删除+重命名；导入 zip；空态卡。
//  ⑤ 光影  ShadersManagerScreen：shaderpacks/ 仅 .zip；同④简化。
//  ⑥ 截图  ScreenshotsManagerScreen：screenshots/ 仅 .png；3 列网格
//          （flow layout）；cell = 缩略图（NSCache+降采样）+ 底部黑 60%
//          遮罩文件名白字（任务规格钦定对比色，非令牌豁免点）；点开全屏
//          查看器（黑底 + 滚动缩放 + 完成钮，同上豁免）。
//  ⑦ 服务器 ServerListScreen：servers.dat（gzip+NBT，ZL2VersionNBT 只读
//          解析 ServerName/Ip——实际键 name/ip）；行=名称+IP+删除/编辑；
//          加号添加；改动即全量回写（ZL2 同语义）：保留解析出的原始
//          Compound（icon 等未触碰标签原样保留），重建 servers List 后
//          ZL2VersionNBT 全量写出。诚实边界：写侧 modified UTF-8 与 Java
//          DataOutput.writeUTF 一致；servers.dat_old 不做轮转。
//  ⑧ 配置  VersionConfigScreen：实例级设置 M3 化——内存滑条
//          （profile[@"allocatedMemory"]，上限 = 0.8×物理内存经
//          ame173_safeHeapCeilingMB()+512 Jetsam 钳制，utils.h 公共符号）、
//          JVM 参数行（profile[@"javaArgs"]，空值删键 = 全局回退）、
//          JVM 预设（profile[@"jvm_preset"] 四档 + 跟随全局删键，Task256
//          键族单一事实源 ame256_effectiveJvmPreset 消费侧）、渲染器覆写
//          RowList（profile[@"renderer"]，真键 getRendererKeys/Names）、
//          服务器 IP（PLProfiles serverIpForProfile:/setServerIp:forProfile:
//          现成 API）；底部「完整实例设置」push 旧 ProfileSettings
//          ViewController（长尾兜底）。
//
// 通用契约：枚举后台队列 / UI 主线程；NSFileManager +
// stringByAppendingPathComponent；颜色/字体/圆角全 ZL2Theme；SF1.x 级
// 符号 + 兜底；中文文案优先既有 localize 键（已审计四表齐备），无键文案
// 按域口径硬编码（UI 写入点走属性点语法，i18n 审计口径内）。
//

#import "ZL2VersionPages.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
#import "ZL2VersionNBT.h"
#import "ModLoaderIconHelper.h"      // 7.0-UI-13-r1：加载器识别（详情头图标口径）
#import "ModpackExportService.h"     // 7.0-UI-13-r1：版本 id 反解（MC 版本口径）
#import "ModService.h"                 // ★ Task343：模组页数据层（scan/toggle/delete/metadata/隔离口径）
#import "ModUpdateService.h"          // ★ Task343：检查更新全流程（双源限流）
#import "PLDownloadClient.h"          // ★ Task343：更新下载（镜像候选 + SHA1 校验）
#import "PLMirrorCenter.h"
#import "ZL2DownloadViewController.h" // ★ Task343：空态「去下载」模组轨直达
#import <CommonCrypto/CommonDigest.h> // ★ Task343：流式 SHA1（Modrinth 反查依赖）
#import "ZL2VersionDetailViewController.h"   // +ameV13_resolvedGameDirForProfileName:（gameDir 重解析兜底）
#import "PLProfiles.h"
#import "ProfileSettingsViewController.h"    // 「完整实例设置」长尾入口（旧链 1:1）
#import "LauncherPreferences.h"              // getRendererKeys/getRendererNames
#import "utils.h"                            // localize() / ame173_safeHeapCeilingMB()
#import "external/UnzipKit/UZKArchive.h"     // 存档 zip 解压（WorldService.m 同款链路）
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>

#pragma mark - 常量与小工具

static const CGFloat ZL2V13CardPadding = 14.0;
static const CGFloat ZL2V13CardSpacing = 12.0;
static const CGFloat ZL2V13ContentMaxWidth = 720.0;

static UIImage *ZL2V13SystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    if (!image) image = [UIImage systemImageNamed:@"circle"];
    return image;
}

/// NSByteCountFormatter 计忆档口径（CleanupViewController 同款 countStyle）
static NSString *ZL2V13ByteCount(unsigned long long bytes) {
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes
                                          countStyle:NSByteCountFormatterCountStyleMemory];
}

/// 错误文案兜底（localize 未知错误；免去括号内省略中项三元式——
/// CleanupViewController.m L120 记录的 ObjC 方括号内 `?:` 编译雷区判例）
static NSString *ZL2V13ErrorText(NSError *err) {
    if (err.localizedDescription.length > 0) return err.localizedDescription;
    return localize(@"resman.common.unknown_error", nil);
}

/// CGImageSource 降采样缩略图（kCGImageSourceThumbnailMaxPixelSize）
static UIImage *ZL2V13ThumbnailAtPath(NSString *path, CGFloat maxPixel) {
    if (path.length == 0) return nil;
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!src) return nil;
    CGFloat scale = [UIScreen mainScreen].scale;
    NSDictionary *opts = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(maxPixel * scale),
    };
    CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(src);
    if (!cg) return nil;
    UIImage *image = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return image;
}

#pragma mark - FlowRow（换行按钮组，任务规格 outlined 组容器）

/// 极简流式换行容器：layoutSubviews 内按 systemLayoutSizeFitting 逐个排布、
/// 越界换行；行数×行高回灌高度约束（M3 FlowRow 等价物）。子视图由容器
/// frame 直排（autoresizing 口径），外层高度经 999 优先级约束驱动 stack。
@interface ZL2V13FlowRow : UIView
@property (nonatomic, assign) CGFloat itemSpacing;
@property (nonatomic, assign) CGFloat lineSpacing;
@property (nonatomic, strong) NSLayoutConstraint *ameV13_heightConstraint;
@end

@implementation ZL2V13FlowRow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _itemSpacing = 8.0;
        _lineSpacing = 8.0;
        _ameV13_heightConstraint = [self.heightAnchor constraintEqualToConstant:36.0];
        _ameV13_heightConstraint.priority = 999;
        _ameV13_heightConstraint.active = YES;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat maxWidth = self.bounds.size.width;
    if (maxWidth <= 0) return;
    CGFloat x = 0;
    CGFloat y = 0;
    CGFloat lineHeight = 0;
    for (UIView *item in self.subviews) {
        if (item.hidden) continue;
        // 容器 frame 直排：子视图交还 autoresizing（outlined 钮无自带约束）
        item.translatesAutoresizingMaskIntoConstraints = YES;
        CGSize fit = [item systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
        CGFloat w = ceil(fit.width);
        CGFloat h = ceil(fit.height);
        if (x > 0 && x + w > maxWidth) {
            x = 0;
            y += lineHeight + self.lineSpacing;
            lineHeight = 0;
        }
        item.frame = CGRectMake(x, y, w, h);
        x += w + self.itemSpacing;
        lineHeight = MAX(lineHeight, h);
    }
    CGFloat total = y + lineHeight;
    if (total > 0 && self.ameV13_heightConstraint.constant != total) {
        self.ameV13_heightConstraint.constant = total;
    }
}

@end

#pragma mark - 截图网格 Cell 与查看器（⑥ 专用）

@interface ZL2V13ScreenshotCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UIView *captionOverlay;
@property (nonatomic, strong) UILabel *nameLabel;
@end

@implementation ZL2V13ScreenshotCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return self;
    _thumbView = [[UIImageView alloc] init];
    _thumbView.contentMode = UIViewContentModeScaleAspectFill;
    _thumbView.clipsToBounds = YES;
    _thumbView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_thumbView];

    // 任务规格：底部黑 60% 遮罩 + 文件名白字（媒体查看对比色，规格钦定）
    _captionOverlay = [[UIView alloc] init];
    _captionOverlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    _captionOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_captionOverlay];

    _nameLabel = [[UILabel alloc] init];
    _nameLabel.font = [ZL2Theme fontLabelMedium];
    _nameLabel.textColor = [UIColor whiteColor];
    _nameLabel.numberOfLines = 1;
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_captionOverlay addSubview:_nameLabel];

    self.contentView.layer.cornerRadius = [ZL2Theme radiusM];
    self.contentView.layer.masksToBounds = YES;
    self.contentView.backgroundColor = [ZL2Theme surfaceVariant];

    [NSLayoutConstraint activateConstraints:@[
        [_thumbView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [_thumbView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [_thumbView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [_thumbView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [_captionOverlay.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [_captionOverlay.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [_captionOverlay.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [_captionOverlay.heightAnchor constraintEqualToConstant:22],
        [_nameLabel.leadingAnchor constraintEqualToAnchor:_captionOverlay.leadingAnchor constant:6],
        [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_captionOverlay.trailingAnchor constant:-6],
        [_nameLabel.centerYAnchor constraintEqualToAnchor:_captionOverlay.centerYAnchor],
    ]];
    return self;
}

@end

/// 全屏查看器：黑底 + 滚动缩放 + 完成钮（任务规格钦定形态）
@interface ZL2V13ImageViewer : UIViewController
@property (nonatomic, copy) NSString *ameV13_imagePath;
@end

@interface ZL2V13ImageViewer () <UIScrollViewDelegate>
@end

@implementation ZL2V13ImageViewer

- (void)viewDidLoad {
    [super viewDidLoad];
    // 黑底/白字 = 媒体查看对比色（任务规格钦定；其余页面仍全令牌）
    self.view.backgroundColor = [UIColor blackColor];

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.minimumZoomScale = 1.0;
    scrollView.maximumZoomScale = 4.0;
    scrollView.delegate = self;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    [self.view addSubview:scrollView];

    UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:self.ameV13_imagePath]];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.userInteractionEnabled = YES;
    [scrollView addSubview:imageView];
    UIButton *doneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    doneButton.titleLabel.font = [ZL2Theme fontLabelLarge];
    [doneButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    NSString *doneTitle = localize(@"resman.common.done", nil);
    [doneButton setTitle:doneTitle forState:UIControlStateNormal];
    doneButton.translatesAutoresizingMaskIntoConstraints = NO;
    [doneButton addTarget:self action:@selector(ameV13_close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:doneButton];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [imageView.centerXAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.centerXAnchor],
        [imageView.centerYAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.centerYAnchor],
        [imageView.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor],
        [imageView.heightAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.heightAnchor],
        [doneButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [doneButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
    ]];
}

- (void)ameV13_close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (nullable UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    for (UIView *sub in scrollView.subviews) {
        if ([sub isKindOfClass:[UIImageView class]]) return sub;
    }
    return nil;
}

@end

#pragma mark - 基类

@interface ZL2VersionPageBase ()
@property (nonatomic, copy, readwrite) NSString *ameV13_profileName;
@property (nonatomic, copy, readwrite) NSString *ameV13_gameDir;
@end

@implementation ZL2VersionPageBase

- (instancetype)initWithProfileName:(NSString *)profileName gameDir:(NSString *)gameDir {
    self = [super init];
    if (!self) return self;
    _ameV13_profileName = [profileName copy];
    _ameV13_gameDir = [gameDir copy];
    self.title = profileName;
    return self;
}

- (void)ameV13_updateProfileName:(NSString *)newName {
    if (![newName isKindOfClass:[NSString class]] || newName.length == 0) return;
    _ameV13_profileName = [newName copy];
    self.title = newName;
}

- (void)ameV13_reloadContent {
    // 子类覆写
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self ameV13_reloadContent];
}

/// 当前实例的活字典（PLProfiles.current 每次现取，随重命名/外部刷新同步）
- (NSMutableDictionary *)ameV13_profileDict {
    NSMutableDictionary *profile = PLProfiles.current.profiles[self.ameV13_profileName];
    if (![profile isKindOfClass:[NSMutableDictionary class]]) return nil;
    return profile;
}

/// 写实例键（nil 值 = 删键；写后 save；Task256 profile 层单写口径）
- (void)ameV13_writeProfileKey:(NSString *)key value:(nullable id)value {
    NSMutableDictionary *profile = [self ameV13_profileDict];
    if (!profile) return;
    if (value == nil) {
        [profile removeObjectForKey:key];
    } else {
        profile[key] = value;
    }
    [PLProfiles.current save];
}

/// 旧 VC showAlert 同款（i18n_str_388 标题 + i18n_str_44 确定钮）
- (void)ameV13_showAlertMessage:(NSString *)message {
    NSString *titleText = localize(@"i18n_str_388", nil);
    NSString *okText = localize(@"i18n_str_44", nil);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:titleText
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:okText style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// 删除确认（M3Dialog；destructive 确认钮）
- (void)ameV13_confirmDeleteTitle:(NSString *)title
                             body:(NSString *)body
                        onConfirm:(void (^)(void))onConfirm {
    NSString *confirmText = localize(@"resman.common.confirm_delete", nil);
    NSString *deleteText = localize(@"resman.common.delete", nil);
    [ZL2M3Dialog showTitle:title
                      body:body
              confirmTitle:deleteText
                destructive:YES
                 onConfirm:onConfirm
                   onCancel:nil];
}

#pragma mark - 通用构件

/// 页面骨架：scrollView + 竖排内容列（999 等式宽度收敛，ZL2Versions 同款）。
/// 返回内容列（调用方继续 addArrangedSubview）；工具条由调用方自建首行。
- (UIStackView *)ameV13_installContentSkeleton {
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.backgroundColor = [UIColor clearColor];
    scrollView.alwaysBounceVertical = YES;
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.alignment = UIStackViewAlignmentFill;
    contentStack.spacing = ZL2V13CardSpacing;
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:contentStack];

    UILayoutGuide *contentLG = scrollView.contentLayoutGuide;
    UILayoutGuide *frameLG = scrollView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [contentStack.topAnchor constraintEqualToAnchor:contentLG.topAnchor constant:4],
        [contentLG.bottomAnchor constraintGreaterThanOrEqualToAnchor:contentStack.bottomAnchor constant:24],
        [contentStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:contentLG.leadingAnchor constant:0],
        [contentLG.trailingAnchor constraintGreaterThanOrEqualToAnchor:contentStack.trailingAnchor constant:0],
        [contentStack.centerXAnchor constraintEqualToAnchor:frameLG.centerXAnchor],
        [contentStack.widthAnchor constraintLessThanOrEqualToConstant:ZL2V13ContentMaxWidth],
    ]];
    NSLayoutConstraint *fillWidth = [contentStack.widthAnchor constraintEqualToAnchor:frameLG.widthAnchor];
    fillWidth.priority = 999;
    fillWidth.active = YES;
    return contentStack;
}

/// 页头行：页名（titleMedium）+ 弹性空隙 + 右侧附件（计数徽章/图标钮）
- (UIStackView *)ameV13_pageHeaderRowWithTitle:(NSString *)title
                                     trailing:(NSArray<UIView *> *)trailing {
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [ZL2Theme fontTitleMedium];
    titleLabel.textColor = [ZL2Theme onSurface];
    titleLabel.numberOfLines = 1;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *spacer = [[UIView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:249 forAxis:UILayoutConstraintAxisHorizontal];
    [spacer setContentCompressionResistancePriority:249 forAxis:UILayoutConstraintAxisHorizontal];

    NSMutableArray *items = [NSMutableArray arrayWithObject:titleLabel];
    [items addObject:spacer];
    for (UIView *v in trailing) [items addObject:v];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:items];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    return row;
}

/// 卡片行容器：surfaceContainer/radiusM，内横排 + padding 14（ZL2Versions 卡同款）
- (UIStackView *)ameV13_rowCardWithViews:(NSArray<UIView *> *)views alignment:(UIStackViewAlignment)alignment {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:views];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = alignment;
    row.spacing = ZL2V13CardSpacing;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [ZL2Theme surfaceContainer];
    card.layer.cornerRadius = [ZL2Theme radiusM];
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:ZL2V13CardPadding],
        [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-ZL2V13CardPadding],
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:ZL2V13CardPadding],
        [row.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-ZL2V13CardPadding],
    ]];

    // 外壳再包一层竖排，让卡片吃满内容列宽（行内 trailing 由内容撑）
    UIStackView *wrap = [[UIStackView alloc] initWithArrangedSubviews:@[card]];
    wrap.axis = UILayoutConstraintAxisVertical;
    wrap.alignment = UIStackViewAlignmentFill;
    wrap.translatesAutoresizingMaskIntoConstraints = NO;
    return wrap;
}

/// 图标占位盒（模组 48 / 存档 42 / 列表图标通用）：surfaceVariant radiusM + 模板符号
- (UIView *)ameV13_iconBoxWithSymbol:(NSString *)symbol fallback:(NSString *)fallback size:(CGFloat)size iconSize:(CGFloat)iconSize {
    UIView *box = [[UIView alloc] init];
    box.backgroundColor = [ZL2Theme surfaceVariant];
    box.layer.cornerRadius = [ZL2Theme radiusM];
    box.layer.masksToBounds = YES;
    box.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[ZL2V13SystemImage(symbol, fallback) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    icon.tintColor = [ZL2Theme onSurfaceVariant];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[
        [box.widthAnchor constraintEqualToConstant:size],
        [box.heightAnchor constraintEqualToConstant:size],
        [icon.centerXAnchor constraintEqualToAnchor:box.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:iconSize],
        [icon.heightAnchor constraintEqualToConstant:iconSize],
    ]];
    return box;
}

/// 图标钮工厂（ZL2Versions iconButtonWithImageName 块载荷同款）
- (UIControl *)ameV13_iconButtonWithImageName:(NSString *)name
                                     fallback:(NSString *)fallback
                                         size:(CGFloat)size
                                accessibility:(NSString *)a11y
                                       action:(void (^)(void))action {
    UIControl *button = [[UIControl alloc] init];
    button.backgroundColor = [UIColor clearColor];
    button.layer.cornerRadius = [ZL2Theme radiusS];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.isAccessibilityElement = YES;
    button.accessibilityTraits = UIAccessibilityTraitButton;
    button.accessibilityLabel = a11y;

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[ZL2V13SystemImage(name, fallback) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    iconView.tintColor = [ZL2Theme onSurfaceVariant];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.userInteractionEnabled = NO;
    [button addSubview:iconView];

    CGFloat iconSize = (size >= 40) ? 20 : 18;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:size],
        [button.heightAnchor constraintEqualToConstant:size],
        [iconView.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:iconSize],
        [iconView.heightAnchor constraintEqualToConstant:iconSize],
    ]];

    button.userInteractionEnabled = YES;
    [button addTarget:self action:@selector(ameV13_dispatchTap:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(button, @selector(ameV13_dispatchTap:), action, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return button;
}

- (void)ameV13_dispatchTap:(UIControl *)sender {
    void (^action)(void) = objc_getAssociatedObject(sender, _cmd);
    if (action) action();
}

/// outlined 按钮（任务规格：radiusS 描边 outlineVariant 1pt / fontLabelLarge /
/// 内容 padding 12×8；destructive = error 色描边与字）
- (UIButton *)ameV13_outlinedButtonWithTitle:(NSString *)title destructive:(BOOL)destructive {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.titleLabel.font = [ZL2Theme fontLabelLarge];
    UIColor *tint = destructive ? [ZL2Theme error] : [ZL2Theme onSurface];
    [button setTitleColor:tint forState:UIControlStateNormal];
    [button setTitle:title forState:UIControlStateNormal];
    button.contentEdgeInsets = UIEdgeInsetsMake(8, 12, 8, 12);
    button.layer.cornerRadius = [ZL2Theme radiusS];
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = (destructive ? [ZL2Theme error] : [ZL2Theme outlineVariant]).CGColor;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.isAccessibilityElement = YES;
    button.accessibilityLabel = title;
    return button;
}

/// 空态卡（archivebox 形制参数化：68pt 符号 + 文案，居中 240pt 高）
- (UIView *)ameV13_emptyStateWithSymbol:(NSString *)symbol fallback:(NSString *)fallback text:(NSString *)text {
    UIView *wrap = [[UIView alloc] init];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[ZL2V13SystemImage(symbol, fallback) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    iconView.tintColor = [ZL2Theme onSurfaceVariant];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [ZL2Theme fontBodyMedium];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[iconView, label]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [wrap.heightAnchor constraintGreaterThanOrEqualToConstant:200],
        [stack.centerXAnchor constraintEqualToAnchor:wrap.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:wrap.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:56],
        [iconView.heightAnchor constraintEqualToConstant:56],
    ]];
    return wrap;
}

/// 双列文本栈（主文 titleMedium / 次文 labelMedium onSurfaceVariant）
- (UIStackView *)ameV13_textStackWithTitle:(NSString *)title detail:(NSString *)detail {
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [ZL2Theme fontTitleMedium];
    titleLabel.textColor = [ZL2Theme onSurface];
    titleLabel.numberOfLines = 1;
    titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *detailLabel = [[UILabel alloc] init];
    detailLabel.text = detail;
    detailLabel.font = [ZL2Theme fontLabelMedium];
    detailLabel.textColor = [ZL2Theme onSurfaceVariant];
    detailLabel.numberOfLines = 1;
    detailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    detailLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, detailLabel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentLeading;
    stack.spacing = 2;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setContentHuggingPriority:249 forAxis:UILayoutConstraintAxisHorizontal];
    [stack setContentCompressionResistancePriority:249 forAxis:UILayoutConstraintAxisHorizontal];
    return stack;
}

/// 弹性空隙（行尾推按钮用）
- (UIView *)ameV13_spacer {
    UIView *spacer = [[UIView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:249 forAxis:UILayoutConstraintAxisHorizontal];
    [spacer setContentCompressionResistancePriority:249 forAxis:UILayoutConstraintAxisHorizontal];
    return spacer;
}

/// 内容列重建（移除全部旧卡）
- (void)ameV13_clearStack:(UIStackView *)stack {
    for (UIView *sub in [stack.arrangedSubviews copy]) {
        [stack removeArrangedSubview:sub];
        [sub removeFromSuperview];
    }
}

/// 目录枚举（仅文件 / 仅目录），按名排序（NSFileManager 常规口径）
- (NSArray<NSDictionary *> *)ameV13_enumerateDirectory:(NSString *)dir filesOnly:(BOOL)filesOnly extensions:(nullable NSArray<NSString *> *)extensions {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    NSArray<NSString *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *entry in entries) {
        if ([entry hasPrefix:@"."]) continue;
        NSString *full = [dir stringByAppendingPathComponent:entry];
        BOOL isDir = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:full isDirectory:&isDir]) continue;
        if (filesOnly && isDir) continue;
        if (!filesOnly && !isDir) continue;
        if (extensions.count > 0) {
            BOOL match = NO;
            for (NSString *ext in extensions) {
                if ([entry.lowercaseString hasSuffix:ext.lowercaseString]) { match = YES; break; }
            }
            if (!match) continue;
        }
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:full error:nil];
        unsigned long long size = [attrs fileSize];
        NSDate *modified = [attrs fileModificationDate];
        if (!modified) modified = [NSDate date];
        [result addObject:@{ @"name": entry, @"path": full, @"isDir": @(isDir), @"size": @(size), @"modified": modified }];
    }
    return result;
}

@end

#pragma mark - ① 概览

@interface ZL2VersionOverviewPage ()
@property (nonatomic, strong) UIStackView *ameV13_contentStack;
@property (nonatomic, strong) UIView *ameV13_iconBox;
@property (nonatomic, strong) UIImageView *ameV13_iconView;
@property (nonatomic, strong) UILabel *ameV13_nameLabel;
@property (nonatomic, strong) UILabel *ameV13_descLabel;
@property (nonatomic, strong) UILabel *ameV13_tagLabel;
@end

@implementation ZL2VersionOverviewPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    _ameV13_contentStack = [self ameV13_installContentSkeleton];

    // —— 版本信息卡（同容器头视觉）——
    _ameV13_iconBox = [[UIView alloc] init];
    _ameV13_iconBox.layer.cornerRadius = [ZL2Theme radiusS];
    _ameV13_iconBox.layer.masksToBounds = YES;
    _ameV13_iconBox.translatesAutoresizingMaskIntoConstraints = NO;

    _ameV13_iconView = [[UIImageView alloc] init];
    _ameV13_iconView.contentMode = UIViewContentModeScaleAspectFit;
    _ameV13_iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_iconBox addSubview:_ameV13_iconView];

    _ameV13_nameLabel = [[UILabel alloc] init];
    _ameV13_nameLabel.font = [ZL2Theme fontTitleMedium];
    _ameV13_nameLabel.textColor = [ZL2Theme onSurface];
    _ameV13_nameLabel.numberOfLines = 1;
    _ameV13_nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _ameV13_nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _ameV13_descLabel = [[UILabel alloc] init];
    _ameV13_descLabel.font = [ZL2Theme fontBodyMedium];
    _ameV13_descLabel.textColor = [ZL2Theme onSurfaceVariant];
    _ameV13_descLabel.numberOfLines = 2;
    _ameV13_descLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _ameV13_descLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _ameV13_tagLabel = [[UILabel alloc] init];
    _ameV13_tagLabel.font = [ZL2Theme fontLabelMedium];
    _ameV13_tagLabel.textColor = [ZL2Theme onSurfaceVariant];
    _ameV13_tagLabel.alpha = 0.7;
    _ameV13_tagLabel.numberOfLines = 1;
    _ameV13_tagLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_ameV13_nameLabel, _ameV13_descLabel, _ameV13_tagLabel]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.alignment = UIStackViewAlignmentLeading;
    textStack.spacing = 2;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *infoCard = [[UIView alloc] init];
    infoCard.backgroundColor = [ZL2Theme surfaceContainer];
    infoCard.layer.cornerRadius = [ZL2Theme radiusM];
    infoCard.layer.masksToBounds = YES;
    infoCard.translatesAutoresizingMaskIntoConstraints = NO;
    [infoCard addSubview:_ameV13_iconBox];
    [infoCard addSubview:textStack];
    [NSLayoutConstraint activateConstraints:@[
        [_ameV13_iconBox.leadingAnchor constraintEqualToAnchor:infoCard.leadingAnchor constant:14],
        [_ameV13_iconBox.centerYAnchor constraintEqualToAnchor:infoCard.centerYAnchor],
        [_ameV13_iconBox.widthAnchor constraintEqualToConstant:34],
        [_ameV13_iconBox.heightAnchor constraintEqualToConstant:34],
        [_ameV13_iconView.centerXAnchor constraintEqualToAnchor:_ameV13_iconBox.centerXAnchor],
        [_ameV13_iconView.centerYAnchor constraintEqualToAnchor:_ameV13_iconBox.centerYAnchor],
        [_ameV13_iconView.widthAnchor constraintEqualToConstant:26],
        [_ameV13_iconView.heightAnchor constraintEqualToConstant:26],
        [textStack.leadingAnchor constraintEqualToAnchor:_ameV13_iconBox.trailingAnchor constant:12],
        [textStack.topAnchor constraintEqualToAnchor:infoCard.topAnchor constant:12],
        [textStack.bottomAnchor constraintEqualToAnchor:infoCard.bottomAnchor constant:-12],
        [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:infoCard.trailingAnchor constant:-14],
    ]];
    UIStackView *infoWrap = [[UIStackView alloc] initWithArrangedSubviews:@[infoCard]];
    infoWrap.axis = UILayoutConstraintAxisVertical;
    infoWrap.alignment = UIStackViewAlignmentFill;
    infoWrap.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_contentStack addArrangedSubview:infoWrap];

    // —— 管理按钮组（FlowRow 换行；ZL2 VersionOverViewScreen 管理区同语义）——
    NSString *renameTitle = @"重命名";
    NSString *summaryTitle = @"编辑摘要";
    NSString *openDirTitle = @"打开游戏目录";
    NSString *deleteTitle = @"删除版本";
    UIButton *renameButton = [self ameV13_outlinedButtonWithTitle:renameTitle destructive:NO];
    UIButton *summaryButton = [self ameV13_outlinedButtonWithTitle:summaryTitle destructive:NO];
    UIButton *openDirButton = [self ameV13_outlinedButtonWithTitle:openDirTitle destructive:NO];
    UIButton *deleteButton = [self ameV13_outlinedButtonWithTitle:deleteTitle destructive:YES];
    [renameButton addTarget:self action:@selector(ameV13_actionRename) forControlEvents:UIControlEventTouchUpInside];
    [summaryButton addTarget:self action:@selector(ameV13_actionEditSummary) forControlEvents:UIControlEventTouchUpInside];
    [openDirButton addTarget:self action:@selector(ameV13_actionOpenGameDir) forControlEvents:UIControlEventTouchUpInside];
    [deleteButton addTarget:self action:@selector(ameV13_actionDeleteVersion) forControlEvents:UIControlEventTouchUpInside];

    ZL2V13FlowRow *flowRow = [[ZL2V13FlowRow alloc] init];
    flowRow.translatesAutoresizingMaskIntoConstraints = NO;
    for (UIButton *button in @[renameButton, summaryButton, openDirButton, deleteButton]) {
        [flowRow addSubview:button];
    }
    [_ameV13_contentStack addArrangedSubview:flowRow];

    [self ameV13_refreshInfoCard];
}

- (void)ameV13_reloadContent {
    [self ameV13_refreshInfoCard];
}

- (void)ameV13_refreshInfoCard {
    NSMutableDictionary *profile = [self ameV13_profileDict];
    NSString *versionId = nil;
    NSString *summary = nil;
    id lastPlayedRaw = nil;
    if (profile) {
        versionId = [profile[@"lastVersionId"] isKindOfClass:[NSString class]] ? (NSString *)profile[@"lastVersionId"] : nil;
        summary = [profile[@"versionSummary"] isKindOfClass:[NSString class]] ? (NSString *)profile[@"versionSummary"] : nil;
        lastPlayedRaw = profile[@"lastPlayed"];
    }

    NSString *loader = versionId.length > 0 ? [ModLoaderIconHelper detectLoaderFromVersionId:versionId] : nil;
    NSDictionary *parsed = versionId.length > 0 ? [ModpackExportService parseVersionId:versionId] : @{};
    NSString *mcVersion = [parsed[@"minecraft"] isKindOfClass:[NSString class]] ? (NSString *)parsed[@"minecraft"] : versionId;

    self.ameV13_nameLabel.text = self.ameV13_profileName;
    if (summary.length > 0) {
        self.ameV13_descLabel.text = summary;
    } else if ([lastPlayedRaw isKindOfClass:[NSNumber class]] && [(NSNumber *)lastPlayedRaw doubleValue] > 0) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[(NSNumber *)lastPlayedRaw doubleValue]];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale currentLocale];
        fmt.doesRelativeDateFormatting = YES;
        fmt.dateStyle = NSDateFormatterShortStyle;
        fmt.timeStyle = NSDateFormatterShortStyle;
        self.ameV13_descLabel.text = [NSString stringWithFormat:localize(@"i18n_str_1069", nil), [fmt stringFromDate:date]];
    } else {
        self.ameV13_descLabel.text = @" ";
    }
    if (mcVersion.length > 0 && loader.length > 0) {
        self.ameV13_tagLabel.text = [NSString stringWithFormat:@"MC %@ · %@ · %@", mcVersion, [ModLoaderIconHelper displayNameForLoader:loader], self.ameV13_gameDir.lastPathComponent];
    } else if (mcVersion.length > 0) {
        self.ameV13_tagLabel.text = [NSString stringWithFormat:@"MC %@ · %@", mcVersion, self.ameV13_gameDir.lastPathComponent];
    } else {
        self.ameV13_tagLabel.text = self.ameV13_gameDir;
    }

    if (loader.length > 0) {
        [ModLoaderIconHelper configureImageView:self.ameV13_iconView forLoader:loader traitCollection:self.traitCollection];
        self.ameV13_iconBox.backgroundColor = [UIColor clearColor];
    } else {
        self.ameV13_iconView.image = [ZL2V13SystemImage(@"gamecontroller", @"cube.box.fill") imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.ameV13_iconView.tintColor = [ZL2Theme onSurfaceVariant];
        self.ameV13_iconBox.backgroundColor = [ZL2Theme surfaceVariant];
    }
}

#pragma mark 概览：重命名（PLProfiles 注册表键换名，Task162 actionDone 链 1:1）

- (void)ameV13_actionRename {
    // 契约（旧链 ProfileSettingsViewController actionDone L3427-3476）：
    //   ① 空名恢复原名；② 重名拒绝（i18n_str_42/i18n_str_1289）；
    //   ③ 删旧键建新键；④ selected 指向旧键时同步新键；
    //   ⑤ save + SelectedProfileChanged。
    // 游戏目录实体不做 rename：versions/<id> 以 lastVersionId 为键且可能
    // 被多实例引用（Task255 引用计数口径），旧链 actionDone 同样只改注册
    // 表键——此处 1:1，不越界。
    NSString *oldKey = self.ameV13_profileName;
    NSMutableDictionary *profile = [self ameV13_profileDict];
    if (!profile) return;

    NSString *alertTitle = @"重命名实例";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = [profile[@"name"] isKindOfClass:[NSString class]] && ((NSString *)profile[@"name"]).length > 0
            ? (NSString *)profile[@"name"] : oldKey;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    NSString *cancelText = localize(@"resman.common.cancel", nil);
    NSString *okText = localize(@"i18n_str_44", nil);
    [alert addAction:[UIAlertAction actionWithTitle:cancelText style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:okText style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newName = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (newName.length == 0) return;  // ① 空名：放弃（旧链恢复原名语义，未提交即无变化）
        if ([newName isEqualToString:oldKey]) return;  // 同名：无操作
        if (PLProfiles.current.profiles[newName]) {
            // ② 重名拒绝（旧链 i18n_str_42/i18n_str_1289）
            [self ameV13_showAlertMessage:localize(@"i18n_str_1289", nil)];
            return;
        }
        // ③ 删旧键建新键（活字典整体迁移，字段零丢失）
        NSMutableDictionary *moving = [PLProfiles.current.profiles[oldKey] mutableCopy];
        if (!moving) return;
        moving[@"name"] = newName;
        [PLProfiles.current.profiles removeObjectForKey:oldKey];
        PLProfiles.current.profiles[newName] = moving;
        // ④ selected 同步（属性 setter 内含 save + SelectedProfileChanged）
        if ([PLProfiles.current.selectedProfileName isEqualToString:oldKey]) {
            PLProfiles.current.selectedProfileName = newName;
        }
        [PLProfiles.current save];
        // ⑤ 全局快照刷新 + 详情容器身份收敛（键名改写后配置页/头卡不悬空）
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectedProfileChanged" object:newName];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2VersionDetailProfileRenamed"
                                                            object:nil
                                                          userInfo:@{@"newName": newName}];
        [self ameV13_updateProfileName:newName];
        [self ameV13_refreshInfoCard];
        NSLog(@"[ZL2VersionPages] rename profile '%@' -> '%@' (registry key only; game dir untouched per old-chain contract)", oldKey, newName);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark 概览：编辑摘要（profile[@"versionSummary"]）

- (void)ameV13_actionEditSummary {
    NSMutableDictionary *profile = [self ameV13_profileDict];
    if (!profile) return;
    NSString *current = [profile[@"versionSummary"] isKindOfClass:[NSString class]] ? (NSString *)profile[@"versionSummary"] : @"";

    NSString *alertTitle = @"编辑摘要";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = current;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    NSString *cancelText = localize(@"resman.common.cancel", nil);
    NSString *okText = localize(@"i18n_str_44", nil);
    [alert addAction:[UIAlertAction actionWithTitle:cancelText style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:okText style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *summary = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [self ameV13_writeProfileKey:@"versionSummary" value:(summary.length > 0 ? summary : nil)];
        [self ameV13_refreshInfoCard];
        // 容器头卡描述行同步（versionSummary 是容器头描述的优先来源）
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2VersionDetailProfileEdited" object:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark 概览：打开游戏目录（目录 Open 模式呈现，iOS14 能力上限）

- (void)ameV13_actionOpenGameDir {
    // UIDocumentPicker 以目录方式呈现该目录（iOS14 无专用于「浏览目录」的
    // API，Open 模式 + 目录 URL = 文件 App 内定位到该目录的等价呈现）。
    NSURL *dirURL = [NSURL fileURLWithPath:self.ameV13_gameDir];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithURLs:@[dirURL]
                                                                                           inMode:UIDocumentPickerModeOpen];
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark 概览：删除版本（旧 VC deleteProfile: 全链 1:1）

- (void)ameV13_actionDeleteVersion {
    NSString *profileName = self.ameV13_profileName;
    // 至少保留一个实例守卫（旧链 i18n_str_1092）
    if (PLProfiles.current.profiles.count <= 1) {
        [self ameV13_showAlertMessage:localize(@"i18n_str_1092", nil)];
        return;
    }
    NSString *titleText = localize(@"i18n_str_457", nil);
    NSString *messageText = [NSString stringWithFormat:localize(@"i18n_str_1093", nil), profileName];
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:titleText
                                                                     message:messageText
                                                              preferredStyle:UIAlertControllerStyleAlert];
    NSString *cancelText = localize(@"resman.common.cancel", nil);
    NSString *deleteText = localize(@"i18n_str_306", nil);
    [confirm addAction:[UIAlertAction actionWithTitle:cancelText style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:deleteText style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        // Task255：删注册表条目后，同一 lastVersionId 不再被引用才连带删实体目录
        NSDictionary *profile = PLProfiles.current.profiles[profileName];
        NSString *versionId = [profile isKindOfClass:NSDictionary.class] && [profile[@"lastVersionId"] isKindOfClass:[NSString class]]
            ? (NSString *)profile[@"lastVersionId"] : nil;

        [PLProfiles.current.profiles removeObjectForKey:profileName];
        if ([PLProfiles.current.selectedProfileName isEqualToString:profileName]) {
            PLProfiles.current.selectedProfileName = PLProfiles.current.profiles.allKeys.firstObject;
        }
        [PLProfiles.current save];

        if (versionId.length > 0) {
            BOOL stillReferenced = NO;
            for (NSString *key in PLProfiles.current.profiles) {
                NSDictionary *other = PLProfiles.current.profiles[key];
                if ([other isKindOfClass:NSDictionary.class] &&
                    [other[@"lastVersionId"] isKindOfClass:[NSString class]] &&
                    [(NSString *)other[@"lastVersionId"] isEqualToString:versionId]) {
                    stillReferenced = YES;
                    break;
                }
            }
            if (!stillReferenced) {
                // Task255 r2 路径口径：POJAV_GAME_DIR/versions 优先、POJAV_HOME 兜底
                NSString *vdir = [NSString stringWithFormat:@"%s/versions/%@",
                    getenv("POJAV_GAME_DIR") ? getenv("POJAV_GAME_DIR") : getenv("POJAV_HOME"), versionId];
                if (![NSFileManager.defaultManager fileExistsAtPath:vdir]) {
                    const char *home = getenv("POJAV_HOME");
                    if (home != NULL) {
                        NSString *legacy = [NSString stringWithFormat:@"%s/versions/%@", home, versionId];
                        if ([NSFileManager.defaultManager fileExistsAtPath:legacy]) vdir = legacy;
                    }
                }
                if ([NSFileManager.defaultManager fileExistsAtPath:vdir]) {
                    NSError *err = nil;
                    if ([NSFileManager.defaultManager removeItemAtPath:vdir error:&err]) {
                        NSLog(@"[ZL2VersionPages] Task255: removed version folder for deleted profile '%@' -> %@", profileName, vdir);
                    } else {
                        NSLog(@"[ZL2VersionPages] Task255: failed to remove %@: %@", vdir, err.localizedDescription);
                        [self ameV13_showAlertMessage:[NSString stringWithFormat:localize(@"i18n_str_1088", nil), err.localizedDescription]];
                    }
                }
            } else {
                NSLog(@"[ZL2VersionPages] Task255: version %@ still referenced, folder kept", versionId);
            }
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
        // 实例已不存在：退回版本列表（容器 pop，子页随容器析构）
        if (self.navigationController && self.navigationController.viewControllers.count > 1) {
            [self.navigationController popViewControllerAnimated:YES];
        }
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

@end

#pragma mark - ② 模组管理（★ Task343：ModService/ModUpdateService 全量接线版）

// 旧 UI 模组页（ModsManagerViewController，1758 行 + 基类 550 行）功能对齐：
//   · 数据层全程 ModService（scan/toggle/delete/metadata/隔离嗅探口径）——
//     退役旁路实现（旧版子页直接 NSFileManager 枚举改名 = 第二实现漂移）；
//   · 搜索（displayName/fileName 实时过滤）+ 状态筛选 chips（全部/已启用/
//     已禁用）+ 排序切换（名称 ⇄ 修改时间）；
//   · 批量选择模式（全选/批量启用/禁用/删除，M3Dialog 确认）；
//   · 检查更新全流程（流式 SHA1 → ModUpdateService 双源限流检查 → M3Dialog
//     确认 → PLDownloadClient 镜像候选 + SHA1 校验并发下载 → 删旧移新保留
//     禁用态 → 结果汇总），忙态横幅阶段文本；
//   · 元数据卡片（jar 内 fabric.mod.json/mods.toml 解析显示名）+ Modrinth
//     项目页跳转（onlineID）+ 加载器错配橙色徽标（ame288 同语义）；
//   · 隔离态三态徽标（ame219）+ 生效 mods 目录提示行（Task264）；
//   · 导入 _copy/_copy_N 同名规避（Task268 同语义）；
//   · 空态「去下载」直达 ZL2 下载中心模组轨 + targetProfileName 透传
//     （Task265/324 语义保留）。
// 有意不做（语义不适用版本详情内嵌页，非功能缺失）：实例切换器/跨实例
// 下载横幅——版本详情天然钉定单实例（Task265 跟随/钉定是旧抽屉入口特有
// 语义）；本页 profileName 即详情页实例，下载中心透传已覆盖对账诉求。
// i18n：全部复用旧页既有键（resman.mods.* / resman.common.* / ame225.mods.*，
// 54 表已齐），零新增键。

// 更新下载任务（旧 ModsManagerViewController ModUpdateTask 同构；改名防符号撞）
@interface ZL2V13ModUpdateTask : NSObject
@property (nonatomic, strong) ModUpdateResult *result;
@property (nonatomic, strong) ModItem *mod;
@property (nonatomic, strong) ModVersion *targetVersion;
@property (nonatomic, copy, nullable) NSString *tempPath;
@property (nonatomic, assign) BOOL downloadSucceeded;
@end
@implementation ZL2V13ModUpdateTask
@end

// 流式 SHA1（旧 ModsManagerSHA1ForFile 同实现：CommonCrypto 256KB 块流式，
// Modrinth 反查依赖；大文件不进内存）
static NSString *ZL2V13ModSHA1ForFile(NSString *path) {
    if (path.length == 0) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return nil;
    FILE *fp = fopen(path.fileSystemRepresentation, "rb");
    if (!fp) return nil;
    unsigned char md[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_CTX ctx;
    CC_SHA1_Init(&ctx);
    unsigned char buf[262144];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) {
        CC_SHA1_Update(&ctx, buf, (CC_LONG)n);
    }
    fclose(fp);
    CC_SHA1_Final(md, &ctx);
    NSMutableString *hex = [NSMutableString stringWithCapacity:40];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", md[i]];
    }
    return hex;
}

@interface ZL2VersionModsPage () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIStackView *ameV13_contentStack;
@property (nonatomic, strong) UIStackView *ameV13_cardsStack;
@property (nonatomic, strong) UILabel *ameV13_countLabel;
@property (nonatomic, strong) UILabel *ameV13_busyLabel;          // 更新忙态阶段横幅
@property (nonatomic, strong) ZL2M3SearchBar *ameV13_searchBar;
@property (nonatomic, strong) NSMutableArray<ZL2M3FilterChip *> *ameV13_filterChips;   // 0 全部/1 启用/2 禁用
@property (nonatomic, strong) ZL2M3FilterChip *ameV13_sortNameChip;   // 排序双 chip（100/101）
@property (nonatomic, strong) ZL2M3FilterChip *ameV13_sortTimeChip;
@property (nonatomic, strong) UILabel *ameV13_isoBadge;           // 隔离态徽标（点按出说明）
@property (nonatomic, strong) UILabel *ameV13_folderCaption;      // 生效 mods 目录提示行
// 选择模式工具条（懒建，随选择态显隐）
@property (nonatomic, strong) UIStackView *ameV13_selectBar;
@property (nonatomic, strong) UILabel *ameV13_selectCountLabel;
@property (nonatomic, copy) NSArray<ModItem *> *ameV13_mods;      // ModService 全量
@property (nonatomic, copy) NSArray<ModItem *> *ameV13_viewMods;  // 搜索+筛选+排序后
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *ameV13_mtimeByPath;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *ameV13_displayNameByPath;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *ameV13_onlineIdByPath;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ModUpdateResult *> *ameV13_updateResults;
@property (nonatomic, strong) NSMutableSet<NSString *> *ameV13_selectedPaths;
@property (nonatomic, assign) BOOL ameV13_selectMode;
@property (nonatomic, assign) BOOL ameV13_updateBusy;
@property (nonatomic, assign) NSInteger ameV13_filterMode;   // 0 全部 1 启用 2 禁用
@property (nonatomic, assign) NSInteger ameV13_sortMode;     // 0 名称 1 修改时间
@end

@implementation ZL2VersionModsPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    _ameV13_mtimeByPath = [NSMutableDictionary dictionary];
    _ameV13_displayNameByPath = [NSMutableDictionary dictionary];
    _ameV13_onlineIdByPath = [NSMutableDictionary dictionary];
    _ameV13_updateResults = [NSMutableDictionary dictionary];
    _ameV13_selectedPaths = [NSMutableSet set];
    _ameV13_filterChips = [NSMutableArray array];

    UILabel *countLabel = [[UILabel alloc] init];
    countLabel.font = [ZL2Theme fontLabelMedium];
    countLabel.textColor = [ZL2Theme onSurfaceVariant];
    countLabel.numberOfLines = 1;
    countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _ameV13_countLabel = countLabel;

    __weak typeof(self) wself = self;
    // 检查更新（旧页顶栏同名入口 1:1）
    UIControl *updateButton = [self ameV13_iconButtonWithImageName:@"arrow.triangle.2.circlepath"
                                                          fallback:@"arrow.2.circlepath"
                                                             size:32
                                                     accessibility:localize(@"resman.mods.check_update", nil)
                                                             action:^{ [wself ameV13_checkForUpdates]; }];
    // 批量选择
    UIControl *selectButton = [self ameV13_iconButtonWithImageName:@"checkmark.circle"
                                                          fallback:@"circle"
                                                             size:32
                                                     accessibility:localize(@"resman.common.select", nil)
                                                             action:^{ [wself ameV13_toggleSelectMode]; }];
    // 导入（多选 zip/jar 复制进 mods/）
    UIControl *importButton = [self ameV13_iconButtonWithImageName:@"square.and.arrow.down"
                                                          fallback:@"tray.and.arrow.down"
                                                             size:32
                                                     accessibility:localize(@"resman.mods.import", nil)
                                                             action:^{ [wself ameV13_showImportPicker]; }];

    NSString *pageTitle = @"模组";
    UIStackView *header = [self ameV13_pageHeaderRowWithTitle:pageTitle
                                                     trailing:@[countLabel, updateButton, selectButton, importButton]];
    _ameV13_contentStack = [self ameV13_installContentSkeleton];
    [_ameV13_contentStack addArrangedSubview:header];

    // 更新忙态横幅（阶段文本；隐藏 = 空文本）
    UILabel *busy = [[UILabel alloc] init];
    busy.font = [ZL2Theme fontLabelMedium];
    busy.textColor = [ZL2Theme onSurfaceVariant];
    busy.numberOfLines = 1;
    busy.translatesAutoresizingMaskIntoConstraints = NO;
    busy.hidden = YES;
    _ameV13_busyLabel = busy;
    [_ameV13_contentStack addArrangedSubview:busy];

    // 搜索（ZL2M3SearchBar；显示名/文件名双口径实时过滤）
    ZL2M3SearchBar *search = [[ZL2M3SearchBar alloc] init];
    search.placeholder = localize(@"resman.mods.search_placeholder", nil);
    __weak typeof(search) wsearch = search;   // 防自持有环（onReturn 捕获搜索框自身）
    search.onTextChanged = ^(NSString *text) { [wself ameV13_applyFilter]; };
    search.onReturn = ^(NSString *text) { [wsearch resignFirstResponder]; };
    _ameV13_searchBar = search;
    [_ameV13_contentStack addArrangedSubview:search];

    // 筛选 chips 行（全部/已启用/已禁用 + 排序切换）
    UIStackView *chips = [[UIStackView alloc] init];
    chips.axis = UILayoutConstraintAxisHorizontal;
    chips.spacing = 8;
    chips.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray<NSString *> *chipTitles = @[
        localize(@"resman.mods.filter.all", nil),
        localize(@"resman.mods.filter.enabled", nil),
        localize(@"resman.mods.filter.disabled", nil),
    ];
    for (NSUInteger i = 0; i < chipTitles.count; i++) {
        ZL2M3FilterChip *chip = [[ZL2M3FilterChip alloc] initWithText:chipTitles[i]];
        chip.tag = (NSInteger)i;
        [chip addTarget:self action:@selector(ameV13_filterChipTapped:)
               forControlEvents:UIControlEventTouchUpInside];
        chip.selected = (i == 0);
        [_ameV13_filterChips addObject:chip];
        [chips addArrangedSubview:chip];
    }
    ZL2M3FilterChip *sortNameChip = [[ZL2M3FilterChip alloc] initWithText:localize(@"resman.mods.sort.name", nil)];
    sortNameChip.tag = 100;   // 排序双 chip：100=名称 / 101=修改时间（选中态随 sortMode）
    [sortNameChip addTarget:self action:@selector(ameV13_sortChipTapped:)
           forControlEvents:UIControlEventTouchUpInside];
    ZL2M3FilterChip *sortTimeChip = [[ZL2M3FilterChip alloc] initWithText:localize(@"resman.mods.sort.modified", nil)];
    sortTimeChip.tag = 101;
    [sortTimeChip addTarget:self action:@selector(ameV13_sortChipTapped:)
           forControlEvents:UIControlEventTouchUpInside];
    _ameV13_sortNameChip = sortNameChip;
    _ameV13_sortTimeChip = sortTimeChip;
    [chips addArrangedSubview:[self ameV13_spacer]];
    [chips addArrangedSubview:sortNameChip];
    [chips addArrangedSubview:sortTimeChip];
    [_ameV13_contentStack addArrangedSubview:chips];
    [self ameV13_refreshSortChips];

    // 隔离态徽标 + 生效目录提示行（ame219 三态 + Task264 目录）
    UILabel *iso = [[UILabel alloc] init];
    iso.font = [ZL2Theme fontLabelMedium];
    iso.numberOfLines = 1;
    iso.translatesAutoresizingMaskIntoConstraints = NO;
    iso.userInteractionEnabled = YES;
    [iso addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ameV13_isoBadgeTapped)]];
    _ameV13_isoBadge = iso;
    UILabel *folder = [[UILabel alloc] init];
    folder.font = [ZL2Theme fontLabelMedium];
    folder.textColor = [ZL2Theme onSurfaceVariant];
    folder.numberOfLines = 1;
    folder.lineBreakMode = NSLineBreakByTruncatingMiddle;
    folder.translatesAutoresizingMaskIntoConstraints = NO;
    _ameV13_folderCaption = folder;
    [_ameV13_contentStack addArrangedSubview:iso];
    [_ameV13_contentStack addArrangedSubview:folder];
    [self ameV13_refreshIsoBadge];

    // 选择模式工具条（懒建；计数字 + 全选/启用/禁用/删除/完成）
    [self ameV13_buildSelectBar];
    [_ameV13_contentStack addArrangedSubview:_ameV13_selectBar];
    _ameV13_selectBar.hidden = YES;

    _ameV13_cardsStack = [[UIStackView alloc] init];
    _ameV13_cardsStack.axis = UILayoutConstraintAxisVertical;
    _ameV13_cardsStack.alignment = UIStackViewAlignmentFill;
    _ameV13_cardsStack.spacing = ZL2V13CardSpacing;
    _ameV13_cardsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_contentStack addArrangedSubview:_ameV13_cardsStack];
}

#pragma mark 隔离徽标与目录行

- (void)ameV13_refreshIsoBadge {
    NSInteger state = [ModService ame219_isolationStateForProfile:self.ameV13_profileName];
    NSString *note = (state == 1) ? localize(@"ame225.mods.isolated_note", nil)
                    : (state == 2) ? localize(@"ame225.mods.sniffed_note", nil)
                                   : localize(@"ame225.mods.shared_note", nil);
    _ameV13_isoBadge.text = [NSString stringWithFormat:@"%@ %@", note, @"›"];
    UIColor *badgeColor = (state == 0) ? [ZL2Theme onSurfaceVariant] : [ZL2Theme tertiary];
    _ameV13_isoBadge.textColor = badgeColor;
    NSString *dir = [ModService.sharedService ame264_effectiveModsFolderForProfile:self.ameV13_profileName];
    _ameV13_folderCaption.text = dir.length > 0
        ? [NSString stringWithFormat:@"%@ %@", localize(@"resman.mods.folder.caption", nil), dir]
        : @"";
}

- (void)ameV13_isoBadgeTapped {
    // 隔离语义说明（Task219 三态口径；版本详情内嵌页无设置跳转诉求）
    NSInteger state = [ModService ame219_isolationStateForProfile:self.ameV13_profileName];
    NSString *note = (state == 1) ? localize(@"ame225.mods.isolated_note", nil)
                    : (state == 2) ? localize(@"ame225.mods.sniffed_note", nil)
                                   : localize(@"ame225.mods.shared_note", nil);
    [self ameV13_showAlertMessage:note];
}

#pragma mark 数据装载（ModService 全量接线）

- (void)ameV13_reloadContent {
    if (_ameV13_updateBusy) return;   // 更新流程持有数据快照，装载完再刷新
    __weak typeof(self) wself = self;
    NSString *profile = self.ameV13_profileName;
    [[ModService sharedService] scanModsForProfile:profile completion:^(NSArray<ModItem *> *mods) {
        __strong typeof(wself) strongSelf = wself;
        if (!strongSelf) return;
        strongSelf.ameV13_mods = mods ?: @[];
        // 目录提示行随扫描刷新（Task264 生效目录实况）
        [strongSelf ameV13_refreshIsoBadge];
        // 修改时间缓存（排序档）+ 元数据补齐（显示名/onlineID，逐个异步）
        [strongSelf ameV13_collectAuxForMods:strongSelf.ameV13_mods];
        [strongSelf ameV13_applyFilter];
    }];
}

- (void)ameV13_collectAuxForMods:(NSArray<ModItem *> *)mods {
    __weak typeof(self) wself = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableDictionary<NSString *, NSNumber *> *mtimes = [NSMutableDictionary dictionary];
        for (ModItem *mod in mods) {
            NSDictionary *attr = [NSFileManager.defaultManager attributesOfItemAtPath:mod.filePath error:nil];
            if (attr) {
                mtimes[mod.filePath] = @([attr fileModificationDate].timeIntervalSince1970);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) strongSelf = wself;
            if (!strongSelf) return;
            [strongSelf.ameV13_mtimeByPath addEntriesFromDictionary:mtimes];
            [strongSelf ameV13_applyFilter];   // mtime 到位后重排一次
        });
    });
    for (ModItem *mod in mods) {
        [[ModService sharedService] fetchMetadataForMod:mod completion:^(ModItem *item, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(wself) strongSelf = wself;
                if (!strongSelf || !item.filePath.length) return;
                if (item.displayName.length > 0) {
                    strongSelf.ameV13_displayNameByPath[item.filePath] = item.displayName;
                }
                if (item.onlineID.length > 0) {
                    strongSelf.ameV13_onlineIdByPath[item.filePath] = item.onlineID;
                }
                [strongSelf ameV13_applyFilter];   // 元数据到位即增量重排（卡片标题升级）
            });
        }];
    }
}

#pragma mark 过滤 / 排序 / 重建

- (void)ameV13_applyFilter {
    NSString *needle = _ameV13_searchBar.text ?: @"";
    needle = [needle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray<ModItem *> *view = [NSMutableArray array];
    for (ModItem *mod in _ameV13_mods) {
        if (_ameV13_filterMode == 1 && mod.disabled) continue;
        if (_ameV13_filterMode == 2 && !mod.disabled) continue;
        if (needle.length > 0) {
            NSString *display = _ameV13_displayNameByPath[mod.filePath] ?: @"";
            NSString *base = mod.basename ?: @"";
            if ([display localizedCaseInsensitiveContainsString:needle] == NO &&
                [base localizedCaseInsensitiveContainsString:needle] == NO &&
                [(mod.fileName ?: @"") localizedCaseInsensitiveContainsString:needle] == NO) {
                continue;
            }
        }
        [view addObject:mod];
    }
    if (_ameV13_sortMode == 0) {
        [view sortUsingComparator:^NSComparisonResult(ModItem *a, ModItem *b) {
            NSString *an = [self ameV13_displayNameFor:a];
            NSString *bn = [self ameV13_displayNameFor:b];
            return [an caseInsensitiveCompare:bn];
        }];
    } else {
        [view sortUsingComparator:^NSComparisonResult(ModItem *a, ModItem *b) {
            double am = [self.ameV13_mtimeByPath[a.filePath] doubleValue];
            double bm = [self.ameV13_mtimeByPath[b.filePath] doubleValue];
            return bm > am ? NSOrderedDescending : (bm < am ? NSOrderedAscending : NSOrderedSame);
        }];
    }
    _ameV13_viewMods = [view copy];
    // 计数徽章 + 清理已不在列表的勾选/徽章态
    _ameV13_countLabel.text = [NSString stringWithFormat:@"共 %ld 个", (long)_ameV13_viewMods.count];
    [_ameV13_selectedPaths intersectSet:[NSSet setWithArray:[_ameV13_viewMods valueForKeyPath:@"filePath"]]];
    [self ameV13_updateSelectCount];
    [self ameV13_rebuildCards];
}

- (NSString *)ameV13_displayNameFor:(ModItem *)mod {
    NSString *display = _ameV13_displayNameByPath[mod.filePath];
    return (display.length > 0) ? display : (mod.basename ?: mod.fileName ?: @"?");
}

#pragma mark 卡片重建

- (void)ameV13_rebuildCards {
    [self ameV13_clearStack:_ameV13_cardsStack];
    if (_ameV13_viewMods.count == 0) {
        BOOL isFiltering = (_ameV13_filterMode != 0) ||
                           ([_ameV13_searchBar.text stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]].length > 0);
        if (_ameV13_mods.count == 0) {
            // 全空态：去下载（ZL2 下载中心模组轨 + 目标实例透传，Task265/324）
            UIView *empty = [self ameV13_emptyStateWithSymbol:@"puzzlepiece.extension"
                                                     fallback:@"puzzlepiece"
                                                         text:localize(@"resman.mods.empty", nil)];
            [_ameV13_cardsStack addArrangedSubview:empty];
            UIControl *goDownload = [self ameV13_iconButtonWithImageName:@"arrow.down.circle.fill"
                                                                fallback:@"arrow.down.circle"
                                                                   size:40
                                                           accessibility:localize(@"resman.common.go_download", nil)
                                                                   action:^{ [self ameV13_openDownloadCenter]; }];
            // 双 spacer 夹持居中（Fill 对齐下 stack 拉伸整行，两 spacer 均分余量）
            UIStackView *cta = [[UIStackView alloc] init];
            cta.axis = UILayoutConstraintAxisHorizontal;
            cta.translatesAutoresizingMaskIntoConstraints = NO;
            [cta addArrangedSubview:[self ameV13_spacer]];
            [cta addArrangedSubview:goDownload];
            [cta addArrangedSubview:[self ameV13_spacer]];
            [_ameV13_cardsStack addArrangedSubview:cta];
        } else if (isFiltering) {
            [_ameV13_cardsStack addArrangedSubview:[self ameV13_emptyStateWithSymbol:@"magnifyingglass"
                                                                            fallback:@"magnifyingglass"
                                                                                text:localize(@"resman.mods.search_empty", nil)]];
        }
        return;
    }
    for (ModItem *mod in _ameV13_viewMods) {
        [_ameV13_cardsStack addArrangedSubview:[self ameV13_cardForMod:mod]];
    }
}

- (UIView *)ameV13_cardForMod:(ModItem *)mod {
    NSString *name = [self ameV13_displayNameFor:mod];
    NSString *sizeText = ZL2V13ByteCount([[[NSFileManager defaultManager]
        attributesOfItemAtPath:mod.filePath error:nil] fileSize]);
    NSMutableArray<NSString *> *detailParts = [NSMutableArray arrayWithObject:sizeText];
    if (mod.disabled) [detailParts addObject:localize(@"resman.common.disabled_tag", nil)];
    ModUpdateResult *upd = _ameV13_updateResults[mod.filePath];
    if (upd) {
        [detailParts addObject:[NSString stringWithFormat:@"%@ → %@",
            localize(@"resman.mods.check_update", nil),
            upd.candidateVersions.firstObject.versionNumber ?: localize(@"resman.mods.update.latest", nil)]];
    }
    UIStackView *textStack = [self ameV13_textStackWithTitle:name
                                                      detail:[detailParts componentsJoinedByString:@" · "]];
    // 加载器错配徽标（ame288 同语义：橙档 tertiary 色 + 错配加载器名）
    NSString *loader = [self ameV13_profileLoaderForDisplay];
    if (loader.length > 0 && [self ameV13_mod:mod mismatchesProfileLoader:loader]) {
        UILabel *badge = [[UILabel alloc] init];
        badge.font = [ZL2Theme fontLabelMedium];
        badge.textColor = [ZL2Theme warning];
        badge.text = [NSString stringWithFormat:localize(@"resman.mods.badge.loader_mismatch", nil), loader];
        badge.translatesAutoresizingMaskIntoConstraints = NO;
        [textStack addArrangedSubview:badge];
    }

    UIView *iconBox = [self ameV13_iconBoxWithSymbol:@"puzzlepiece.extension" fallback:@"puzzlepiece" size:48 iconSize:26];
    UIView *spacer = [self ameV13_spacer];

    if (_ameV13_selectMode) {
        // 选择模式：圆圈勾选钮替代开关/删除（基类工具条承担批量动作）
        BOOL checked = [_ameV13_selectedPaths containsObject:mod.filePath];
        UIControl *check = [self ameV13_iconButtonWithImageName:checked ? @"checkmark.circle.fill" : @"circle"
                                                      fallback:checked ? @"checkmark.circle.fill" : @"circle"
                                                                 size:32
                                                         accessibility:localize(@"resman.common.select", nil)
                                                                 action:^{ [self ameV13_toggleSelectedMod:mod]; }];
        UIStackView *wrap = [self ameV13_rowCardWithViews:@[iconBox, textStack, spacer, check]
                                                alignment:UIStackViewAlignmentCenter];
        UITapGestureRecognizer *rowTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ameV13_cardTapped:)];
        [wrap addGestureRecognizer:rowTap];
        objc_setAssociatedObject(wrap, @selector(ameV13_cardTapped:), mod.filePath, OBJC_ASSOCIATION_COPY_NONATOMIC);
        return wrap;
    }

    // 启用/禁用开关（ModService.toggleEnableForMod：Task217 失败弹窗 + 201 自愈重扫）
    ZL2M3Switch *toggle = [[ZL2M3Switch alloc] init];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    toggle.accessibilityLabel = name;
    toggle.on = !mod.disabled;
    [toggle addTarget:self action:@selector(ameV13_toggleChanged:) forControlEvents:UIControlEventValueChanged];
    objc_setAssociatedObject(toggle, @selector(ameV13_toggleChanged:), mod.filePath, OBJC_ASSOCIATION_COPY_NONATOMIC);

    UIControl *deleteButton = [self ameV13_iconButtonWithImageName:@"trash"
                                                          fallback:@"trash.fill"
                                                             size:32
                                                     accessibility:localize(@"resman.common.delete", nil)
                                                             action:^{ [self ameV13_confirmDeleteMod:mod]; }];

    UIStackView *wrap = [self ameV13_rowCardWithViews:@[iconBox, textStack, spacer, toggle, deleteButton]
                                            alignment:UIStackViewAlignmentCenter];
    // 行点按 = Modrinth 项目页（onlineID 命中）；未命中出「链接不可用」说明
    UITapGestureRecognizer *rowTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ameV13_cardTapped:)];
    [wrap addGestureRecognizer:rowTap];
    objc_setAssociatedObject(wrap, @selector(ameV13_cardTapped:), mod.filePath, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return wrap;
}

#pragma mark 卡片动作

- (void)ameV13_cardTapped:(UITapGestureRecognizer *)sender {
    NSString *path = objc_getAssociatedObject(sender.view, @selector(ameV13_cardTapped:));
    if (path.length == 0) return;
    if (_ameV13_selectMode) {
        for (ModItem *mod in _ameV13_viewMods) {
            if ([mod.filePath isEqualToString:path]) { [self ameV13_toggleSelectedMod:mod]; return; }
        }
        return;
    }
    NSString *onlineId = _ameV13_onlineIdByPath[path];
    if (onlineId.length > 0) {
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://modrinth.com/mod/%@", onlineId]];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            return;
        }
    }
    [self ameV13_showAlertMessage:localize(@"resman.mods.link_unavailable_message", nil)];
}

- (void)ameV13_toggleChanged:(ZL2M3Switch *)sender {
    NSString *path = objc_getAssociatedObject(sender, @selector(ameV13_toggleChanged:));
    ModItem *target = nil;
    for (ModItem *mod in _ameV13_viewMods) {
        if ([mod.filePath isEqualToString:path]) { target = mod; break; }
    }
    if (!target) { sender.on = !sender.on; return; }
    // ZL2M3Switch 契约：sender.on = 用户意图新值
    target.disabled = !sender.on;
    NSError *error = nil;
    BOOL ok = [[ModService sharedService] toggleEnableForMod:target error:&error];
    if (!ok) {
        // Task217 家族：失败一律弹窗给真实原因；ModServiceError 201（源文件
        // 缺失）额外自愈重扫——幽灵条目即刻消失，不再是"点了没反应"
        sender.on = !sender.on;   // 视觉回滚（失败时模型态未变）
        [self ameV13_showAlertMessage:error.localizedDescription ?: localize(@"common.unknown_error", nil)];
        if ([error.domain isEqualToString:@"ModServiceError"] && error.code == 201) {
            [self ameV13_reloadContent];
        }
        return;
    }
    NSLog(@"[ZL2VersionPages] Task343 mod toggle: %@ -> %@", target.fileName, target.disabled ? @"disabled" : @"enabled");
}

- (void)ameV13_confirmDeleteMod:(ModItem *)mod {
    NSString *name = [self ameV13_displayNameFor:mod];
    NSString *bodyText = [NSString stringWithFormat:localize(@"resman.common.delete_message_irreversible", nil), name];
    __weak typeof(self) weakSelf = self;
    [self ameV13_confirmDeleteTitle:name
                               body:bodyText
                          onConfirm:^{
        NSError *err = nil;
        if ([[ModService sharedService] deleteMod:mod error:&err]) {
            [weakSelf.ameV13_updateResults removeObjectForKey:mod.filePath];
            [weakSelf.ameV13_selectedPaths removeObject:mod.filePath];
            [weakSelf ameV13_reloadContent];
        } else {
            NSString *failedText = localize(@"resman.common.delete_failed", nil);
            [weakSelf ameV13_showAlertMessage:[NSString stringWithFormat:@"%@: %@", failedText, ZL2V13ErrorText(err)]];
        }
    }];
}

#pragma mark 导入（Task268 同名 _copy_N 规避）

- (void)ameV13_showImportPicker {
    UTType *jarType = [UTType typeWithFilenameExtension:@"jar"];
    if (!jarType) jarType = UTTypeData;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeZIP, jarType] asCopy:YES];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    NSString *modsDir = [self.ameV13_gameDir stringByAppendingPathComponent:@"mods"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [NSFileManager.defaultManager createDirectoryAtPath:modsDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSInteger ok = 0;
        NSInteger fail = 0;
        for (NSURL *url in urls) {
            // Task268 同名规避：mods/ 已有同名时 _copy / _copy_N 循环探底
            NSString *base = url.lastPathComponent;
            NSString *dest = [modsDir stringByAppendingPathComponent:base];
            NSString *nameNoExt = base.stringByDeletingPathExtension;
            NSString *ext = base.pathExtension;
            NSUInteger copyIdx = 0;
            while ([NSFileManager.defaultManager fileExistsAtPath:dest]) {
                copyIdx++;
                NSString *candidate = (copyIdx == 1)
                    ? [NSString stringWithFormat:@"%@_copy%@", nameNoExt, ext.length ? [@"." stringByAppendingString:ext] : @""]
                    : [NSString stringWithFormat:@"%@_copy_%lu%@", nameNoExt, (unsigned long)copyIdx, ext.length ? [@"." stringByAppendingString:ext] : @""];
                dest = [modsDir stringByAppendingPathComponent:candidate];
                if (copyIdx > 999) break;   // 病态防御
            }
            NSError *err = nil;
            if ([NSFileManager.defaultManager copyItemAtPath:url.path toPath:dest error:&err]) {
                ok++;
            } else {
                fail++;
                NSLog(@"[ZL2VersionPages] Task343 mod import failed %@: %@", url.lastPathComponent, err.localizedDescription);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (fail > 0) {
                NSString *resultText = [NSString stringWithFormat:localize(@"resman.common.import_result", nil), (long)ok, (long)fail];
                [self ameV13_showAlertMessage:resultText];
            }
            [self ameV13_reloadContent];
        });
    });
}

#pragma mark 批量选择模式

- (void)ameV13_buildSelectBar {
    UIStackView *bar = [[UIStackView alloc] init];
    bar.axis = UILayoutConstraintAxisHorizontal;
    bar.spacing = 8;
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *count = [[UILabel alloc] init];
    count.font = [ZL2Theme fontLabelLarge];
    count.textColor = [ZL2Theme onSurface];
    count.translatesAutoresizingMaskIntoConstraints = NO;
    _ameV13_selectCountLabel = count;
    [bar addArrangedSubview:count];
    [bar addArrangedSubview:[self ameV13_spacer]];
    __weak typeof(self) wself = self;
    UIControl *allBtn = [self ameV13_iconButtonWithImageName:@"checkmark.circle" fallback:@"circle" size:30
                                                     accessibility:localize(@"resman.common.select", nil)
                                                             action:^{ [wself ameV13_selectAll]; }];
    UIControl *enableBtn = [self ameV13_iconButtonWithImageName:@"eye" fallback:@"eye.fill" size:30
                                                      accessibility:localize(@"resman.common.enable", nil)
                                                              action:^{ [wself ameV13_batchSetDisabled:NO]; }];
    UIControl *disableBtn = [self ameV13_iconButtonWithImageName:@"eye.slash" fallback:@"eye.slash.fill" size:30
                                                       accessibility:localize(@"resman.common.disable", nil)
                                                               action:^{ [wself ameV13_batchSetDisabled:YES]; }];
    UIControl *deleteBtn = [self ameV13_iconButtonWithImageName:@"trash" fallback:@"trash.fill" size:30
                                                      accessibility:localize(@"resman.common.batch_delete", nil)
                                                              action:^{ [wself ameV13_batchDelete]; }];
    UIControl *doneBtn = [self ameV13_iconButtonWithImageName:@"xmark.circle.fill" fallback:@"xmark.circle" size:30
                                                    accessibility:localize(@"resman.common.done", nil)
                                                            action:^{ [wself ameV13_toggleSelectMode]; }];
    [bar addArrangedSubview:allBtn];
    [bar addArrangedSubview:enableBtn];
    [bar addArrangedSubview:disableBtn];
    [bar addArrangedSubview:deleteBtn];
    [bar addArrangedSubview:doneBtn];
    _ameV13_selectBar = bar;
}

- (void)ameV13_toggleSelectMode {
    if (!_ameV13_selectMode && _ameV13_viewMods.count == 0) return;
    _ameV13_selectMode = !_ameV13_selectMode;
    if (_ameV13_selectMode) {
        [_ameV13_selectedPaths removeAllObjects];
    } else {
        [_ameV13_selectedPaths removeAllObjects];
    }
    _ameV13_selectBar.hidden = !_ameV13_selectMode;
    [self ameV13_updateSelectCount];
    [self ameV13_rebuildCards];
}

- (void)ameV13_updateSelectCount {
    _ameV13_selectCountLabel.text = [NSString stringWithFormat:localize(@"resman.common.selected_count", nil),
                                     (long)_ameV13_selectedPaths.count];
}

- (void)ameV13_toggleSelectedMod:(ModItem *)mod {
    if ([_ameV13_selectedPaths containsObject:mod.filePath]) {
        [_ameV13_selectedPaths removeObject:mod.filePath];
    } else {
        [_ameV13_selectedPaths addObject:mod.filePath];
    }
    [self ameV13_updateSelectCount];
    [self ameV13_rebuildCards];
}

- (void)ameV13_selectAll {
    BOOL allSelected = (_ameV13_selectedPaths.count >= _ameV13_viewMods.count && _ameV13_viewMods.count > 0);
    [_ameV13_selectedPaths removeAllObjects];
    if (!allSelected) {
        for (ModItem *mod in _ameV13_viewMods) [_ameV13_selectedPaths addObject:mod.filePath];
    }
    [self ameV13_updateSelectCount];
    [self ameV13_rebuildCards];
}

- (NSArray<ModItem *> *)ameV13_selectedMods {
    NSMutableArray<ModItem *> *items = [NSMutableArray array];
    for (ModItem *mod in _ameV13_viewMods) {
        if ([_ameV13_selectedPaths containsObject:mod.filePath]) [items addObject:mod];
    }
    return [items copy];
}

- (void)ameV13_batchSetDisabled:(BOOL)wantDisabled {
    NSArray<ModItem *> *items = [self ameV13_selectedMods];
    if (items.count == 0) {
        [self ameV13_showAlertMessage:localize(@"resman.mods.none_selected", nil)];
        return;
    }
    NSInteger ok = 0;
    NSInteger fail = 0;
    for (ModItem *mod in items) {
        if (mod.disabled == wantDisabled) { ok++; continue; }   // 语义上无操作计成功
        mod.disabled = wantDisabled;
        NSError *err = nil;
        if ([[ModService sharedService] toggleEnableForMod:mod error:&err]) ok++;
        else fail++;
    }
    [self ameV13_reloadContent];
    [self ameV13_showAlertMessage:[NSString stringWithFormat:localize(@"resman.mods.batch.toggle_complete", nil), (long)ok, (long)fail]];
}

- (void)ameV13_batchDelete {
    NSArray<ModItem *> *items = [self ameV13_selectedMods];
    if (items.count == 0) {
        [self ameV13_showAlertMessage:localize(@"resman.mods.none_selected", nil)];
        return;
    }
    NSString *bodyText = [NSString stringWithFormat:localize(@"resman.mods.batch.delete_message", nil), (long)items.count];
    __weak typeof(self) weakSelf = self;
    [self ameV13_confirmDeleteTitle:localize(@"resman.common.batch_delete", nil)
                               body:bodyText
                          onConfirm:^{
        NSInteger ok = 0;
        NSInteger fail = 0;
        for (ModItem *mod in items) {
            NSError *err = nil;
            if ([[ModService sharedService] deleteMod:mod error:&err]) {
                ok++;
                [weakSelf.ameV13_updateResults removeObjectForKey:mod.filePath];
            } else {
                fail++;
            }
        }
        [weakSelf.ameV13_selectedPaths removeAllObjects];
        [weakSelf ameV13_reloadContent];
        [weakSelf ameV13_showAlertMessage:[NSString stringWithFormat:localize(@"resman.mods.batch.result_message", nil), (long)ok, (long)fail]];
    }];
}

#pragma mark 检查更新全流程（旧页状态机 1:1：空闲→检查中→确认→下载替换中→完成）

- (void)ameV13_setBusy:(BOOL)busy text:(nullable NSString *)text {
    _ameV13_updateBusy = busy;
    _ameV13_busyLabel.hidden = !busy;
    _ameV13_busyLabel.text = text ?: @"";
}

- (void)ameV13_checkForUpdates {
    if (_ameV13_updateBusy) return;   // 防重复触发
    if (_ameV13_mods.count == 0) {
        [self ameV13_showAlertMessage:localize(@"resman.mods.no_local_for_update", nil)];
        return;
    }
    // gameVersion/loader：本实例 lastVersionId 反解（Task217 parseVersionId 全形态口径）
    NSDictionary *prof = PLProfiles.current.profiles[self.ameV13_profileName] ?: @{};
    NSString *lastVersionId = [prof isKindOfClass:[NSDictionary class]] ? prof[@"lastVersionId"] : nil;
    if (lastVersionId.length == 0) {
        [self ameV13_showAlertMessage:localize(@"resman.mods.no_version_info", nil)];
        return;
    }
    NSDictionary *parsed = [ModpackExportService parseVersionId:lastVersionId];
    NSString *gameVersion = parsed[@"minecraft"];
    NSString *loader = parsed[@"loader"];
    if (![gameVersion isKindOfClass:[NSString class]] || gameVersion.length == 0) {
        gameVersion = lastVersionId;   // 纯 <mc> 格式，无 loader
        loader = nil;
    }

    [self ameV13_setBusy:YES text:localize(@"resman.mods.update.checking", nil)];
    NSArray<ModItem *> *mods = [_ameV13_mods copy];
    NSString *gv = gameVersion;
    NSString *ld = loader;
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    __weak typeof(self) weakSelf = self;
    dispatch_async(queue, ^{
        // 阶段 1：补齐 SHA1（Modrinth 反查必需；大文件流式计算）
        for (ModItem *mod in mods) {
            if (mod.fileSHA1.length == 0) {
                mod.fileSHA1 = ZL2V13ModSHA1ForFile(mod.filePath);
            }
        }
        // 阶段 2：并发检查（dispatch_group 汇总 + 信号量限流 3，旧页同刻度）
        dispatch_group_t group = dispatch_group_create();
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(3);
        NSObject *lock = [[NSObject alloc] init];
        NSMutableArray<ModUpdateResult *> *updatable = [NSMutableArray array];
        __block NSInteger unrecognized = 0;
        __block NSInteger completed = 0;
        NSInteger total = mods.count;
        for (ModItem *mod in mods) {
            dispatch_group_enter(group);
            dispatch_async(queue, ^{
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                [[ModUpdateService sharedService] checkUpdateForMod:mod
                                                        gameVersion:gv
                                                             loader:ld
                                                        projectType:@"mod"
                                                         completion:^(ModUpdateResult *result) {
                    @synchronized(lock) {
                        if (result) {
                            if ([result hasUpdate]) [updatable addObject:result];
                        } else {
                            unrecognized++;   // 双源未命中 → 无法识别
                        }
                        completed++;
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [weakSelf ameV13_setBusy:YES
                                            text:[NSString stringWithFormat:localize(@"resman.mods.update.checking_progress", nil), (long)completed, (long)total]];
                    });
                    dispatch_semaphore_signal(semaphore);
                    dispatch_group_leave(group);
                }];
            });
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf ameV13_setBusy:NO text:nil];
            // 徽章：命中更新的 Mod 显示更新标记
            [strongSelf.ameV13_updateResults removeAllObjects];
            for (ModUpdateResult *result in updatable) {
                if (result.localFilePath.length > 0) {
                    strongSelf.ameV13_updateResults[result.localFilePath] = result;
                }
            }
            [strongSelf ameV13_applyFilter];
            if (updatable.count == 0) {
                NSString *message = localize(@"resman.mods.update.all_latest", nil);
                if (unrecognized > 0) {
                    message = [NSString stringWithFormat:localize(@"resman.mods.update.all_latest_skipped", nil), (long)unrecognized];
                }
                [strongSelf ameV13_showAlertMessage:message];
            } else {
                [strongSelf ameV13_presentUpdateConfirmWithResults:[updatable copy] skipped:unrecognized];
            }
        });
    });
}

/// 更新确认（M3Dialog；逐项列 名称 当前→新版本，超长截断 8 项，旧页同口径）
- (void)ameV13_presentUpdateConfirmWithResults:(NSArray<ModUpdateResult *> *)results skipped:(NSInteger)skipped {
    if (results.count == 0) return;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSUInteger maxLines = 8;
    for (NSUInteger i = 0; i < results.count && i < maxLines; i++) {
        ModUpdateResult *result = results[i];
        NSString *name = result.localFilePath.lastPathComponent ?: localize(@"resman.common.unknown_file", nil);
        NSString *display = _ameV13_displayNameByPath[result.localFilePath];
        if (display.length > 0) name = display;
        NSString *current = result.currentVersion.versionNumber ?: @"?";
        NSString *target = result.candidateVersions.firstObject.versionNumber ?: localize(@"resman.mods.update.latest", nil);
        [lines addObject:[NSString stringWithFormat:@"%@\n%@ → %@", name, current, target]];
    }
    if (results.count > maxLines) {
        [lines addObject:[NSString stringWithFormat:localize(@"resman.mods.update.more_total", nil), (long)results.count]];
    }
    if (skipped > 0) {
        [lines addObject:[NSString stringWithFormat:localize(@"resman.mods.update.skipped_line", nil), (long)skipped]];
    }
    NSString *body = [lines componentsJoinedByString:@"\n"];
    __weak typeof(self) weakSelf = self;
    [ZL2M3Dialog showTitle:[NSString stringWithFormat:localize(@"resman.mods.update.found_title", nil), (long)results.count]
                      body:body
              confirmTitle:localize(@"resman.mods.update.update_all", nil)
               destructive:NO
                onConfirm:^{ [weakSelf ameV13_performUpdatesWithResults:results skipped:skipped]; }
                 onCancel:nil];
}

/// 执行更新：并发下载到临时目录（PLDownloadClient，镜像候选 + SHA1 校验 +
/// zip EOCD 兜底）→ 删旧移新（保留禁用态）→ 清徽章、重载、汇总（旧页 1:1）
- (void)ameV13_performUpdatesWithResults:(NSArray<ModUpdateResult *> *)results skipped:(NSInteger)skipped {
    NSMutableArray<ZL2V13ModUpdateTask *> *tasks = [NSMutableArray array];
    for (ModUpdateResult *result in results) {
        ModVersion *target = result.candidateVersions.firstObject;
        if (!target) continue;
        ZL2V13ModUpdateTask *task = [[ZL2V13ModUpdateTask alloc] init];
        task.result = result;
        task.targetVersion = target;
        for (ModItem *mod in _ameV13_mods) {
            if ([mod.filePath isEqualToString:result.localFilePath]) { task.mod = mod; break; }
        }
        [tasks addObject:task];
    }
    if (tasks.count == 0) return;

    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"ModUpdate_%@", [[NSUUID UUID] UUIDString]]];
    NSError *mkError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir
                              withIntermediateDirectories:YES attributes:nil error:&mkError];
    if (mkError) {
        [self ameV13_showAlertMessage:[NSString stringWithFormat:@"%@: %@",
            localize(@"resman.mods.update.failed_title", nil), mkError.localizedDescription]];
        return;
    }

    [self ameV13_setBusy:YES text:[NSString stringWithFormat:localize(@"resman.mods.update.downloading", nil), 0L, (long)tasks.count]];
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(4);
    NSObject *progressLock = [[NSObject alloc] init];
    __block NSInteger downloadDone = 0;
    NSInteger total = tasks.count;
    __weak typeof(self) weakSelf = self;

    for (ZL2V13ModUpdateTask *task in tasks) {
        NSDictionary *primaryFile = task.targetVersion.primaryFile;
        if (![primaryFile isKindOfClass:[NSDictionary class]]) { task.downloadSucceeded = NO; continue; }
        NSString *urlString = [primaryFile[@"url"] isKindOfClass:[NSString class]] ? primaryFile[@"url"] : nil;
        NSString *fileName = [primaryFile[@"filename"] isKindOfClass:[NSString class]] ? primaryFile[@"filename"] : nil;
        NSDictionary *hashes = [primaryFile[@"hashes"] isKindOfClass:[NSDictionary class]] ? primaryFile[@"hashes"] : nil;
        NSString *sha1 = nil;
        if ([hashes[@"sha1"] isKindOfClass:[NSString class]]) sha1 = hashes[@"sha1"];
        NSURL *url = urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;
        if (!url || fileName.length == 0) { task.downloadSucceeded = NO; continue; }

        dispatch_group_enter(group);
        dispatch_async(queue, ^{
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            PLDownloadRequest *request = [[PLDownloadRequest alloc] init];
            // 镜像候选列表（官方 CDN + 镜像，按用户策略排序）
            request.candidateURLs = [PLMirrorCenter candidateURLsForOriginalURL:url
                                                                   resourceType:PLMirrorResourceTypeAssetDownload];
            request.expectedSHA1 = sha1.length > 0 ? sha1 : nil;
            request.destinationPath = [tempDir stringByAppendingPathComponent:fileName];
            request.taskIdentifier = [NSString stringWithFormat:@"modupdate-%@", [[NSUUID UUID] UUIDString]];
            request.allowZipFallbackCheck = YES;   // 无 SHA1 时 zip EOCD 兜底
            [[PLDownloadClient sharedClient] startRequest:request
                                                 progress:nil
                                                    speed:nil
                                               completion:^(BOOL success, NSError *error) {
                if (success) {
                    task.downloadSucceeded = YES;
                    task.tempPath = request.destinationPath;
                } else {
                    task.downloadSucceeded = NO;
                    task.tempPath = nil;
                    NSLog(@"[ZL2VersionPages] Task343 update download failed (%@): %@", fileName, error);
                }
                NSInteger done;
                @synchronized(progressLock) { downloadDone++; done = downloadDone; }
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf ameV13_setBusy:YES
                                        text:[NSString stringWithFormat:localize(@"resman.mods.update.downloading", nil), (long)done, (long)total]];
                });
                dispatch_semaphore_signal(semaphore);
                dispatch_group_leave(group);
            }];
        });
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            return;
        }
        [strongSelf ameV13_setBusy:YES text:localize(@"resman.mods.update.replacing", nil)];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSFileManager *fm = [NSFileManager defaultManager];
            NSInteger successCount = 0;
            NSInteger failCount = 0;
            for (ZL2V13ModUpdateTask *task in tasks) {
                NSString *fileName = task.result.localFilePath.lastPathComponent ?: localize(@"resman.common.unknown_file", nil);
                if (!task.downloadSucceeded || task.tempPath.length == 0) { failCount++; continue; }
                // 下载文件名优先（新版本文件名可能变化）
                NSDictionary *primaryFile = task.targetVersion.primaryFile;
                NSString *downloadName = [primaryFile isKindOfClass:[NSDictionary class]]
                    ? ([primaryFile[@"filename"] isKindOfClass:[NSString class]] ? primaryFile[@"filename"] : nil)
                    : nil;
                if (downloadName.length > 0) fileName = downloadName;
                NSString *oldPath = task.result.localFilePath;
                NSString *oldDir = [oldPath stringByDeletingLastPathComponent];
                // 旧文件处于禁用状态（.disabled 后缀）时，新文件同样禁用，保留用户意图
                BOOL keepDisabled = [oldPath.lowercaseString hasSuffix:@".disabled"];
                NSString *newPath = [oldDir stringByAppendingPathComponent:fileName];
                if (keepDisabled && ![newPath.lowercaseString hasSuffix:@".disabled"]) {
                    newPath = [newPath stringByAppendingString:@".disabled"];
                }
                @try {
                    if ([fm fileExistsAtPath:oldPath]) [fm removeItemAtPath:oldPath error:nil];
                    if (![newPath isEqualToString:oldPath] && [fm fileExistsAtPath:newPath]) [fm removeItemAtPath:newPath error:nil];
                    NSError *moveError = nil;
                    if ([fm moveItemAtPath:task.tempPath toPath:newPath error:&moveError]) {
                        successCount++;
                        task.tempPath = nil;
                    } else {
                        failCount++;
                        NSLog(@"[ZL2VersionPages] Task343 update replace failed (%@): %@", fileName, moveError);
                    }
                } @catch (NSException *exception) {
                    failCount++;
                    NSLog(@"[ZL2VersionPages] Task343 update replace exception (%@): %@", fileName, exception);
                }
            }
            [fm removeItemAtPath:tempDir error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) innerSelf = weakSelf;
                if (!innerSelf) return;
                [innerSelf.ameV13_updateResults removeAllObjects];
                [innerSelf ameV13_setBusy:NO text:nil];
                [innerSelf ameV13_reloadContent];
                [innerSelf ameV13_showAlertMessage:[NSString stringWithFormat:localize(@"resman.mods.update.done_message", nil),
                                                    (long)successCount, (long)failCount, (long)skipped]];
            });
        });
    });
}

#pragma mark 去下载（Task265/324：ZL2 下载中心模组轨直达）

- (void)ameV13_openDownloadCenter {
    ZL2DownloadViewController *dvc = [[ZL2DownloadViewController alloc] init];
    dvc.selectedIndex = 2;   // 模组轨
    dvc.targetProfileName = self.ameV13_profileName;
    [self.navigationController pushViewController:dvc animated:YES];
}

#pragma mark 加载器识别（旧页 ame288 同语义：实例名启发式推断 + 错配判定）

- (NSString *)ameV13_profileLoaderForDisplay {
    NSDictionary *prof = PLProfiles.current.profiles[self.ameV13_profileName] ?: @{};
    NSString *vid = [prof isKindOfClass:[NSDictionary class]] ? prof[@"lastVersionId"] : nil;
    if (vid.length == 0) return @"";
    NSDictionary *parsed = [ModpackExportService parseVersionId:vid];
    NSString *loader = parsed[@"loader"];
    return [loader isKindOfClass:[NSString class]] ? (loader.lowercaseString ?: @"") : @"";
}

- (BOOL)ameV13_mod:(ModItem *)mod mismatchesProfileLoader:(NSString *)loader {
    if (loader.length == 0) return NO;
    NSString *l = loader.lowercaseString;
    BOOL wantsFabric = [l containsString:@"fabric"];
    BOOL wantsNeo = [l containsString:@"neoforge"];
    BOOL wantsForge = [l containsString:@"forge"] && !wantsNeo;
    // ModItem.isFabric/isForge/isNeoForge 由元数据解析填充；未解析出家族
    // 信息（纯 jar 无清单）不误报
    BOOL familyKnown = mod.isFabric || mod.isForge || mod.isNeoForge;
    if (!familyKnown) return NO;
    if (wantsNeo) return !mod.isNeoForge;
    if (wantsForge) return !mod.isForge;
    if (wantsFabric) return !mod.isFabric;
    return NO;
}

#pragma mark 筛选/排序 chips

- (void)ameV13_filterChipTapped:(ZL2M3FilterChip *)sender {
    _ameV13_filterMode = sender.tag;
    for (ZL2M3FilterChip *chip in _ameV13_filterChips) {
        chip.selected = (chip.tag == sender.tag);
    }
    [self ameV13_applyFilter];
}

- (void)ameV13_sortChipTapped:(ZL2M3FilterChip *)sender {
    _ameV13_sortMode = (sender.tag == 101) ? 1 : 0;
    [self ameV13_refreshSortChips];
    [self ameV13_applyFilter];
}

- (void)ameV13_refreshSortChips {
    _ameV13_sortNameChip.selected = (_ameV13_sortMode == 0);
    _ameV13_sortTimeChip.selected = (_ameV13_sortMode == 1);
}

@end

#pragma mark - ③ 存档管理

@interface ZL2VersionSavesPage () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIStackView *ameV13_contentStack;
@property (nonatomic, strong) UIStackView *ameV13_cardsStack;
@property (nonatomic, strong) NSCache *ameV13_iconCache;
@property (nonatomic, copy) NSArray<NSDictionary *> *ameV13_rows;
@end

@implementation ZL2VersionSavesPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    _ameV13_iconCache = [NSCache new];

    UIControl *importButton = [self ameV13_iconButtonWithImageName:@"square.and.arrow.down"
                                                          fallback:@"tray.and.arrow.down"
                                                             size:32
                                                     accessibility:localize(@"resman.worlds.import", nil)
                                                            action:^{ [self ameV13_showImportPicker]; }];
    NSString *pageTitle = @"存档";
    UIStackView *header = [self ameV13_pageHeaderRowWithTitle:pageTitle trailing:@[importButton]];
    _ameV13_contentStack = [self ameV13_installContentSkeleton];
    [_ameV13_contentStack addArrangedSubview:header];

    _ameV13_cardsStack = [[UIStackView alloc] init];
    _ameV13_cardsStack.axis = UILayoutConstraintAxisVertical;
    _ameV13_cardsStack.alignment = UIStackViewAlignmentFill;
    _ameV13_cardsStack.spacing = ZL2V13CardSpacing;
    _ameV13_cardsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_contentStack addArrangedSubview:_ameV13_cardsStack];
}

- (void)ameV13_reloadContent {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *savesDir = [self.ameV13_gameDir stringByAppendingPathComponent:@"saves"];
        NSArray<NSDictionary *> *dirs = [self ameV13_enumerateDirectory:savesDir filesOnly:NO extensions:nil];
        NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
        for (NSDictionary *dirInfo in dirs) {
            NSString *path = dirInfo[@"path"];
            NSString *folderName = dirInfo[@"name"];
            NSDate *modified = dirInfo[@"modified"];

            // level.dat 只读解析（失败显示文件名不炸）：LevelName / LastPlayed
            NSString *levelName = nil;
            double lastPlayedSec = 0;
            NSData *levelData = [NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:@"level.dat"]];
            if (levelData.length > 0) {
                ZL2NBTTag *root = [ZL2VersionNBT parseCompressedData:levelData error:nil];
                ZL2NBTTag *dataTag = [root tagForKey:@"Data"];
                NSString *nameValue = [dataTag stringForKey:@"LevelName"];
                if ([nameValue isKindOfClass:[NSString class]]) levelName = nameValue;
                ZL2NBTTag *playedTag = [dataTag tagForKey:@"LastPlayed"];
                if (playedTag && [playedTag.value isKindOfClass:[NSNumber class]]) {
                    lastPlayedSec = [(NSNumber *)playedTag.value doubleValue] / 1000.0;  // Java ms → s
                }
            }
            NSDate *rowModified = modified;
            if (!rowModified) rowModified = [NSDate date];
            [rows addObject:@{
                @"folder": folderName,
                @"path": path,
                @"displayName": (levelName.length > 0 ? levelName : folderName),
                @"lastPlayed": @(lastPlayedSec),
                @"modified": rowModified,
                @"iconPath": [path stringByAppendingPathComponent:@"icon.png"],
            }];
        }
        // 按上次游玩降序（最近先看）
        [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [b[@"lastPlayed"] compare:a[@"lastPlayed"]];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.ameV13_rows = rows;
            [self ameV13_rebuildCards];
        });
    });
}

- (void)ameV13_rebuildCards {
    [self ameV13_clearStack:_ameV13_cardsStack];
    if (self.ameV13_rows.count == 0) {
        NSString *emptyText = localize(@"resman.worlds.empty", nil);
        [_ameV13_cardsStack addArrangedSubview:[self ameV13_emptyStateWithSymbol:@"globe" fallback:@"circle" text:emptyText]];
        return;
    }
    for (NSDictionary *row in self.ameV13_rows) {
        [_ameV13_cardsStack addArrangedSubview:[self ameV13_cardForRow:row]];
    }
}

- (UIView *)ameV13_cardForRow:(NSDictionary *)row {
    // 42pt icon.png（有则显示，降采样 + NSCache；无则 globe 占位盒）
    UIView *iconHolder = nil;
    UIImage *icon = ZL2V13ThumbnailAtPath(row[@"iconPath"], 42.0);
    if (icon) {
        NSString *cacheKey = [NSString stringWithFormat:@"save42|%@", row[@"path"]];
        [self.ameV13_iconCache setObject:icon forKey:cacheKey];
        UIImageView *iconView = [[UIImageView alloc] initWithImage:icon];
        iconView.contentMode = UIViewContentModeScaleAspectFill;
        iconView.clipsToBounds = YES;
        iconView.layer.cornerRadius = [ZL2Theme radiusM];
        iconView.layer.masksToBounds = YES;
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [iconView.widthAnchor constraintEqualToConstant:42],
            [iconView.heightAnchor constraintEqualToConstant:42],
        ]];
        iconHolder = iconView;
    } else {
        iconHolder = [self ameV13_iconBoxWithSymbol:@"globe" fallback:@"circle" size:42 iconSize:24];
    }

    // 详情行：LastPlayed（level.dat）优先，缺省回退目录 mtime
    NSString *detailText = nil;
    double lastPlayed = [row[@"lastPlayed"] doubleValue];
    if (lastPlayed > 0) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:lastPlayed];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale currentLocale];
        fmt.doesRelativeDateFormatting = YES;
        fmt.dateStyle = NSDateFormatterShortStyle;
        fmt.timeStyle = NSDateFormatterShortStyle;
        detailText = [NSString stringWithFormat:localize(@"resman.worlds.last_played", nil), [fmt stringFromDate:date]];
    } else {
        NSDate *modified = row[@"modified"];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale currentLocale];
        fmt.doesRelativeDateFormatting = YES;
        fmt.dateStyle = NSDateFormatterShortStyle;
        fmt.timeStyle = NSDateFormatterShortStyle;
        detailText = [NSString stringWithFormat:localize(@"resman.worlds.last_played", nil), [fmt stringFromDate:modified]];
    }
    UIStackView *textStack = [self ameV13_textStackWithTitle:row[@"displayName"] detail:detailText];
    UIView *spacer = [self ameV13_spacer];

    NSString *folderName = row[@"folder"];
    NSString *folderPath = row[@"path"];
    UIControl *renameButton = [self ameV13_iconButtonWithImageName:@"pencil"
                                                          fallback:@"square.and.pencil"
                                                             size:32
                                                     accessibility:@"重命名"
                                                            action:^{ [self ameV13_actionRenameSave:folderName path:folderPath]; }];
    UIControl *deleteButton = [self ameV13_iconButtonWithImageName:@"trash"
                                                          fallback:@"trash.fill"
                                                             size:32
                                                     accessibility:localize(@"resman.common.delete", nil)
                                                            action:^{ [self ameV13_confirmDeleteSave:folderName path:folderPath]; }];

    UIStackView *wrap = [self ameV13_rowCardWithViews:@[iconHolder, textStack, spacer, renameButton, deleteButton]
                                            alignment:UIStackViewAlignmentCenter];
    return wrap;
}

#pragma mark 存档：重命名 / 删除 / 导入

- (void)ameV13_actionRenameSave:(NSString *)folderName path:(NSString *)path {
    NSString *alertTitle = @"重命名存档";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = folderName;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    NSString *cancelText = localize(@"resman.common.cancel", nil);
    NSString *okText = localize(@"i18n_str_44", nil);
    [alert addAction:[UIAlertAction actionWithTitle:cancelText style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:okText style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newName = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (newName.length == 0 || [newName isEqualToString:folderName]) return;
        NSString *newPath = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:newName];
        if ([NSFileManager.defaultManager fileExistsAtPath:newPath]) {
            [self ameV13_showAlertMessage:localize(@"i18n_str_1289", nil)];
            return;
        }
        NSError *err = nil;
        if ([NSFileManager.defaultManager moveItemAtPath:path toPath:newPath error:&err]) {
            [self ameV13_reloadContent];
        } else {
            [self ameV13_showAlertMessage:[NSString stringWithFormat:@"%@: %@", localize(@"resman.common.operation_failed", nil), ZL2V13ErrorText(err)]];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)ameV13_confirmDeleteSave:(NSString *)folderName path:(NSString *)path {
    NSString *bodyText = [NSString stringWithFormat:localize(@"resman.worlds.delete_message", nil), folderName];
    __weak typeof(self) weakSelf = self;
    NSString *confirmTitle = localize(@"resman.common.confirm_delete", nil);
    NSString *deleteText = localize(@"resman.common.delete", nil);
    [ZL2M3Dialog showTitle:confirmTitle
                      body:bodyText
              confirmTitle:deleteText
                destructive:YES
                 onConfirm:^{
        NSError *err = nil;
        if ([NSFileManager.defaultManager removeItemAtPath:path error:&err]) {
            [weakSelf ameV13_reloadContent];
        } else {
            NSString *failedText = localize(@"resman.common.delete_failed", nil);
            [weakSelf ameV13_showAlertMessage:[NSString stringWithFormat:@"%@: %@", failedText, ZL2V13ErrorText(err)]];
        }
    }
                   onCancel:nil];
}

- (void)ameV13_showImportPicker {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeZIP] asCopy:YES];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    NSString *savesDir = [self.ameV13_gameDir stringByAppendingPathComponent:@"saves"];
    [NSFileManager.defaultManager createDirectoryAtPath:savesDir withIntermediateDirectories:YES attributes:nil error:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSInteger ok = 0;
        NSInteger fail = 0;
        for (NSURL *url in urls) {
            BOOL success = [self ameV13_extractWorldZipAt:url.path toSavesDir:savesDir worldName:url.lastPathComponent error:nil];
            if (success) ok++; else fail++;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (fail > 0) {
                NSString *resultText = [NSString stringWithFormat:localize(@"resman.common.import_result", nil), (long)ok, (long)fail];
                [self ameV13_showAlertMessage:resultText];
            }
            [self ameV13_reloadContent];
        });
    });
}

/// WorldService.m extractWorldZipAt:toSavesDir:worldName: 同款解压语义：
/// ① 全部条目共享同一顶层目录 → 直接解压进 saves/；② 散装 → 以 zip 名建
/// 子目录再解压（重名追加 _1 后缀）；③ 解压失败清理空目录；④ level.dat
/// 缺失仅记日志不阻断（部分 zip 层级更深）。
- (BOOL)ameV13_extractWorldZipAt:(NSString *)zipPath
                      toSavesDir:(NSString *)savesDir
                       worldName:(NSString *)worldName
                           error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];

    // ① 顶层目录检测（__MACOSX 元数据跳过）
    NSError *listErr = nil;
    UZKArchive *listArchive = [[UZKArchive alloc] initWithPath:zipPath error:&listErr];
    if (!listArchive || listErr) {
        if (error) *error = listErr;
        return NO;
    }
    NSArray<NSString *> *fileNames = [listArchive listFilenames:&listErr];
    if (!fileNames || fileNames.count == 0) {
        if (error) *error = listErr;
        return NO;
    }
    NSMutableSet<NSString *> *topLevels = [NSMutableSet set];
    for (NSString *entryName in fileNames) {
        if (entryName.length == 0) continue;
        if ([entryName hasPrefix:@"__MACOSX/"]) continue;
        NSString *firstComponent = [entryName componentsSeparatedByString:@"/"].firstObject;
        if (firstComponent.length == 0) continue;
        [topLevels addObject:firstComponent];
    }
    NSString *topLevelDir = (topLevels.count == 1) ? [topLevels anyObject] : nil;

    NSString *extractTargetDir = nil;
    NSString *finalWorldDir = nil;
    if (topLevelDir) {
        extractTargetDir = savesDir;
        finalWorldDir = [savesDir stringByAppendingPathComponent:topLevelDir];
        if ([fm fileExistsAtPath:finalWorldDir]) {
            // 顶层同名世界已存在：以 zip 名（去 .zip）追加数字后缀建目录再解压
            NSString *baseName = worldName;
            if ([baseName.lowercaseString hasSuffix:@".zip"]) {
                baseName = [baseName substringToIndex:baseName.length - @".zip".length];
            }
            NSString *candidate = [savesDir stringByAppendingPathComponent:baseName];
            NSInteger suffix = 1;
            while ([fm fileExistsAtPath:candidate]) {
                candidate = [savesDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%ld", baseName, (long)suffix]];
                suffix++;
            }
            [fm createDirectoryAtPath:candidate withIntermediateDirectories:YES attributes:nil error:nil];
            extractTargetDir = candidate;
            finalWorldDir = candidate;
        }
    } else {
        // ② 散装：以 zip 名建子目录（重名追加后缀）
        NSString *baseName = worldName.length > 0 ? worldName : [zipPath lastPathComponent];
        if ([baseName.lowercaseString hasSuffix:@".zip"]) {
            baseName = [baseName substringToIndex:baseName.length - @".zip".length];
        }
        NSString *candidate = [savesDir stringByAppendingPathComponent:baseName];
        NSInteger suffix = 1;
        while ([fm fileExistsAtPath:candidate]) {
            candidate = [savesDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%ld", baseName, (long)suffix]];
            suffix++;
        }
        extractTargetDir = candidate;
        finalWorldDir = candidate;
        NSError *createError = nil;
        if (![fm createDirectoryAtPath:extractTargetDir withIntermediateDirectories:YES attributes:nil error:&createError]) {
            if (error) *error = createError;
            return NO;
        }
    }

    // 解压（UnzipKit，WorldService 同款 API）
    NSError *archiveError = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:zipPath error:&archiveError];
    if (!archive || archiveError) {
        if (error) *error = archiveError;
        return NO;
    }
    NSError *extractError = nil;
    BOOL success = [archive extractFilesTo:extractTargetDir overwrite:YES error:&extractError];
    if (!success || extractError) {
        if (error) *error = extractError;
        if (!topLevelDir && [fm fileExistsAtPath:extractTargetDir]) {
            NSArray<NSString *> *leftover = [fm contentsOfDirectoryAtPath:extractTargetDir error:nil];
            if (leftover.count == 0) [fm removeItemAtPath:extractTargetDir error:nil];
        }
        return NO;
    }
    NSString *levelDatCheck = [finalWorldDir stringByAppendingPathComponent:@"level.dat"];
    if (![fm fileExistsAtPath:levelDatCheck]) {
        NSLog(@"[ZL2VersionPages] warning: level.dat not found at %@ after extraction", finalWorldDir);
    }
    NSLog(@"[ZL2VersionPages] save zip extracted to: %@", finalWorldDir);
    return YES;
}

@end

#pragma mark - ④ 资源包 / ⑤ 光影（共用行卡逻辑）

/// 资源包/光影共用的本地包列表页：目录枚举口径与导入内容类型由子类给参。
@interface ZL2VersionPacksPageBase () <UIDocumentPickerDelegate>   // 类扩展（主体已在 ZL2VersionPages.h；7.0-UI-13-r2 重复接口定义根除）
@property (nonatomic, strong) UIStackView *ameV13_contentStack;
@property (nonatomic, strong) UIStackView *ameV13_cardsStack;
@property (nonatomic, strong) UILabel *ameV13_countLabel;
@property (nonatomic, copy) NSArray<NSDictionary *> *ameV13_rows;
- (NSString *)ameV13_pageTitle;               // 页名
- (NSString *)ameV13_folderName;              // 子目录名（resourcepacks / shaderpacks）
- (BOOL)ameV13_acceptsDirectories;            // 资源包=目录+zip；光影=仅 zip
- (NSString *)ameV13_emptyText;               // 空态文案
- (NSString *)ameV13_importA11y;              // 导入钮 a11y
- (NSString *)ameV13_emptySymbol;             // 空态符号
- (NSString *)ameV13_emptyFallback;           // 空态兜底符号
- (void)ameV13_configureImportPicker:(UIDocumentPickerViewController *)picker;  // 子类定制（光影限定 zip）
@end

@implementation ZL2VersionPacksPageBase

- (NSString *)ameV13_pageTitle { return @""; }
- (NSString *)ameV13_folderName { return @""; }
- (BOOL)ameV13_acceptsDirectories { return NO; }
- (NSString *)ameV13_emptyText { return @""; }
- (NSString *)ameV13_importA11y { return @""; }
- (NSString *)ameV13_emptySymbol { return @"archivebox"; }
- (NSString *)ameV13_emptyFallback { return @"circle"; }
- (void)ameV13_configureImportPicker:(UIDocumentPickerViewController *)picker { }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    UILabel *countLabel = [[UILabel alloc] init];
    countLabel.font = [ZL2Theme fontLabelMedium];
    countLabel.textColor = [ZL2Theme onSurfaceVariant];
    countLabel.numberOfLines = 1;
    countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _ameV13_countLabel = countLabel;

    UIControl *importButton = [self ameV13_iconButtonWithImageName:@"square.and.arrow.down"
                                                          fallback:@"tray.and.arrow.down"
                                                             size:32
                                                     accessibility:[self ameV13_importA11y]
                                                            action:^{ [self ameV13_showImportPicker]; }];
    UIStackView *header = [self ameV13_pageHeaderRowWithTitle:[self ameV13_pageTitle] trailing:@[countLabel, importButton]];
    _ameV13_contentStack = [self ameV13_installContentSkeleton];
    [_ameV13_contentStack addArrangedSubview:header];

    _ameV13_cardsStack = [[UIStackView alloc] init];
    _ameV13_cardsStack.axis = UILayoutConstraintAxisVertical;
    _ameV13_cardsStack.alignment = UIStackViewAlignmentFill;
    _ameV13_cardsStack.spacing = ZL2V13CardSpacing;
    _ameV13_cardsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_contentStack addArrangedSubview:_ameV13_cardsStack];
}

- (void)ameV13_reloadContent {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *dir = [self.ameV13_gameDir stringByAppendingPathComponent:[self ameV13_folderName]];
        NSArray<NSDictionary *> *files = [self ameV13_enumerateDirectory:dir filesOnly:YES extensions:@[@".zip"]];
        NSArray<NSDictionary *> *dirs = [self ameV13_acceptsDirectories]
            ? [self ameV13_enumerateDirectory:dir filesOnly:NO extensions:nil] : @[];
        NSMutableArray<NSDictionary *> *rows = [NSMutableArray arrayWithArray:dirs];
        [rows addObjectsFromArray:files];
        [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"name"] compare:b[@"name"]];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.ameV13_rows = rows;
            self.ameV13_countLabel.text = [NSString stringWithFormat:@"共 %ld 个", (long)rows.count];
            [self ameV13_rebuildCards];
        });
    });
}

- (void)ameV13_rebuildCards {
    [self ameV13_clearStack:_ameV13_cardsStack];
    if (self.ameV13_rows.count == 0) {
        [_ameV13_cardsStack addArrangedSubview:[self ameV13_emptyStateWithSymbol:[self ameV13_emptySymbol]
                                                                        fallback:[self ameV13_emptyFallback]
                                                                            text:[self ameV13_emptyText]]];
        return;
    }
    for (NSDictionary *row in self.ameV13_rows) {
        [_ameV13_cardsStack addArrangedSubview:[self ameV13_rowCardForPack:row]];
    }
}

- (UIView *)ameV13_rowCardForPack:(NSDictionary *)row {
    NSString *name = row[@"name"];
    NSString *path = row[@"path"];
    BOOL isDir = [row[@"isDir"] boolValue];

    NSString *symbol = isDir ? @"folder" : @"doc.zipper";
    NSString *fallbackSymbol = isDir ? @"circle" : @"doc";
    UIView *iconBox = [self ameV13_iconBoxWithSymbol:symbol fallback:fallbackSymbol size:42 iconSize:22];
    UIStackView *textStack = [self ameV13_textStackWithTitle:name detail:ZL2V13ByteCount([row[@"size"] unsignedLongLongValue])];
    UIView *spacer = [self ameV13_spacer];

    NSString *rowName = name;
    NSString *rowPath = path;
    __weak typeof(self) weakSelf = self;
    UIControl *renameButton = [self ameV13_iconButtonWithImageName:@"pencil"
                                                          fallback:@"square.and.pencil"
                                                             size:32
                                                     accessibility:@"重命名"
                                                            action:^{
        [weakSelf ameV13_actionRenamePack:rowName path:rowPath];
    }];
    UIControl *deleteButton = [self ameV13_iconButtonWithImageName:@"trash"
                                                          fallback:@"trash.fill"
                                                             size:32
                                                     accessibility:localize(@"resman.common.delete", nil)
                                                            action:^{
        NSString *bodyText = [NSString stringWithFormat:localize(@"resman.common.delete_message_irreversible", nil), rowName];
        NSString *confirmTitle = localize(@"resman.common.confirm_delete", nil);
        NSString *deleteText = localize(@"resman.common.delete", nil);
        [ZL2M3Dialog showTitle:confirmTitle
                          body:bodyText
                  confirmTitle:deleteText
                    destructive:YES
                     onConfirm:^{
            NSError *err = nil;
            if ([NSFileManager.defaultManager removeItemAtPath:rowPath error:&err]) {
                [weakSelf ameV13_reloadContent];
            } else {
                NSString *failedText = localize(@"resman.common.delete_failed", nil);
                [weakSelf ameV13_showAlertMessage:[NSString stringWithFormat:@"%@: %@", failedText, ZL2V13ErrorText(err)]];
            }
        }
                       onCancel:nil];
    }];

    UIStackView *wrap = [self ameV13_rowCardWithViews:@[iconBox, textStack, spacer, renameButton, deleteButton]
                                            alignment:UIStackViewAlignmentCenter];
    return wrap;
}

- (void)ameV13_actionRenamePack:(NSString *)name path:(NSString *)path {
    NSString *alertTitle = @"重命名";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = name;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    NSString *cancelText = localize(@"resman.common.cancel", nil);
    NSString *okText = localize(@"i18n_str_44", nil);
    [alert addAction:[UIAlertAction actionWithTitle:cancelText style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:okText style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newName = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (newName.length == 0 || [newName isEqualToString:name]) return;
        // 保留扩展名（重命名语义：改主名，后缀不动）
        NSString *ext = path.pathExtension;
        if (ext.length > 0 && ![newName.lowercaseString hasSuffix:[NSString stringWithFormat:@".%@", ext.lowercaseString]]) {
            NSString *withExt = [newName stringByAppendingPathExtension:ext];
            if (withExt) newName = withExt;
        }
        NSString *newPath = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:newName];
        if ([NSFileManager.defaultManager fileExistsAtPath:newPath]) {
            [self ameV13_showAlertMessage:localize(@"i18n_str_1289", nil)];
            return;
        }
        NSError *err = nil;
        if ([NSFileManager.defaultManager moveItemAtPath:path toPath:newPath error:&err]) {
            [self ameV13_reloadContent];
        } else {
            [self ameV13_showAlertMessage:[NSString stringWithFormat:@"%@: %@", localize(@"resman.common.operation_failed", nil), ZL2V13ErrorText(err)]];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)ameV13_showImportPicker {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeZIP] asCopy:YES];
    picker.allowsMultipleSelection = YES;
    [self ameV13_configureImportPicker:picker];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    NSString *dir = [self.ameV13_gameDir stringByAppendingPathComponent:[self ameV13_folderName]];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSInteger ok = 0;
        NSInteger fail = 0;
        for (NSURL *url in urls) {
            NSString *dest = [dir stringByAppendingPathComponent:url.lastPathComponent];
            NSError *err = nil;
            if ([NSFileManager.defaultManager copyItemAtPath:url.path toPath:dest error:&err]) {
                ok++;
            } else {
                fail++;
                NSLog(@"[ZL2VersionPages] pack import failed %@: %@", url.lastPathComponent, err.localizedDescription);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (fail > 0) {
                NSString *resultText = [NSString stringWithFormat:localize(@"resman.common.import_result", nil), (long)ok, (long)fail];
                [self ameV13_showAlertMessage:resultText];
            }
            [self ameV13_reloadContent];
        });
    });
}

@end

// ZL2VersionResourcePacksPage / ZL2VersionShadersPage 主体已在 ZL2VersionPages.h
//（7.0-UI-13-r2：.m 内重复 @interface 根除——空体重声明即 duplicate interface 错误）

@implementation ZL2VersionResourcePacksPage
- (NSString *)ameV13_pageTitle { return @"资源包"; }
- (NSString *)ameV13_folderName { return @"resourcepacks"; }
- (BOOL)ameV13_acceptsDirectories { return YES; }
- (NSString *)ameV13_emptyText { return localize(@"resman.resourcepacks.empty", nil); }
- (NSString *)ameV13_importA11y { return localize(@"resman.resourcepacks.import", nil); }
- (NSString *)ameV13_emptySymbol { return @"paintbrush"; }
- (NSString *)ameV13_emptyFallback { return @"photo"; }
@end

@implementation ZL2VersionShadersPage
- (NSString *)ameV13_pageTitle { return @"光影"; }
- (NSString *)ameV13_folderName { return @"shaderpacks"; }
- (BOOL)ameV13_acceptsDirectories { return NO; }
- (NSString *)ameV13_emptyText { return localize(@"resman.shaders.empty", nil); }
- (NSString *)ameV13_importA11y { return localize(@"resman.shaders.import", nil); }
- (NSString *)ameV13_emptySymbol { return @"lightbulb"; }
- (NSString *)ameV13_emptyFallback { return @"circle"; }
@end

#pragma mark - ⑥ 截图

@interface ZL2VersionScreenshotsPage () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView *ameV13_gridView;
@property (nonatomic, strong) UIView *ameV13_emptyView;
@property (nonatomic, strong) NSCache *ameV13_thumbCache;
@property (nonatomic, copy) NSArray<NSDictionary *> *ameV13_rows;
@end

@implementation ZL2VersionScreenshotsPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    _ameV13_thumbCache = [NSCache new];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 8;
    layout.sectionInset = UIEdgeInsetsZero;
    _ameV13_gridView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _ameV13_gridView.backgroundColor = [UIColor clearColor];
    _ameV13_gridView.dataSource = self;
    _ameV13_gridView.delegate = self;
    _ameV13_gridView.alwaysBounceVertical = YES;
    _ameV13_gridView.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_gridView registerClass:[ZL2V13ScreenshotCell class] forCellWithReuseIdentifier:@"ZL2V13Shot"];
    [self.view addSubview:_ameV13_gridView];
    [NSLayoutConstraint activateConstraints:@[
        [_ameV13_gridView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_ameV13_gridView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_ameV13_gridView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_ameV13_gridView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    _ameV13_emptyView = [self ameV13_emptyStateWithSymbol:@"photo.on.rectangle" fallback:@"photo" text:@"还没有截图"];
    _ameV13_emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    _ameV13_emptyView.hidden = YES;
    [self.view addSubview:_ameV13_emptyView];
    [NSLayoutConstraint activateConstraints:@[
        [_ameV13_emptyView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_ameV13_emptyView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_ameV13_emptyView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_ameV13_emptyView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 3 列网格（任务规格；flow layout 最简实现）
    CGFloat width = _ameV13_gridView.bounds.size.width;
    if (width <= 0) return;
    CGFloat itemWidth = ((width - 16.0) / 3.0);
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)_ameV13_gridView.collectionViewLayout;
    CGFloat side = MAX(80.0, itemWidth);
    if (layout.itemSize.width != side) {
        layout.itemSize = CGSizeMake(side, side);
        [layout invalidateLayout];
    }
}

- (void)ameV13_reloadContent {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *dir = [self.ameV13_gameDir stringByAppendingPathComponent:@"screenshots"];
        NSArray<NSDictionary *> *rows = [self ameV13_enumerateDirectory:dir filesOnly:YES extensions:@[@".png"]];
        rows = [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [b[@"modified"] compare:a[@"modified"]];  // 新截图在前
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.ameV13_rows = rows;
            self.ameV13_emptyView.hidden = (rows.count > 0);
            _ameV13_gridView.hidden = (rows.count == 0);
            [_ameV13_gridView reloadData];
        });
    });
}

#pragma mark UICollectionView

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.ameV13_rows.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ZL2V13ScreenshotCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ZL2V13Shot" forIndexPath:indexPath];
    NSDictionary *row = self.ameV13_rows[indexPath.item];
    NSString *path = row[@"path"];
    NSString *cacheKey = [NSString stringWithFormat:@"shot240|%@", path];
    UIImage *thumb = [self.ameV13_thumbCache objectForKey:cacheKey];
    if (!thumb) {
        thumb = ZL2V13ThumbnailAtPath(path, 240.0);
        if (thumb) [self.ameV13_thumbCache setObject:thumb forKey:cacheKey];
    }
    cell.thumbView.image = thumb;
    cell.nameLabel.text = row[@"name"];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    NSDictionary *row = self.ameV13_rows[indexPath.item];
    ZL2V13ImageViewer *viewer = [[ZL2V13ImageViewer alloc] init];
    viewer.ameV13_imagePath = row[@"path"];
    viewer.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:viewer animated:YES completion:nil];
}

@end

#pragma mark - ⑦ 服务器列表

@interface ZL2VersionServersPage ()
@property (nonatomic, strong) UIStackView *ameV13_contentStack;
@property (nonatomic, strong) UIStackView *ameV13_cardsStack;
@property (nonatomic, copy) NSArray<NSDictionary *> *ameV13_rows;   // {name, ip, tag}
@property (nonatomic, strong) ZL2NBTTag *ameV13_rootTag;            // 全量回写基底（icon 等未触碰标签保留）
@end

@implementation ZL2VersionServersPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    // 加号添加（ZL2 ServerListScreen FAB 语义 → 页头图标钮）
    UIControl *addButton = [self ameV13_iconButtonWithImageName:@"plus"
                                                       fallback:@"plus.circle.fill"
                                                           size:32
                                                   accessibility:@"添加服务器"
                                                          action:^{ [self ameV13_actionAddServer]; }];
    NSString *pageTitle = @"服务器";
    UIStackView *header = [self ameV13_pageHeaderRowWithTitle:pageTitle trailing:@[addButton]];
    _ameV13_contentStack = [self ameV13_installContentSkeleton];
    [_ameV13_contentStack addArrangedSubview:header];

    _ameV13_cardsStack = [[UIStackView alloc] init];
    _ameV13_cardsStack.axis = UILayoutConstraintAxisVertical;
    _ameV13_cardsStack.alignment = UIStackViewAlignmentFill;
    _ameV13_cardsStack.spacing = ZL2V13CardSpacing;
    _ameV13_cardsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_contentStack addArrangedSubview:_ameV13_cardsStack];
}

- (NSString *)ameV13_serversDatPath {
    return [self.ameV13_gameDir stringByAppendingPathComponent:@"servers.dat"];
}

- (void)ameV13_reloadContent {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
        ZL2NBTTag *root = nil;
        NSData *data = [NSData dataWithContentsOfFile:[self ameV13_serversDatPath]];
        if (data.length > 0) {
            root = [ZL2VersionNBT parseCompressedData:data error:nil];
        }
        if (root) {
            ZL2NBTTag *serversTag = [root tagForKey:@"servers"];
            if (serversTag && serversTag.type == ZL2NBTTagTypeList && [serversTag.value isKindOfClass:[NSArray class]]) {
                for (ZL2NBTTag *item in (NSArray<ZL2NBTTag *> *)serversTag.value) {
                    if (item.type != ZL2NBTTagTypeCompound) continue;
                    NSString *nameValue = [item stringForKey:@"name"];
                    if (!nameValue) nameValue = @"";
                    NSString *ipValue = [item stringForKey:@"ip"];
                    if (!ipValue) ipValue = @"";
                    if (nameValue.length == 0) nameValue = @"未命名服务器";
                    [rows addObject:@{
                        @"name": nameValue,
                        @"ip": ipValue,
                        @"tag": item,   // 原始 Compound 保留（icon 等标签全量回写不丢）
                    }];
                }
            }
        } else if (data.length > 0) {
            NSLog(@"[ZL2VersionPages] servers.dat parse failed (kept file untouched)");
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.ameV13_rows = rows;
            self.ameV13_rootTag = root;
            [self ameV13_rebuildCards];
        });
    });
}

- (void)ameV13_rebuildCards {
    [self ameV13_clearStack:_ameV13_cardsStack];
    if (self.ameV13_rows.count == 0) {
        [_ameV13_cardsStack addArrangedSubview:[self ameV13_emptyStateWithSymbol:@"dns" fallback:@"network" text:@"暂无服务器"]];
        return;
    }
    for (NSUInteger i = 0; i < self.ameV13_rows.count; i++) {
        [_ameV13_cardsStack addArrangedSubview:[self ameV13_cardForRow:self.ameV13_rows[i] index:(NSInteger)i]];
    }
}

- (UIView *)ameV13_cardForRow:(NSDictionary *)row index:(NSInteger)index {
    UIView *iconBox = [self ameV13_iconBoxWithSymbol:@"dns" fallback:@"network" size:42 iconSize:22];
    UIStackView *textStack = [self ameV13_textStackWithTitle:row[@"name"] detail:row[@"ip"]];
    UIView *spacer = [self ameV13_spacer];

    __weak typeof(self) weakSelf = self;
    UIControl *editButton = [self ameV13_iconButtonWithImageName:@"pencil"
                                                        fallback:@"square.and.pencil"
                                                           size:32
                                                   accessibility:@"编辑"
                                                          action:^{ [weakSelf ameV13_actionEditServerAtIndex:index]; }];
    UIControl *deleteButton = [self ameV13_iconButtonWithImageName:@"trash"
                                                          fallback:@"trash.fill"
                                                             size:32
                                                   accessibility:localize(@"resman.common.delete", nil)
                                                          action:^{ [weakSelf ameV13_actionDeleteServerAtIndex:index]; }];
    UIStackView *wrap = [self ameV13_rowCardWithViews:@[iconBox, textStack, spacer, editButton, deleteButton]
                                            alignment:UIStackViewAlignmentCenter];
    return wrap;
}

#pragma mark 服务器：添加 / 编辑 / 删除（改动即全量回写）

- (void)ameV13_actionAddServer {
    [self ameV13_presentServerEditorWithName:@"" ip:@"" index:-1];
}

- (void)ameV13_actionEditServerAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.ameV13_rows.count) return;
    NSDictionary *row = self.ameV13_rows[index];
    [self ameV13_presentServerEditorWithName:row[@"name"] ip:row[@"ip"] index:index];
}

- (void)ameV13_presentServerEditorWithName:(NSString *)name ip:(NSString *)ip index:(NSInteger)index {
    NSString *alertTitle = (index < 0) ? @"添加服务器" : @"编辑服务器";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"名称";
        textField.text = name;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"IP 地址";
        textField.text = ip;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.keyboardType = UIKeyboardTypeURL;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    NSString *cancelText = localize(@"resman.common.cancel", nil);
    NSString *okText = localize(@"i18n_str_44", nil);
    [alert addAction:[UIAlertAction actionWithTitle:cancelText style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:okText style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newName = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *newIp = [alert.textFields.lastObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (newIp.length == 0) return;  // 无 IP 的条目无意义（ZL2 编辑器同约束）
        if (newName.length == 0) newName = newIp;
        [self ameV13_upsertServerWithName:newName ip:newIp index:index];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)ameV13_upsertServerWithName:(NSString *)name ip:(NSString *)ip index:(NSInteger)index {
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray arrayWithArray:self.ameV13_rows];
    if (index >= 0 && index < (NSInteger)rows.count) {
        NSDictionary *old = rows[index];
        id existingTag = old[@"tag"];
        if (![existingTag isKindOfClass:[ZL2NBTTag class]]) existingTag = [NSNull null];
        rows[index] = @{ @"name": name, @"ip": ip, @"tag": existingTag };
    } else {
        [rows addObject:@{ @"name": name, @"ip": ip, @"tag": [NSNull null] }];
    }
    self.ameV13_rows = rows;
    [self ameV13_rewriteServersDat];
    [self ameV13_rebuildCards];
}

- (void)ameV13_actionDeleteServerAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.ameV13_rows.count) return;
    NSDictionary *row = self.ameV13_rows[index];
    NSString *name = row[@"name"];
    NSString *bodyText = [NSString stringWithFormat:localize(@"resman.common.delete_message_irreversible", nil), name];
    __weak typeof(self) weakSelf = self;
    NSString *confirmTitle = localize(@"resman.common.confirm_delete", nil);
    NSString *deleteText = localize(@"resman.common.delete", nil);
    [ZL2M3Dialog showTitle:confirmTitle
                      body:bodyText
              confirmTitle:deleteText
                destructive:YES
                 onConfirm:^{
        NSMutableArray<NSDictionary *> *rows = [NSMutableArray arrayWithArray:weakSelf.ameV13_rows];
        if (index < (NSInteger)rows.count) {
            [rows removeObjectAtIndex:index];
            weakSelf.ameV13_rows = rows;
            [weakSelf ameV13_rewriteServersDat];
            [weakSelf ameV13_rebuildCards];
        }
    }
                   onCancel:nil];
}

/// 全量回写（ZL2 ServerListScreen「改动即全量回写」同语义）：
/// 根 Compound 保留解析产物全部子标签；servers List 重建（已存在的条目
/// 沿用原始 Compound tag——icon/隐藏字段不丢；新增条目构造 name/ip 双
/// String Compound）。写侧 NBT 字符串 = Java modified UTF-8（ZL2VersionNBT
/// 写端保证）；servers.dat_old 不做轮转（诚实边界）。
- (void)ameV13_rewriteServersDat {
    ZL2NBTTag *root = self.ameV13_rootTag;
    if (!root) {
        root = [[ZL2NBTTag alloc] init];
        root.type = ZL2NBTTagTypeCompound;
        root.name = @"";
        root.value = [NSMutableDictionary dictionary];
    }
    NSMutableDictionary<NSString *, ZL2NBTTag *> *rootChildren = root.value;
    if (![rootChildren isKindOfClass:[NSMutableDictionary class]]) {
        rootChildren = [NSMutableDictionary dictionary];
        root.value = rootChildren;
    }

    ZL2NBTTag *serversTag = [[ZL2NBTTag alloc] init];
    serversTag.type = ZL2NBTTagTypeList;
    serversTag.name = @"servers";
    NSMutableArray<ZL2NBTTag *> *items = [NSMutableArray array];
    for (NSDictionary *row in self.ameV13_rows) {
        ZL2NBTTag *compound = row[@"tag"];
        if (![compound isKindOfClass:[ZL2NBTTag class]] || compound.type != ZL2NBTTagTypeCompound) {
            compound = [[ZL2NBTTag alloc] init];
            compound.type = ZL2NBTTagTypeCompound;
            compound.name = nil;
            compound.value = [NSMutableDictionary dictionary];
        }
        NSMutableDictionary<NSString *, ZL2NBTTag *> *children = compound.value;
        if (![children isKindOfClass:[NSMutableDictionary class]]) {
            children = [NSMutableDictionary dictionary];
            compound.value = children;
        }
        ZL2NBTTag *nameTag = children[@"name"];
        if (!nameTag || nameTag.type != ZL2NBTTagTypeString) {
            nameTag = [[ZL2NBTTag alloc] init];
            nameTag.type = ZL2NBTTagTypeString;
            nameTag.name = @"name";
            children[@"name"] = nameTag;
        }
        nameTag.value = row[@"name"];
        ZL2NBTTag *ipTag = children[@"ip"];
        if (!ipTag || ipTag.type != ZL2NBTTagTypeString) {
            ipTag = [[ZL2NBTTag alloc] init];
            ipTag.type = ZL2NBTTagTypeString;
            ipTag.name = @"ip";
            children[@"ip"] = ipTag;
        }
        ipTag.value = row[@"ip"];
        [items addObject:compound];
    }
    serversTag.value = items;
    rootChildren[@"servers"] = serversTag;

    NSData *outData = [ZL2VersionNBT writeCompressedRootTag:root error:nil];
    if (!outData) {
        NSLog(@"[ZL2VersionPages] servers.dat rewrite failed (serialization)");
        [self ameV13_showAlertMessage:localize(@"resman.common.operation_failed", nil)];
        return;
    }
    BOOL ok = [outData writeToFile:[self ameV13_serversDatPath] options:NSDataWritingAtomic error:nil];
    if (!ok) {
        NSLog(@"[ZL2VersionPages] servers.dat write failed");
        [self ameV13_showAlertMessage:localize(@"resman.common.operation_failed", nil)];
        return;
    }
    NSLog(@"[ZL2VersionPages] servers.dat rewritten (%lu servers)", (unsigned long)self.ameV13_rows.count);
}

@end

#pragma mark - ⑧ 配置

@interface ZL2VersionConfigPage () <UITextFieldDelegate>
@property (nonatomic, strong) UIStackView *ameV13_contentStack;
@property (nonatomic, strong) UILabel *ameV13_memoryValueLabel;
@property (nonatomic, strong) UISlider *ameV13_memorySlider;
@property (nonatomic, strong) UITextField *ameV13_javaArgsField;
@property (nonatomic, strong) UITextField *ameV13_serverIpField;
@property (nonatomic, strong) UILabel *ameV13_presetValueLabel;
@property (nonatomic, strong) UIStackView *ameV13_rendererRowsStack;
@property (nonatomic, assign) NSInteger ameV13_maxMemory;
@property (nonatomic, assign) NSInteger ameV13_pendingMemory;
@end

@implementation ZL2VersionConfigPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    _ameV13_contentStack = [self ameV13_installContentSkeleton];

    // —— 内存滑条卡 ——
    UIView *memoryCard = [self ameV13_buildMemoryCard];
    UIStackView *memoryWrap = [[UIStackView alloc] initWithArrangedSubviews:@[memoryCard]];
    memoryWrap.axis = UILayoutConstraintAxisVertical;
    memoryWrap.alignment = UIStackViewAlignmentFill;
    memoryWrap.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_contentStack addArrangedSubview:memoryWrap];

    // —— JVM 参数行 ——
    UIView *argsCard = [self ameV13_buildJavaArgsCard];
    UIStackView *argsWrap = [[UIStackView alloc] initWithArrangedSubviews:@[argsCard]];
    argsWrap.axis = UILayoutConstraintAxisVertical;
    argsWrap.alignment = UIStackViewAlignmentFill;
    argsWrap.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_contentStack addArrangedSubview:argsWrap];

    // —— JVM 预设行（点击换档）——
    UIView *presetCard = [self ameV13_buildPresetCard];
    UIStackView *presetWrap = [[UIStackView alloc] initWithArrangedSubviews:@[presetCard]];
    presetWrap.axis = UILayoutConstraintAxisVertical;
    presetWrap.alignment = UIStackViewAlignmentFill;
    presetWrap.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_contentStack addArrangedSubview:presetWrap];

    // —— 渲染器覆写 RowList ——
    UILabel *rendererHeader = [[UILabel alloc] init];
    rendererHeader.text = @"渲染器覆写";
    rendererHeader.font = [ZL2Theme fontTitleMedium];
    rendererHeader.textColor = [ZL2Theme onSurface];
    rendererHeader.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *rendererHint = [[UILabel alloc] init];
    rendererHint.text = @"为本实例覆写渲染器（保存到实例，不影响其他实例）";
    rendererHint.font = [ZL2Theme fontLabelMedium];
    rendererHint.textColor = [ZL2Theme onSurfaceVariant];
    rendererHint.numberOfLines = 0;
    rendererHint.translatesAutoresizingMaskIntoConstraints = NO;
    UIStackView *rendererHeaderStack = [[UIStackView alloc] initWithArrangedSubviews:@[rendererHeader, rendererHint]];
    rendererHeaderStack.axis = UILayoutConstraintAxisVertical;
    rendererHeaderStack.alignment = UIStackViewAlignmentLeading;
    rendererHeaderStack.spacing = 2;
    rendererHeaderStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_contentStack addArrangedSubview:rendererHeaderStack];

    _ameV13_rendererRowsStack = [[UIStackView alloc] init];
    _ameV13_rendererRowsStack.axis = UILayoutConstraintAxisVertical;
    _ameV13_rendererRowsStack.alignment = UIStackViewAlignmentFill;
    _ameV13_rendererRowsStack.spacing = 8;
    _ameV13_rendererRowsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_contentStack addArrangedSubview:_ameV13_rendererRowsStack];

    // —— 服务器 IP 行 ——
    UIView *serverIpCard = [self ameV13_buildServerIpCard];
    UIStackView *serverIpWrap = [[UIStackView alloc] initWithArrangedSubviews:@[serverIpCard]];
    serverIpWrap.axis = UILayoutConstraintAxisVertical;
    serverIpWrap.alignment = UIStackViewAlignmentFill;
    serverIpWrap.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_contentStack addArrangedSubview:serverIpWrap];

    // —— 完整实例设置（长尾兜底：push 旧 ProfileSettingsViewController）——
    NSString *fullTitle = @"完整实例设置";
    UIButton *fullButton = [self ameV13_outlinedButtonWithTitle:fullTitle destructive:NO];
    fullButton.contentEdgeInsets = UIEdgeInsetsMake(12, 12, 12, 12);
    [fullButton addTarget:self action:@selector(ameV13_openFullSettings) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *fullWrap = [[UIStackView alloc] initWithArrangedSubviews:@[fullButton]];
    fullWrap.axis = UILayoutConstraintAxisVertical;
    fullWrap.alignment = UIStackViewAlignmentFill;
    fullWrap.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_contentStack addArrangedSubview:fullWrap];

    [self ameV13_loadValues];
    [self ameV13_rebuildRendererRows];
}

#pragma mark 配置：各卡构建

- (UIView *)ameV13_buildMemoryCard {
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"内存分配";
    titleLabel.font = [ZL2Theme fontTitleMedium];
    titleLabel.textColor = [ZL2Theme onSurface];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _ameV13_memoryValueLabel = [[UILabel alloc] init];
    _ameV13_memoryValueLabel.font = [ZL2Theme fontLabelLarge];
    _ameV13_memoryValueLabel.textColor = [ZL2Theme onSurfaceVariant];
    _ameV13_memoryValueLabel.numberOfLines = 1;
    _ameV13_memoryValueLabel.textAlignment = NSTextAlignmentRight;
    _ameV13_memoryValueLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _ameV13_memorySlider = [[UISlider alloc] init];
    _ameV13_memorySlider.translatesAutoresizingMaskIntoConstraints = NO;
    [_ameV13_memorySlider addTarget:self action:@selector(ameV13_memoryValueChanged) forControlEvents:UIControlEventValueChanged];
    [_ameV13_memorySlider addTarget:self action:@selector(ameV13_memoryTouchUp) forControlEvents:UIControlEventTouchUpInside];
    [_ameV13_memorySlider addTarget:self action:@selector(ameV13_memoryTouchUp) forControlEvents:UIControlEventTouchUpOutside];

    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.text = @"拖动调整本实例的 JVM 堆内存（512 MB 起）";
    hintLabel.font = [ZL2Theme fontLabelMedium];
    hintLabel.textColor = [ZL2Theme onSurfaceVariant];
    hintLabel.numberOfLines = 0;
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, [self ameV13_spacer], _ameV13_memoryValueLabel]];
    titleRow.axis = UILayoutConstraintAxisHorizontal;
    titleRow.alignment = UIStackViewAlignmentCenter;
    titleRow.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleRow, _ameV13_memorySlider, hintLabel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [ZL2Theme surfaceContainer];
    card.layer.cornerRadius = [ZL2Theme radiusM];
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:ZL2V13CardPadding],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-ZL2V13CardPadding],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:ZL2V13CardPadding],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-ZL2V13CardPadding],
    ]];
    return card;
}

- (UIView *)ameV13_buildJavaArgsCard {
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"JVM 参数";
    titleLabel.font = [ZL2Theme fontTitleMedium];
    titleLabel.textColor = [ZL2Theme onSurface];
    titleLabel.numberOfLines = 0;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _ameV13_javaArgsField = [[UITextField alloc] init];
    _ameV13_javaArgsField.font = [ZL2Theme fontBodyMedium];
    _ameV13_javaArgsField.textColor = [ZL2Theme onSurface];
    _ameV13_javaArgsField.backgroundColor = [ZL2Theme surfaceVariant];
    _ameV13_javaArgsField.layer.cornerRadius = [ZL2Theme radiusS];
    _ameV13_javaArgsField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _ameV13_javaArgsField.autocorrectionType = UITextAutocorrectionTypeNo;
    _ameV13_javaArgsField.keyboardType = UIKeyboardTypeASCIICapable;
    _ameV13_javaArgsField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _ameV13_javaArgsField.delegate = self;
    _ameV13_javaArgsField.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *leftPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 1)];
    _ameV13_javaArgsField.leftView = leftPad;
    _ameV13_javaArgsField.leftViewMode = UITextFieldViewModeAlways;
    [_ameV13_javaArgsField addTarget:self action:@selector(ameV13_javaArgsEditingEnded) forControlEvents:UIControlEventEditingDidEnd];

    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.text = @"留空回退全局 java.java_args（启动链 PLProfiles 回退口径）";
    hintLabel.font = [ZL2Theme fontLabelMedium];
    hintLabel.textColor = [ZL2Theme onSurfaceVariant];
    hintLabel.numberOfLines = 0;
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, _ameV13_javaArgsField, hintLabel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [ZL2Theme surfaceContainer];
    card.layer.cornerRadius = [ZL2Theme radiusM];
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:ZL2V13CardPadding],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-ZL2V13CardPadding],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:ZL2V13CardPadding],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-ZL2V13CardPadding],
        [_ameV13_javaArgsField.heightAnchor constraintEqualToConstant:38],
    ]];
    return card;
}

- (UIView *)ameV13_buildPresetCard {
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = localize(@"preference.title.jvm_preset", nil);
    titleLabel.font = [ZL2Theme fontTitleMedium];
    titleLabel.textColor = [ZL2Theme onSurface];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _ameV13_presetValueLabel = [[UILabel alloc] init];
    _ameV13_presetValueLabel.font = [ZL2Theme fontLabelLarge];
    _ameV13_presetValueLabel.textColor = [ZL2Theme onSurfaceVariant];
    _ameV13_presetValueLabel.numberOfLines = 1;
    _ameV13_presetValueLabel.textAlignment = NSTextAlignmentRight;
    _ameV13_presetValueLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[ZL2V13SystemImage(@"chevron.right", @"circle") imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    chevron.tintColor = [ZL2Theme onSurfaceVariant];
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [chevron.widthAnchor constraintEqualToConstant:14],
        [chevron.heightAnchor constraintEqualToConstant:14],
    ]];

    UIControl *tapRow = [[UIControl alloc] init];
    tapRow.translatesAutoresizingMaskIntoConstraints = NO;
    [tapRow addTarget:self action:@selector(ameV13_showPresetPicker) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, [self ameV13_spacer], _ameV13_presetValueLabel, chevron]];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [tapRow addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:tapRow.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:tapRow.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:tapRow.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:tapRow.trailingAnchor],
    ]];

    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [ZL2Theme surfaceContainer];
    card.layer.cornerRadius = [ZL2Theme radiusM];
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:tapRow];
    [NSLayoutConstraint activateConstraints:@[
        [tapRow.topAnchor constraintEqualToAnchor:card.topAnchor constant:ZL2V13CardPadding],
        [tapRow.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-ZL2V13CardPadding],
        [tapRow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:ZL2V13CardPadding],
        [tapRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-ZL2V13CardPadding],
    ]];
    return card;
}

- (UIView *)ameV13_buildServerIpCard {
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"服务器地址";
    titleLabel.font = [ZL2Theme fontTitleMedium];
    titleLabel.textColor = [ZL2Theme onSurface];
    titleLabel.numberOfLines = 0;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _ameV13_serverIpField = [[UITextField alloc] init];
    _ameV13_serverIpField.font = [ZL2Theme fontBodyMedium];
    _ameV13_serverIpField.textColor = [ZL2Theme onSurface];
    _ameV13_serverIpField.backgroundColor = [ZL2Theme surfaceVariant];
    _ameV13_serverIpField.layer.cornerRadius = [ZL2Theme radiusS];
    _ameV13_serverIpField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _ameV13_serverIpField.autocorrectionType = UITextAutocorrectionTypeNo;
    _ameV13_serverIpField.keyboardType = UIKeyboardTypeURL;
    _ameV13_serverIpField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _ameV13_serverIpField.delegate = self;
    _ameV13_serverIpField.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *leftPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 1)];
    _ameV13_serverIpField.leftView = leftPad;
    _ameV13_serverIpField.leftViewMode = UITextFieldViewModeAlways;
    [_ameV13_serverIpField addTarget:self action:@selector(ameV13_serverIpEditingEnded) forControlEvents:UIControlEventEditingDidEnd];

    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.text = @"FCL 风格：启动后自动加入该服务器，留空则不加入";
    hintLabel.font = [ZL2Theme fontLabelMedium];
    hintLabel.textColor = [ZL2Theme onSurfaceVariant];
    hintLabel.numberOfLines = 0;
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, _ameV13_serverIpField, hintLabel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [ZL2Theme surfaceContainer];
    card.layer.cornerRadius = [ZL2Theme radiusM];
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:ZL2V13CardPadding],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-ZL2V13CardPadding],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:ZL2V13CardPadding],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-ZL2V13CardPadding],
        [_ameV13_serverIpField.heightAnchor constraintEqualToConstant:38],
    ]];
    return card;
}

#pragma mark 配置：读值 / 渲染器行 / 事件

- (void)ameV13_loadValues {
    NSMutableDictionary *profile = [self ameV13_profileDict];
    // 内存上限 = 0.8×物理内存（下限 1024），再过 Task173 Jetsam 钳制
    //（ame173_safeHeapCeilingMB 为 utils.h 公共符号，与实例设置页同源）
    long long totalMemory = [NSProcessInfo processInfo].physicalMemory;
    NSInteger maxMemory = (NSInteger)(totalMemory / (1024 * 1024));
    maxMemory = (NSInteger)(maxMemory * 0.8);
    if (maxMemory < 1024) maxMemory = 1024;
    NSInteger sliderCap = (NSInteger)ame173_safeHeapCeilingMB() + 512;
    if (maxMemory > sliderCap) maxMemory = sliderCap;
    _ameV13_maxMemory = maxMemory;

    NSInteger allocated = 0;
    if ([profile[@"allocatedMemory"] isKindOfClass:[NSNumber class]]) {
        allocated = [(NSNumber *)profile[@"allocatedMemory"] integerValue];
    }
    if (allocated <= 0) allocated = MIN(maxMemory / 2, 2048);
    if (allocated > maxMemory) allocated = maxMemory;
    _ameV13_pendingMemory = allocated;

    _ameV13_memorySlider.minimumValue = 512.0;
    _ameV13_memorySlider.maximumValue = (float)maxMemory;
    _ameV13_memorySlider.value = (float)allocated;
    self.ameV13_memoryValueLabel.text = [NSString stringWithFormat:@"%ld MB", (long)allocated];

    NSString *args = [profile[@"javaArgs"] isKindOfClass:[NSString class]] ? (NSString *)profile[@"javaArgs"] : @"";
    self.ameV13_javaArgsField.text = args;
    self.ameV13_javaArgsField.placeholder = @"(default)";

    [self ameV13_refreshPresetValue];

    NSString *serverIp = [PLProfiles.current serverIpForProfile:self.ameV13_profileName];
    if (!serverIp) serverIp = @"";
    self.ameV13_serverIpField.text = serverIp;
    self.ameV13_serverIpField.placeholder = @"play.example.com";
}

- (void)ameV13_refreshPresetValue {
    NSMutableDictionary *profile = [self ameV13_profileDict];
    NSString *preset = [profile[@"jvm_preset"] isKindOfClass:[NSString class]] ? (NSString *)profile[@"jvm_preset"] : nil;
    if (preset.length == 0) {
        self.ameV13_presetValueLabel.text = localize(@"preference.profile.jvm_follow_global", nil);
        return;
    }
    NSDictionary *names = @{
        @"memory":      localize(@"jvm.preset.memory", nil),
        @"normal":      localize(@"jvm.preset.normal", nil),
        @"performance": localize(@"jvm.preset.performance", nil),
        @"custom":      localize(@"jvm.preset.custom", nil),
    };
    NSString *display = names[preset];
    self.ameV13_presetValueLabel.text = (display.length > 0) ? display : preset;
}

- (void)ameV13_rebuildRendererRows {
    [self ameV13_clearStack:_ameV13_rendererRowsStack];
    NSMutableDictionary *profile = [self ameV13_profileDict];
    NSString *selected = [profile[@"renderer"] isKindOfClass:[NSString class]] && ((NSString *)profile[@"renderer"]).length > 0
        ? (NSString *)profile[@"renderer"] : @"auto";

    NSArray *keys = getRendererKeys(NO);
    NSArray *names = getRendererNames(NO);
    for (NSInteger i = 0; i < (NSInteger)keys.count; i++) {
        NSString *key = keys[i];
        NSString *name = (i < (NSInteger)names.count) ? names[i] : key;
        BOOL isSelected = [selected isEqualToString:key];
        NSString *rowTitle = isSelected ? [NSString stringWithFormat:@"✓ %@", name] : name;
        UIButton *rowButton = [self ameV13_outlinedButtonWithTitle:rowTitle destructive:NO];
        rowButton.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
        if (isSelected) {
            rowButton.layer.borderColor = [ZL2Theme primary].CGColor;
            [rowButton setTitleColor:[ZL2Theme primary] forState:UIControlStateNormal];
        }
        objc_setAssociatedObject(rowButton, @selector(ameV13_rendererTapped:), key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [rowButton addTarget:self action:@selector(ameV13_rendererTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_ameV13_rendererRowsStack addArrangedSubview:rowButton];
    }
}

#pragma mark 配置：内存滑条（值即时预览，松手落盘）

- (void)ameV13_memoryValueChanged {
    NSInteger value = (NSInteger)self.ameV13_memorySlider.value;
    _ameV13_pendingMemory = value;
    self.ameV13_memoryValueLabel.text = [NSString stringWithFormat:@"%ld MB", (long)value];
}

- (void)ameV13_memoryTouchUp {
    // 旧 saveSettings 手动分支同口径：显式落值 + 清 memoryAuto 标记
    _ameV13_pendingMemory = (NSInteger)self.ameV13_memorySlider.value;
    NSMutableDictionary *profile = [self ameV13_profileDict];
    if (!profile) return;
    profile[@"allocatedMemory"] = @(_ameV13_pendingMemory);
    [profile removeObjectForKey:@"memoryAuto"];
    [PLProfiles.current save];
    NSLog(@"[ZL2VersionPages] memory for '%@' -> %ld MB (memoryAuto cleared)", self.ameV13_profileName, (long)_ameV13_pendingMemory);
}

#pragma mark 配置：JVM 参数 / 预设 / 服务器 IP

- (void)ameV13_javaArgsEditingEnded {
    // 空值删键（回退全局 java.java_args；saveSettings 同口径）
    NSString *args = [self.ameV13_javaArgsField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self ameV13_writeProfileKey:@"javaArgs" value:(args.length > 0 ? args : nil)];
}

- (void)ameV13_serverIpEditingEnded {
    NSString *ip = [self.ameV13_serverIpField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!ip) ip = @"";
    [PLProfiles.current setServerIp:ip forProfile:self.ameV13_profileName];
}

- (void)ameV13_showPresetPicker {
    // Task256 键族：nil（跟随全局，删键）+ memory/normal/performance/custom
    NSString *titleText = localize(@"preference.title.jvm_preset", nil);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:titleText
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSString *followText = localize(@"preference.profile.jvm_follow_global", nil);
    [alert addAction:[UIAlertAction actionWithTitle:followText style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self ameV13_writeProfileKey:@"jvm_preset" value:nil];
        [self ameV13_refreshPresetValue];
    }]];
    NSArray *presetKeys = @[@"memory", @"normal", @"performance", @"custom"];
    NSArray *presetNames = @[
        localize(@"jvm.preset.memory", nil),
        localize(@"jvm.preset.normal", nil),
        localize(@"jvm.preset.performance", nil),
        localize(@"jvm.preset.custom", nil),
    ];
    for (NSInteger i = 0; i < (NSInteger)presetKeys.count; i++) {
        NSString *key = presetKeys[i];
        NSString *name = presetNames[i];
        [alert addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self ameV13_writeProfileKey:@"jvm_preset" value:key];
            [self ameV13_refreshPresetValue];
        }]];
    }
    NSString *cancelText = localize(@"resman.common.cancel", nil);
    [alert addAction:[UIAlertAction actionWithTitle:cancelText style:UIAlertActionStyleCancel handler:nil]];
    // iPad 锚点（iPhone 上 popoverPresentationController 为 nil，旧 VC 同口径）
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1, 1);
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)ameV13_rendererTapped:(UIButton *)sender {
    NSString *key = objc_getAssociatedObject(sender, @selector(ameV13_rendererTapped:));
    if (key.length == 0) return;
    [self ameV13_writeProfileKey:@"renderer" value:key];
    [self ameV13_rebuildRendererRows];
    NSLog(@"[ZL2VersionPages] renderer for '%@' -> %@", self.ameV13_profileName, key);
}

#pragma mark 配置：完整实例设置（旧 ProfileSettingsViewController 长尾兜底）

- (void)ameV13_openFullSettings {
    // 旧 VC editProfile: 同款目标与 init（[[alloc] init] + profileName 属性）
    ProfileSettingsViewController *vc = [[ProfileSettingsViewController alloc] init];
    vc.profileName = self.ameV13_profileName;
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark UITextFieldDelegate（收起键盘即落盘）

- (void)textFieldDidEndEditing:(UITextField *)textField {
    // 落盘走各 field 的 EditingDidEnd target；此处仅收起态刷新
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
