//
// ZL2VersionDetailViewController.m — ZL2 版本详情容器实现（7.0-UI-13-V）
//
// 视觉对标（ZalithLauncher2 VersionSettingsScreen.kt L95-246 实证）：
//   · 头卡 = M3 Surface(surfaceContainer/radiusM)：加载器图标 34dp
//     （ModLoaderIconHelper 检出；取不到 → surfaceVariant radiusS 容器 +
//     gamecontroller 兜底，ZL2VersionsViewController 卡内同款手法）+
//     版本名（titleMedium）/ 描述行（bodyMedium, onSurfaceVariant）+
//     标签行（MC版本 · 加载器，labelSmall alpha 0.7）+ 右侧「完成」文本钮。
//   · TabMenu = 竖排 NavigationRailItem 列（IntrinsicSize.Min，顶部起排）：
//     32dp 图标胶囊 + 4dp 间距 + labelMedium 标签；active = primaryContainer
//     胶囊 + onPrimaryContainer 图标 + primary 标签；inactive = 透明胶囊 +
//     onSurfaceVariant。division 分隔线（onSurface alpha 0.4）同位移植：
//     ZL2 在 ModsManager 与 ServerList 前（VersionSettingsScreen.kt L159-168）。
//   · 内容切换 = 子页懒建缓存 + addChild + 0.18s crossDissolve
//     （ZL2ShellViewController.m ame_attachChildIfNeeded/showPage 同手法）。
//
// 子页集合（★Task432）：公共八页 = ZL2VersionPages.h（概览/模组/存档/资源包/
//   光影/截图/服务器/配置）；「修改版本」= 本 .m 私有页 ZL2V13ModifyVersionPage
//   （ZL2 ModifyVersionScreen.kt 列表选择 + 确认安装语义；loader 家族换装全链
//   复用 PLComponentService，Vanilla/Quilt 无既有安装 API → 展示禁用注明
//   「暂不支持」；★Task441 批次三②：页名如实改「更换加载器」——第 10 期 4.5
//   两条出路（解锁或如实改页名）任选其一清账，本仓选如实改页名，诚实边界不造假入口）；存档子页 = 本 .m 私有桥接页 ZL2V13SavesDatapacksBridgePage
//   （内嵌 ZL2VersionSavesPage + 顶部数据包入口行 → ZL2V13DatapacksPage
//   第九子页，对应下载轨 Task432 收敛注记「数据包→版本子页第九子页」）。
//   旧注「ModifyVersion 编辑页语义折入概览页管理组」随本轮真实现落地废除
//   （概览页 Task429 组件管理行保留零回归，职责分工：组件行 = 已装组件
//   查看/换版，修改版本页 = loader 家族选择换装）。
//

#import "ZL2VersionDetailViewController.h"
#import "ZL2Theme.h"
#import "ZL2VersionPages.h"
#import "PLProfiles.h"
#import "ModLoaderIconHelper.h"
#import "ModpackExportService.h"
#import "ModService.h"
#import "PLComponentService.h"   // ★Task432 实锤一：修改版本页 loader 换装链（analyze/availableVersions/install）
#import "ZL2M3Kit.h"             // ★Task432：安装二次确认 M3Dialog（PLComponentsPage 同款）
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>   // ★Task432 缺口#6：数据包导入 picker（UTTypeZIP/UTTypeFolder）
#import <objc/runtime.h>   // ★Task432：数据包页 iconButton block 载荷关联对象（ameV13_dispatchTap 判例）
#import "utils.h"   // localize()

// ★Task432：ZL2VersionPageBase 私有构件自含声明（构件实现在 ZL2VersionPages.m
//   基类 @implementation 内、随容器必同链；运行期消息必命中。消费方 TU 自含
//   判例同款：选择器一一对应勿漂移；本 TU 未消费的成员不收）。
@interface ZL2VersionPageBase (Task432VPageBridge)
- (UIStackView *)ameV13_installContentSkeleton;                       // 页骨架（scrollView + 999 宽收敛列）
- (UIStackView *)ameV13_pageHeaderRowWithTitle:(NSString *)title
                                      trailing:(NSArray<UIView *> *)trailing;  // 页头行
- (UIStackView *)ameV13_rowCardWithViews:(NSArray<UIView *> *)views
                              alignment:(UIStackViewAlignment)alignment;  // 行卡容器
- (UIView *)ameV13_iconBoxWithSymbol:(NSString *)symbol
                           fallback:(NSString *)fallback
                              size:(CGFloat)size
                          iconSize:(CGFloat)iconSize;                  // 图标占位盒
- (void)ameV13_showAlertMessage:(NSString *)message;                  // 旧 VC showAlert 同款
@end

#pragma mark - ★Task432 私有子页（声明前置于消费点；实现于文件尾）

/// 「修改版本」私有页（rail 第 3 项；ZL2 ModifyVersionScreen.kt 列表选择 +
/// 确认安装语义；loader 家族换装复用 PLComponentService 安装链）
@interface ZL2V13ModifyVersionPage : ZL2VersionPageBase
@end

/// 存档桥接私有页（rail 第 5 项=存档）：内嵌 ZL2VersionSavesPage 原页零回归，
/// 顶部加「数据包」入口行（缺口#6 第九子页入口；入口在存档子页内）
@interface ZL2V13SavesDatapacksBridgePage : ZL2VersionPageBase
@end

/// 数据包私有子页（世界存档目录 datapacks/ 枚举 + 删除 + 导入；push 呈现）
@interface ZL2V13DatapacksPage : UIViewController
- (instancetype)initWithWorldPath:(NSString *)worldPath
                        worldName:(NSString *)worldName;
@end

#pragma mark - 常量

// 内容列边距/宽度（ZL2VersionsViewController 同款 999 等式宽度方案）
static const CGFloat ZL2V13PageMargin = 16.0;
static const CGFloat ZL2V13ContentMaxWidth = 720.0;
static const CGFloat ZL2V13RailWidth = 160.0;          // 任务规格：左轨 160pt（iPhone 同宽）
static const CGFloat ZL2V13RailItemSize = 56.0;        // M3 NavigationRailItem 高
static const CGFloat ZL2V13RailCapsuleSize = 32.0;     // 32pt 胶囊
static const CGFloat ZL2V13AnimateDuration = 0.18;     // 全域动画时长（ZL2Shell 同款）

static UIImage *ZL2V13SystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    if (!image) image = [UIImage systemImageNamed:@"circle"];
    return image;
}

#pragma mark - 私有导航项（ZL2RailItem 视觉同款）

@interface ZL2VersionDetailNavItem : UIControl
@property (nonatomic, strong) UIView *iconBg;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, assign) NSInteger pageIndex;
- (void)ameV13_setSelected:(BOOL)selected;
@end

@implementation ZL2VersionDetailNavItem

// ★ Task397：轨项形态重排（用户三次复诉「标签页触发位置靠左」终解）——
// 原 M3 NavigationRail 形态（图标胶囊+文字上下竖排、整行内居中悬空）在
// 全宽命中面（Task372）下视觉字形只占行中 ~60pt，行左缘空带也能触发切
// 换 = 「触发位置比标签靠左」的错位感；且与壳层侧栏（图标+文字横排左
// 对齐）视觉语言割裂。本轮改横排左对齐：字形起点 = 命中面起点（16pt
// 边距线上）＝ 所见即所点，与 shell 侧栏同语言；选中态由图标胶囊着色
// 升级为整行胶囊背景（MD3 NavigationDrawer 语义，全宽命中有视觉支撑）。
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return self;
    self.layer.cornerRadius = 14.0;   // Task397：整行胶囊选中底（与卡圆角同族）
    _iconBg = [[UIView alloc] init];
    _iconBg.translatesAutoresizingMaskIntoConstraints = NO;
    _iconBg.layer.cornerRadius = ZL2V13RailCapsuleSize / 2.0;  // 全圆胶囊
    _iconBg.layer.masksToBounds = YES;
    [self addSubview:_iconBg];

    _icon = [[UIImageView alloc] init];
    _icon.translatesAutoresizingMaskIntoConstraints = NO;
    _icon.contentMode = UIViewContentModeScaleAspectFit;
    _icon.userInteractionEnabled = NO;
    [_iconBg addSubview:_icon];

    _label = [[UILabel alloc] init];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    _label.font = [ZL2Theme fontLabelMedium];
    _label.textAlignment = NSTextAlignmentLeft;   // Task397：左对齐（与图标同列起点语言）
    _label.userInteractionEnabled = NO;
    [self addSubview:_label];

    [NSLayoutConstraint activateConstraints:@[
        // Task397：横排左对齐——图标胶囊 leading 12 / 垂直居中；文字
        // leading = 胶囊尾 +10 同行居中，字形起点即命中起点
        [_iconBg.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
        [_iconBg.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_iconBg.widthAnchor constraintEqualToConstant:ZL2V13RailCapsuleSize],
        [_iconBg.heightAnchor constraintEqualToConstant:ZL2V13RailCapsuleSize],
        [_icon.centerXAnchor constraintEqualToAnchor:_iconBg.centerXAnchor],
        [_icon.centerYAnchor constraintEqualToAnchor:_iconBg.centerYAnchor],
        [_icon.widthAnchor constraintEqualToConstant:20],
        [_icon.heightAnchor constraintEqualToConstant:20],
        [_label.leadingAnchor constraintEqualToAnchor:_iconBg.trailingAnchor constant:10.0],
        [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_label.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-8.0],
    ]];
    return self;
}

