//
// ZL2HomeViewController.m — ZL2 真布局主页实现（7.0-UI-13-H：7:3 双栏）
//
// 对标 ZalithLauncher2 LauncherScreen 真结构：
//   LauncherScreen.kt            → Row{ 内容区(weight 7) + ActionMenu(3/10 宽
//                                  clamp[240,320]，停靠左/右持久化) }
//   ActionMenu.kt                → 账号卡 / 版本选择卡 / 大启动按钮竖排
//                                  （iOS 简化：ZL2 的 ActionMenu 拖拽换边
//                                  → 长按菜单卡切换停靠边 + NSUserDefaults
//                                  "zl2.home.actionMenuSide" 持久化）
//   HomeGrid.kt                  → 实例卡网格（2 列 iPhone / 3 列 iPad，
//                                  间距 6；点卡选实例，卡上播放键 = 选该
//                                  实例并直接启动；长按 = M3 底部菜单）
//   version/VersionCardContent.kt → 实例卡内容语义（图标/名称/信息行）
//
// 启动链 1:1 保留旧版语义（与 UI 解耦，本版逐行照抄）：self.task 反查
// 统一进度页 → 无账号挂 pending 后切账户页（@"UpdateAccountInfo" 回来自动
// 续启动）→ ShowHomePage 旧契约 → profile/versionId 校验 → lastPlayed
// 时间戳 → @"FindVersionInRemoteList" 回调 → MinecraftResourceDownloadTask
// 下载 + KVO 百分比刷新（handleError 桩遵循 KVO 野指针纪律：task=nil 之前
// 先移除观察者）。任务完成后统一进度页由任务内部（autoPresentDetail）接管。
//
// ★ Task323 启动续链补齐（"点启动后游戏不起"根修）：下载 100% 后 1:1 走旧
// 链完成分支（LauncherRightPanelViewController L1682-1755）——profile 覆盖
// （graphicsApi/javaVersion/allocatedMemory）→ Task224 叠层收口 + 沉降 →
// PLJITGate 门禁（invokeAfterJITEnabled 状态机共享化，JIT 深链/等待环/弃启
// 回调全量）→ UIKit_launchMinecraftSurfaceVC 换根 SurfaceViewController。
// 7.0-UI 重建时该段曾整体缺失（下载完成即静默终止 = 游戏永远不起）。
//
// 数据链：实例列表/排序/加载器识别/有效性判定 = ZL2VersionsViewController
// 同款契约（PLProfiles 键降序；ModLoaderIconHelper detectLoaderFromVersionId
// + ModpackExportService parseVersionId 反解；versions/<id>/<id>.json 存在
// 判定，GAME_DIR 优先 POJAV_HOME 兜底）。删除链 = ZL2VersionsViewController
// ame_deleteProfile 1:1（≥1 守卫 + 二次确认 + Task255 实体目录连带删除）。
//
// 导航协议：本页不直接 push 任何页面——切页需求一律经壳的通知契约：
//   @"ShowAccountManager"   → 壳切到账户页（账号卡点击 + 无账号点启动）
//   @"ZL2ShellNavigate"     → 壳切页（userInfo[@"index"] = @(pageIndex)；
//                              版本选择卡/设置小图标=2、空态「去下载」=1）
//   @"ShowHomePage"         → 壳切回主页（启动链既有契约，兼容旧监听方）
//   @"ZL2OpenVersionDetail" → 版本详情容器（壳接线；userInfo[@"profile"]
//                              = 实例名，长按菜单「打开版本详情」发送）
//
// 通知面：监听 @"UpdateAccountInfo" / @"ShowHomePage"（旧契约 1:1）+
// @"SelectedProfileChanged" / @"ReloadProfileList"（实例表变化 → 网格与
// 选择卡刷新；发送方 = 版本页/本页删除链）；发送 @"ReloadProfileList"
// （下载完成，旧链同款）/ @"SelectedProfileChanged"（选实例）。
//
// 红线遵守：iOS 14.0+（无 button.configuration / UIMenu /
// UISheetPresentationController；UICollectionView 经典 dataSource，无
// iOS15+ cell registration；SF 符号全 SF1.0 级并带旧名 fallback，尺寸用
// UIImageSymbolConfiguration——iOS13+ API，在本仓 iOS14 上限内）；
// 颜色/字体/圆角一律取 ZL2Theme 动态令牌（无 traitCollection 分支）；
// 全部子视图 translatesAutoresizingMaskIntoConstraints = NO；视图身份
// 直接属性持有 + block 载荷（sender.tag / viewWithTag 一律不用）；继承
// UIKit 属性一律 self. 访问（7.0-UI-12-r2 判例）；alert 一律 present 到
// 本 VC；长按菜单删除项经 onDismiss 回调时序收口（弹层收起完成后再
// present 确认框，防"双层 present 目标错乱"）。
//

#import "ZL2HomeViewController.h"
#import "ZL2Theme.h"
#import "ControlRepoViewController.h"   // ★Task343：控件自动检查更新挂载（旧 Root 壳退役后移防主页）
#import "ZL2M3Kit.h"                 // ZL2M3BottomSheet（长按卡菜单）
#import "authenticator/BaseAuthenticator.h"
#import "PLProfiles.h"
#import "AvatarManager.h"            // ame185 头像三层回退链（账户页同款）
#import "ModLoaderIconHelper.h"      // 加载器识别 + 图标（版本页同款契约）
#import "ModpackExportService.h"     // +parseVersionId:（lastVersionId 反解 MC 版本）
#import "MinecraftResourceDownloadTask.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "PLTaskProgressViewController.h"
#import "PLJITGate.h"        // Task323：启动续链 JIT 门禁（RP 状态机共享化）
// Task323：续链终点换根符号——有意不 import ios_uikit_bridge.h（该头带 jni.h
// 传递链，ui_fluent_smoke 的 -I 窄路径 TU 首例；本文件仅消费此一个 C 符号，
// 前向声明同签名 ios_uikit_bridge.h:42，零传递风险）
void UIKit_launchMinecraftSurfaceVC(UIWindow *window, NSDictionary *metadata);
#import "LauncherPreferences.h" // Task323：profile 覆盖 setPrefString/setPrefInt（旧链同款）
#import "utils.h"   // localize()
#import "AmePluginRuntime.h" // ★Task328：插件贡献行计数（主页直达 chip 可见性）

// KVO 观察上下文（旧链 ProgressObserverContext 同款静态指针判别，防父类/他人混淆）
static void *ZL2HomeProgressObserverContext = &ZL2HomeProgressObserverContext;

// ActionMenu 停靠边持久化 key（ZL2 ActionMenuDrag 停靠语义的 iOS 简化等价）
static NSString * const ZL2HomeMenuSideDefaultsKey = @"zl2.home.actionMenuSide";

// 双栏布局常量（LauncherScreen.kt Row 规格）
static const CGFloat ZL2HomeMenuWidthRatio   = 0.30;  // 侧菜单 = 容器宽 3/10
static const CGFloat ZL2HomeMenuWidthMax     = 320;   // 侧菜单宽上限
static const CGFloat ZL2HomeMenuWidthMin     = 240;   // 侧菜单宽下限
static const CGFloat ZL2HomeMenuEdgePadding  = 10;    // 菜单列内边距
static const CGFloat ZL2HomeGridSpacing      = 6;     // 卡片间距（行/列同值）
static const CGFloat ZL2HomeGridInsetH       = 12;    // section 左右 inset
static const CGFloat ZL2HomeGridInsetTop     = 12;    // section 顶 inset
static const CGFloat ZL2HomeGridInsetBottom  = 16;    // section 底 inset
static const CGFloat ZL2HomeCardHeight       = 132;   // 实例卡高
static const CGFloat ZL2HomeCardMinWidth     = 140;   // 窄屏降列阈值（列宽低于则减列）

// ActionMenu 组件高度
static const CGFloat ZL2HomeAccountCardHeight  = 76;  // 账号卡（48 头像 + 上下 14）
static const CGFloat ZL2HomeVersionCardHeight  = 68;  // 版本选择卡（40 图标 + 上下 14）
static const CGFloat ZL2HomeLaunchButtonHeight = 48;  // 大启动钮（ScalingActionButton 48.dp）

// SF Symbols 取图兜底（本页符号全为 SF1.0 级，均带旧名 fallback；保留兜底
// 是历史判例纪律：符号名异常时降级到旧名而不是空白）
static UIImage *ZL2HomeSystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

// 定尺寸符号取图（UIImageSymbolConfiguration 为 iOS13+ API，在本仓 iOS14
// 上限内；用于 16pt 播放小图标等精确字号场景）
static UIImage *ZL2HomeSizedImage(NSString *name, NSString *fallback, CGFloat pointSize) {
    UIImage *image = [UIImage systemImageNamed:name
                               withConfiguration:[UIImageSymbolConfiguration
                                                  configurationWithPointSize:pointSize]];
    if (!image && fallback) {
        image = [UIImage systemImageNamed:fallback
                        withConfiguration:[UIImageSymbolConfiguration
                                           configurationWithPointSize:pointSize]];
    }
    if (!image) image = ZL2HomeSystemImage(name, fallback);
    return image;
}

#pragma mark - 私有点击控件（block 载荷，零 tag / 零 viewWithTag）

// 通用可点容器：账号卡 / 版本选择卡 / 卡内小按钮 / 弹层行共用。
// init 时挂好 touchUpInside → ame_action block（实例自身为 target，
// 零 viewWithTag、零 sender.tag 载荷）。
@interface ZL2HomeTapControl : UIControl
@property (nonatomic, copy, nullable) void (^ame_action)(void);
@end

@implementation ZL2HomeTapControl

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self addTarget:self
                 action:@selector(ame_dispatchAction)
       forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)ame_dispatchAction {
    if (self.ame_action) self.ame_action();
}

@end

#pragma mark - 实例卡 cell（经典 dataSource 路径，iOS14 安全：无 cell registration）

// ZL2 版本卡网格单元：surfaceContainer / radiusM；选中 = primaryContainer
// 2pt 描边。内容 = 实例图标 40 + 实例名 + 信息行（MC 版本/加载器）+ 右下
// 小启动钮。点卡 = 选实例（ame_onCard）；播放键 = 选实例并直接启动
// （ame_onPlay）；长按 = M3 底部菜单（由 VC 的网格长按手势统一处理）。
@interface ZL2HomeVersionCardCell : UICollectionViewCell

@property (nonatomic, strong) ZL2HomeTapControl *cardBody;
@property (nonatomic, strong) UIView *iconBg;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) ZL2HomeTapControl *playButton;
@property (nonatomic, strong) UIImageView *playIconView;
@property (nonatomic, strong) UILabel *playLabel;

// 点击载荷（cellForItem 时注入；prepareForReuse 清空防旧实例残留）
@property (nonatomic, copy, nullable) void (^ame_onCard)(void);
@property (nonatomic, copy, nullable) void (^ame_onPlay)(void);

- (void)ame_configureWithRow:(NSDictionary *)row;

@end