- (void)ameV13_setSelected:(BOOL)selected {
    // ★ Task397：选中态升级整行胶囊底（全宽命中面的视觉支撑；原图标胶囊
    // 着色退役——横排左对齐后胶囊底与整行底重复强调）
    self.backgroundColor = selected ? [ZL2Theme primaryContainer] : [UIColor clearColor];
    self.iconBg.backgroundColor = [UIColor clearColor];
    self.icon.tintColor = selected ? [ZL2Theme onPrimaryContainer] : [ZL2Theme onSurfaceVariant];
    self.label.textColor = selected ? [ZL2Theme onPrimaryContainer] : [ZL2Theme onSurfaceVariant];
    self.accessibilityTraits = selected ? UIAccessibilityTraitSelected : UIAccessibilityTraitButton;
}

@end

#pragma mark - 容器

@interface ZL2VersionDetailViewController ()

// 头卡
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UIView *iconBg;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UILabel *tagLabel;

// 左轨 / 内容
@property (nonatomic, strong) UIStackView *railStack;
@property (nonatomic, strong) NSMutableArray<ZL2VersionDetailNavItem *> *railItems;
@property (nonatomic, strong) UIView *contentContainer;

// 状态
@property (nonatomic, copy) NSString *ameV13_profileName;
@property (nonatomic, assign) NSInteger ameV13_selectedIndex;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIViewController *> *ameV13_childCache;

@end

@implementation ZL2VersionDetailViewController

- (instancetype)initWithProfileName:(NSString *)profileName {
    self = [super init];
    if (!self) return self;
    _ameV13_profileName = [profileName copy];
    _ameV13_selectedIndex = -1;
    _ameV13_childCache = [NSMutableDictionary dictionary];
    self.title = profileName;
    return self;
}

#pragma mark - 实例名→游戏目录解析链（工具方法，全部子页枚举走它）

/// ModService.m resolveAbsoluteGameDirForProfile:（L212-243）同契约移植：
///   ① profile[@"gameDir"] 缺失/空/"." → Task225 隔离嗅探
///      （+[ModService ame225_sniffedIsolationGameDirForProfile:]，公共类
///      方法，与启动链 JavaLauncher L2435 / ModService 三处同源规则）；
///      未命中 → POJAV_GAME_DIR（NSHomeDirectory 兜底）。
///   ② 显式绝对路径 → 原样。
///   ③ 显式相对路径 → POJAV_GAME_DIR 拼接（剥 "./" 前缀）。
/// POJAV_GAME_DIR 本身 = instances/<general.game_directory> 软链
/// （VersionManagerViewController switchGameDirTo: L1624-1641 建立），
/// 故此链与 JavaLauncher L2422-2426 的启动目录解析终点一致。
+ (NSString *)ameV13_resolvedGameDirForProfileName:(NSString *)profileName {
    NSDictionary *prof = PLProfiles.current.profiles[profileName];
    if (![prof isKindOfClass:[NSDictionary class]]) prof = @{};
    NSString *gameDir = prof[@"gameDir"];
    if (![gameDir isKindOfClass:[NSString class]] || gameDir.length == 0 || [gameDir isEqualToString:@"."]) {
        // Task225：无显式隔离 → 嗅探版本目录形状（auto 语义）
        NSString *sniffed = [ModService ame225_sniffedIsolationGameDirForProfile:prof];
        if ([sniffed isKindOfClass:[NSString class]] && sniffed.length > 0) return sniffed;
        const char *env = getenv("POJAV_GAME_DIR");
        return env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
    }
    if ([gameDir isAbsolutePath]) return gameDir;
    const char *env = getenv("POJAV_GAME_DIR");
    NSString *base = env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
    NSString *clean = [gameDir hasPrefix:@"./"] ? [gameDir substringFromIndex:2] : gameDir;
    return [base stringByAppendingPathComponent:clean];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];

    // 概览页重命名后同步键名/标题/头卡（页面自更新自身，容器级身份由本通知收敛：
    // 缓存子页的 ameV13_profileName 一并改写，配置页 serverIp/完整设置入口不悬空）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ameV13_profileRenamed:)
                                                 name:@"ZL2VersionDetailProfileRenamed"
                                               object:nil];

    // ★Task432：loader 换装成功（PLComponentService.installComponent 收口广播）
    //   → 注册表现取 + 头卡刷新（MC 版本/加载器标签行即时跟随，防换装后头卡
    //   显示旧态直到页回归）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ameV13_profileListReloaded:)
                                                 name:@"ReloadProfileList"
                                               object:nil];

    [self ameV13_buildHeaderCard];
    [self ameV13_buildBody];
    [self ameV13_refreshHeader];
    [self ameV13_selectPage:0];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)ameV13_profileRenamed:(NSNotification *)note {
    NSString *newName = note.userInfo[@"newName"];
    if (![newName isKindOfClass:[NSString class]] || newName.length == 0) return;
    self.ameV13_profileName = newName;
    self.title = newName;
    [self.ameV13_childCache enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, UIViewController *child, BOOL *stop) {
        if ([child isKindOfClass:[ZL2VersionPageBase class]]) {
            [(ZL2VersionPageBase *)child ameV13_updateProfileName:newName];
        }
    }];
    [self ameV13_refreshHeader];
}

// ★Task432：换装/实例表变更广播（ReloadProfileList）→ 头卡即时刷新
- (void)ameV13_profileListReloaded:(NSNotification *)note {
    [PLProfiles updateCurrent];
    [self ameV13_refreshHeader];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 重命名/删除回写注册表后头卡随视图回归刷新（ZL2Versions reloadVersions 同口径）
    [PLProfiles updateCurrent];
    [self ameV13_refreshHeader];
}

#pragma mark - 头卡

- (void)ameV13_buildHeaderCard {
    _headerCard = [[UIView alloc] init];
    _headerCard.backgroundColor = [ZL2Theme surfaceContainer];
    _headerCard.layer.cornerRadius = [ZL2Theme radiusM];
    _headerCard.layer.masksToBounds = YES;
    _headerCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_headerCard];

    // 34pt 加载器图标（ZL2VersionsViewController 卡内同款：PNG 原色 /
    // SF 品牌色；取不到 → surfaceVariant radiusS 容器 + gamecontroller 兜底）
    _iconBg = [[UIView alloc] init];
    _iconBg.layer.cornerRadius = [ZL2Theme radiusS];
    _iconBg.layer.masksToBounds = YES;
    _iconBg.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_iconBg];

    _iconView = [[UIImageView alloc] init];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_iconBg addSubview:_iconView];

    _nameLabel = [[UILabel alloc] init];
    _nameLabel.font = [ZL2Theme fontTitleMedium];
    _nameLabel.textColor = [ZL2Theme onSurface];
    _nameLabel.numberOfLines = 1;
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _descLabel = [[UILabel alloc] init];
    _descLabel.font = [ZL2Theme fontBodyMedium];
    _descLabel.textColor = [ZL2Theme onSurfaceVariant];
    _descLabel.numberOfLines = 1;
    _descLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _descLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _tagLabel = [[UILabel alloc] init];
    _tagLabel.font = [ZL2Theme fontLabelMedium];
    _tagLabel.textColor = [ZL2Theme onSurfaceVariant];
    _tagLabel.alpha = 0.7;
    _tagLabel.numberOfLines = 1;
    _tagLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _tagLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _descLabel, _tagLabel]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.alignment = UIStackViewAlignmentLeading;
    textStack.spacing = 2;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:textStack];

    // 「完成」（dismiss 语义：pop 优先，无 nav 时 dismiss 兜底）
    NSString *doneTitle = localize(@"resman.common.done", nil);
    UIButton *doneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    doneButton.titleLabel.font = [ZL2Theme fontLabelLarge];
    [doneButton setTitleColor:[ZL2Theme primary] forState:UIControlStateNormal];
    [doneButton setTitle:doneTitle forState:UIControlStateNormal];
    doneButton.contentEdgeInsets = UIEdgeInsetsMake(8, 12, 8, 12);
    doneButton.translatesAutoresizingMaskIntoConstraints = NO;
    doneButton.isAccessibilityElement = YES;
    doneButton.accessibilityLabel = doneTitle;
    [doneButton addTarget:self action:@selector(ameV13_finish) forControlEvents:UIControlEventTouchUpInside];
    [_headerCard addSubview:doneButton];

    [NSLayoutConstraint activateConstraints:@[
        [_headerCard.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [_headerCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:ZL2V13PageMargin],
        [_headerCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-ZL2V13PageMargin],

        [_iconBg.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:14],
        [_iconBg.centerYAnchor constraintEqualToAnchor:_headerCard.centerYAnchor],
        [_iconBg.widthAnchor constraintEqualToConstant:34],
        [_iconBg.heightAnchor constraintEqualToConstant:34],
        [_iconView.centerXAnchor constraintEqualToAnchor:_iconBg.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:_iconBg.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:26],
        [_iconView.heightAnchor constraintEqualToConstant:26],

        [textStack.leadingAnchor constraintEqualToAnchor:_iconBg.trailingAnchor constant:12],
        [textStack.topAnchor constraintEqualToAnchor:_headerCard.topAnchor constant:12],
        [textStack.bottomAnchor constraintLessThanOrEqualToAnchor:_headerCard.bottomAnchor constant:-12],
        [doneButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:textStack.trailingAnchor constant:8],
        [doneButton.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-6],
        [doneButton.centerYAnchor constraintEqualToAnchor:_headerCard.centerYAnchor],
    ]];
}

- (void)ameV13_refreshHeader {
    // 身份 = 注册表字典键（Task162 口径：name 字段与键可能分叉，键为准）
    NSMutableDictionary *profile = PLProfiles.current.profiles[self.ameV13_profileName];
    if (![profile isKindOfClass:[NSMutableDictionary class]]) profile = nil;

    NSString *displayName = nil;
    NSString *descText = nil;
    NSString *versionId = nil;
    if (profile) {
        displayName = [profile[@"name"] isKindOfClass:[NSString class]] && ((NSString *)profile[@"name"]).length > 0
            ? (NSString *)profile[@"name"] : self.ameV13_profileName;
        versionId = [profile[@"lastVersionId"] isKindOfClass:[NSString class]] ? (NSString *)profile[@"lastVersionId"] : nil;
        // 描述行：自定义摘要（概览页「编辑摘要」写入）优先，缺省回退最后游玩时间
        // （ZL2Versions 列表行同源格式：i18n_str_1069「最后游玩：%@」）
        NSString *summary = [profile[@"versionSummary"] isKindOfClass:[NSString class]] ? (NSString *)profile[@"versionSummary"] : nil;
        if (summary.length > 0) {
            descText = summary;
        } else {
            descText = [self ameV13_formatLastPlayed:profile[@"lastPlayed"]];
        }
    } else {
        displayName = self.ameV13_profileName;
        descText = @"";
    }

    NSString *loader = versionId.length > 0 ? [ModLoaderIconHelper detectLoaderFromVersionId:versionId] : nil;
    NSDictionary *parsed = versionId.length > 0 ? [ModpackExportService parseVersionId:versionId] : @{};
    NSString *mcVersion = [parsed[@"minecraft"] isKindOfClass:[NSString class]] ? (NSString *)parsed[@"minecraft"] : versionId;

    self.nameLabel.text = displayName;
    self.descLabel.text = descText.length > 0 ? descText : @" ";
    if (mcVersion.length > 0 && loader.length > 0) {
        self.tagLabel.text = [NSString stringWithFormat:@"MC %@ · %@", mcVersion, [ModLoaderIconHelper displayNameForLoader:loader]];
    } else if (mcVersion.length > 0) {
        self.tagLabel.text = [NSString stringWithFormat:@"MC %@", mcVersion];
    } else if (loader.length > 0) {
        self.tagLabel.text = [ModLoaderIconHelper displayNameForLoader:loader];
    } else {
        self.tagLabel.text = @" ";
    }

    if (loader.length > 0) {
        [ModLoaderIconHelper configureImageView:self.iconView forLoader:loader traitCollection:self.traitCollection];
        self.iconBg.backgroundColor = [UIColor clearColor];
    } else {
        UIImage *fallbackIcon = ZL2V13SystemImage(@"gamecontroller", @"cube.box.fill");
        self.iconView.image = [fallbackIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.iconView.tintColor = [ZL2Theme onSurfaceVariant];
        self.iconBg.backgroundColor = [ZL2Theme surfaceVariant];
    }
}

/// lastPlayed 时间戳 → 「最后游玩：xxx」（ZL2VersionsViewController 1:1）
- (NSString *)ameV13_formatLastPlayed:(id)lastPlayedRaw {
    if (!lastPlayedRaw) return @"";
    NSTimeInterval ts = 0;
    if ([lastPlayedRaw isKindOfClass:[NSNumber class]]) {
        ts = [(NSNumber *)lastPlayedRaw doubleValue];
    } else if ([lastPlayedRaw isKindOfClass:[NSString class]]) {
        ts = [(NSString *)lastPlayedRaw doubleValue];
    } else {
        return @"";
    }
    if (ts <= 0) return @"";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale currentLocale];
    fmt.doesRelativeDateFormatting = YES;
    fmt.dateStyle = NSDateFormatterShortStyle;
    fmt.timeStyle = NSDateFormatterShortStyle;
    return [NSString stringWithFormat:localize(@"i18n_str_1069", nil), [fmt stringFromDate:date]];
}

#pragma mark - 左子导航轨 + 内容容器

- (void)ameV13_buildBody {
    // 左轨（160pt，顶部起排；division 分隔线同 ZL2 settingItems：模组前 / 服务器前）
    // ★ Task372：轨项改全宽行 —— "左侧模组等按钮触发点位靠左"修复。
    //   原形态 = 栈居中(Center) + 项内宽 152 再居中 —— 双层居中虽然几何上
    //   自洽，但命中面与视觉胶囊/标签之间存在 4pt×2 的隐性边带，iPad 实机
    //   上手指落点偏左时极易落进边带外的主观空档，用户感知为"要点靠左才中"。
    //   改为 Fill 全宽行：命中面 = 整列 160pt，视觉内容仍居中不变（胶囊/标签
    //   锚在项中心），零主观空档；分隔线同步全宽（发丝线全宽 = M3 常态）。
    _railStack = [[UIStackView alloc] init];
    _railStack.axis = UILayoutConstraintAxisVertical;
    _railStack.alignment = UIStackViewAlignmentFill;
    _railStack.spacing = 2;
    _railStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_railStack];

    _railItems = [NSMutableArray array];
    // (标题, SF 主名, SF 兜底)：ZL2 settingItems 图标语义映射 SF 可用族
    // ★Task432 实锤一：rail 9 项 1:1 对齐 ZL2 settingItems（VersionSettingsScreen.kt
    //   L159-168）——概览 / 配置 / 修改版本 ｜ 模组 / 存档 / 资源包 / 光影 /
    //   截图 ｜ 服务器。配置回第 2 位（原尾部第 8 位）、新增「修改版本」第 3 位；
    //   修改版本 = ic_edit_outlined → square.and.pencil（SF1.0 级 + 兜底）。
    NSArray<NSArray<NSString *> *> *defs = @[
        @[localize(@"ame369.vdet.overview", @"概览"),   @"square.grid.2x2",         @"circle.grid.2x2"],
        @[localize(@"ame369.vdet.config", @"配置"),   @"slider.horizontal.3",     @"gearshape"],
        @[localize(@"ame432.vdet.modify", @"修改版本"), @"square.and.pencil",       @"pencil.tip"],
        @[localize(@"ame369.common.mods", @"模组"),   @"puzzlepiece.extension",   @"puzzlepiece"],
        @[localize(@"ame369.common.worlds", @"存档"),   @"globe",                   @"circle"],
        @[localize(@"ame369.common.resource_packs", @"资源包"), @"paintbrush",              @"circle"],
        @[localize(@"ame369.common.shaders", @"光影"),   @"lightbulb",               @"circle"],
        @[localize(@"ame369.vdet.screenshots", @"截图"),   @"photo.on.rectangle",      @"photo"],
        @[localize(@"ame369.common.servers", @"服务器"), @"dns",                     @"network"],
    ];
    // division 位（★Task432：三组分隔 = ZL2 CategoryItem division 标记直译——
    //   ZL2 在 ModsManager 与 ServerList 项自带 division=true，TabMenu 渲染在
    //   项前插线 → iOS 同位 = 模组(idx 3)前 / 服务器(idx 8)前两处）
    NSArray<NSNumber *> *divisionMarks = @[@3, @8];

    for (NSUInteger i = 0; i < defs.count; i++) {
        if ([divisionMarks containsObject:@((NSInteger)i)]) {
            UIView *divider = [[UIView alloc] init];
            divider.backgroundColor = [ZL2Theme onSurface];
            divider.alpha = 0.4;
            divider.translatesAutoresizingMaskIntoConstraints = NO;
            divider.userInteractionEnabled = NO;
            [_railStack addArrangedSubview:divider];
            // ★ Task372：Fill 全宽行下分隔线不再约束内宽（自然铺满轨宽）；
            //   高度 1 不变，左右留白交给视觉（发丝线全宽不硌眼）
            [divider.heightAnchor constraintEqualToConstant:1].active = YES;
            [_railStack setCustomSpacing:12 afterView:divider];
        }

        NSArray<NSString *> *def = defs[i];
        ZL2VersionDetailNavItem *item = [[ZL2VersionDetailNavItem alloc] initWithFrame:CGRectZero];
        item.pageIndex = (NSInteger)i;
        item.label.text = def[0];
        item.icon.image = [ZL2V13SystemImage(def[1], def[2]) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        item.isAccessibilityElement = YES;
        item.accessibilityLabel = def[0];
        [item addTarget:self action:@selector(ameV13_railItemTapped:) forControlEvents:UIControlEventTouchUpInside];
        // ★ Task372：不再约束项内宽（Fill 对齐自动铺满 160pt 轨宽 = 命中面即整行）
        [item.heightAnchor constraintEqualToConstant:ZL2V13RailItemSize].active = YES;
        [_railStack addArrangedSubview:item];
        [_railItems addObject:item];
    }

    [NSLayoutConstraint activateConstraints:@[
        // ★ Task379：轨列前导对齐页头边距（8→ZL2V13PageMargin）——装机实锤：
        //   fluent NavigationView 窗格（280pt）右侧轨列贴 8pt 边带，比页头卡
        //   凸出 8pt = 用户感知"点位偏左"。对齐后轨列与页头卡同线，彻底
        //   脱离窗格邻接带；命中面仍为整列全宽（372 口径不变）。
        [_railStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:ZL2V13PageMargin],
        [_railStack.trailingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:ZL2V13PageMargin + ZL2V13RailWidth],
        [_railStack.topAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:12],
        [_railStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
    ]];

    // 内容容器 = 轨右到页尾的整块填充；子页内部自持 999 等式宽度收敛
    //（ZL2VersionsViewController L211-226 同款，最大宽由子页自管）
    _contentContainer = [[UIView alloc] init];
    _contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _contentContainer.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_contentContainer];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_contentContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:ZL2V13PageMargin + ZL2V13RailWidth + 4],
        [_contentContainer.topAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:12],
        [_contentContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-ZL2V13PageMargin],
        [_contentContainer.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
    ]];
}

#pragma mark - 子页切换（ZL2Shell 手法：懒建缓存 + addChild + crossDissolve）

- (void)ameV13_railItemTapped:(ZL2VersionDetailNavItem *)sender {
    [self ameV13_selectPage:sender.pageIndex];
}