@implementation ZL2HomeVersionCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = [UIColor clearColor];

        // 卡本体（可点 = 选实例）
        _cardBody = [[ZL2HomeTapControl alloc] init];
        _cardBody.backgroundColor = [ZL2Theme surfaceContainer];
        _cardBody.layer.cornerRadius = [ZL2Theme radiusM];
        _cardBody.layer.borderWidth = 0;
        _cardBody.translatesAutoresizingMaskIntoConstraints = NO;
        _cardBody.isAccessibilityElement = YES;
        _cardBody.accessibilityTraits = UIAccessibilityTraitButton;
        [self.contentView addSubview:_cardBody];

        // —— 实例图标 40（加载器品牌图标优先，兜底 gamecontroller 模板）——
        _iconBg = [[UIView alloc] init];
        _iconBg.layer.cornerRadius = [ZL2Theme radiusS];
        _iconBg.layer.masksToBounds = YES;
        _iconBg.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardBody addSubview:_iconBg];

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.userInteractionEnabled = NO;
        [_iconBg addSubview:_iconView];

        // —— 名称 / 信息行 ——
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [ZL2Theme fontLabelLarge];
        _nameLabel.textColor = [ZL2Theme onSurface];
        _nameLabel.numberOfLines = 1;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.userInteractionEnabled = NO;
        [_cardBody addSubview:_nameLabel];

        _infoLabel = [[UILabel alloc] init];
        _infoLabel.font = [ZL2Theme fontLabelMedium];
        _infoLabel.textColor = [ZL2Theme onSurfaceVariant];
        _infoLabel.numberOfLines = 1;
        _infoLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _infoLabel.userInteractionEnabled = NO;
        [_cardBody addSubview:_infoLabel];

        // —— 右下小启动钮（16pt 播放图标 + 文字，primary 色）——
        _playButton = [[ZL2HomeTapControl alloc] init];
        _playButton.layer.cornerRadius = [ZL2Theme radiusS];
        _playButton.translatesAutoresizingMaskIntoConstraints = NO;
        _playButton.isAccessibilityElement = YES;
        _playButton.accessibilityTraits = UIAccessibilityTraitButton;
        [_cardBody addSubview:_playButton];

        UIImage *playImage = ZL2HomeSizedImage(@"play.fill", @"play", 16);
        _playIconView = [[UIImageView alloc] initWithImage:[playImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        _playIconView.tintColor = [ZL2Theme primary];
        _playIconView.contentMode = UIViewContentModeScaleAspectFit;
        _playIconView.translatesAutoresizingMaskIntoConstraints = NO;
        _playIconView.userInteractionEnabled = NO;
        [_playButton addSubview:_playIconView];

        _playLabel = [[UILabel alloc] init];
        // 常量文案先落位再测宽（小钮宽度 = 内容宽的测量依据）
        _playLabel.text = @"启动";
        _playLabel.font = [ZL2Theme fontLabelMedium];
        _playLabel.textColor = [ZL2Theme primary];
        _playLabel.numberOfLines = 1;
        _playLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _playLabel.userInteractionEnabled = NO;
        [_playButton addSubview:_playLabel];

        // 小钮宽度 = 内容宽（10 + 16 + 5 + 文字 + 10），文字恒为「启动」常量，
        // 构建期一次测量定宽（自绘尺寸控件无 intrinsic，等式收敛唯一解）
        CGSize playTextSize = [_playLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, 18)];
        CGFloat playWidth = 10 + 16 + 5 + ceil(playTextSize.width) + 10;

        __weak typeof(self) weakSelf = self;
        _cardBody.ame_action = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf.ame_onCard) strongSelf.ame_onCard();
        };
        _playButton.ame_action = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf.ame_onPlay) strongSelf.ame_onPlay();
        };

        [NSLayoutConstraint activateConstraints:@[
            [_cardBody.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_cardBody.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [_cardBody.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_cardBody.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

            // 图标 40：左上锚定（12, 12）
            [_iconBg.leadingAnchor constraintEqualToAnchor:_cardBody.leadingAnchor constant:12],
            [_iconBg.topAnchor constraintEqualToAnchor:_cardBody.topAnchor constant:12],
            [_iconBg.widthAnchor constraintEqualToConstant:40],
            [_iconBg.heightAnchor constraintEqualToConstant:40],
            [_iconView.centerXAnchor constraintEqualToAnchor:_iconBg.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconBg.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:26],
            [_iconView.heightAnchor constraintEqualToConstant:26],

            // 名称/信息行：图标右侧两行，底不低于小启动钮顶
            [_nameLabel.leadingAnchor constraintEqualToAnchor:_iconBg.trailingAnchor constant:10],
            [_nameLabel.topAnchor constraintEqualToAnchor:_cardBody.topAnchor constant:16],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_cardBody.trailingAnchor constant:-12],
            [_infoLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_infoLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:3],
            [_infoLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_cardBody.trailingAnchor constant:-12],
            [_infoLabel.bottomAnchor constraintLessThanOrEqualToAnchor:_playButton.topAnchor constant:-6],

            // 右下小启动钮
            [_playButton.trailingAnchor constraintEqualToAnchor:_cardBody.trailingAnchor constant:-10],
            [_playButton.bottomAnchor constraintEqualToAnchor:_cardBody.bottomAnchor constant:-10],
            [_playButton.widthAnchor constraintEqualToConstant:playWidth],
            [_playButton.heightAnchor constraintEqualToConstant:28],
            [_playIconView.leadingAnchor constraintEqualToAnchor:_playButton.leadingAnchor constant:10],
            [_playIconView.centerYAnchor constraintEqualToAnchor:_playButton.centerYAnchor],
            [_playIconView.widthAnchor constraintEqualToConstant:16],
            [_playIconView.heightAnchor constraintEqualToConstant:16],
            [_playLabel.leadingAnchor constraintEqualToAnchor:_playIconView.trailingAnchor constant:5],
            [_playLabel.centerYAnchor constraintEqualToAnchor:_playButton.centerYAnchor],
            [_playLabel.trailingAnchor constraintEqualToAnchor:_playButton.trailingAnchor constant:-10],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.ame_onCard = nil;
    self.ame_onPlay = nil;
}

// 行模型 → 卡内容（row 键与 ZL2VersionsViewController 同款：name/versionId/
// loader/mcVersion/valid/isSelected）
- (void)ame_configureWithRow:(NSDictionary *)row {
    NSString *profileName = row[@"name"];
    NSString *versionId = row[@"versionId"]; // ★ Task351 r1：行模型键注释链含 versionId（@334 未选择版本分支引用），CI 首轮实锤漏声明
    NSString *loader = row[@"loader"];
    NSString *mcVersion = row[@"mcVersion"];
    BOOL valid = [row[@"valid"] boolValue];
    BOOL isSelected = [row[@"isSelected"] boolValue];

    self.nameLabel.text = profileName;

    // 信息行：MC 版本/加载器小字；无效版本 = error 色提示（版本页同语义）
    if (!valid) {
        // ★ Task351：versionId 空 = 未选择版本（收编推断也未命中），区别于
        //   “选了但实体缺失”的无效态——引导语义不同（前者去安装版本）
        if (versionId.length == 0) {
            self.infoLabel.text = localize(@"ame351.instance.no_version", nil);
        } else {
            self.infoLabel.text = @"该版本无效";
        }
        self.infoLabel.textColor = [ZL2Theme error];
    } else {
        if (mcVersion.length > 0 && loader.length > 0) {
            self.infoLabel.text = [NSString stringWithFormat:@"MC %@ · %@",
                                   mcVersion, [ModLoaderIconHelper displayNameForLoader:loader]];
        } else if (mcVersion.length > 0) {
            self.infoLabel.text = [NSString stringWithFormat:@"MC %@", mcVersion];
        } else if (loader.length > 0) {
            self.infoLabel.text = [ModLoaderIconHelper displayNameForLoader:loader];
        } else {
            self.infoLabel.text = @"";
        }
        self.infoLabel.textColor = [ZL2Theme onSurfaceVariant];
    }

    // 实例图标：加载器图标（PNG 原色 / SF 品牌色，版本页同款）；取不到 →
    // gamecontroller 兜底装进 surfaceVariant 容器
    if (loader.length > 0) {
        [ModLoaderIconHelper configureImageView:self.iconView
                                      forLoader:loader
                                 traitCollection:self.traitCollection];
        self.iconBg.backgroundColor = [UIColor clearColor];
    } else {
        UIImage *fallbackIcon = ZL2HomeSystemImage(@"gamecontroller.fill", @"gamecontroller");
        self.iconView.image = [fallbackIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.iconView.tintColor = [ZL2Theme onSurfaceVariant];
        self.iconBg.backgroundColor = [ZL2Theme surfaceVariant];
    }

    // 选中态：primaryContainer 2pt 描边（复用残留防护：未选中恒清零）
    self.cardBody.layer.borderWidth = isSelected ? 2 : 0;
    self.cardBody.layer.borderColor = [ZL2Theme primaryContainer].CGColor;

    self.cardBody.accessibilityLabel = [NSString stringWithFormat:@"实例 %@，%@",
                                        profileName, isSelected ? @"当前实例" : @"点按选用"];
    self.playButton.accessibilityLabel = [NSString stringWithFormat:@"启动 %@",
                                          profileName];
}

@end

#pragma mark - 私有扩展

@interface ZL2HomeViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

// 双栏根（Row：内容区 weight 7 + ActionMenu 3/10）
@property (nonatomic, strong) UIView *contentArea;
@property (nonatomic, strong) UICollectionView *gridView;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIView *actionMenu;
@property (nonatomic, strong) UIStackView *menuStack;
// 当前停靠边约束组（换边时整组替换：YES = 停靠右侧）
@property (nonatomic, strong, nullable) NSArray<NSLayoutConstraint *> *ame_sideConstraints;
@property (nonatomic, assign) BOOL ame_menuOnRight;
@property (nonatomic, assign) NSInteger lastColumnCount;

// —— ActionMenu：账号卡 ——
@property (nonatomic, strong) ZL2HomeTapControl *accountCard;
@property (nonatomic, strong) UIView *accountAvatarBg;    // 48 圆底
@property (nonatomic, strong) UIImageView *accountAvatarView;
@property (nonatomic, strong) UILabel *accountNameLabel;
@property (nonatomic, strong) UILabel *accountTypeLabel;

// —— ActionMenu：版本选择卡 ——
@property (nonatomic, strong) ZL2HomeTapControl *versionCard;
@property (nonatomic, strong) UIView *versionIconBg;
@property (nonatomic, strong) UIImageView *versionIconView;
@property (nonatomic, strong) UILabel *versionNameLabel;
@property (nonatomic, strong) UILabel *versionLoaderLabel;
@property (nonatomic, strong) ZL2HomeTapControl *versionRefreshButton;
@property (nonatomic, strong) ZL2HomeTapControl *versionSettingsButton;

// —— ActionMenu：大启动钮 + 状态行 + 停靠提示 ——
@property (nonatomic, strong) UIControl *launchButton;
@property (nonatomic, strong) UIImageView *launchIconView;
@property (nonatomic, strong) UILabel *launchButtonLabel;
@property (nonatomic, strong) UILabel *launchStatusLabel;  // KVO 百分比行（下载态可见）
@property (nonatomic, strong) UILabel *menuHintLabel;
// ★ Task328：插件功能直达 chip（无贡献行时塌缩隐藏，零回归）
@property (nonatomic, strong) UIControl *pluginChipButton;
@property (nonatomic, strong) UIImageView *pluginChipIconView;
@property (nonatomic, strong) UILabel *pluginChipLabel;

// 数据（实例行模型：name/versionId/loader/mcVersion/valid/isSelected）
@property (nonatomic, copy) NSArray<NSDictionary *> *ame_rows;
// 长按菜单删除项的时序收口载荷（弹层 onDismiss 后执行）
@property (nonatomic, copy, nullable) void (^ame_pendingSheetAction)(void);

// 启动链状态（1:1 旧链）
@property (nonatomic, strong) MinecraftResourceDownloadTask *task;
// FCL 风格：无账号点启动 → 挂标记切账户页，登录成功（UpdateAccountInfo）自动续启动
@property (nonatomic, assign) BOOL ame_pendingLaunchAfterLogin;
// 启动链进行中（FindVersionInRemoteList 反查 → 下载就绪的窗口期防双击；
// 与 self.task 一并构成按钮禁用的单一来源，恢复交互时统一清位）
@property (nonatomic, assign) BOOL ame_launchChainActive;

@end

@implementation ZL2HomeViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [ZL2Theme surface];
    [self buildViews];
    // ★Task343：控件自动检查更新挂载点（Task255 链 1:1——旧 Root 壳物理退役，
    // 开关门控 + 静态一次性守卫在 autoCheckControlUpdatesOnce 实现内，主页
    // viewDidLoad 每启动恰一次）
    [ControlRepoViewController autoCheckControlUpdatesOnce];
    // 复用注册（经典 dataSource 路径；cell 类自带 configure，无 iOS15+ registration）
    [self.gridView registerClass:[ZL2HomeVersionCardCell class]
      forCellWithReuseIdentifier:@"zl2_home_version_card"];
    [self ame_restoreMenuSide];
    [self ame_applySideConstraintsAnimated:NO];
    [self refreshLaunchState];

    // 通知监听：账号信息变化 / 壳切回主页 → 刷新三态（旧契约 1:1）；
    // 实例表变化（版本页选用/删除、本页删除链）→ 网格与选择卡刷新。
    // dealloc 统一移除。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(accountOrHomeDidChange:)
                                                 name:@"UpdateAccountInfo"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(accountOrHomeDidChange:)
                                                 name:@"ShowHomePage"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileListDidChange)
                                                 name:@"SelectedProfileChanged"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileListDidChange)
                                                 name:@"ReloadProfileList"
                                               object:nil];

    // 长按菜单卡 = 切换 ActionMenu 停靠边（ZL2 ActionMenuDrag 简化等价）
    UILongPressGestureRecognizer *menuLongPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(ame_handleMenuLongPress:)];
    [self.actionMenu addGestureRecognizer:menuLongPress];

    // 长按实例卡 = M3 底部菜单
    UILongPressGestureRecognizer *cardLongPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(ame_handleCardLongPress:)];
    [self.gridView addGestureRecognizer:cardLongPress];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshLaunchState];
    // ★ Task328：插件 chip 计数刷新（插件启停/装载变化回主页即刻反映）
    [self ame328_refreshPluginChip];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 列数（2/3，窄屏降 1）随网格宽切换：变化时失效布局重取 sizeForItem
    NSInteger columns = [self ame_columnsForWidth:self.gridView.bounds.size.width];
    if (columns != self.lastColumnCount) {
        self.lastColumnCount = columns;
        [self.gridView.collectionViewLayout invalidateLayout];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    // 异常路径兜底：若 KVO 仍在观察（handleError/完成分支均未触达），解除注册
    @try {
        [self.task.progress removeObserver:self
                                forKeyPath:@"fractionCompleted"
                                   context:ZL2HomeProgressObserverContext];
    } @catch (NSException *e) {}
}