- (UIViewController *)ameV13_childForIndex:(NSInteger)index {
    NSNumber *key = @(index);
    UIViewController *cached = self.ameV13_childCache[key];
    if (cached) return cached;

    UIViewController *vc = nil;
    NSString *profileName = self.ameV13_profileName;
    NSString *gameDir = [ZL2VersionDetailViewController ameV13_resolvedGameDirForProfileName:profileName];
    // ★Task432 实锤一：case 映射随 rail 9 项重排同步重编（ZL2 NavigationUI
    //   entryProvider 装载序 1:1：OverView→Config→ModifyVersion→Mods→Saves→
    //   ResourcePack→Shaders→Screenshots→ServerList）；idx 4 存档 = 本 .m 私有
    //   桥接页（内嵌存档原页 + 数据包入口行，缺口#6）。
    switch (index) {
        case 0: vc = [[ZL2VersionOverviewPage alloc]       initWithProfileName:profileName gameDir:gameDir]; break;
        case 1: vc = [[ZL2VersionConfigPage alloc]         initWithProfileName:profileName gameDir:gameDir]; break;
        case 2: vc = [[ZL2V13ModifyVersionPage alloc]      initWithProfileName:profileName gameDir:gameDir]; break;
        case 3: vc = [[ZL2VersionModsPage alloc]           initWithProfileName:profileName gameDir:gameDir]; break;
        case 4: vc = [[ZL2V13SavesDatapacksBridgePage alloc] initWithProfileName:profileName gameDir:gameDir]; break;
        case 5: vc = [[ZL2VersionResourcePacksPage alloc]  initWithProfileName:profileName gameDir:gameDir]; break;
        case 6: vc = [[ZL2VersionShadersPage alloc]        initWithProfileName:profileName gameDir:gameDir]; break;
        case 7: vc = [[ZL2VersionScreenshotsPage alloc]    initWithProfileName:profileName gameDir:gameDir]; break;
        case 8: vc = [[ZL2VersionServersPage alloc]        initWithProfileName:profileName gameDir:gameDir]; break;
        default: break;
    }
    if (!vc) return nil;
    self.ameV13_childCache[key] = vc;
    return vc;
}

- (void)ameV13_attachChildIfNeeded:(UIViewController *)child {
    if (child.parentViewController == self) return;
    [self addChildViewController:child];
    child.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentContainer addSubview:child.view];
    [NSLayoutConstraint activateConstraints:@[
        [child.view.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [child.view.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [child.view.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [child.view.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
    ]];
    [child didMoveToParentViewController:self];
}

- (void)ameV13_selectPage:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.railItems.count) return;
    if (index == self.ameV13_selectedIndex) return;

    UIViewController *next = [self ameV13_childForIndex:index];
    if (!next) return;

    UIViewController *prev = nil;
    if (self.ameV13_selectedIndex >= 0) {
        prev = self.ameV13_childCache[@(self.ameV13_selectedIndex)];
    }

    [self ameV13_attachChildIfNeeded:next];

    void (^apply)(void) = ^{
        prev.view.hidden = YES;
        next.view.hidden = NO;
    };
    if (prev && prev.view.superview) {
        [UIView transitionWithView:self.contentContainer
                          duration:ZL2V13AnimateDuration
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:apply
                        completion:nil];
    } else {
        apply();
    }

    self.ameV13_selectedIndex = index;
    [self.railItems enumerateObjectsUsingBlock:^(ZL2VersionDetailNavItem *item, NSUInteger idx, BOOL *stop) {
        [item ameV13_setSelected:((NSInteger)idx == index)];
    }];
}

#pragma mark - 完成

- (void)ameV13_finish {
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

@end

#pragma mark - ★Task432 实锤一：修改版本私有页（ZL2 ModifyVersionScreen.kt 语义）

// 交互语义对标 zl2-ref ModifyVersionScreen.kt：信息展示（实例名 / MC 版本 /
// 当前 loader 家族与版本）+ loader 家族列表选择 + 选版本 → 二次确认 → 安装。
// 安装链全量复用 PLComponentService（Task429 FCL 服务，零新安装代码）：
//   analyzeComponentsForProfile  → 当前家族展示（fabric/forge/neoforge/…
//     五分类扫描链，含 clean 链根 MC 版本）；
//   availableVersionsForComponentType → 版本选单（forge=BMCLAPI 清单面 /
//     neoforge=NeoForgeVersionFetcher / fabric=Fabric meta，服务内既有）；
//   installComponent:type:version: → 事务性换装（成功后 lastVersionId repoint
//     + ReloadProfileList 广播，旧版本实体保留；容器头卡经该广播即时刷新）。
// 家族面（任务规格五族）：Forge / NeoForge / Fabric = 可换装；Vanilla / Quilt
//   无既有安装 API（clean 仅展示不换版——PLComponentService :510 判例语义
//   「原版本体：换版本请走游戏下载页」/ quilt 仅检测谱系归并无安装器与清单源）→
//   展示但禁用并注明「暂不支持」（诚实边界，不造假入口）；★Task441 批次三②
//   页名如实改「更换加载器」（ame432.vdet.modify 四表+fill 同步）。
// 视觉 = 本文件页族同款（基类骨架 999 宽收敛 + surfaceContainer 行卡 +
//   ZL2Theme 令牌）；基类私有构件经文件头 Task432VPageBridge 自含声明消费。

static const CGFloat ZL2V13PageCardSpacing = 12.0;   // 页内行卡间距（ZL2VersionPages 常量族同值，TU 本地）

@interface ZL2V13ModifyVersionPage ()
@property (nonatomic, strong) UIStackView *ame432_contentStack;
@property (nonatomic, strong) UIStackView *ame432_familyStack;      // 家族行容器（重扫即重建）
@property (nonatomic, strong) UILabel *ame432_instanceValueLabel;
@property (nonatomic, strong) UILabel *ame432_mcValueLabel;
@property (nonatomic, strong) UILabel *ame432_loaderValueLabel;
@property (nonatomic, strong) UILabel *ame432_stateLabel;           // 获取版本/安装中态
@property (nonatomic, copy) NSString *ame432_gameVersion;           // 继承链根 MC 版本（clean 条目）
@property (nonatomic, copy) NSString *ame432_currentType;           // 当前在装 loader 家族（PLComponentType*）
@property (nonatomic, copy) NSString *ame432_currentVersion;        // 当前在装 loader 版本
@property (nonatomic, assign) BOOL ame432_busy;                     // 拉清单/安装中（行点击闸门）
@end

@implementation ZL2V13ModifyVersionPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    _ame432_contentStack = [self ameV13_installContentSkeleton];
    [_ame432_contentStack addArrangedSubview:
        [self ameV13_pageHeaderRowWithTitle:localize(@"ame432.vdet.modify", @"修改版本") trailing:nil]];

    // ① 信息卡三行：实例 / MC 版本 / 当前加载器（ModifyVersionScreen 信息行语义）
    _ame432_instanceValueLabel = [self ame432_infoValueLabel];
    _ame432_mcValueLabel = [self ame432_infoValueLabel];
    _ame432_loaderValueLabel = [self ame432_infoValueLabel];
    UILabel *instanceTitle = [self ame432_infoTitleLabel:localize(@"ame432.vdet.modify.instance", @"实例")];
    UILabel *mcTitle = [self ame432_infoTitleLabel:localize(@"ame432.vdet.modify.mc_version", @"MC 版本")];
    UILabel *loaderTitle = [self ame432_infoTitleLabel:localize(@"ame432.vdet.modify.current_loader", @"当前加载器")];
    UIView *instanceCard = [self ameV13_rowCardWithViews:@[instanceTitle, [self ame432_spacer], _ame432_instanceValueLabel]
                                               alignment:UIStackViewAlignmentCenter];
    UIView *mcCard = [self ameV13_rowCardWithViews:@[mcTitle, [self ame432_spacer], _ame432_mcValueLabel]
                                         alignment:UIStackViewAlignmentCenter];
    UIView *loaderCard = [self ameV13_rowCardWithViews:@[loaderTitle, [self ame432_spacer], _ame432_loaderValueLabel]
                                             alignment:UIStackViewAlignmentCenter];
    _ame432_instanceValueLabel.text = self.ameV13_profileName;
    [_ame432_contentStack addArrangedSubview:instanceCard];
    [_ame432_contentStack addArrangedSubview:mcCard];
    [_ame432_contentStack addArrangedSubview:loaderCard];

    // ② loader 家族区（ModifyVersionScreen loader 列表选择语义）：
    //    目标加载器小节标题 + 五族行（重扫即重建）
    UILabel *familyTitle = [[UILabel alloc] init];
    familyTitle.text = localize(@"ame432.vdet.modify.family_title", @"目标加载器（点击选择版本后安装）");
    familyTitle.font = [ZL2Theme fontTitleMedium];
    familyTitle.textColor = [ZL2Theme onSurface];
    familyTitle.numberOfLines = 1;
    familyTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [_ame432_contentStack addArrangedSubview:familyTitle];

    _ame432_familyStack = [[UIStackView alloc] init];
    _ame432_familyStack.axis = UILayoutConstraintAxisVertical;
    _ame432_familyStack.alignment = UIStackViewAlignmentFill;
    _ame432_familyStack.spacing = ZL2V13PageCardSpacing;
    _ame432_familyStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_ame432_contentStack addArrangedSubview:_ame432_familyStack];

    // ③ 态行（获取版本 / 安装中；闲时隐藏）
    _ame432_stateLabel = [[UILabel alloc] init];
    _ame432_stateLabel.font = [ZL2Theme fontBodyMedium];
    _ame432_stateLabel.textColor = [ZL2Theme onSurfaceVariant];
    _ame432_stateLabel.numberOfLines = 0;
    _ame432_stateLabel.textAlignment = NSTextAlignmentCenter;
    _ame432_stateLabel.hidden = YES;
    _ame432_stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_ame432_contentStack addArrangedSubview:_ame432_stateLabel];

    // 首扫由基类 viewWillAppear → ameV13_reloadContent 触发（防双发）
}