#pragma mark - Layout

- (void)buildViews {
    [self ame_buildActionMenu];
    [self ame_buildContentArea];
    [self ame_buildEmptyState];
}

/// ActionMenu 竖排：账号卡 → 版本选择卡 → 弹性占位 → 下载状态行 →
/// 大启动钮 → 停靠边提示（长按切换）。停靠边只决定整列贴左/贴右。
- (void)ame_buildActionMenu {
    // 7.0-UI-14 真机对齐：ZL2 ActionMenuCardContent = 单张 BackgroundCard
    //（extraLarge 圆角，cardColor = surfaceBright），内部账号区居中贴顶、
    //  版本行+启动钮贴底；旧三张分离小卡废弃
    _actionMenu = [[UIView alloc] init];
    _actionMenu.backgroundColor = [ZL2Theme surfaceBright];
    _actionMenu.layer.cornerRadius = [ZL2Theme radiusXL];
    _actionMenu.layer.masksToBounds = YES;
    _actionMenu.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_actionMenu];

    _menuStack = [[UIStackView alloc] init];
    _menuStack.axis = UILayoutConstraintAxisVertical;
    _menuStack.alignment = UIStackViewAlignmentFill;
    _menuStack.spacing = 8;
    _menuStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_actionMenu addSubview:_menuStack];

    // —— ① 账号区（单卡内贴顶：头像居中 + 名字/类型居中竖排；点击→账号管理）——
    _accountCard = [[ZL2HomeTapControl alloc] init];
    _accountCard.backgroundColor = [UIColor clearColor];
    _accountCard.translatesAutoresizingMaskIntoConstraints = NO;
    _accountCard.isAccessibilityElement = YES;
    _accountCard.accessibilityTraits = UIAccessibilityTraitButton;
    _accountCard.accessibilityIdentifier = @"zl2_home_account_card";
    [_accountCard addTarget:self
                     action:@selector(accountCardTapped)
           forControlEvents:UIControlEventTouchUpInside];
    [_menuStack addArrangedSubview:_accountCard];

    // 头像 64 圆（ZL2 PlayerFace 64.dp；未登录 = 加号占位）
    _accountAvatarBg = [[UIView alloc] init];
    _accountAvatarBg.layer.cornerRadius = 32;
    _accountAvatarBg.layer.masksToBounds = YES;
    _accountAvatarBg.translatesAutoresizingMaskIntoConstraints = NO;
    _accountAvatarBg.userInteractionEnabled = NO;
    [_accountCard addSubview:_accountAvatarBg];

    _accountAvatarView = [[UIImageView alloc] init];
    _accountAvatarView.contentMode = UIViewContentModeScaleAspectFit;
    _accountAvatarView.translatesAutoresizingMaskIntoConstraints = NO;
    _accountAvatarView.userInteractionEnabled = NO;
    [_accountAvatarBg addSubview:_accountAvatarView];

    _accountNameLabel = [[UILabel alloc] init];
    _accountNameLabel.font = [ZL2Theme fontTitleMedium];
    _accountNameLabel.textColor = [ZL2Theme onSurface];
    _accountNameLabel.numberOfLines = 1;
    _accountNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _accountNameLabel.textAlignment = NSTextAlignmentCenter;
    _accountNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _accountNameLabel.userInteractionEnabled = NO;
    [_accountCard addSubview:_accountNameLabel];

    _accountTypeLabel = [[UILabel alloc] init];
    _accountTypeLabel.font = [ZL2Theme fontLabelMedium];
    _accountTypeLabel.textColor = [ZL2Theme onSurfaceVariant];
    _accountTypeLabel.numberOfLines = 1;
    _accountTypeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _accountTypeLabel.textAlignment = NSTextAlignmentCenter;
    _accountTypeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _accountTypeLabel.userInteractionEnabled = NO;
    [_accountCard addSubview:_accountTypeLabel];

    // —— ② 版本行（单卡内贴底：ZL2 VersionsContent = 版本行 + 齿轮钮 + 启动钮）——
    _versionCard = [[ZL2HomeTapControl alloc] init];
    _versionCard.backgroundColor = [UIColor clearColor];
    _versionCard.translatesAutoresizingMaskIntoConstraints = NO;
    _versionCard.isAccessibilityElement = YES;
    _versionCard.accessibilityTraits = UIAccessibilityTraitButton;
    _versionCard.accessibilityIdentifier = @"zl2_home_version_card";
    [_versionCard addTarget:self
                     action:@selector(versionCardTapped)
           forControlEvents:UIControlEventTouchUpInside];
    [_menuStack addArrangedSubview:_versionCard];

    _versionIconBg = [[UIView alloc] init];
    _versionIconBg.layer.cornerRadius = [ZL2Theme radiusS];
    _versionIconBg.layer.masksToBounds = YES;
    _versionIconBg.translatesAutoresizingMaskIntoConstraints = NO;
    _versionIconBg.userInteractionEnabled = NO;
    [_versionCard addSubview:_versionIconBg];

    _versionIconView = [[UIImageView alloc] init];
    _versionIconView.contentMode = UIViewContentModeScaleAspectFit;
    _versionIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _versionIconView.userInteractionEnabled = NO;
    [_versionIconBg addSubview:_versionIconView];

    _versionNameLabel = [[UILabel alloc] init];
    _versionNameLabel.font = [ZL2Theme fontLabelLarge];
    _versionNameLabel.textColor = [ZL2Theme onSurface];
    _versionNameLabel.numberOfLines = 1;
    _versionNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _versionNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _versionNameLabel.userInteractionEnabled = NO;
    [_versionCard addSubview:_versionNameLabel];

    _versionLoaderLabel = [[UILabel alloc] init];
    _versionLoaderLabel.font = [ZL2Theme fontLabelMedium];
    _versionLoaderLabel.textColor = [ZL2Theme onSurfaceVariant];
    _versionLoaderLabel.numberOfLines = 1;
    _versionLoaderLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _versionLoaderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _versionLoaderLabel.userInteractionEnabled = NO;
    [_versionCard addSubview:_versionLoaderLabel];

    // 刷新小图标（arrow.clockwise，SF1.0）：重拉 PLProfiles 注册表并刷新
    _versionRefreshButton = [self ame_iconButtonWithSymbol:@"arrow.clockwise"
                                                  fallback:@"sync"
                                                    a11y:@"刷新实例列表"];
    // 刷新/设置小钮的 block 统一 weak self（钮为 VC 属性持有，强捕自环）
    __weak ZL2HomeViewController *weakSelf = self;
    _versionRefreshButton.ame_action = ^{
        [weakSelf versionRefreshTapped];
    };
    [_versionCard addSubview:_versionRefreshButton];

    // 设置小图标（gearshape，iOS14 符号带旧名 fallback）：壳切版本管理页
    _versionSettingsButton = [self ame_iconButtonWithSymbol:@"gearshape"
                                                   fallback:@"gear"
                                                       a11y:@"版本管理"];
    _versionSettingsButton.ame_action = ^{
        [weakSelf versionSettingsTapped];
    };
    [_versionCard addSubview:_versionSettingsButton];

    // —— 弹性占位：把启动组压到列底 ——
    UIView *spacer = [[UIView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow
                               forAxis:UILayoutConstraintAxisVertical];
    [spacer setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                             forAxis:UILayoutConstraintAxisVertical];
    [_menuStack addArrangedSubview:spacer];

    // —— 下载状态行（KVO 百分比态；非下载态隐藏塌缩）——
    _launchStatusLabel = [[UILabel alloc] init];
    _launchStatusLabel.font = [ZL2Theme fontLabelMedium];
    _launchStatusLabel.textColor = [ZL2Theme onSurfaceVariant];
    _launchStatusLabel.textAlignment = NSTextAlignmentCenter;
    _launchStatusLabel.numberOfLines = 1;
    _launchStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _launchStatusLabel.isAccessibilityElement = YES;
    _launchStatusLabel.hidden = YES;
    [_menuStack addArrangedSubview:_launchStatusLabel];

    // —— ③ 大启动钮（ScalingActionButton 语义：primary 底 / onPrimary 字 /
    // 28 圆角 / 高 48 / 播放图标 + 三态文案；"zl2_home_launch" 为向导锚点）——
    _launchButton = [[UIControl alloc] init];
    _launchButton.accessibilityIdentifier = @"zl2_home_launch";
    _launchButton.layer.cornerRadius = [ZL2Theme radiusXL];   // 28（spec 定稿）
    _launchButton.translatesAutoresizingMaskIntoConstraints = NO;
    _launchButton.isAccessibilityElement = YES;
    [_launchButton addTarget:self
                      action:@selector(launchButtonTapped)
            forControlEvents:UIControlEventTouchUpInside];
    [_menuStack addArrangedSubview:_launchButton];

    UIImage *launchPlayImage = ZL2HomeSizedImage(@"play.fill", @"play", 18);
    _launchIconView = [[UIImageView alloc] initWithImage:[launchPlayImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _launchIconView.contentMode = UIViewContentModeScaleAspectFit;
    _launchIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _launchIconView.userInteractionEnabled = NO;

    _launchButtonLabel = [[UILabel alloc] init];
    _launchButtonLabel.font = [ZL2Theme fontLabelLarge];
    _launchButtonLabel.textColor = [ZL2Theme onPrimary];
    _launchButtonLabel.numberOfLines = 1;
    _launchButtonLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _launchButtonLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _launchButtonLabel.userInteractionEnabled = NO;

    // 图标 + 文案水平组（stack 自带 intrinsic 尺寸，组内居中零歧义）
    UIStackView *launchContent = [[UIStackView alloc] initWithArrangedSubviews:@[_launchIconView, _launchButtonLabel]];
    launchContent.axis = UILayoutConstraintAxisHorizontal;
    launchContent.alignment = UIStackViewAlignmentCenter;
    launchContent.spacing = 8;
    launchContent.translatesAutoresizingMaskIntoConstraints = NO;
    launchContent.userInteractionEnabled = NO;
    [_launchButton addSubview:launchContent];

    // —— ⑤ 插件功能直达 chip（★ Task328：插件效果可见性第三刀——设置页组
    //    上移/计数之外，主页一键直达 设置 → 启动器 → 插件功能区；无贡献行
    //    时塌缩隐藏 = 零回归。puzzlepiece.extension 为 SF2.0/iOS14 符号，带
    //    旧名 fallback，本仓 iOS14 上限内）——
    _pluginChipButton = [[UIControl alloc] init];
    _pluginChipButton.backgroundColor = [ZL2Theme surfaceContainerHigh];
    _pluginChipButton.layer.cornerRadius = [ZL2Theme radiusS];
    _pluginChipButton.translatesAutoresizingMaskIntoConstraints = NO;
    _pluginChipButton.isAccessibilityElement = YES;
    _pluginChipButton.accessibilityTraits = UIAccessibilityTraitButton;
    _pluginChipButton.accessibilityIdentifier = @"zl2_home_plugin_chip";
    _pluginChipButton.hidden = YES;   // 初始塌缩，viewWillAppear 计数刷新后放行（防首建闪现）
    [_pluginChipButton addTarget:self
                          action:@selector(ame328_pluginChipTapped)
                forControlEvents:UIControlEventTouchUpInside];
    [_menuStack addArrangedSubview:_pluginChipButton];

    UIImage *pluginChipImage = ZL2HomeSizedImage(@"puzzlepiece.extension", @"gearshape", 14);
    _pluginChipIconView = [[UIImageView alloc] initWithImage:[pluginChipImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _pluginChipIconView.contentMode = UIViewContentModeScaleAspectFit;
    _pluginChipIconView.tintColor = [ZL2Theme onSurfaceVariant];
    _pluginChipIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _pluginChipIconView.userInteractionEnabled = NO;

    _pluginChipLabel = [[UILabel alloc] init];
    _pluginChipLabel.font = [ZL2Theme fontLabelMedium];
    _pluginChipLabel.textColor = [ZL2Theme onSurface];
    _pluginChipLabel.textAlignment = NSTextAlignmentCenter;
    _pluginChipLabel.numberOfLines = 1;
    _pluginChipLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _pluginChipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _pluginChipLabel.userInteractionEnabled = NO;

    UIStackView *pluginChipContent =
        [[UIStackView alloc] initWithArrangedSubviews:@[_pluginChipIconView, _pluginChipLabel]];
    pluginChipContent.axis = UILayoutConstraintAxisHorizontal;
    pluginChipContent.alignment = UIStackViewAlignmentCenter;
    pluginChipContent.spacing = 6;
    pluginChipContent.translatesAutoresizingMaskIntoConstraints = NO;
    pluginChipContent.userInteractionEnabled = NO;
    [_pluginChipButton addSubview:pluginChipContent];

    [_pluginChipButton.heightAnchor constraintEqualToConstant:34].active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [pluginChipContent.centerXAnchor constraintEqualToAnchor:_pluginChipButton.centerXAnchor],
        [pluginChipContent.centerYAnchor constraintEqualToAnchor:_pluginChipButton.centerYAnchor],
        [pluginChipContent.leadingAnchor constraintGreaterThanOrEqualToAnchor:_pluginChipButton.leadingAnchor constant:12],
        [_pluginChipButton.trailingAnchor constraintGreaterThanOrEqualToAnchor:pluginChipContent.trailingAnchor constant:12],
    ]];

    // —— ④ 停靠边提示（ActionMenuDrag 简化语义的可见性说明）——
    _menuHintLabel = [[UILabel alloc] init];
    _menuHintLabel.text = @"长按菜单可切换停靠边";
    _menuHintLabel.font = [ZL2Theme fontLabelMedium];
    _menuHintLabel.textColor = [ZL2Theme onSurfaceVariant];
    _menuHintLabel.textAlignment = NSTextAlignmentCenter;
    _menuHintLabel.numberOfLines = 1;
    _menuHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_menuStack addArrangedSubview:_menuHintLabel];

    // 账号区布局（7.0-UI-14 单卡贴顶竖排：64 头像居中 + 名字/类型居中下方）
    [NSLayoutConstraint activateConstraints:@[
        [_accountCard.heightAnchor constraintEqualToConstant:148],
        [_accountAvatarBg.centerXAnchor constraintEqualToAnchor:_accountCard.centerXAnchor],
        [_accountAvatarBg.topAnchor constraintEqualToAnchor:_accountCard.topAnchor constant:14],
        [_accountAvatarBg.widthAnchor constraintEqualToConstant:64],
        [_accountAvatarBg.heightAnchor constraintEqualToConstant:64],
        [_accountAvatarView.centerXAnchor constraintEqualToAnchor:_accountAvatarBg.centerXAnchor],
        [_accountAvatarView.centerYAnchor constraintEqualToAnchor:_accountAvatarBg.centerYAnchor],
        [_accountAvatarView.widthAnchor constraintEqualToConstant:58],
        [_accountAvatarView.heightAnchor constraintEqualToConstant:58],
        [_accountNameLabel.topAnchor constraintEqualToAnchor:_accountAvatarBg.bottomAnchor constant:6],
        [_accountNameLabel.centerXAnchor constraintEqualToAnchor:_accountCard.centerXAnchor],
        [_accountNameLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_accountCard.leadingAnchor constant:8],
        [_accountNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_accountCard.trailingAnchor constant:-8],
        [_accountTypeLabel.topAnchor constraintEqualToAnchor:_accountNameLabel.bottomAnchor constant:1],
        [_accountTypeLabel.centerXAnchor constraintEqualToAnchor:_accountCard.centerXAnchor],
        [_accountTypeLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_accountCard.leadingAnchor constant:8],
        [_accountTypeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_accountCard.trailingAnchor constant:-8],

        // 版本选择卡内布局（40 图标 + 名字/加载器双行，卡高 68）
        [_versionCard.heightAnchor constraintEqualToConstant:ZL2HomeVersionCardHeight],
        [_versionIconBg.leadingAnchor constraintEqualToAnchor:_versionCard.leadingAnchor constant:14],
        [_versionIconBg.centerYAnchor constraintEqualToAnchor:_versionCard.centerYAnchor],
        [_versionIconBg.widthAnchor constraintEqualToConstant:40],
        [_versionIconBg.heightAnchor constraintEqualToConstant:40],
        [_versionIconView.centerXAnchor constraintEqualToAnchor:_versionIconBg.centerXAnchor],
        [_versionIconView.centerYAnchor constraintEqualToAnchor:_versionIconBg.centerYAnchor],
        [_versionIconView.widthAnchor constraintEqualToConstant:24],
        [_versionIconView.heightAnchor constraintEqualToConstant:24],
        [_versionNameLabel.leadingAnchor constraintEqualToAnchor:_versionIconBg.trailingAnchor constant:10],
        [_versionNameLabel.centerYAnchor constraintEqualToAnchor:_versionCard.centerYAnchor constant:-9],
        [_versionNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_versionRefreshButton.leadingAnchor constant:-8],
        [_versionLoaderLabel.leadingAnchor constraintEqualToAnchor:_versionIconBg.trailingAnchor constant:10],
        [_versionLoaderLabel.centerYAnchor constraintEqualToAnchor:_versionCard.centerYAnchor constant:9],
        [_versionLoaderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_versionRefreshButton.leadingAnchor constant:-8],
        [_versionRefreshButton.trailingAnchor constraintEqualToAnchor:_versionSettingsButton.leadingAnchor constant:-4],
        [_versionRefreshButton.centerYAnchor constraintEqualToAnchor:_versionCard.centerYAnchor],
        [_versionSettingsButton.trailingAnchor constraintEqualToAnchor:_versionCard.trailingAnchor constant:-12],
        [_versionSettingsButton.centerYAnchor constraintEqualToAnchor:_versionCard.centerYAnchor],

        // 大启动钮内布局（图标+文案水平组居中，高 48；不等式四边防溢出）
        [_launchButton.heightAnchor constraintEqualToConstant:ZL2HomeLaunchButtonHeight],
        [launchContent.centerXAnchor constraintEqualToAnchor:_launchButton.centerXAnchor],
        [launchContent.centerYAnchor constraintEqualToAnchor:_launchButton.centerYAnchor],
        [launchContent.leadingAnchor constraintGreaterThanOrEqualToAnchor:_launchButton.leadingAnchor constant:16],
        [launchContent.trailingAnchor constraintLessThanOrEqualToAnchor:_launchButton.trailingAnchor constant:-16],
        [launchContent.topAnchor constraintGreaterThanOrEqualToAnchor:_launchButton.topAnchor constant:4],
        [launchContent.bottomAnchor constraintLessThanOrEqualToAnchor:_launchButton.bottomAnchor constant:-4],
        [_launchIconView.widthAnchor constraintEqualToConstant:18],
        [_launchIconView.heightAnchor constraintEqualToConstant:18],

        // 菜单列整体内边距
        [_menuStack.topAnchor constraintEqualToAnchor:_actionMenu.topAnchor constant:ZL2HomeMenuEdgePadding],
        [_menuStack.bottomAnchor constraintEqualToAnchor:_actionMenu.bottomAnchor constant:-ZL2HomeMenuEdgePadding],
        [_menuStack.leadingAnchor constraintEqualToAnchor:_actionMenu.leadingAnchor constant:ZL2HomeMenuEdgePadding],
        [_menuStack.trailingAnchor constraintEqualToAnchor:_actionMenu.trailingAnchor constant:-ZL2HomeMenuEdgePadding],
    ]];
}

/// 小图标钮工厂：32×32 / 18pt 模板图标（菜单卡内刷新/设置两钮共用）
- (ZL2HomeTapControl *)ame_iconButtonWithSymbol:(NSString *)symbol
                                       fallback:(NSString *)fallback
                                           a11y:(NSString *)a11y {
    ZL2HomeTapControl *button = [[ZL2HomeTapControl alloc] init];
    button.backgroundColor = [UIColor clearColor];
    button.layer.cornerRadius = [ZL2Theme radiusS];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.isAccessibilityElement = YES;
    button.accessibilityTraits = UIAccessibilityTraitButton;
    button.accessibilityLabel = a11y;

    UIImage *image = ZL2HomeSystemImage(symbol, fallback);
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    iconView.tintColor = [ZL2Theme onSurfaceVariant];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.userInteractionEnabled = NO;
    [button addSubview:iconView];

    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:32],
        [button.heightAnchor constraintEqualToConstant:32],
        [iconView.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:18],
        [iconView.heightAnchor constraintEqualToConstant:18],
    ]];
    return button;
}

/// 内容区：实例卡网格（2 列 iPhone / 3 列 iPad，间距 6，垂直滚动）
- (void)ame_buildContentArea {
    _contentArea = [[UIView alloc] init];
    _contentArea.backgroundColor = [UIColor clearColor];
    _contentArea.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_contentArea];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    layout.minimumInteritemSpacing = ZL2HomeGridSpacing;
    layout.minimumLineSpacing = ZL2HomeGridSpacing;
    layout.sectionInset = UIEdgeInsetsMake(ZL2HomeGridInsetTop, ZL2HomeGridInsetH,
                                           ZL2HomeGridInsetBottom, ZL2HomeGridInsetH);

    _gridView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                   collectionViewLayout:layout];
    _gridView.backgroundColor = [UIColor clearColor];
    _gridView.dataSource = self;
    _gridView.delegate = self;
    _gridView.alwaysBounceVertical = YES;
    _gridView.allowsSelection = NO;   // 点击走卡内 UIControl；选择态不用
    _gridView.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentArea addSubview:_gridView];

    [NSLayoutConstraint activateConstraints:@[
        [_contentArea.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_contentArea.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [_gridView.topAnchor constraintEqualToAnchor:_contentArea.topAnchor],
        [_gridView.bottomAnchor constraintEqualToAnchor:_contentArea.bottomAnchor],
        [_gridView.leadingAnchor constraintEqualToAnchor:_contentArea.leadingAnchor],
        [_gridView.trailingAnchor constraintEqualToAnchor:_contentArea.trailingAnchor],
    ]];
}