// 返回本页即重扫（换装成功 pop 回来/ReloadProfileList 后条目即时刷新）
- (void)ameV13_reloadContent {
    __weak typeof(self) wself = self;
    [PLComponentService analyzeComponentsForProfile:self.ameV13_profileName
                                         completion:^(NSArray<PLComponentEntry *> *entries) {
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        [sself ame432_applyEntries:entries];
    }];
}

// 概览页重命名后容器广播 → 实例行即时跟随（基类只改 name/title，这里补 UI）
- (void)ameV13_updateProfileName:(NSString *)newName {
    [super ameV13_updateProfileName:newName];
    self.ame432_instanceValueLabel.text = newName;
}

#pragma mark 信息卡构件

- (UILabel *)ame432_infoTitleLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [ZL2Theme fontBodyMedium];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (UILabel *)ame432_infoValueLabel {
    UILabel *label = [[UILabel alloc] init];
    label.font = [ZL2Theme fontBodyMedium];
    label.textColor = [ZL2Theme onSurface];
    label.numberOfLines = 1;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.textAlignment = NSTextAlignmentRight;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (UIView *)ame432_spacer {
    UIView *spacer = [[UIView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:248 forAxis:UILayoutConstraintAxisHorizontal];
    [spacer setContentCompressionResistancePriority:249 forAxis:UILayoutConstraintAxisHorizontal];
    return spacer;
}

#pragma mark 分析结果渲染

- (void)ame432_applyEntries:(NSArray<PLComponentEntry *> *)entries {
    NSString *mcVersion = nil;
    NSString *currentType = nil;
    NSString *currentVersion = nil;
    for (PLComponentEntry *entry in entries) {
        if ([entry.type isEqualToString:PLComponentTypeClean]) {
            // clean = 干净本体条目：MC 版本取继承链根（服务口径）
            if (!mcVersion && entry.minecraftVersion.length > 0) mcVersion = entry.minecraftVersion;
        } else if (!currentType && ![entry.type isEqualToString:PLComponentTypeOptiFine]) {
            // loader 家族 = 首个非 clean/optifine 条目（服务返回序 fabric→forge→neoforge）
            currentType = entry.type;
            currentVersion = entry.version;
        }
    }
    self.ame432_gameVersion = mcVersion;
    self.ame432_currentType = currentType;
    self.ame432_currentVersion = currentVersion;

    self.ame432_mcValueLabel.text = mcVersion.length > 0 ? mcVersion : @"—";
    if (currentType.length > 0) {
        NSString *familyName = [PLComponentService displayNameForComponentType:currentType];
        self.ame432_loaderValueLabel.text = currentVersion.length > 0
            ? [NSString stringWithFormat:@"%@ %@", familyName, currentVersion]
            : familyName;
    } else {
        self.ame432_loaderValueLabel.text = localize(@"ame432.vdet.modify.loader_none", @"原版（未装加载器）");
    }

    [self ame432_rebuildFamilyRows];
}

/// 家族行重建（analyze 后 / 换装完成后调用；禁用行不可点，无造假入口）
- (void)ame432_rebuildFamilyRows {
    for (UIView *v in [_ame432_familyStack.arrangedSubviews copy]) [v removeFromSuperview];
    NSArray<NSArray *> *defs = [self ame432_familyDefs];

    [defs enumerateObjectsUsingBlock:^(NSArray *def, NSUInteger idx, BOOL *stop) {
        NSString *displayName = def[0];
        NSString *type = def[1];
        BOOL enabled = [def[2] boolValue];
        BOOL isCurrent = (self.ame432_currentType.length > 0 &&
                          [self.ame432_currentType isEqualToString:type]);

        UILabel *title = [[UILabel alloc] init];
        title.text = displayName;
        title.font = [ZL2Theme fontBodyMedium];
        title.textColor = enabled ? [ZL2Theme onSurface] : [ZL2Theme onSurfaceVariant];
        title.numberOfLines = 1;
        title.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *value = [[UILabel alloc] init];
        value.font = [ZL2Theme fontLabelMedium];
        value.textColor = enabled ? [ZL2Theme primary] : [ZL2Theme onSurfaceVariant];
        value.numberOfLines = 1;
        value.lineBreakMode = NSLineBreakByTruncatingMiddle;
        value.textAlignment = NSTextAlignmentRight;
        if (isCurrent) {
            // 当前在装家族：尾随当前版本号（ModifyVersionScreen installed 语义）
            NSString *v = self.ame432_currentVersion;
            value.text = v.length > 0
                ? [NSString stringWithFormat:localize(@"ame432.vdet.modify.current_fmt", @"当前 %@"), v]
                : localize(@"ame432.vdet.modify.current_fmt", @"当前 %@");
        } else if (enabled) {
            value.text = localize(@"ame432.vdet.modify.tap_hint", @"点击选择版本");
        } else {
            value.text = localize(@"ame432.vdet.modify.unsupported", @"暂不支持");
        }
        value.translatesAutoresizingMaskIntoConstraints = NO;

        NSMutableArray *views = [NSMutableArray arrayWithObject:title];
        [views addObject:[self ame432_spacer]];
        [views addObject:value];
        if (enabled) {
            UIImageView *chevron = [[UIImageView alloc] initWithImage:
                [ZL2V13SystemImage(@"chevron.right", @"chevron.forward") imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
            chevron.tintColor = [ZL2Theme onSurfaceVariant];
            chevron.contentMode = UIViewContentModeScaleAspectFit;
            chevron.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [chevron.widthAnchor constraintEqualToConstant:16],
                [chevron.heightAnchor constraintEqualToConstant:16],
            ]];
            [views addObject:chevron];
        }

        UIControl *row = [[UIControl alloc] init];
        row.backgroundColor = [ZL2Theme surfaceContainer];
        row.layer.cornerRadius = [ZL2Theme radiusM];
        row.layer.masksToBounds = YES;
        row.tag = (NSInteger)idx;   // 仅作 ame432_familyTapped: 下标载荷（域内判例）
        row.isAccessibilityElement = YES;
        row.accessibilityTraits = enabled ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
        // 括号内 ?: 雷区判例：三元式出括号再拼 a11y 描述
        NSString *valueText = value.text;
        if (valueText.length == 0) valueText = @"";
        row.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", displayName, valueText];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.userInteractionEnabled = enabled && !self.ame432_busy;

        // 行卡几何照基类 ameV13_rowCardWithViews（内边距 14，行尾钉卡缘）
        UIStackView *inner = [[UIStackView alloc] initWithArrangedSubviews:views];
        inner.axis = UILayoutConstraintAxisHorizontal;
        inner.alignment = UIStackViewAlignmentCenter;
        inner.spacing = ZL2V13PageCardSpacing;
        inner.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:inner];
        [NSLayoutConstraint activateConstraints:@[
            [inner.topAnchor constraintEqualToAnchor:row.topAnchor constant:14],
            [inner.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-14],
            [inner.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14],
            [inner.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14],
            [row.heightAnchor constraintGreaterThanOrEqualToConstant:52],
        ]];

        if (enabled) {
            [row addTarget:self action:@selector(ame432_familyTapped:) forControlEvents:UIControlEventTouchUpInside];
        }
        [_ame432_familyStack addArrangedSubview:row];
    }];
}

#pragma mark 家族选择 → 版本选单 → 确认安装

/// 家族五族定义单一源（(显示名, PLComponentService type, 可安装)）：
///   Vanilla / Forge / NeoForge / Fabric / Quilt 按任务规格；forge/neoforge/
///   fabric = 既有安装 API 三族；vanilla（clean 仅展示）/ quilt（无安装器）
///   禁用。行渲染与点击分流共用本表，禁分叉。
- (NSArray<NSArray *> *)ame432_familyDefs {
    return @[
        @[localize(@"ame432.vdet.modify.family.vanilla", @"原版"), PLComponentTypeClean, @NO],
        @[@"Forge",   PLComponentTypeForge,    @YES],
        @[@"NeoForge", PLComponentTypeNeoForge, @YES],
        @[@"Fabric",  PLComponentTypeFabric,   @YES],
        @[@"Quilt",   @"quilt",                @NO],
    ];
}

- (void)ame432_familyTapped:(UIControl *)sender {
    if (self.ame432_busy) return;
    NSArray<NSArray *> *defs = [self ame432_familyDefs];
    NSUInteger idx = (NSUInteger)sender.tag;
    if (idx >= defs.count) return;
    NSString *displayName = defs[idx][0];
    NSString *type = defs[idx][1];

    // 无本体版本（未装/版本 JSON 不可读）→ 诚实拦截（服务侧也会失败，这里提前给因）
    if (self.ame432_gameVersion.length == 0) {
        [self ameV13_showAlertMessage:localize(@"ame432.vdet.modify.no_base", @"实例尚未安装 MC 版本，无法修改加载器")];
        return;
    }

    self.ame432_busy = YES;
    self.ame432_stateLabel.hidden = NO;
    self.ame432_stateLabel.text = [NSString stringWithFormat:
        localize(@"ame432.vdet.modify.versions_loading", @"正在获取 %@ 可用版本…"), displayName];
    __weak typeof(self) wself = self;
    [PLComponentService availableVersionsForComponentType:type
                                              gameVersion:self.ame432_gameVersion
                                               completion:^(NSArray<NSString *> *versions, NSError *error) {
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        sself.ame432_busy = NO;
        sself.ame432_stateLabel.hidden = YES;
        if (error || versions.count == 0) {
            NSString *detail = error.localizedDescription;
            if (detail.length == 0) detail = @"";
            NSString *noVersions = localize(@"ame432.vdet.modify.no_versions",
                                            @"暂无可用版本（网络异常或该 MC 版本不受支持）");
            if (detail.length > 0) {
                [sself ameV13_showAlertMessage:[NSString stringWithFormat:@"%@\n%@", noVersions, detail]];
            } else {
                [sself ameV13_showAlertMessage:noVersions];
            }
            return;
        }
        [sself ame432_presentVersionPicker:versions familyName:displayName type:type];
    }];
}

/// 版本选单（ModifyVersionScreen 列表选择语义；actionSheet 滚动承载全量清单，
/// iPad 锚点照配置页 ameV13_showPresetPicker 判例）
- (void)ame432_presentVersionPicker:(NSArray<NSString *> *)versions
                         familyName:(NSString *)familyName
                               type:(NSString *)type {
    NSString *titleText = [NSString stringWithFormat:
        localize(@"ame432.vdet.modify.pick_version_title", @"选择 %@ 版本"), familyName];
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:titleText
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *version in versions) {
        if (![version isKindOfClass:[NSString class]] || version.length == 0) continue;
        [picker addAction:[UIAlertAction actionWithTitle:version
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
            [self ame432_confirmInstall:version familyName:familyName type:type];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    picker.popoverPresentationController.sourceView = self.view;
    picker.popoverPresentationController.sourceRect =
        CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1.0, 1.0);
    [self presentViewController:picker animated:YES completion:nil];
}

/// 换版二次确认（UI 层职责，PLComponentService .h 约定；M3Dialog 照
/// PLComponentsPage 确认单判例）
- (void)ame432_confirmInstall:(NSString *)version familyName:(NSString *)familyName type:(NSString *)type {
    // 括号内 ?: 雷区判例：fallback 先出括号再拼串
    NSString *mcVersion = self.ame432_gameVersion;
    if (mcVersion.length == 0) mcVersion = @"";
    NSString *bodyText = [NSString stringWithFormat:
        localize(@"ame432.vdet.modify.confirm_body",
                 @"将为实例「%@」安装 %@ %@（MC %@）。\n安装成功后实例指向新版本实体，旧版本实体保留。"),
        self.ameV13_profileName, familyName, version, mcVersion];
    __weak typeof(self) wself = self;
    [ZL2M3Dialog showTitle:localize(@"ame432.vdet.modify.confirm_title", @"确认安装")
                      body:bodyText
              confirmTitle:localize(@"ame432.vdet.modify.confirm_install", @"安装")
                destructive:NO
                 onConfirm:^{
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        [sself ame432_startInstall:version familyName:familyName type:type];
    }
                   onCancel:nil];
}

- (void)ame432_startInstall:(NSString *)version familyName:(NSString *)familyName type:(NSString *)type {
    self.ame432_busy = YES;
    [self ame432_setFamilyRowsInteractive:NO];
    self.ame432_stateLabel.hidden = NO;
    self.ame432_stateLabel.text = [NSString stringWithFormat:
        localize(@"ame432.vdet.modify.installing", @"正在安装 %@ %@…"), familyName, version];
    __weak typeof(self) wself = self;
    [PLComponentService installComponent:self.ameV13_profileName
                                    type:type
                                 version:version
                              completion:^(BOOL success, NSString *newVersionId, NSError *error) {
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        sself.ame432_busy = NO;
        sself.ame432_stateLabel.hidden = YES;
        if (success) {
            // 服务侧已 repoint lastVersionId 并广播 ReloadProfileList（容器头卡
            //   随监听刷新）；本页重扫即得新家族态
            NSString *entityText = newVersionId;
            if (entityText.length == 0) entityText = @"";
            [sself ameV13_showAlertMessage:[NSString stringWithFormat:
                localize(@"ame432.vdet.modify.install_ok", @"已安装 %@（版本实体 %@）"),
                familyName, entityText]];
            [sself ameV13_reloadContent];
        } else {
            NSString *detail = error.localizedDescription;
            NSString *failed = localize(@"ame432.vdet.modify.install_failed", @"安装失败");
            if (detail.length > 0) {
                [sself ameV13_showAlertMessage:[NSString stringWithFormat:@"%@: %@", failed, detail]];
            } else {
                [sself ameV13_showAlertMessage:failed];
            }
            [sself ame432_setFamilyRowsInteractive:YES];
        }
    }];
}

- (void)ame432_setFamilyRowsInteractive:(BOOL)interactive {
    // 可点集 = ame432_familyDefs 中 enabled 家族（单一源，防顺序漂移后错位）
    NSMutableSet<NSNumber *> *enabledTags = [NSMutableSet set];
    [[self ame432_familyDefs] enumerateObjectsUsingBlock:^(NSArray *def, NSUInteger idx, BOOL *stop) {
        if ([def[2] boolValue]) [enabledTags addObject:@((NSInteger)idx)];
    }];
    for (UIView *v in _ame432_familyStack.arrangedSubviews) {
        if ([v isKindOfClass:[UIControl class]]) {
            UIControl *row = (UIControl *)v;
            row.userInteractionEnabled = interactive && [enabledTags containsObject:@(row.tag)];
        }
    }
}

@end

#pragma mark - ★Task432 缺口#6：存档桥接页（内嵌存档原页 + 数据包入口行）

// rail 第 5 项「存档」= 本桥接页：原 ZL2VersionSavesPage 整页零回归内嵌
// （addChild + 四边钉入；appearance 回调由 UIKit 沿子 VC 链自动透传，存档
// 重扫语义不变），顶部加一行「数据包」入口卡（缺口#6：入口在存档子页内）。
// 世界目录解析 = 存档原页同款口径：<gameDir>/saves/<world>（数据包位于
// saves/<world>/datapacks/，Minecraft 存档域标准布局，非自造路径）。

@interface ZL2V13SavesDatapacksBridgePage ()
@property (nonatomic, strong) ZL2VersionSavesPage *ame432_savesChild;
@property (nonatomic, strong) UIControl *ame432_entryRow;
@end

@implementation ZL2V13SavesDatapacksBridgePage

- (instancetype)initWithProfileName:(NSString *)profileName gameDir:(NSString *)gameDir {
    self = [super initWithProfileName:profileName gameDir:gameDir];
    if (!self) return self;
    _ame432_savesChild = [[ZL2VersionSavesPage alloc] initWithProfileName:profileName gameDir:gameDir];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    // 「数据包」入口行（行卡形态与页族一致；点击 → 世界选择 → 数据包子页）
    UILabel *title = [[UILabel alloc] init];
    title.text = localize(@"ame432.vdet.datapacks.entry", @"数据包");
    title.font = [ZL2Theme fontBodyMedium];
    title.textColor = [ZL2Theme onSurface];
    title.numberOfLines = 1;
    title.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *hint = [[UILabel alloc] init];
    hint.text = localize(@"ame432.vdet.datapacks.entry_hint", @"世界目录内管理");
    hint.font = [ZL2Theme fontLabelMedium];
    hint.textColor = [ZL2Theme onSurfaceVariant];
    hint.numberOfLines = 1;
    hint.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *chevron = [[UIImageView alloc] initWithImage:
        [ZL2V13SystemImage(@"chevron.right", @"chevron.forward") imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    chevron.tintColor = [ZL2Theme onSurfaceVariant];
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [chevron.widthAnchor constraintEqualToConstant:16],
        [chevron.heightAnchor constraintEqualToConstant:16],
    ]];

    UIView *iconBox = [self ameV13_iconBoxWithSymbol:@"doc.zipper" fallback:@"doc" size:42 iconSize:22];

    UIView *spacer = [[UIView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:248 forAxis:UILayoutConstraintAxisHorizontal];
    [spacer setContentCompressionResistancePriority:249 forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[title, hint]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.alignment = UIStackViewAlignmentLeading;
    textStack.spacing = 2;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *inner = [[UIStackView alloc] initWithArrangedSubviews:@[iconBox, textStack, spacer, chevron]];
    inner.axis = UILayoutConstraintAxisHorizontal;
    inner.alignment = UIStackViewAlignmentCenter;
    inner.spacing = ZL2V13PageCardSpacing;
    inner.translatesAutoresizingMaskIntoConstraints = NO;

    _ame432_entryRow = [[UIControl alloc] init];
    _ame432_entryRow.backgroundColor = [ZL2Theme surfaceContainer];
    _ame432_entryRow.layer.cornerRadius = [ZL2Theme radiusM];
    _ame432_entryRow.layer.masksToBounds = YES;
    _ame432_entryRow.translatesAutoresizingMaskIntoConstraints = NO;
    _ame432_entryRow.isAccessibilityElement = YES;
    _ame432_entryRow.accessibilityTraits = UIAccessibilityTraitButton;
    _ame432_entryRow.accessibilityLabel = localize(@"ame432.vdet.datapacks.entry", @"数据包");
    [_ame432_entryRow addSubview:inner];
    [NSLayoutConstraint activateConstraints:@[
        [inner.topAnchor constraintEqualToAnchor:_ame432_entryRow.topAnchor constant:10],
        [inner.bottomAnchor constraintEqualToAnchor:_ame432_entryRow.bottomAnchor constant:-10],
        [inner.leadingAnchor constraintEqualToAnchor:_ame432_entryRow.leadingAnchor constant:14],
        [inner.trailingAnchor constraintEqualToAnchor:_ame432_entryRow.trailingAnchor constant:-14],
        [_ame432_entryRow.heightAnchor constraintGreaterThanOrEqualToConstant:52],
    ]];
    [_ame432_entryRow addTarget:self action:@selector(ame432_datapacksEntryTapped)
              forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_ame432_entryRow];

    // 内嵌存档原页（addChild 四边钉入；重扫/导入/删除语义零回归）
    [self addChildViewController:_ame432_savesChild];
    _ame432_savesChild.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_ame432_savesChild.view];
    [NSLayoutConstraint activateConstraints:@[
        [_ame432_entryRow.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_ame432_entryRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_ame432_entryRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [_ame432_savesChild.view.topAnchor constraintEqualToAnchor:_ame432_entryRow.bottomAnchor constant:ZL2V13PageCardSpacing],
        [_ame432_savesChild.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_ame432_savesChild.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_ame432_savesChild.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [_ame432_savesChild didMoveToParentViewController:self];
}

// 概览页重命名广播 → 内嵌存档页一并跟随（容器只认 ZL2VersionPageBase 桥接层）
- (void)ameV13_updateProfileName:(NSString *)newName {
    [super ameV13_updateProfileName:newName];
    [_ame432_savesChild ameV13_updateProfileName:newName];
}

#pragma mark 入口：世界选择 → 数据包子页

- (void)ame432_datapacksEntryTapped {
    // 世界目录枚举（存档原页同口径：<gameDir>/saves/ 下的一级目录）
    NSString *savesDir = [self.ameV13_gameDir stringByAppendingPathComponent:@"saves"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:savesDir error:nil];
    NSMutableArray<NSString *> *worlds = [NSMutableArray array];
    for (NSString *name in contents) {
        if (name.length == 0 || [name hasPrefix:@"."]) continue;
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:[savesDir stringByAppendingPathComponent:name] isDirectory:&isDir] && isDir) {
            [worlds addObject:name];
        }
    }
    [worlds sortUsingSelector:@selector(localizedStandardCompare:)];

    if (worlds.count == 0) {
        [self ameV13_showAlertMessage:localize(@"ame432.vdet.datapacks.no_world",
                                                @"暂无存档（数据包位于世界存档目录内）")];
        return;
    }
    if (worlds.count == 1) {
        [self ame432_openDatapacksForWorld:worlds.firstObject];
        return;
    }
    // 多世界 → 世界选单（Minecraft 数据包语义：datapacks 属于每个世界各一份）
    UIAlertController *picker = [UIAlertController
        alertControllerWithTitle:localize(@"ame432.vdet.datapacks.pick_world", @"选择要管理数据包的世界")
                          message:nil
                   preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *worldName in worlds) {
        [picker addAction:[UIAlertAction actionWithTitle:worldName
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
            [self ame432_openDatapacksForWorld:worldName];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    picker.popoverPresentationController.sourceView = self.view;
    picker.popoverPresentationController.sourceRect =
        CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1.0, 1.0);
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)ame432_openDatapacksForWorld:(NSString *)worldName {
    NSString *worldPath = [[self.ameV13_gameDir stringByAppendingPathComponent:@"saves"]
                           stringByAppendingPathComponent:worldName];
    ZL2V13DatapacksPage *vc = [[ZL2V13DatapacksPage alloc] initWithWorldPath:worldPath worldName:worldName];
    // 宿主 nav push；无 nav 宿主时 present 包 nav 兜底（ZL2AssetSearch ame_push 同判例）
    if (self.navigationController) {
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

@end

#pragma mark - ★Task432 缺口#6：数据包第九子页（datapacks/ 枚举 + 删除 + 导入）

// 世界存档目录 datapacks/ 子目录管理页（Minecraft 数据包域标准布局：
// <gameDir>/saves/<world>/datapacks/，条目 = zip 或同名目录，游戏内加载
// 时自校验 pack.mcmeta，本页不做格式裁剪 = 与游戏同口径）。语义对标
// ZL2 数据包下载轨（Task432 收敛注记「数据包→版本子页第九子页」）的本地
// 管理端：列表 / 删除（M3 确认弹窗）/ 导入（UIDocumentPicker 拷入 zip 或
// 文件夹）。i18n = ame432.vdet.datapacks.*（键清单见移交报告）。

@interface ZL2V13DatapacksPage () <UIDocumentPickerDelegate>
@property (nonatomic, copy) NSString *ame432_worldPath;
@property (nonatomic, copy) NSString *ame432_worldName;
@property (nonatomic, strong) UIStackView *ame432_contentStack;
@property (nonatomic, strong) UIStackView *ame432_cardsStack;
@property (nonatomic, copy) NSArray<NSDictionary *> *ame432_rows;
@end

@implementation ZL2V13DatapacksPage

- (instancetype)initWithWorldPath:(NSString *)worldPath worldName:(NSString *)worldName {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return self;
    _ame432_worldPath = [worldPath copy];
    _ame432_worldName = [worldName copy];
    self.title = localize(@"ame432.vdet.datapacks.entry", @"数据包");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // push 实底页（与 attached 子页 clear 底不同；ZL2AssetSearch 版本页同款）
    self.view.backgroundColor = [ZL2Theme surface];

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

    _ame432_contentStack = [[UIStackView alloc] init];
    _ame432_contentStack.axis = UILayoutConstraintAxisVertical;
    _ame432_contentStack.alignment = UIStackViewAlignmentFill;
    _ame432_contentStack.spacing = ZL2V13PageCardSpacing;
    _ame432_contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:_ame432_contentStack];

    UILayoutGuide *contentLG = scrollView.contentLayoutGuide;
    UILayoutGuide *frameLG = scrollView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_ame432_contentStack.topAnchor constraintEqualToAnchor:contentLG.topAnchor constant:12],
        [contentLG.bottomAnchor constraintGreaterThanOrEqualToAnchor:_ame432_contentStack.bottomAnchor constant:24],
        [_ame432_contentStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:contentLG.leadingAnchor constant:0],
        [contentLG.trailingAnchor constraintGreaterThanOrEqualToAnchor:_ame432_contentStack.trailingAnchor constant:0],
        [_ame432_contentStack.centerXAnchor constraintEqualToAnchor:frameLG.centerXAnchor],
        [_ame432_contentStack.widthAnchor constraintLessThanOrEqualToConstant:720.0],
    ]];
    NSLayoutConstraint *fillWidth = [_ame432_contentStack.widthAnchor constraintEqualToAnchor:frameLG.widthAnchor];
    fillWidth.priority = 999;
    fillWidth.active = YES;

    // 页头行：页名 + 世界名副行 ｜ 右侧导入钮（saves 页 import 图标钮同款）
    // 弱捕获：action block 经关联对象被按钮持有，强捕自引用 = pop 后页泄漏
    __weak typeof(self) wself = self;
    UIControl *importButton = [self ame432_iconButtonWithImageName:@"square.and.arrow.down"
                                                          fallback:@"tray.and.arrow.down"
                                                             size:32
                                                    accessibility:localize(@"ame432.vdet.datapacks.import", @"导入数据包")
                                                           action:^{ [wself ame432_importTapped]; }];
    UILabel *pageTitle = [[UILabel alloc] init];
    pageTitle.text = localize(@"ame432.vdet.datapacks.entry", @"数据包");
    pageTitle.font = [ZL2Theme fontTitleMedium];
    pageTitle.textColor = [ZL2Theme onSurface];
    pageTitle.numberOfLines = 1;
    pageTitle.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *worldLabel = [[UILabel alloc] init];
    // 括号内 ?: 雷区判例：世界名 fallback 先出括号
    NSString *worldNameText = self.ame432_worldName;
    if (worldNameText.length == 0) worldNameText = @"";
    worldLabel.text = [NSString stringWithFormat:
        localize(@"ame432.vdet.datapacks.world_fmt", @"世界：%@"), worldNameText];
    worldLabel.font = [ZL2Theme fontLabelMedium];
    worldLabel.textColor = [ZL2Theme onSurfaceVariant];
    worldLabel.numberOfLines = 1;
    worldLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    worldLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *spacer = [[UIView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:248 forAxis:UILayoutConstraintAxisHorizontal];
    [spacer setContentCompressionResistancePriority:249 forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *titleStack = [[UIStackView alloc] initWithArrangedSubviews:@[pageTitle, worldLabel]];
    titleStack.axis = UILayoutConstraintAxisVertical;
    titleStack.alignment = UIStackViewAlignmentLeading;
    titleStack.spacing = 2;
    titleStack.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[titleStack, spacer, importButton]];
    header.axis = UILayoutConstraintAxisHorizontal;
    header.alignment = UIStackViewAlignmentCenter;
    header.spacing = ZL2V13PageCardSpacing;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [_ame432_contentStack addArrangedSubview:header];

    _ame432_cardsStack = [[UIStackView alloc] init];
    _ame432_cardsStack.axis = UILayoutConstraintAxisVertical;
    _ame432_cardsStack.alignment = UIStackViewAlignmentFill;
    _ame432_cardsStack.spacing = ZL2V13PageCardSpacing;
    _ame432_cardsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_ame432_contentStack addArrangedSubview:_ame432_cardsStack];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self ame432_reload];
}

#pragma mark 数据包枚举（zip / 目录双形态）

- (void)ame432_reload {
    NSString *packsDir = [self.ame432_worldPath stringByAppendingPathComponent:@"datapacks"];
    // ★Task434 弱捕获：一次性 async 块不直捕 self（对齐本页 wself/sself 家法）
    __weak typeof(self) wself = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:packsDir error:nil];
        NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
        for (NSString *name in contents) {
            if (name.length == 0 || [name hasPrefix:@"."]) continue;
            NSString *path = [packsDir stringByAppendingPathComponent:name];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:path isDirectory:&isDir]) continue;
            // Minecraft 数据包形态 = zip 包 或 目录；其余文件跳过（游戏不识别）
            if (!isDir && ![name.lowercaseString hasSuffix:@".zip"]) continue;
            NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
            unsigned long long size = [attrs fileSize];
            NSDate *modified = [attrs fileModificationDate];
            if (!modified) modified = [NSDate date];
            [rows addObject:@{
                @"name": name,
                @"path": path,
                @"isDir": @(isDir),
                @"size": @(size),
                @"modified": modified,
            }];
        }
        // 按修改时间降序（最近导入先看；存档页排序口径同款）
        [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [b[@"modified"] compare:a[@"modified"]];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself;   // ★Task434 弱捕获对齐
            if (!sself) return;
            sself.ame432_rows = rows;
            [sself ame432_rebuildCards];
        });
    });
}