/// 空态：archivebox 68 +「没有安装版本」+「去下载」钮（壳切下载页 index=1；
/// 与 ZL2VersionsViewController versions_manage_no_versions 同语义）
- (void)ame_buildEmptyState {
    _emptyStateView = [[UIView alloc] init];
    _emptyStateView.backgroundColor = [UIColor clearColor];
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyStateView.hidden = YES;
    [_contentArea addSubview:_emptyStateView];

    UIImage *archiveImage = ZL2HomeSystemImage(@"archivebox", nil);
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[archiveImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    iconView.tintColor = [ZL2Theme onSurfaceVariant];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.userInteractionEnabled = NO;

    UILabel *label = [[UILabel alloc] init];
    label.text = @"没有安装版本";
    label.font = [ZL2Theme fontBodyMedium];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.userInteractionEnabled = NO;

    ZL2HomeTapControl *downloadButton = [[ZL2HomeTapControl alloc] init];
    downloadButton.backgroundColor = [ZL2Theme primary];
    downloadButton.layer.cornerRadius = [ZL2Theme radiusS];
    downloadButton.translatesAutoresizingMaskIntoConstraints = NO;
    downloadButton.isAccessibilityElement = YES;
    downloadButton.accessibilityTraits = UIAccessibilityTraitButton;

    UILabel *downloadLabel = [[UILabel alloc] init];
    downloadLabel.text = @"去下载";
    downloadLabel.font = [ZL2Theme fontLabelLarge];
    downloadLabel.textColor = [ZL2Theme onPrimary];
    downloadLabel.numberOfLines = 1;
    downloadLabel.textAlignment = NSTextAlignmentCenter;
    downloadLabel.translatesAutoresizingMaskIntoConstraints = NO;
    downloadLabel.userInteractionEnabled = NO;
    [downloadButton addSubview:downloadLabel];

    downloadButton.ame_action = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2ShellNavigate"
                                                            object:nil
                                                          userInfo:@{@"index": @(1)}];
    };

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[iconView, label, downloadButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.userInteractionEnabled = YES;
    [_emptyStateView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateView.topAnchor constraintEqualToAnchor:_contentArea.topAnchor],
        [_emptyStateView.bottomAnchor constraintEqualToAnchor:_contentArea.bottomAnchor],
        [_emptyStateView.leadingAnchor constraintEqualToAnchor:_contentArea.leadingAnchor],
        [_emptyStateView.trailingAnchor constraintEqualToAnchor:_contentArea.trailingAnchor],
        [stack.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:_emptyStateView.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:_emptyStateView.leadingAnchor constant:20],
        [_emptyStateView.trailingAnchor constraintGreaterThanOrEqualToAnchor:stack.trailingAnchor constant:20],
        [iconView.widthAnchor constraintEqualToConstant:68],
        [iconView.heightAnchor constraintEqualToConstant:68],
        [downloadButton.widthAnchor constraintEqualToConstant:132],
        [downloadButton.heightAnchor constraintEqualToConstant:40],
        [downloadLabel.centerXAnchor constraintEqualToAnchor:downloadButton.centerXAnchor],
        [downloadLabel.centerYAnchor constraintEqualToAnchor:downloadButton.centerYAnchor],
    ]];
}

#pragma mark - 停靠边（ActionMenu 左右换边 + 持久化）

/// 恢复持久化停靠边（缺省 = 右侧；脏值回退默认）
- (void)ame_restoreMenuSide {
    NSString *side = [[NSUserDefaults standardUserDefaults] stringForKey:ZL2HomeMenuSideDefaultsKey];
    self.ame_menuOnRight = ![side isEqualToString:@"left"];
}

/// 重建双栏约束组：ActionMenu 宽 = 容器 3/10（优先级 999）clamp[240, 320]，
/// 内容区吃余量；停靠左/右只换 leading/trailing 挂接
- (void)ame_applySideConstraintsAnimated:(BOOL)animated {
    if (self.ame_sideConstraints) {
        [NSLayoutConstraint deactivateConstraints:self.ame_sideConstraints];
    }

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    UIView *menu = self.actionMenu;
    UIView *content = self.contentArea;
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];

    // 菜单宽：0.3 × 容器宽（可破），上下限 required 收敛出 clamp 语义
    NSLayoutConstraint *ratio = [menu.widthAnchor constraintEqualToAnchor:self.view.widthAnchor
                                                              multiplier:ZL2HomeMenuWidthRatio];
    ratio.priority = 999;
    [constraints addObjectsFromArray:@[
        ratio,
        [menu.widthAnchor constraintGreaterThanOrEqualToConstant:ZL2HomeMenuWidthMin],
        [menu.widthAnchor constraintLessThanOrEqualToConstant:ZL2HomeMenuWidthMax],

        // 纵向：菜单列贴安全区上下（内边距由 menuStack 承担）；
        // 内容区贴安全区上下（网格 inset 承担留白）
        [menu.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [menu.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
        [content.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
    ]];

    if (self.ame_menuOnRight) {
        // [内容区][菜单] —— 菜单贴右
        [constraints addObjectsFromArray:@[
            [menu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [content.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [content.trailingAnchor constraintEqualToAnchor:menu.leadingAnchor],
        ]];
    } else {
        // [菜单][内容区] —— 菜单贴左
        [constraints addObjectsFromArray:@[
            [menu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [content.leadingAnchor constraintEqualToAnchor:menu.trailingAnchor],
            [content.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        ]];
    }

    [NSLayoutConstraint activateConstraints:constraints];
    self.ame_sideConstraints = constraints;

    if (animated) {
        [UIView animateWithDuration:0.22
                          animations:^{ [self.view layoutIfNeeded]; }];
    }
}

// ★ Task328：插件 chip 计数刷新——贡献行数（四内置件 = 4）即“插件在跑”
//   的可见信号；无贡献行时整枚 chip 塌缩隐藏（UIStackView arrangedSubview
//   hidden 自带零高度塌缩，零回归）。
- (void)ame328_refreshPluginChip {
    NSInteger ame328_rows = (NSInteger)[[AmePluginRuntime allContributedRows] count];
    self.pluginChipButton.hidden = (ame328_rows <= 0);
    if (ame328_rows > 0) {
        self.pluginChipLabel.text = [NSString stringWithFormat:@"%@ (%ld)",
            localize(@"ame327.plugin.rows.title", nil), (long)ame328_rows];
        self.pluginChipButton.accessibilityLabel = self.pluginChipLabel.text;
    }
}

// ★ Task328：插件 chip → 壳切设置（index 4）→ 枢纽子页定点（启动器 = 4）。
//   两段通知【同步】派发：第一段让壳 attach 设置枢纽（懒建路径子页 attach
//   同步触发 viewDidLoad，观察者先注册）；第二段定点通知随即必达——先建
//   后点的时序确定，枢纽已存在的重访路径同样命中。
- (void)ame328_pluginChipTapped {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2ShellNavigate"
                                                        object:nil
                                                      userInfo:@{@"index": @4}];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2SettingsSelectPage"
                                                        object:nil
                                                      userInfo:@{@"index": @(4)}];
}

- (void)ame_handleMenuLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    self.ame_menuOnRight = !self.ame_menuOnRight;
    [[NSUserDefaults standardUserDefaults] setObject:(self.ame_menuOnRight ? @"right" : @"left")
                                              forKey:ZL2HomeMenuSideDefaultsKey];
    [self ame_applySideConstraintsAnimated:YES];
}

#pragma mark - Grid Datasource / Delegate

- (NSInteger)collectionView:(UICollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.ame_rows.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ZL2HomeVersionCardCell *cell =
        [collectionView dequeueReusableCellWithReuseIdentifier:@"zl2_home_version_card"
                                                   forIndexPath:indexPath];
    NSDictionary *row = self.ame_rows[(NSUInteger)indexPath.item];
    NSString *profileName = row[@"name"];

    [cell ame_configureWithRow:row];
    __weak ZL2HomeViewController *weakSelf = self;
    cell.ame_onCard = ^{
        [weakSelf ame_selectProfileNamed:profileName];
    };
    cell.ame_onPlay = ^{
        [weakSelf ame_playProfileNamed:profileName];
    };
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat gridWidth = collectionView.bounds.size.width;
    NSInteger columns = [self ame_columnsForWidth:gridWidth];
    CGFloat available = gridWidth - ZL2HomeGridInsetH * 2;
    CGFloat itemWidth = ((available - (columns - 1) * ZL2HomeGridSpacing) / columns);
    return CGSizeMake(itemWidth, ZL2HomeCardHeight);
}

// 列数：iPad 3 列 / iPhone 2 列；列宽低于阈值逐级降列（窄屏/iPhone 竖屏
// 菜单占 240 后内容区过窄的兜底，防止出现 <140pt 破相卡）
- (NSInteger)ame_columnsForWidth:(CGFloat)width {
    if (width <= 0) return 1;
    NSInteger columns = (self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad) ? 3 : 2;
    CGFloat available = width - ZL2HomeGridInsetH * 2;
    while (columns > 1) {
        CGFloat columnWidth = (available - (columns - 1) * ZL2HomeGridSpacing) / columns;
        if (columnWidth >= ZL2HomeCardMinWidth) break;
        columns--;
    }
    return columns;
}

#pragma mark - Gestures

/// 长按实例卡 → M3 底部菜单（设为当前实例 / 打开版本详情 / 删除）
- (void)ame_handleCardLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint location = [gesture locationInView:self.gridView];
    NSIndexPath *target = [self.gridView indexPathForItemAtPoint:location];
    if (!target || target.item >= (NSInteger)self.ame_rows.count) return;
    NSDictionary *row = self.ame_rows[(NSUInteger)target.item];
    [self ame_showActionSheetForProfile:row[@"name"]];
}

#pragma mark - Data Build（ZL2VersionsViewController 同款契约）

/// 全量重建实例行模型（loadProfiles 排序同款：键降序）
- (void)ame_rebuildData {
    NSMutableDictionary *profiles = PLProfiles.current.profiles;
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSString *key in profiles.allKeys) {
        [keys addObject:key];
    }
    NSArray<NSString *> *sorted = [keys sortedArrayUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        return [obj2 compare:obj1];
    }];

    NSString *selected = PLProfiles.current.selectedProfileName;
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    for (NSString *name in sorted) {
        NSDictionary *profile = profiles[name];
        if (![profile isKindOfClass:[NSDictionary class]]) continue;

        NSString *versionId = profile[@"lastVersionId"];
        if (![versionId isKindOfClass:[NSString class]]) versionId = nil;

        // ★ Task351：latest 别名占位符（latest-release/latest-snapshot/latest）
        //   不进加载器/MC 版本解析——启动链在线解析，信息行留空避免
        //   “MC latest-release” 伪文案
        BOOL ame351_alias = [self ame_isLatestAlias:versionId];

        // 加载器 / MC 版本：版本页同款双契约（字符串识别 + parseVersionId 反解）
        NSString *loader = (versionId && !ame351_alias)
            ? [ModLoaderIconHelper detectLoaderFromVersionId:versionId] : nil;
        NSDictionary *parsed = (versionId && !ame351_alias)
            ? [ModpackExportService parseVersionId:versionId] : @{};
        NSString *mcVersion = parsed[@"minecraft"] ?: (ame351_alias ? @"" : versionId);

        BOOL valid = [self ame_isVersionIdValid:versionId forProfile:profile];

        [rows addObject:@{
            @"name": name,
            @"versionId": versionId ?: @"",
            @"loader": loader ?: @"",
            @"mcVersion": mcVersion ?: @"",
            @"valid": @(valid),
            @"isSelected": @([name isEqualToString:selected]),
        }];
    }
    self.ame_rows = rows;
}