- (void)ame432_rebuildCards {
    for (UIView *v in [_ame432_cardsStack.arrangedSubviews copy]) [v removeFromSuperview];
    if (self.ame432_rows.count == 0) {
        [_ame432_cardsStack addArrangedSubview:
            [self ame432_emptyStateWithSymbol:@"doc.zipper" fallback:@"doc"
                                         text:localize(@"ame432.vdet.datapacks.empty",
                                                       @"暂无数据包。点右上角导入 zip 或文件夹。")]];
        return;
    }
    for (NSDictionary *row in self.ame432_rows) {
        [_ame432_cardsStack addArrangedSubview:[self ame432_cardForRow:row]];
    }
}

- (UIView *)ame432_cardForRow:(NSDictionary *)row {
    BOOL isDir = [row[@"isDir"] boolValue];
    UIView *iconBox = [self ame432_iconBoxWithSymbol:(isDir ? @"folder" : @"doc.zipper")
                                            fallback:(isDir ? @"folder.fill" : @"doc")
                                                size:42
                                            iconSize:22];

    NSString *name = row[@"name"];
    // 尾行：目录形态 → 「目录」；zip → 人类可读大小（NSByteCountFormatter 计忆档口径）
    NSString *detailText = isDir
        ? localize(@"ame432.vdet.datapacks.dir_tag", @"目录")
        : [NSByteCountFormatter stringFromByteCount:[row[@"size"] longLongValue]
                                         countStyle:NSByteCountFormatterCountStyleMemory];

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = name;
    nameLabel.font = [ZL2Theme fontTitleMedium];
    nameLabel.textColor = [ZL2Theme onSurface];
    nameLabel.numberOfLines = 1;
    nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *detailLabel = [[UILabel alloc] init];
    detailLabel.text = detailText;
    detailLabel.font = [ZL2Theme fontLabelMedium];
    detailLabel.textColor = [ZL2Theme onSurfaceVariant];
    detailLabel.numberOfLines = 1;
    detailLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[nameLabel, detailLabel]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.alignment = UIStackViewAlignmentLeading;
    textStack.spacing = 2;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    [textStack setContentHuggingPriority:249 forAxis:UILayoutConstraintAxisHorizontal];
    [textStack setContentCompressionResistancePriority:249 forAxis:UILayoutConstraintAxisHorizontal];

    // 弱捕获：action block 经关联对象被按钮持有，强捕自引用 = pop 后页泄漏
    __weak typeof(self) wself = self;
    UIControl *deleteButton = [self ame432_iconButtonWithImageName:@"trash"
                                                          fallback:@"trash.fill"
                                                             size:32
                                                    accessibility:localize(@"resman.common.delete", nil)
                                                           action:^{ [wself ame432_confirmDeleteRow:row]; }];

    UIView *spacer = [[UIView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:248 forAxis:UILayoutConstraintAxisHorizontal];
    [spacer setContentCompressionResistancePriority:249 forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *inner = [[UIStackView alloc] initWithArrangedSubviews:@[iconBox, textStack, spacer, deleteButton]];
    inner.axis = UILayoutConstraintAxisHorizontal;
    inner.alignment = UIStackViewAlignmentCenter;
    inner.spacing = ZL2V13PageCardSpacing;
    inner.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [ZL2Theme surfaceContainer];
    card.layer.cornerRadius = [ZL2Theme radiusM];
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:inner];
    [NSLayoutConstraint activateConstraints:@[
        [inner.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],
        [inner.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10],
        [inner.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [inner.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
    ]];
    return card;
}

#pragma mark 删除（M3 确认弹窗）

- (void)ame432_confirmDeleteRow:(NSDictionary *)row {
    NSString *name = row[@"name"];
    NSString *path = row[@"path"];
    NSString *bodyText = [NSString stringWithFormat:
        localize(@"ame432.vdet.datapacks.delete_confirm", @"删除数据包「%@」？该操作不可撤销。"), name];
    __weak typeof(self) wself = self;
    [ZL2M3Dialog showTitle:localize(@"resman.common.confirm_delete", nil)
                      body:bodyText
              confirmTitle:localize(@"resman.common.delete", nil)
                destructive:YES
                 onConfirm:^{
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        NSError *err = nil;
        if ([NSFileManager.defaultManager removeItemAtPath:path error:&err]) {
            NSLog(@"[ZL2VersionDetail] Task432: datapack removed: %@", name);
            [sself ame432_reload];
        } else {
            // 括号内 ?: 雷区判例：错误文案出括号再拼（CleanupViewController L120）
            NSString *failedText = localize(@"resman.common.delete_failed", nil);
            NSString *detail = err.localizedDescription;
            if (detail.length == 0) detail = @"";
            [sself ame432_showAlert:[NSString stringWithFormat:@"%@: %@", failedText, detail]];
        }
    }
                   onCancel:nil];
}

#pragma mark 导入（UIDocumentPicker 拷入 zip / 文件夹）

- (void)ame432_importTapped {
    // zip + 文件夹双内容类型（Minecraft 数据包两形态；asCopy 拷入 =
    // saves 页 import 同款语义；服务只读源文件）
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeZIP, UTTypeFolder] asCopy:YES];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    NSString *packsDir = [self.ame432_worldPath stringByAppendingPathComponent:@"datapacks"];
    [NSFileManager.defaultManager createDirectoryAtPath:packsDir
                            withIntermediateDirectories:YES attributes:nil error:nil];
    // ★Task434 弱捕获：一次性 async 块不直捕 self（对齐本页 wself/sself 家法）
    __weak typeof(self) wself = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSInteger ok = 0;
        NSInteger fail = 0;
        for (NSURL *url in urls) {
            // 重名去重（目录/zip 同名追加 _N 后缀；saves 页候选名判例同款）
            NSString *baseName = url.lastPathComponent;
            if (baseName.length == 0) { fail++; continue; }
            NSString *candidate = [packsDir stringByAppendingPathComponent:baseName];
            NSString *stem = baseName;
            BOOL isZip = [stem.lowercaseString hasSuffix:@".zip"];
            if (isZip) stem = [stem substringToIndex:stem.length - @".zip".length];
            NSInteger suffix = 1;
            while ([NSFileManager.defaultManager fileExistsAtPath:candidate]) {
                NSString *tagged = isZip
                    ? [NSString stringWithFormat:@"%@_%ld.zip", stem, (long)suffix]
                    : [NSString stringWithFormat:@"%@_%ld", stem, (long)suffix];
                candidate = [packsDir stringByAppendingPathComponent:tagged];
                suffix++;
            }
            NSError *err = nil;
            if ([NSFileManager.defaultManager copyItemAtURL:url toURL:[NSURL fileURLWithPath:candidate] error:&err]) {
                NSLog(@"[ZL2VersionDetail] Task432: datapack imported: %@", candidate);
                ok++;
            } else {
                NSLog(@"[ZL2VersionDetail] Task432: datapack import failed (%@): %@",
                      url.lastPathComponent, err.localizedDescription);
                fail++;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself;   // ★Task434 弱捕获对齐
            if (!sself) return;
            if (fail > 0) {
                NSString *resultText = [NSString stringWithFormat:
                    localize(@"resman.common.import_result", nil), (long)ok, (long)fail];
                [sself ame432_showAlert:resultText];
            }
            [sself ame432_reload];
        });
    });
}