- (void)ame_rebuildGrid {
    [self.gridView reloadData];
    BOOL empty = (self.ame_rows.count == 0);
    self.emptyStateView.hidden = !empty;
    self.gridView.hidden = empty;
}

- (BOOL)ame_isVersionIdValid:(NSString *)versionId {
    return [self ame_isVersionIdValid:versionId forProfile:nil];
}

// ★ Task351：latest 别名占位符（MinecraftResourceDownloadTask 启动链在线
//   解析，本地 versions/ 按字面查询必 miss）
- (BOOL)ame_isLatestAlias:(NSString *)versionId {
    return [versionId isEqualToString:@"latest-release"] ||
           [versionId isEqualToString:@"latest-snapshot"] ||
           [versionId isEqualToString:@"latest"];
}

- (BOOL)ame_isVersionIdValid:(NSString *)versionId forProfile:(NSDictionary *)profile {
    if (versionId.length == 0) return NO;
    // ★ Task351：latest 别名占位符恒有效——启动链在线解析为实际版本并按需
    //   下载，本地 versions/ 按字面查询必 miss = 出厂 (Default) 卡
    //   "该版本无效"的误判根因。
    if ([self ame_isLatestAlias:versionId]) return YES;
    // 与版本页 Task255/Task256 路径口径逐项一致：真机实体在
    // POJAV_GAME_DIR/versions（= instances/<当前实例>/versions），
    // POJAV_HOME/versions 仅旧版布局存在，作降序兜底（双 NULL 防御）。
    const char *gameDir = getenv("POJAV_GAME_DIR");
    const char *home = getenv("POJAV_HOME");
    NSString *root = nil;
    if (gameDir) {
        root = [NSString stringWithUTF8String:gameDir];
    } else if (home) {
        root = [NSString stringWithUTF8String:home];
    }
    if (root.length == 0) return NO;
    // ★ Task351：profile 自身 gameDir 优先——版本隔离实例的版本实体在自己
    //   目录（instances/<n>/versions），原实现只查当前实例 root，非当前实例
    //   即使实体在也必误判（Task349 收编条目 gameDir 绝对路径锚定正好可消费）。
    NSString *ame351_gd = [profile isKindOfClass:[NSDictionary class]]
        ? profile[@"gameDir"] : nil;
    if ([ame351_gd isKindOfClass:[NSString class]] &&
        ame351_gd.length > 0 && ![ame351_gd isEqualToString:@"."]) {
        NSString *ame351_json = [NSString stringWithFormat:
            @"%@/versions/%@/%@.json", ame351_gd, versionId, versionId];
        if ([NSFileManager.defaultManager fileExistsAtPath:ame351_json]) return YES;
    }
    NSString *vdir = [NSString stringWithFormat:@"%@/versions/%@", root, versionId];
    NSString *jsonPath = [vdir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", versionId]];
    if ([NSFileManager.defaultManager fileExistsAtPath:jsonPath]) return YES;
    if (gameDir && home) {
        // 主根未命中时再查旧布局兜底根（仅当主根来自 POJAV_GAME_DIR）
        NSString *legacy = [NSString stringWithFormat:@"%s/versions/%@/%@.json", home, versionId, versionId];
        return [NSFileManager.defaultManager fileExistsAtPath:legacy];
    }
    return NO;
}

#pragma mark - Profile Actions（版本页同款语义）

/// 选用实例：版本页 selectProfileNamed 同款——同名静默防抖，写 selected
/// + save + post @"SelectedProfileChanged" + 重建
- (void)ame_selectProfileNamed:(NSString *)profileName {
    NSString *selected = PLProfiles.current.selectedProfileName;
    if ([profileName isEqualToString:selected]) return;
    PLProfiles.current.selectedProfileName = profileName;
    [PLProfiles.current save];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectedProfileChanged" object:nil];
    [self ame_rebuildData];
    [self ame_rebuildGrid];
    [self ame_refreshVersionCard];
}

/// 卡上播放键：切该实例为选中并直接走启动链（ZL2 版本卡语义；启动入口
/// 复用大按钮同一链路：下载中反查进度页 / 有任务提示 / launchGame）
- (void)ame_playProfileNamed:(NSString *)profileName {
    [self ame_selectProfileNamed:profileName];
    [self launchButtonTapped];
}

/// 长按卡 M3 底部菜单：设为当前实例 / 打开版本详情 / 删除（红色）。
/// 删除项经 ame_pendingSheetAction 时序收口：弹层 onDismiss 完成后再走
/// 确认框（防双层 present 目标错乱）。
- (void)ame_showActionSheetForProfile:(NSString *)profileName {
    UIStackView *sheetStack = [[UIStackView alloc] init];
    sheetStack.axis = UILayoutConstraintAxisVertical;
    sheetStack.alignment = UIStackViewAlignmentFill;
    sheetStack.spacing = 2;
    sheetStack.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = profileName;
    titleLabel.font = [ZL2Theme fontTitleMedium];
    titleLabel.textColor = [ZL2Theme onSurface];
    titleLabel.numberOfLines = 1;
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [sheetStack addArrangedSubview:titleLabel];
    [titleLabel.heightAnchor constraintEqualToConstant:32].active = YES;

    __weak ZL2HomeViewController *weakSelf = self;

    // ① 设为当前实例（checkmark.circle，SF1.0）
    [sheetStack addArrangedSubview:
        [self ame_sheetRowWithSymbol:@"checkmark.circle"
                             fallback:@"check.circle"
                                 text:@"设为当前实例"
                          destructive:NO
                              action:^{
            [ZL2M3BottomSheet dismissWithContentView:sheetStack];
            [weakSelf ame_selectProfileNamed:profileName];
        }]];

    // ② 打开版本详情（info.circle，SF1.0）——容器由壳接线，本页只发通知
    [sheetStack addArrangedSubview:
        [self ame_sheetRowWithSymbol:@"info.circle"
                             fallback:nil
                                 text:@"打开版本详情"
                          destructive:NO
                              action:^{
            [ZL2M3BottomSheet dismissWithContentView:sheetStack];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2OpenVersionDetail"
                                                                object:nil
                                                              userInfo:@{@"profile": profileName}];
        }]];

    // ③ 删除（trash，SF1.0；error 色 destructive 语义）
    [sheetStack addArrangedSubview:
        [self ame_sheetRowWithSymbol:@"trash"
                             fallback:@"trash.fill"
                                 text:localize(@"i18n_str_306", nil)
                          destructive:YES
                              action:^{
            // 弹层行 block 捕 self 会临时持有 VC——统一走 weak→strong 纪律
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            void (^deleteAction)(void) = ^{
                [weakSelf ame_deleteProfile:profileName];
            };
            strongSelf.ame_pendingSheetAction = deleteAction;
            [ZL2M3BottomSheet dismissWithContentView:sheetStack];
        }]];

    [ZL2M3BottomSheet presentWithContentView:sheetStack
                                  onDismiss:^{
        void (^pending)(void) = weakSelf.ame_pendingSheetAction;
        weakSelf.ame_pendingSheetAction = nil;
        if (pending) pending();
    }];
}

/// 弹层行工厂：48 高整行（22 图标 + 文案）；destructive = error 色
- (ZL2HomeTapControl *)ame_sheetRowWithSymbol:(NSString *)symbol
                                     fallback:(NSString *)fallback
                                         text:(NSString *)text
                                  destructive:(BOOL)destructive
                                       action:(void (^)(void))action {
    ZL2HomeTapControl *rowControl = [[ZL2HomeTapControl alloc] init];
    rowControl.backgroundColor = [UIColor clearColor];
    rowControl.translatesAutoresizingMaskIntoConstraints = NO;
    rowControl.isAccessibilityElement = YES;
    rowControl.accessibilityTraits = UIAccessibilityTraitButton;
    rowControl.accessibilityLabel = text;

    UIImage *image = ZL2HomeSystemImage(symbol, fallback);
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    iconView.tintColor = destructive ? [ZL2Theme error] : [ZL2Theme onSurfaceVariant];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.userInteractionEnabled = NO;
    [rowControl addSubview:iconView];

    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [ZL2Theme fontLabelLarge];
    label.textColor = destructive ? [ZL2Theme error] : [ZL2Theme onSurface];
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.userInteractionEnabled = NO;
    [rowControl addSubview:label];

    rowControl.ame_action = action;

    [NSLayoutConstraint activateConstraints:@[
        [rowControl.heightAnchor constraintEqualToConstant:48],
        [iconView.leadingAnchor constraintEqualToAnchor:rowControl.leadingAnchor constant:8],
        [iconView.centerYAnchor constraintEqualToAnchor:rowControl.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:22],
        [iconView.heightAnchor constraintEqualToConstant:22],
        [label.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:14],
        [label.centerYAnchor constraintEqualToAnchor:rowControl.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:rowControl.trailingAnchor constant:-8],
    ]];
    return rowControl;
}

/// 删除实例：版本页 deleteProfile（旧 VC L1893-1971）1:1 移植——至少保留
/// 一个实例守卫 + 二次确认 + 注册表删除 + 选中回退 + Task255 实体目录
/// 连带删除（引用计数守卫）+ 重建 + ReloadProfileList。
- (void)ame_deleteProfile:(NSString *)profileName {
    if (self.ame_rows.count <= 1) {
        [self showAlert:localize(@"i18n_str_1092", nil)];
        return;
    }

    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_457", nil)
                                                                     message:[NSString stringWithFormat:localize(@"i18n_str_1093", nil), profileName]
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_306", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        // Task255：删除注册表条目后，若同一 lastVersionId 不再被任何其他
        // 实例引用 → 连带删除 versions/<id> 实体目录（含隔离 game 目录）。
        NSDictionary *profile = PLProfiles.current.profiles[profileName];
        NSString *versionId = [profile isKindOfClass:NSDictionary.class] ? profile[@"lastVersionId"] : nil;

        [PLProfiles.current.profiles removeObjectForKey:profileName];
        if ([PLProfiles.current.selectedProfileName isEqualToString:profileName]) {
            PLProfiles.current.selectedProfileName = PLProfiles.current.profiles.allKeys.firstObject;
        }
        [PLProfiles.current save];

        if ([versionId isKindOfClass:[NSString class]] && versionId.length > 0) {
            BOOL stillReferenced = NO;
            for (NSString *key in PLProfiles.current.profiles) {
                NSDictionary *p = PLProfiles.current.profiles[key];
                if ([p isKindOfClass:NSDictionary.class] &&
                    [p[@"lastVersionId"] isKindOfClass:[NSString class]] &&
                    [p[@"lastVersionId"] isEqualToString:versionId]) {
                    stillReferenced = YES;
                    break;
                }
            }
            if (!stillReferenced) {
                // Task255 r2 路径根修正：版本实体在 POJAV_GAME_DIR/versions
                //（= instances/<当前实例>/versions），POJAV_HOME/versions 仅
                // 旧版布局存在，作降序兜底（旧 VC 同款）。
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
                        NSLog(@"[ZL2Home] Task255: removed version folder for deleted profile '%@' -> %@", profileName, vdir);
                    } else {
                        NSLog(@"[ZL2Home] Task255: failed to remove version folder %@: %@", vdir, err.localizedDescription);
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self showAlert:[NSString stringWithFormat:localize(@"i18n_str_1088", nil), err.localizedDescription]];
                        });
                    }
                }
            } else {
                NSLog(@"[ZL2Home] Task255: version %@ still referenced by other profile(s), folder kept", versionId);
            }
        }

        [self refreshLaunchState];
        // 旧 VC 同款：通知全局快照刷新（主页/下载页不再残留已删版本）
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - State Refresh (public)

- (void)refreshLaunchState {
    [self ame_refreshAccountCard];
    [self ame_refreshVersionCard];
    [self ame_refreshLaunchButton];
    // 实例网格随三态刷新全量重建（列表小、PLProfiles 为内存注册表，廉价；
    // 壳侧手动调 / viewWillAppear 回来时保证网格与选择卡一致）
    [self ame_rebuildData];
    [self ame_rebuildGrid];
}

// —— 账号卡 ——（显示名取 BaseAuthenticator.current.authData[@"username"]，
// 旧链同款 Demo. 规整；类型文字 = Task220 判别口径本地推导，零新增外部符号；
// 头像 = AvatarManager ame185 三层回退链，未登录 = 加号占位）
- (void)ame_refreshAccountCard {
    NSString *displayName = localize(@"i18n_str_357", nil);
    NSString *typeText = @"";
    BaseAuthenticator *auth = BaseAuthenticator.current;
    NSDictionary *authData = nil;
    if (auth && auth.authData) {
        authData = auth.authData;
        NSString *username = authData[@"username"];
        if ([username isKindOfClass:[NSString class]] && username.length > 0) {
            if ([username hasPrefix:@"Demo."]) {
                username = [username substringFromIndex:5];
                typeText = localize(@"login.option.demo", @"演示");
            } else {
                typeText = [self ame_typeTextForAccountData:auth.authData];
            }
            displayName = username;
        }
    }
    self.accountNameLabel.text = displayName;
    self.accountTypeLabel.text = typeText;
    self.accountCard.accessibilityLabel = [NSString stringWithFormat:@"账户：%@", displayName];

    if (authData) {
        __weak ZL2HomeViewController *weakSelf = self;
        [[AvatarManager sharedManager] ame185_fetchAvatarForAuthData:authData
                                                          completion:^(UIImage *image) {
            if (image) {
                weakSelf.accountAvatarView.image = image;      // 真头像（默认渲染，圆底裁切）
                weakSelf.accountAvatarView.tintColor = nil;
            } else {
                UIImage *placeholder = ZL2HomeSystemImage(@"person.crop.circle.fill", @"person.circle.fill");
                weakSelf.accountAvatarView.image = [placeholder imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                weakSelf.accountAvatarView.tintColor = [ZL2Theme onSurfaceVariant];
            }
        }];
    } else {
        // 未登录：加号占位（ZL2 ActionMenu 账号槽语义）
        UIImage *plusImage = ZL2HomeSystemImage(@"plus.circle.fill", @"plus.circle");
        self.accountAvatarView.image = [plusImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.accountAvatarView.tintColor = [ZL2Theme onSurfaceVariant];
    }
}

// —— 版本选择卡 ——（当前实例名 + 加载器小标签；无实例显示「选择版本」）
- (void)ame_refreshVersionCard {
    NSString *selectedProfile = PLProfiles.current.selectedProfileName;
    if (selectedProfile) {
        NSDictionary *profile = PLProfiles.current.profiles[selectedProfile];
        NSString *versionId = [profile isKindOfClass:[NSDictionary class]] ? profile[@"lastVersionId"] : nil;
        if (![versionId isKindOfClass:[NSString class]]) versionId = nil;

        NSString *loader = versionId ? [ModLoaderIconHelper detectLoaderFromVersionId:versionId] : nil;
        NSDictionary *parsed = versionId ? [ModpackExportService parseVersionId:versionId] : @{};
        NSString *mcVersion = parsed[@"minecraft"] ?: versionId;

        self.versionNameLabel.text = selectedProfile;
        self.versionNameLabel.textColor = [ZL2Theme onSurface];

        if (mcVersion.length > 0 && loader.length > 0) {
            self.versionLoaderLabel.text = [NSString stringWithFormat:@"MC %@ · %@",
                                            mcVersion, [ModLoaderIconHelper displayNameForLoader:loader]];
        } else if (mcVersion.length > 0) {
            self.versionLoaderLabel.text = [NSString stringWithFormat:@"MC %@", mcVersion];
        } else if (loader.length > 0) {
            self.versionLoaderLabel.text = [ModLoaderIconHelper displayNameForLoader:loader];
        } else {
            self.versionLoaderLabel.text = @"";
        }

        if (loader.length > 0) {
            [ModLoaderIconHelper configureImageView:self.versionIconView
                                          forLoader:loader
                                     traitCollection:self.traitCollection];
            self.versionIconBg.backgroundColor = [UIColor clearColor];
        } else {
            UIImage *fallbackIcon = ZL2HomeSystemImage(@"gamecontroller.fill", @"gamecontroller");
            self.versionIconView.image = [fallbackIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            self.versionIconView.tintColor = [ZL2Theme onSurfaceVariant];
            self.versionIconBg.backgroundColor = [ZL2Theme surfaceVariant];
        }
    } else {
        self.versionNameLabel.text = @"选择版本";
        self.versionNameLabel.textColor = [ZL2Theme onSurfaceVariant];
        self.versionLoaderLabel.text = @"";
        UIImage *fallbackIcon = ZL2HomeSystemImage(@"gamecontroller.fill", @"gamecontroller");
        self.versionIconView.image = [fallbackIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.versionIconView.tintColor = [ZL2Theme onSurfaceVariant];
        self.versionIconBg.backgroundColor = [ZL2Theme surfaceVariant];
    }
}

// —— 大启动钮三态 ——（禁用判定/文案/着色 1:1 旧链；百分比行仅下载态可见）
- (void)ame_refreshLaunchButton {
    BaseAuthenticator *auth = BaseAuthenticator.current;
    BOOL buttonEnabled = (self.task == nil) && !self.ame_launchChainActive;
    self.launchButton.enabled = buttonEnabled;
    self.launchButton.backgroundColor = buttonEnabled ? [ZL2Theme launchReadyTint]
                                                      : [ZL2Theme launchDisabledTint];
    self.launchIconView.tintColor = buttonEnabled ? [ZL2Theme onPrimary]
                                                  : [ZL2Theme onSurfaceVariant];
    self.launchButtonLabel.textColor = buttonEnabled ? [ZL2Theme onPrimary]
                                                     : [ZL2Theme onSurfaceVariant];

    BOOL hasActiveTasks = [[DownloadTaskManager sharedManager] hasActiveTasks];
    BOOL hasAccount = (auth != nil);
    NSString *statusText;
    if (hasActiveTasks) {
        statusText = localize(@"i18n_str_434", nil);   // 下载中
    } else if (!hasAccount) {
        statusText = localize(@"i18n_str_435", nil);   // 登录并启动
    } else {
        statusText = localize(@"i18n_str_412", nil);   // 启动游戏
    }
    self.launchButtonLabel.text = statusText;
    self.launchStatusLabel.text = statusText;
    self.launchStatusLabel.hidden = (self.task == nil);
    self.launchButton.accessibilityLabel = statusText;
    self.launchButton.accessibilityTraits = UIAccessibilityTraitButton;
}

#pragma mark - Notifications

- (void)accountOrHomeDidChange:(NSNotification *)notification {
    [self refreshLaunchState];

    // FCL 风格续启动：用户从启动按钮进入登录（pending=YES），账号就绪后自动继续启动链
    if ([notification.name isEqualToString:@"UpdateAccountInfo"] &&
        self.ame_pendingLaunchAfterLogin &&
        BaseAuthenticator.current != nil) {
        self.ame_pendingLaunchAfterLogin = NO;
        [self launchGame];
    }
}

// 实例表变化（版本页选用/删除、本页删除链、下载完成）：网格与选择卡刷新
- (void)profileListDidChange {
    [self refreshLaunchState];
}

#pragma mark - Tap Handlers

- (void)accountCardTapped {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowAccountManager" object:nil];
}

// 版本选择卡卡体 = 版本管理页（ZL2 版本选择器语义）
- (void)versionCardTapped {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2ShellNavigate"
                                                        object:nil
                                                      userInfo:@{@"index": @2}];
}

- (void)versionSettingsTapped {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2ShellNavigate"
                                                        object:nil
                                                      userInfo:@{@"index": @2}];
}

// 刷新态：重拉 PLProfiles 注册表后全量刷新（网格 + 选择卡 + 三态）
- (void)versionRefreshTapped {
    [PLProfiles updateCurrent];
    [self refreshLaunchState];
}

#pragma mark - Launch Chain（1:1 旧链语义；历史指针：旧右面板续链段，类已 Task343 退役）

- (void)launchButtonTapped {
    if (self.task) {
        // 下载中点击启动按钮 → 反查 DownloadTaskManager 打开统一进度页
        // （任务由 MinecraftResourceDownloadTask 内部注册，按 rawTask 反查 taskId）
        NSString *taskId = nil;
        for (DownloadTaskItem *item in [DownloadTaskManager sharedManager].allTasks) {
            if (item.rawTask == self.task) {
                taskId = item.taskId;
                break;
            }
        }
        if (taskId) {
            [PLTaskProgressViewController presentForTaskId:taskId];
        }
        return;
    }

    if ([[DownloadTaskManager sharedManager] hasActiveTasks]) {
        // 旧链语义：无本页发起的任务但存在其他进行中下载 → 提示后仍允许启动
        // （某些下载与游戏本体启动无依赖关系，强制等待反而阻塞体验）
        [self showAlert:localize(@"i18n_str_388", nil) message:localize(@"i18n_str_430", nil)];
    }

    [self launchGame];
}

- (void)launchGame {
    BaseAuthenticator *currentAuth = BaseAuthenticator.current;
    if (!currentAuth) {
        // FCL 风格：无账号 → 挂 pending 标记切账户管理页，
        // @"UpdateAccountInfo" 回来（accountOrHomeDidChange:）自动继续启动
        self.ame_pendingLaunchAfterLogin = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowAccountManager" object:nil];
        return;
    }
    self.ame_pendingLaunchAfterLogin = NO;

    // 旧契约：启动链发生在主页语境（Task261 判例：点启动 → 确定性秒回主页）
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowHomePage" object:nil];

    NSString *selectedProfile = PLProfiles.current.selectedProfileName;
    if (!selectedProfile) {
        [self showAlert:localize(@"i18n_str_431", nil)];
        return;
    }

    NSString *versionId = PLProfiles.current.profiles[selectedProfile][@"lastVersionId"];
    // ★ Task352：空/缺失版本 = "未选择版本"（收编与 Task352 修复遍也未命中
    //   的如实态，引导语义：去版本/下载页选择或安装），不再弹误导性的
    //   "无法获取版本信息"（str_43 语义是版本存在但获取失败）
    if (![versionId isKindOfClass:[NSString class]] || versionId.length == 0) {
        [self showAlert:localize(@"ame351.instance.no_version", nil)];
        return;
    }

    // FCL 风格：记录最后游玩时间戳到 profile，供版本管理页显示
    NSMutableDictionary *profiles = PLProfiles.current.profiles;
    NSMutableDictionary *profile = [profiles[selectedProfile] mutableCopy];
    if (profile) {
        profile[@"lastPlayed"] = @([[NSDate date] timeIntervalSince1970]);
        profiles[selectedProfile] = profile;
        [PLProfiles.current save];
    }

    // ★ Task353：启动期版本根对齐（"该版本无效/找不到版本信息"终局线）。
    //   病历（装机 29f8b67 latestlog 实锤）：版本轴实例（Ame329 统一后
    //   gameDir=instances/<x>/versions/<vid>）的版本实体在 profile 自洽根，
    //   而启动链三级口径（ZL2VersionIndex ②③ 本地扫描 / MRDT versions/<id>
    //   落位与校验 / Java DIR_HOME_VERSION=POJAV_GAME_DIR/versions）全部以
    //   全局 POJAV_GAME_DIR（=偏好当前实例）为根——卡片判定侧 Task351 已吃
    //   profile gameDir（卡显示"有效"），启动侧没吃 = 判定/启动两张皮，点
    //   启动必弹 i18n_str_432（unresolved loaded=1 localScan=0 disk=0）。
    //   修法：发 FindVersionInRemoteList 前把 POJAV_GAME_DIR 对齐到 profile
    //   版本根 R（R/versions/<vid>/<vid>.json 真实存在，PLProfiles 纯读探
    //   测），Java/MRDT/索引三段全链同根自洽；对齐后 MRDT 校验链（缺啥补啥）
    //   顺势把 libraries/assets 补进 profile 自根 = 版本隔离安装语义闭环。
    //   注册表失守面由 PLProfiles ame353 last-known-good 锚兜住（对齐窗口内
    //   updateCurrent 读不到新根注册表时回读旧锚，绝不出厂重置误写）。
    //   nil（latest 别名/未装/实体不在）零触碰 = 正常在线解析下载流原样。
    {
        NSString *ame353_root = [PLProfiles ame353_versionRootForProfileName:selectedProfile];
        if (ame353_root.length > 0) {
            NSString *ame353_prev = @(getenv("POJAV_GAME_DIR") ?: "");
            if (![ame353_root isEqualToString:ame353_prev]) {
                setenv("POJAV_GAME_DIR", ame353_root.UTF8String, 1);
                NSLog(@"[Ame353] launch version-root aligned: %@ -> %@ (profile=%@, vid=%@)",
                      ame353_prev, ame353_root, selectedProfile, versionId);
            }
        }
    }

    // 设置 UI 为下载状态（反查窗口期防双击；恢复点：回调失败/完成/handleError）
    [self setLaunchInteractionEnabled:NO];

    // 通过通知从远程版本列表反查版本对象（本地版本查不到 → 提示 + 恢复交互）
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[@"versionId"] = versionId;
    __weak ZL2HomeViewController *weakSelf = self;
    userInfo[@"callback"] = ^(NSDictionary *version) {
        if (version) {
            [weakSelf startDownloadWithVersion:version profileName:selectedProfile];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf setLaunchInteractionEnabled:YES];
                [weakSelf showAlert:localize(@"i18n_str_432", nil)];
            });
        }
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:@"FindVersionInRemoteList"
                                                        object:nil
                                                      userInfo:userInfo];
}