#pragma mark 本页构件（push 页不走 ZL2VersionPageBase，构件 TU 本地自建）

- (UIView *)ame432_iconBoxWithSymbol:(NSString *)symbol fallback:(NSString *)fallback
                                size:(CGFloat)size iconSize:(CGFloat)iconSize {
    UIView *box = [[UIView alloc] init];
    box.backgroundColor = [ZL2Theme surfaceVariant];
    box.layer.cornerRadius = [ZL2Theme radiusM];
    box.layer.masksToBounds = YES;
    box.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *icon = [[UIImageView alloc] initWithImage:
        [ZL2V13SystemImage(symbol, fallback) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
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

- (UIControl *)ame432_iconButtonWithImageName:(NSString *)name fallback:(NSString *)fallback
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

    UIImageView *iconView = [[UIImageView alloc] initWithImage:
        [ZL2V13SystemImage(name, fallback) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
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

    // 域内判例：iconButton block 载荷走关联对象（ameV13_dispatchTap 同款）
    button.userInteractionEnabled = YES;
    [button addTarget:self action:@selector(ame432_dispatchTap:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(button, @selector(ame432_dispatchTap:), action, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return button;
}

- (void)ame432_dispatchTap:(UIControl *)sender {
    void (^action)(void) = objc_getAssociatedObject(sender, _cmd);
    if (action) action();
}

- (UIView *)ame432_emptyStateWithSymbol:(NSString *)symbol fallback:(NSString *)fallback text:(NSString *)text {
    UIView *wrap = [[UIView alloc] init];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *iconView = [[UIImageView alloc] initWithImage:
        [ZL2V13SystemImage(symbol, fallback) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    iconView.tintColor = [ZL2Theme onSurfaceVariant];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [ZL2Theme fontBodyMedium];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
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
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:wrap.leadingAnchor constant:24],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:wrap.trailingAnchor constant:-24],
    ]];
    return wrap;
}

/// 旧 VC showAlert 同款（i18n_str_388 标题 + i18n_str_44 确定钮；本页为 push 页
/// 不继承 ZL2VersionPageBase，弹窗形态照抄保证页族一致）
- (void)ame432_showAlert:(NSString *)message {
    NSString *titleText = localize(@"i18n_str_388", nil);
    NSString *okText = localize(@"i18n_str_44", nil);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:titleText
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:okText style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