- (void)startDownloadWithVersion:(NSDictionary *)versionObject profileName:(NSString *)profileName {
    self.task = [MinecraftResourceDownloadTask new];

    // ★ Task318：Task304 launchcheck 键补移植——本页是 1:1 旧链移植
    //  （LauncherRightPanelViewController L1403-1550 同语义），但旧链带
    //   ame300_launchcheck=YES 而本页漏带：已装实例（目录+json 完整）点启动
    //   会撞 Task300 改名窗"实例已存在"每次必弹。补键对齐 = 校验链语义，
    //   verify-and-continue 零弹窗；目录不存在时正常下载流程不受影响。
    NSMutableDictionary *ame318_launchVersion =
        [versionObject isKindOfClass:[NSDictionary class]] ? [versionObject mutableCopy] : [NSMutableDictionary dictionary];
    ame318_launchVersion[@"ame300_launchcheck"] = @YES;

    __weak ZL2HomeViewController *weakSelf = self;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // handleError 桩：主线程恢复交互 + KVO 野指针纪律（task=nil 之前先移除观察者）。
        // 注：本页无 UIProgressView，旧链的 progressView.observedProgress = nil 在此无对应物。
        weakSelf.task.handleError = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf setLaunchInteractionEnabled:YES];
                @try {
                    [weakSelf.task.progress removeObserver:weakSelf
                                                forKeyPath:@"fractionCompleted"
                                                   context:ZL2HomeProgressObserverContext];
                } @catch (NSException *e) {}
                weakSelf.task = nil;
                [weakSelf refreshLaunchState];
            });
        };

        [weakSelf.task downloadVersion:ame318_launchVersion];

        dispatch_async(dispatch_get_main_queue(), ^{
            // KVO 观察下载进度（OptionInitial：挂上即回调一次，状态行立即进百分比态）
            [weakSelf.task.progress addObserver:weakSelf
                                     forKeyPath:@"fractionCompleted"
                                        options:NSKeyValueObservingOptionInitial
                                        context:ZL2HomeProgressObserverContext];
            // 统一进度页由任务内部阶段上报（autoPresentDetail）自动弹出，此处不手动 present
            [weakSelf refreshLaunchState];
        });
    });
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    if (context != ZL2HomeProgressObserverContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    // 强持有 progress 快照：即便 task 在异步落地前被 handleError 清空，
    // removeObserver 的对象依然存活（wild-pointer 双保险）
    NSProgress *progress = self.task.progress;
    if (!progress) return;
    NSInteger percent = (NSInteger)(progress.fractionCompleted * 100.0 + 0.5);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (percent >= 100) {
            // 下载完成：统一进度页由任务内部接管（autoPresentDetail）。
            // KVO 野指针纪律：task=nil 之前先移除观察者（旧链完成分支同款）。
            @try {
                [progress removeObserver:self
                              forKeyPath:@"fractionCompleted"
                                 context:ZL2HomeProgressObserverContext];
            } @catch (NSException *e) {}

            // ★ Task323 根修（"点启动后游戏不起"装机病历 203d22b latestlog
            //   实锤）：本页 7.0-UI 重建时完成分支只移植到"收尾刷新"为止，
            //   旧链（LauncherRightPanelViewController L1682-1755）的续链——
            //   profile 覆盖 → Task224 叠层收口 → invokeAfterJITEnabled →
            //   UIKit_launchMinecraftSurfaceVC——整段缺失，下载 100% 后静默
            //   终止 = 无 JIT 日志/无 SurfaceSwap/无 JVM spawn。现 1:1 补齐：
            NSDictionary *ame323_metadata = self.task.metadata;
            if ([ame323_metadata isKindOfClass:[NSDictionary class]]) {
                // ① profile 覆盖（旧链 L1684-1724 同款：Task140 分居语义保留）
                NSString *profileName = PLProfiles.current.selectedProfileName;
                NSDictionary *profile = PLProfiles.current.profiles[profileName];
                if (profile) {
                    // 应用图形 API 设置（MC 26.2+ 游戏内 OpenGL/Vulkan 切换）
                    NSString *graphicsApi = profile[@"graphicsApi"];
                    if (graphicsApi.length > 0) {
                        setPrefString(@"video.graphics_api", graphicsApi);
                    }
                    // 应用Java版本设置（兼容旧版直装器写入的 NSDictionary 格式）
                    id javaVerRaw = profile[@"javaVersion"];
                    NSString *javaVer = nil;
                    if ([javaVerRaw isKindOfClass:[NSDictionary class]]) {
                        id major = javaVerRaw[@"majorVersion"];
                        javaVer = major ? [major description] : @"auto";
                    } else if ([javaVerRaw isKindOfClass:[NSString class]]) {
                        javaVer = javaVerRaw;
                    } else {
                        javaVer = @"auto";
                    }
                    if (![javaVer isEqualToString:@"auto"]) {
                        setPrefString(@"java.java_version", javaVer);
                    }
                    // 应用内存设置
                    NSInteger allocatedMemory = [profile[@"allocatedMemory"] integerValue];
                    if (allocatedMemory > 0) {
                        setPrefInt(@"general.ram_allocation", (int)allocatedMemory);
                    }
                }
                // ② Task224 叠层收口 + JIT 门禁续链（旧链 L1726-1755 同款；
                //    门禁 onStage 会推进状态行：i18n_str_436 "等待 JIT" 等）
                [self ame323_beginJITGatedLaunchForMetadata:ame323_metadata];
            } else {
                // 无 metadata（下载完成但版本 JSON 缺失等异常）：维持旧行为收尾
                self.task = nil;
                [self setLaunchInteractionEnabled:YES];
                // 旧链同款：通知刷新版本列表（新版本已落盘可被版本管理页发现）
                [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
            }
        } else {
            self.launchStatusLabel.text =
                [NSString stringWithFormat:@"%@ %ld%%", localize(@"i18n_str_434", nil), (long)percent];
        }
    });
}

// Task323：启动续链第二段（旧链 LauncherRightPanelViewController L1726-1755
// Task224 收口 1:1）：先把页面之上呈现的整条 UI 链 dismiss 干净（版本设置/
// 编辑页文本框 + 拼音键盘后台化楔死主队列的病历，0.8s/0.5s 沉降），之后进
// JIT 门禁（PLJITGate = 旧链 invokeAfterJITEnabled 状态机共享化），就绪后
// 换根 SurfaceViewController 启动 JVM。
- (void)ame323_beginJITGatedLaunchForMetadata:(NSDictionary *)metadata {
    UIWindow *ame323_window = self.view.window;
    UIViewController *ame323_root = ame323_window.rootViewController;
    UIViewController *ame323_top = ame323_root;
    while (ame323_top.presentedViewController) {
        ame323_top = ame323_top.presentedViewController;
    }
    __weak typeof(self) weakSelf = self;
    void (^ame323_beginJITWait)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        // 弃启回调：旧链 Task267 取消路径同款（task=nil + 恢复交互 + 刷列表）
        void (^ame323_onAbandon)(void) = ^{
            __strong typeof(weakSelf) strongSelf2 = weakSelf;
            if (!strongSelf2) return;
            strongSelf2.task = nil;
            [strongSelf2 setLaunchInteractionEnabled:YES];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
        };
        // 等待期 task 必须保活（handler 从 task.metadata 现读——旧链同款）
        NSDictionary *ame323_launchMeta = strongSelf.task.metadata ?: metadata;
        [PLJITGate invokeAfterJITEnabledWithHandler:^{
            // Task183/185：JIT 就绪后换根 SurfaceViewController（JVM 进程内
            // JLI_Launch 由 SurfaceViewController → launchJVM 链承担）
            UIKit_launchMinecraftSurfaceVC(ame323_window, ame323_launchMeta);
        } hostVC:strongSelf onAbandon:ame323_onAbandon onStage:^(NSString *stageText) {
            __strong typeof(weakSelf) strongSelf3 = weakSelf;
            if (!strongSelf3) return;
            strongSelf3.launchStatusLabel.text = stageText;
        }];
    };
    if (ame323_top != ame323_root && ame323_top.presentingViewController) {
        NSLog(@"[JIT] [ZL2Home] Task224 closing presented stack ('%@') + 0.8s settle before JIT wait",
              NSStringFromClass([ame323_top class]));
        [ame323_top.presentingViewController dismissViewControllerAnimated:YES completion:^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ame323_beginJITWait);
        }];
    } else {
        // 无叠加 UI：仍给半拍让 resign/清理落地
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ame323_beginJITWait);
    }
}

- (void)setLaunchInteractionEnabled:(BOOL)enabled {
    self.ame_launchChainActive = !enabled;
    // 旧链同款：启动/下载期间保持屏幕常亮
    UIApplication.sharedApplication.idleTimerDisabled = !enabled;
    // 按钮可用态统一由 refreshLaunchState 依据 task/pending 派生（单一来源）
    [self refreshLaunchState];
}

#pragma mark - Profile Metadata Helpers（账户页同口径本地移植，零新增外部符号）

// 账号类型文字（Task220 判别口径——accountType 显式优先，旧文件回退键位嗅探）
- (NSString *)ame_typeTextForAccountData:(NSDictionary *)accountData {
    NSString *type = accountData[@"accountType"];
    if ([type isKindOfClass:[NSString class]] && type.length > 0) {
        if ([type isEqualToString:@"thirdparty"]) {
            return localize(@"login.option.3rdparty", @"第三方");
        }
        if ([type isEqualToString:@"local"]) {
            return localize(@"login.option.local", @"本地");
        }
        return @"Microsoft";
    }
    // 旧文件回退（与 loadSavedName 同口径：clientToken 先于 xboxGamertag）
    if (accountData[@"clientToken"] != nil) {
        return localize(@"login.option.3rdparty", @"第三方");
    }
    if (accountData[@"xboxGamertag"] == nil) {
        return localize(@"login.option.local", @"本地");
    }
    return @"Microsoft";
}

#pragma mark - Alerts

- (void)showAlert:(NSString *)message {
    [self showAlert:message message:nil];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
