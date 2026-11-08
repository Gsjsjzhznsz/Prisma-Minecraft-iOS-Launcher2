//
// ZL2HomeViewController.m — ZL2 真布局主页实现（7.0-UI-13-H：7:3 双栏）
//
// 对标 ZalithLauncher2 LauncherScreen 真结构：
//   LauncherScreen.kt            → Row{ 内容区(weight 7) + ActionMenu(3/10 宽
//                                  clamp[240,320]，停靠左/右持久化) }
//   ActionMenu.kt                → ★ Task400 卡片化：瓦片卡（顶）/账户封面流
//                                  卡/版本封面流卡（中段滚动区）+ 启动组卡
//                                  （钉底）；栏容器透明、四卡 surfaceContainer/
//                                  radiusXL、8pt 卡间隙（iOS 简化：ZL2 的
//                                  ★ Task403 停靠换边退役：右栏恒右，换边
//                                  选项/提示/持久化键提及一并清零（遗言零残留）
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
// ★ Task378 r2：目录瓦片改走壳通知接线（@"ZL2ShellOpenFileManager"）——有意不
//   import FolderBrowserViewController.h：ui_fluent_smoke 预览链接窄清单不含
//   该 TU，直连类符号 = _OBJC_CLASS_$ 未定义链接雷（Task323 ios_uikit_bridge
//   判例同族）；壳统一接线纪律同款（页面间零直连）。
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
#import "AmeFlowSelectView.h"  // ★ Task393 封面流选择器（★ Task401 更名+横轴化，账户横排/版本竖排双驻主页右栏）
#import "authenticator/ThirdPartyAuthenticator.h" // ★ Task400：账户滚轮选中链（第三方 refreshToken）
#import "NMToast.h"  // ★ Task400：选中链 stale 降级非侵入提示（账户页同款）

// ★ Task400：账户页共享链 C 符号前向声明（验证集合/第三方判别单源共享；
//   零头文件传递依赖，两 TU 同在 smoke 窄链接清单——UIKit_launchMinecraftSurfaceVC 同款判例）
NSMutableSet *ZL2AccountsSharedValidatedSet(void);
BOOL ZL2AccountsSharedIsThirdParty(NSDictionary *accountData);

// ★ Task400：AFNetworking 错误响应体键（仅消费此一个 extern 常量——账户页
//   同款判例；定义由真实构建 libAFNetworking / 预览桩 ZL2PagesStub 提供）
extern NSString * const AFNetworkingOperationFailingURLResponseDataErrorKey;

// KVO 观察上下文（旧链 ProgressObserverContext 同款静态指针判别，防父类/他人混淆）
static void *ZL2HomeProgressObserverContext = &ZL2HomeProgressObserverContext;
static NSString * const ZL2SidebarCardOrderDefaultsKey = @"zl2.home.sidebarCardOrder";

// ActionMenu 停靠边持久化 key（ZL2 ActionMenuDrag 停靠语义的 iOS 简化等价）
// ★Task404 恢复：73c10b7 曾随「固定右栏」退役本键与换边交互，用户复诉
// 「你怎么把停靠边功能删除了」——长按右栏菜单换停靠边为用户在用功能，原样回滚。
static NSString * const ZL2HomeMenuSideDefaultsKey = @"zl2.home.actionMenuSide";

// 双栏布局常量（LauncherScreen.kt Row 规格）
static const CGFloat ZL2HomeMenuWidthRatio   = 0.28;  // 右栏比例（停靠换边恢复后沿用 73c10b7 收窄值，用户未复诉宽度）
static const CGFloat ZL2HomeMenuWidthMax     = 300;
static const CGFloat ZL2HomeMenuWidthMin     = 220;
static const CGFloat ZL2HomeGridSpacing      = 6;     // 卡片间距（行/列同值）
static const CGFloat ZL2HomeGridInsetH       = 12;    // section 左右 inset
static const CGFloat ZL2HomeGridInsetTop     = 12;    // section 顶 inset
static const CGFloat ZL2HomeGridInsetBottom  = 16;    // section 底 inset
static const CGFloat ZL2HomeCardHeight       = 132;   // 实例卡高
static const CGFloat ZL2HomeCardMinWidth     = 140;   // 窄屏降列阈值（列宽低于则减列）

// ActionMenu 组件高度
static const CGFloat ZL2HomeLaunchButtonHeight = 48;  // 大启动钮（ScalingActionButton 48.dp）

// ★ Task401：右栏口径（用户规格 2026-11-04 三点纠错）：
//   ① 保留原来的右边栏（整块面板：surfaceContainer + radiusXL + 四边 8pt，
//     Task392 原样）——面板不拆除；② 每个卡片区域在面板上抠成透明窗：
//     卡底透明直透启动器背景（背景白→卡窗即白），卡间间隙 = 栏距屏边
//     8pt，卡窗圆角 = 右侧栏圆角 radiusXL；③ 账户卡 = 原头像+名称样式
//     横排五枚封面流（水平拖动选择）；版本卡 = 竖排封面流占五个正常
//     实例版本信息高度；④ 五瓦片卡驻顶；启动组卡钉底。
static const CGFloat ZL2HomeCardGap            = 8;   // 卡间间隙 = 栏距屏边 8pt（用户规格）
static const CGFloat ZL2HomeCardPadding        = 8;   // 卡内边距（与卡间隙同律）
static const CGFloat ZL2HomeAccountWheelH      = 88;  // 账户横排滚轮视口高（头像 32 + 名称/类型两行 + 上下留白）
static const CGFloat ZL2HomeAccountEntryAvatar = 32;  // 横排条目头像边长（原头像卡同语言等比缩位）
static const CGFloat ZL2HomeAccountFlowGapH    = 4;   // 横排条目间隙
static const CGFloat ZL2HomeVersionFlowItemH   = 64;  // 版本滚轮条目高（图标 40 + 双行文 =「五个正常的实例版本信息高度」口径）
static const CGFloat ZL2HomeFlowItemGap        = 10;  // 竖排条目间隙（实例卡图标→名称间隙参照，Task393 用户规格沿用）
static const CGFloat ZL2HomeCardFooterHeight   = 32;  // 卡尾动作行钮边长（账户管理/刷新/齿轮）

// ★ Task378 五入口快航瓦片（顶栏退役承接：壳 RailItem×5 → 本栏顶部）
// ★ Task392 一行化+图标减半（用户规格 2026-11-03：图标“缩小两倍”+“改成一行的”+
//   其余 UI 相应改变——55（=22×2.5）→ 27.5（=55÷2），两行 3+2 → 一行×5，
//   瓦片高 94 → 66.5（10 + 27.5 图标 + 2 + 15 标签 + 12），间距/留白口径不变）
static const CGFloat ZL2HomeQuickNavIconSize   = 27.5;  // 图标 = 55 ÷ 2（用户规格“缩小两倍”）
static const CGFloat ZL2HomeQuickNavTileHeight = 66.5;  // 瓦片高（10 + 27.5 图标 + 2 + 15 标签 + 12）
static const CGFloat ZL2HomeQuickNavGap        = 6;    // 行内统一间距（与两侧行内对称留白同值）

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

#pragma mark - ★ Task401 面板灰棱绘制视图（整块灰面板 + 四卡窗 even-odd 排除）

// 职责：把原右边栏整块灰面板画成“只剩灰棱”——外轮廓 = 面板圆角矩形
//（radiusXL = 右侧栏圆角），四卡窗区域从填充中排除（even-odd）：窗区不画
// = 透明 = 直透启动器背景（背景白→窗即白）。
// 实现注：r2 实锤（CI smoke 截图两轮整块实心）layer.mask + CAShapeLayer
// 在本场景不可靠（shape 层填充规则/挂接时序两不确定面），改用 drawRect
// 直画 —— UIBezierPath -fill 对 usesEvenOddFillRule 的支持是 CoreGraphics
// 契约，零中间层；深浅切换经 traitCollectionDidChange 重绘；几何由宿主
// 每帧喂（ame_setHoleRects：仅变化才重绘，滚动中逐帧调用零压力）。
@interface Ame401PanelHolesView : UIView
/// 挂四卡窗宿主（drawRect 绘制期自取帧——零跨视图喂矩形时序面）
- (void)ame401_setHostCards:(NSArray<UIView *> *)cards;
@end

@implementation Ame401PanelHolesView {
    NSArray<UIView *> *_ame401_cards;    // 四卡窗宿主（弱语义由宿主持有保证）
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;
        self.isAccessibilityElement = NO;
    }
    return self;
}

- (void)ame401_setHostCards:(NSArray<UIView *> *)cards {
    _ame401_cards = [cards copy];
    [self setNeedsDisplay];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self setNeedsDisplay];   // 自身几何变化即重绘（滚动中子帧变化由宿主 scrollViewDidScroll 补触发）
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    // 自测量：卡窗矩形 = 绘制期直读四卡帧（本视图坐标），不依赖外部喂矩形
    NSMutableArray<NSValue *> *ame401_holes = [NSMutableArray array];
    for (UIView *ame401_card in _ame401_cards) {
        if (ame401_card == nil || ame401_card.hidden || ame401_card.window == nil) continue;
        CGRect ame401_r = [ame401_card convertRect:ame401_card.bounds toView:self];
        if (ame401_r.size.width < 1.0 || ame401_r.size.height < 1.0) continue;
        [ame401_holes addObject:[NSValue valueWithCGRect:ame401_r]];
    }

    CGFloat ame401_radius = [ZL2Theme radiusXL];
    UIBezierPath *ame401_path = [UIBezierPath
        bezierPathWithRoundedRect:self.bounds cornerRadius:ame401_radius];
    for (NSValue *ame401_v in ame401_holes) {
        CGRect ame401_r = ame401_v.CGRectValue;
        [ame401_path appendPath:[UIBezierPath bezierPathWithRoundedRect:ame401_r
                                                           cornerRadius:ame401_radius]];
    }
    ame401_path.usesEvenOddFillRule = YES;
    // 动态令牌逐 trait 解析（drawRect 无自动深浅跟随，本视图自理）
    UIColor *ame401_color = [[ZL2Theme surfaceContainer]
        resolvedColorWithTraitCollection:self.traitCollection];
    // r4 自诊锚：洞为零（帧链路断）= 面板画纯红 —— smoke 截图一眼定位
    //（正常态恒有四洞；红色只可能出现在帧链路断裂的异常装机上）
    if (ame401_holes.count == 0 && !CGRectIsEmpty(self.bounds)) {
        ame401_color = [UIColor systemRedColor];
    }
    [ame401_color setFill];
    [ame401_path fill];   // even-odd：窗区交叉计数 2 = 偶数 = 不填 = 透明
}

@end

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
        _playLabel.text = localize(@"ame369.home.play", @"启动");
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
            self.infoLabel.text = localize(@"ame369.common.invalid_version", @"该版本无效");
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

    self.cardBody.accessibilityLabel = [NSString stringWithFormat:localize(@"ame369.common.instance_a11y_fmt", @"实例 %@，%@"),
                                        profileName, isSelected ? localize(@"ame369.home.current_instance", @"当前实例") : localize(@"ame369.home.tap_to_select", @"点按选用")];
    self.playButton.accessibilityLabel = [NSString stringWithFormat:localize(@"ame369.home.launch_fmt", @"启动 %@"),
                                          profileName];
}

@end

#pragma mark - 私有扩展

@interface ZL2HomeViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

- (void)restoreSidebarCardOrder;
- (void)saveSidebarCardOrder;

// 双栏根（Row：内容区 weight 7 + ActionMenu 3/10）
@property (nonatomic, strong) UIView *contentArea;
@property (nonatomic, strong) UICollectionView *gridView;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIView *actionMenu;
@property (nonatomic, strong) UIStackView *menuStack;
// ★ Task378/Task400：五入口快航瓦片（卡片化后驻右栏顶卡——用户规格第 3 条
//   「五个按钮在顶上」；一行×5 fillEqually，图标 27.5）
@property (nonatomic, strong) UIView *quickNavCard;
@property (nonatomic, strong) UIStackView *quickNavWrap;
// ★ Task400/Task401：右栏卡片化——中段滚动区（瓦片/账户滚轮/版本滚轮三卡，
//   总高超出屏高时滚动）+ 启动组卡钉底永可见；★ Task401 面板灰棱视图
//   （原右边栏整块灰面板还原体：drawRect 画灰棱 + even-odd 排除四卡窗 =
//   卡窗直透启动器背景，见类注释）
@property (nonatomic, strong) UIScrollView *menuScrollView;
@property (nonatomic, strong) Ame401PanelHolesView *panelBackdrop;
@property (nonatomic, strong) UIView *launchCard;
@property (nonatomic, strong) UIStackView *launchStack;
// 停靠边约束组（★Task404 换边恢复：左右两套挂接整组替换，重建时先卸后立）
@property (nonatomic, weak) UIView *draggedSidebarCard;
@property (nonatomic, strong, nullable) NSArray<NSLayoutConstraint *> *ame_sideConstraints;
// 当前停靠边（YES = 右侧；长按右栏菜单切换 + NSUserDefaults 持久化，★Task404 恢复）
@property (nonatomic, assign) BOOL ame_menuOnRight;
// 停靠边提示（★Task404 恢复：73c10b7 退役后 b78a16c 摘除的「长按菜单可切换停靠边」，随功能一并回滚）
@property (nonatomic, strong) UILabel *menuHintLabel;
// ★Task406 停靠镜像（第14轮规格「切换停靠边之后转盘和按钮是不是要镜像」）：
// 面板停靠左 = 卡尾四钮换钉 + 启动钮/插件 chip 内容组反排 + 版本滚轮条目镜像重建。
// 原钉四约束持引用，换边时整组卸/立（防新旧钉对峙互破）。
@property (nonatomic, strong, nullable) NSLayoutConstraint *ame_pinManageLeading;    // 管理钮贴左原钉
@property (nonatomic, strong, nullable) NSLayoutConstraint *ame_pinDeleteTrailing;   // 删除钮贴右原钉
@property (nonatomic, strong, nullable) NSLayoutConstraint *ame_pinSettingsTrailing; // 齿轮贴右原钉
@property (nonatomic, strong, nullable) NSLayoutConstraint *ame_pinRefreshChain;     // 刷新↔齿轮链条原钉
@property (nonatomic, strong, nullable) NSLayoutConstraint *ame_pinFooterChain;      // ★Task409 管理↔删除相邻链原钉（镜像面必卸，见 ame_applyPanelMirror）
@property (nonatomic, strong, nullable) NSArray<NSLayoutConstraint *> *ame_mirrorConstraints; // 当前镜像钉组
@property (nonatomic, assign) BOOL ame_panelMirrorLeft;        // 当前镜像态（幂等闸）
@property (nonatomic, strong, nullable) UIStackView *ame_launchContentStack;   // 启动钮图标+文案组
@property (nonatomic, strong, nullable) UIStackView *ame_pluginContentStack;   // 插件 chip 图标+文案组
@property (nonatomic, assign) BOOL ame_launchContentReversed;
@property (nonatomic, assign) BOOL ame_pluginContentReversed;
// ★Task405 退役：ame_embeddedContentConstraints 随提取机制一并拆除（右栏回归主页私有）
@property (nonatomic, assign) NSInteger lastColumnCount;
@property (nonatomic, assign) CGFloat lastGridWidth;   // ★ Task387：上次布局网格宽（宽度变化即失效重排）

// —— ★ Task400/Task401：ActionMenu 账户封面流卡（原头像+名称卡原地横排
//    五枚封面流——用户规格「账户是用原来的样式横排五个作列表选择」）——
@property (nonatomic, strong) UIView *accountCard;
@property (nonatomic, strong) AmeFlowSelectView *accountFlow;
@property (nonatomic, strong) ZL2HomeTapControl *accountManageButton;   // 卡尾账户管理小钮
@property (nonatomic, strong) ZL2HomeTapControl *accountDeleteButton;
@property (nonatomic, strong) UIActivityIndicatorView *accountSpinner; // 选中链忙态占位
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *ame400_accountList;   // 账户数据源（accounts 目录扫描）
@property (nonatomic, copy, nullable) NSArray<NSString *> *ame400_accountKeys;      // 上轮条目键序（数据未变则免重建防吸附回跳）

// —— ★ Task400/Task401：ActionMenu 版本封面流卡（原地竖排滚轮，占五个正常
//    实例版本信息高度——用户规格「实例版本也一样改」）——
@property (nonatomic, strong) UIView *versionCard;
@property (nonatomic, strong) AmeFlowSelectView *versionFlow;
@property (nonatomic, strong) ZL2HomeTapControl *versionRefreshButton;  // 卡尾刷新小钮
@property (nonatomic, strong) ZL2HomeTapControl *versionSettingsButton; // 卡尾齿轮小钮
@property (nonatomic, copy, nullable) NSArray<NSString *> *ame400_versionRowNames;  // 上轮行名序（数据未变则免重建防吸附回跳）

// —— ActionMenu：大启动钮 + 状态行 ——
@property (nonatomic, strong) UIControl *launchButton;
@property (nonatomic, strong) UIImageView *launchIconView;
@property (nonatomic, strong) UILabel *launchButtonLabel;
@property (nonatomic, strong) UILabel *launchStatusLabel;  // KVO 百分比行（下载态可见）
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
    // ★ Task400：ZL2HomeShowVersionPicker 总线入口随弹层退役（版本滚轮
    //   原地驻右栏，无呈现/收起时序）

    // 长按菜单卡 = 切换 ActionMenu 停靠边（ZL2 ActionMenuDrag 简化等价；
    // ★Task404 恢复；★Task408 再装——3dc220d「重写主页右侧四卡栏」曾随重写
    // 拆除本手势并把停靠边改死右侧，用户第 16 轮复诉「停靠边也无法调节」。
    // 面板任意处长按 0.5s = 换边；排序长按已同轮退役（手势冲突，见 C 线注）。
    UILongPressGestureRecognizer *menuLongPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(ame_handleMenuLongPress:)];
    menuLongPress.minimumPressDuration = 0.5;
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
    // ★ Task401：面板卡窗随布局实时重抠（旋转/换边/滚轮重建后窗口位移动）
    [self ame_refreshPanelMask];
    // ★ Task401 r5 收敛补触发：r4 smoke 实锤启动窗洞比卡矮 ~26pt（绘制期
    //   取帧早于栈内 intrinsic 收敛，尾帧后无重绘触发）——布局事务提交后
    //   异步补两跳重绘，取帧必为收敛终值
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.panelBackdrop setNeedsDisplay];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.panelBackdrop setNeedsDisplay];
        });
    });
    // ★ Task387：卡片自适应根修——原实现仅在列数（2/3）变化时失效布局，
    //   右栏/侧栏几何变化（折叠侧边栏、窗口缩放、旋转）导致的同列数宽度
    //   变化全部漏掉：sizeForItem 持旧宽算卡宽，流式布局把余量聚中 = 两列
    //   卡中间大空档（IMG_0558 实锤）。本轮改为宽度变化即失效重排，
    //   卡宽恒 = (网格宽 − 边距 − 间距×(列数−1)) / 列数，吃满可用宽。
    CGFloat ame387_width = self.gridView.bounds.size.width;
    NSInteger columns = [self ame_columnsForWidth:ame387_width];
    BOOL ame387_widthMoved = (fabs(ame387_width - self.lastGridWidth) > 0.5);
    if (columns != self.lastColumnCount || ame387_widthMoved) {
        self.lastColumnCount = columns;
        self.lastGridWidth = ame387_width;
        [self.gridView.collectionViewLayout invalidateLayout];
    }
}

#pragma mark - ★ Task401 面板卡窗几何（灰棱视图喂矩形）

// 卡窗几何重喂：四卡窗（五瓦片/账户滚轮/版本滚轮/启动组）换算到面板坐标
//（滚动位相实时）+ 滚动区裁剪相交，交 Ame401PanelHolesView 重绘（仅变化
// 才重画）。必须在主线程且有尺寸后调用（viewDidLayoutSubviews /
// scrollViewDidScroll 双驱动保证）。
- (void)ame_refreshPanelMask {
    CGSize ame401_size = self.actionMenu.bounds.size;
    if (ame401_size.width < 1.0 || ame401_size.height < 1.0) return;

    CGRect ame401_scrollFrame = [self.menuScrollView convertRect:self.menuScrollView.bounds
                                                          toView:self.actionMenu];
    NSMutableArray<NSValue *> *ame401_rects = [NSMutableArray array];
    NSArray<UIView *> *ame401_cards = @[self.quickNavCard, self.accountCard,
                                        self.versionCard, self.launchCard];
    for (UIView *ame401_card in ame401_cards) {
        if (ame401_card == nil || ame401_card.hidden) continue;
        CGRect ame401_r = [ame401_card convertRect:ame401_card.bounds
                                            toView:self.panelBackdrop];
        if (ame401_r.size.width < 1.0 || ame401_r.size.height < 1.0) continue;
        // 卡窗与滚动区裁剪相交：滚动出视口的卡不越权吃掉面板边缘灰边
        //（启动组卡钉底在滚动区外，不相交）
        if (ame401_card != self.launchCard) {
            CGRect ame401_clipped = CGRectIntersection(ame401_r, ame401_scrollFrame);
            if (CGRectIsNull(ame401_clipped)) continue;
            ame401_r = ame401_clipped;
        }
        [ame401_rects addObject:[NSValue valueWithCGRect:ame401_r]];
    }
    // r4：喂矩形链路退役（两轮 CI smoke 实锤洞恒空）——绘制期自取帧，
    // 宿主只负责触发重绘（布局/滚动/滚动位相变化）
    [self.panelBackdrop setNeedsDisplay];
}

// ★ Task401：中段滚动时卡窗位相连续变 → 逐帧重抠（网格滚动同样回调本方法，
// 以 scrollView 身份分流）
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.menuScrollView) {
        [self ame_refreshPanelMask];
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

/// ActionMenu 竖排（★ Task401 面板还原+卡窗透明——用户规格 2026-11-04：
///   「保留原来的右边栏，每一个卡片的颜色是透明（透明到启动器背景，
///   例如背景是白色，右侧栏是灰色，那么透明后就应该是白色）」）：
///   - 整块灰面板还原（panelBackdrop：surfaceContainer + radiusXL，
///     Task392 原样口径），不拆除；
///   - 四张卡区（五瓦片/账户横排滚轮/版本竖排滚轮/启动组）在面板上
///     抠成透明窗（layer.mask even-odd 挖洞）：卡窗处直透启动器背景
///     （背景白→卡窗即白），卡窗圆角 = 右侧栏圆角 radiusXL；
///   - 卡间间隙与面板四周留白同值 8pt（= 栏距屏边距离，用户规格
///     「每个卡片中间都要留点间隙（右侧栏距离屏幕边缘的距离）」）；
///   - 面板随滚动/布局实时重抠（scrollViewDidScroll + layoutSubviews）；
///     ① 五瓦片卡窗（驻顶——用户规格「五个按钮在顶上」）
///     ② 账户横排滚轮卡窗（原头像+名称样式横排五枚，水平拖动选择）
///     ③ 版本竖排滚轮卡窗（占五个正常实例版本信息高度）
///     ④ 启动组卡窗（状态行/大启动钮/插件 chip，钉底永可见）
- (void)ame_buildActionMenu {
    _actionMenu = [[UIView alloc] init];
    // ★ Task401：栏容器透明（灰面板下沉到背板，卡窗挖洞透启动器背景）
    _actionMenu.backgroundColor = [UIColor clearColor];
    _actionMenu.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_actionMenu];

    // —— 面板灰棱视图（原右边栏整块灰面板还原体；drawRect 画灰棱，
//      四卡窗 even-odd 排除 = 直透启动器背景）——
    _panelBackdrop = [[Ame401PanelHolesView alloc] init];
    _panelBackdrop.translatesAutoresizingMaskIntoConstraints = NO;
    _panelBackdrop.hidden = YES;
    [_actionMenu addSubview:_panelBackdrop];

    // —— ④ 启动组卡窗（钉底；先建，滚动区底缘锚它；卡底透明 = 挖洞）——
    _launchCard = [[UIView alloc] init];
    _launchCard.backgroundColor = [ZL2Theme surfaceContainer];
    _launchCard.layer.cornerRadius = [ZL2Theme radiusXL];
    _launchCard.layer.masksToBounds = YES;
    _launchCard.accessibilityIdentifier = @"zl2.sidebar.launch";
    _launchCard.translatesAutoresizingMaskIntoConstraints = NO;
    [_actionMenu addSubview:_launchCard];

    _launchStack = [[UIStackView alloc] init];
    _launchStack.axis = UILayoutConstraintAxisVertical;
    _launchStack.alignment = UIStackViewAlignmentFill;
    _launchStack.spacing = ZL2HomeCardPadding;
    _launchStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_launchCard addSubview:_launchStack];

    // —— 中段滚动区（瓦片/账户滚轮/版本滚轮三卡窗；总高超出时滚动；
    //    ★ Task401 四边内缩 8pt = 面板四周留灰边与卡间隙同律）——
    _menuScrollView = [[UIScrollView alloc] init];
    _menuScrollView.backgroundColor = [UIColor clearColor];
    _menuScrollView.showsVerticalScrollIndicator = NO;
    _menuScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _menuScrollView.delegate = self;   // ★ Task401：滚动时实时重抠面板卡窗
    [_actionMenu addSubview:_menuScrollView];

    _menuStack = [[UIStackView alloc] init];
    _menuStack.axis = UILayoutConstraintAxisVertical;
    _menuStack.alignment = UIStackViewAlignmentFill;
    _menuStack.spacing = ZL2HomeCardGap;   // ★ Task400：卡间间隙 = 栏距屏边 8pt（用户规格）
    _menuStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_menuScrollView addSubview:_menuStack];

    __weak ZL2HomeViewController *weakSelf = self;

    // —— ① 五瓦片卡窗（★ Task400 驻顶：用户规格「五个按钮在顶上」；
    //      ★ Task401 卡底透明 = 面板挖洞）——
    _quickNavCard = [[UIView alloc] init];
    _quickNavCard.backgroundColor = [ZL2Theme surfaceContainer];
    _quickNavCard.layer.cornerRadius = [ZL2Theme radiusXL];
    _quickNavCard.layer.masksToBounds = YES;
    _quickNavCard.translatesAutoresizingMaskIntoConstraints = NO;
    _quickNavCard.isAccessibilityElement = NO;
    _quickNavCard.accessibilityIdentifier = @"zl2.sidebar.menu";
    [_menuStack addArrangedSubview:_quickNavCard];
    [self ame378_buildQuickNav];
    // ★ Task402：五瓦片卡退役；★ Task408 无条件化——壳左栏/fui 双导航常在，
    //   主页瓦片 = 第二重复切换面（第 16 轮复诉「又有2个重复的切换标签页区域」）。
    // ★ Task410 条件化回归（第 18 轮复诉「md3界面zl2的右上角切换标签页区域
    //   不见了」）：Task378 顶栏退役 + Task408b 无条件退役后，topbar(bare/MD3)
    //   骨架全屏零导航实体（3dc220d 注释「右上角快捷入口已移除；主页右栏是
    //   五个入口的唯一位置」的唯一位置也被 408b 摘除）= MD3 模式无任何页面
    //   切换入口。本卡回归为 bare 骨架的唯一切换区（面板首卡 = 停靠右时屏幕
    //   右上角）；navigationview(fui) 骨架壳左栏窗格常在，本卡维持退役防双导
    //   航重复（第 16 轮口径不变）。hidden → arranged 塌缩零占位，卡体与构建
    //   器保留（fui 向导锚 zl2_shell_topbar_rail 挂瓦片行 + ame378 C1/C4 门禁
    //   锚在位），面板卡窗经 ame_refreshPanelMask 内建 hidden 跳过自动重抠。
    _quickNavCard.hidden = [[ZL2Theme ame347_shellLayout]
                            isEqualToString:@"navigationview"];

    // —— ② 账户横排封面流卡窗（原头像+名称样式横排五枚，水平拖动选择；
    //      ★ Task401 用户规格「账户是用原来的样式横排五个作列表选择」）——
    _accountCard = [[UIView alloc] init];
    _accountCard.backgroundColor = [ZL2Theme surfaceContainer];
    _accountCard.layer.cornerRadius = [ZL2Theme radiusXL];
    _accountCard.layer.masksToBounds = YES;
    _accountCard.translatesAutoresizingMaskIntoConstraints = NO;
    _accountCard.isAccessibilityElement = NO;   // 滚轮（adjustable）+ 卡尾钮各自可达
    _accountCard.accessibilityIdentifier = @"zl2.sidebar.accounts";
    [_menuStack addArrangedSubview:_accountCard];

    _accountFlow = [[AmeFlowSelectView alloc] init];
    _accountFlow.axis = AmeFlowSelectAxisHorizontal;   // ★ Task401：横排（水平拖动选择）
    _accountFlow.interItemGap = ZL2HomeAccountFlowGapH;
    _accountFlow.accessibilityLabel = localize(@"login.option.select", @"选择账户");
    _accountFlow.translatesAutoresizingMaskIntoConstraints = NO;
    [_accountCard addSubview:_accountFlow];
    // ★Task409 无缝循环槽位复制工厂：小集合（如双账号）相位接缝原在窗内
    // 可见（|d|=1 < 窗半宽 1.55 = 「账号转盘没有无限衔接」实体）；组件自动
    // 复制槽位推接缝出窗，副本由此按逻辑下标现建像素同款条目（weakSelf 防
    // 组件→工厂→宿主保留环）。
    _accountFlow.ame_copyFactory = ^UIView *(NSUInteger ame409_idx) {
        if (!weakSelf) return nil;
        if (weakSelf.ame400_accountList.count == 0) return [weakSelf ame400_signedOutFlowItem];
        return [weakSelf ame400_accountFlowItemForData:
                    weakSelf.ame400_accountList[ame409_idx % weakSelf.ame400_accountList.count]];
    };

    // 卡尾动作行：账户管理小钮（原账号卡点击语义收口于此）+ 选中链忙态 spinner
    _accountManageButton = [self ame_accountActionButtonWithSymbol:@"person.badge.plus"
                                                          fallback:@"person.crop.circle.badge.plus"
                                                             title:@"添加账户"];
    _accountManageButton.ame_action = ^{
        [weakSelf ame_requestAccountAction:@"ZL2AccountsRequestAdd"];
    };
    [_accountCard addSubview:_accountManageButton];
    _accountDeleteButton = [self ame_accountActionButtonWithSymbol:@"person.crop.circle.badge.minus"
                                                          fallback:@"trash"
                                                             title:@"删除账户"];
    _accountDeleteButton.ame_action = ^{
        [weakSelf ame_requestAccountAction:@"ZL2AccountsRequestDeleteCurrent"];
    };
    [_accountCard addSubview:_accountDeleteButton];

    _accountSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _accountSpinner.hidesWhenStopped = YES;
    _accountSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [_accountCard addSubview:_accountSpinner];

    // 吸附落定（下标变化）→ 原选中链（Task128 会话校验/第三方 stale 降级/
    // 微软本地 refreshToken——账户页 selectAccountAtIndex 同款全链）
    _accountFlow.onSettle = ^(NSInteger ame400_index) {
        if (ame400_index >= 0) {
            [weakSelf ame400_selectAccountAtIndex:(NSUInteger)ame400_index];
        }
    };

    // —— ③ 版本竖排封面流卡窗（原地滚轮；条目 = 加载器图标 40 + 实例名/
    //      信息行；高度 = 五个正常实例版本信息行（用户规格「占用的比例算
    //      五个正常的实例版本信息高度」）；吸附落定即选用）——
    _versionCard = [[UIView alloc] init];
    _versionCard.backgroundColor = [ZL2Theme surfaceContainer];
    _versionCard.layer.cornerRadius = [ZL2Theme radiusXL];
    _versionCard.layer.masksToBounds = YES;
    _versionCard.translatesAutoresizingMaskIntoConstraints = NO;
    _versionCard.isAccessibilityElement = NO;
    _versionCard.accessibilityIdentifier = @"zl2.sidebar.instances";
    [_menuStack addArrangedSubview:_versionCard];
    [_menuStack addArrangedSubview:_launchCard];
    // ★Task408 四卡排序长按退役：与面板换边长按同一手势面（排序 0.45s 先行
    // 劫持 = 用户第 16 轮复诉「停靠边也无法调节」实体），换边以用户明示诉求
    // 优先；restoreSidebarCardOrder 保留（历史排序仍尊重）；重挂待专属编辑
    // 模式再议。
    [self restoreSidebarCardOrder];

    _versionFlow = [[AmeFlowSelectView alloc] init];
    _versionFlow.axis = AmeFlowSelectAxisVertical;   // ★ Task401：竖排（与横排同一套物理）
    _versionFlow.itemHeight = ZL2HomeVersionFlowItemH;
    _versionFlow.interItemGap = ZL2HomeFlowItemGap;
    _versionFlow.accessibilityLabel = localize(@"i18n_str_38", nil);   // 选择版本（四表既有键）
    _versionFlow.translatesAutoresizingMaskIntoConstraints = NO;
    [_versionCard addSubview:_versionFlow];
    // ★Task409 槽位复制工厂（同账户流：实例 ≤ 5 枚时竖排接缝 |d|≤2.5 落窗内）
    _versionFlow.ame_copyFactory = ^UIView *(NSUInteger ame409_idx) {
        if (!weakSelf) return nil;
        if (weakSelf.ame_rows.count == 0) return [weakSelf ame400_emptyVersionFlowItem];
        return [weakSelf ame400_versionFlowItemForRow:
                    weakSelf.ame_rows[ame409_idx % weakSelf.ame_rows.count]];
    };

    // 卡尾动作行：刷新（重拉注册表）+ 齿轮（版本管理页直达）——原版本卡
    // 内双小钮语义原样平移
    _versionRefreshButton = [self ame_iconButtonWithSymbol:@"arrow.clockwise"
                                                  fallback:@"sync"
                                                    a11y:localize(@"ame369.home.refresh_instances_a11y", @"刷新实例列表")];
    _versionRefreshButton.ame_action = ^{
        [weakSelf versionRefreshTapped];
    };
    [_versionCard addSubview:_versionRefreshButton];

    _versionSettingsButton = [self ame_iconButtonWithSymbol:@"gearshape"
                                                   fallback:@"gear"
                                                       a11y:localize(@"ame369.home.version_manager_a11y", @"版本管理")];
    _versionSettingsButton.ame_action = ^{
        [weakSelf versionSettingsTapped];
    };
    [_versionCard addSubview:_versionSettingsButton];

    // 吸附落定（下标变化）→ 选用该实例（版本页 ame_selectProfileNamed 同款链；
    // 原地滚轮无收起语义——Task393 弹层 0.35s 驻留收起随弹层一并退役）
    _versionFlow.onSettle = ^(NSInteger ame400_index) {
        if (ame400_index >= 0) {
            [weakSelf ame393_selectProfileAtIndex:(NSUInteger)ame400_index];
        }
    };

    // —— 下载状态行（KVO 百分比态；非下载态隐藏塌缩）——
    _launchStatusLabel = [[UILabel alloc] init];
    _launchStatusLabel.font = [ZL2Theme fontLabelMedium];
    _launchStatusLabel.textColor = [ZL2Theme onSurfaceVariant];
    _launchStatusLabel.textAlignment = NSTextAlignmentCenter;
    _launchStatusLabel.numberOfLines = 1;
    _launchStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _launchStatusLabel.isAccessibilityElement = YES;
    _launchStatusLabel.hidden = YES;
    [_launchStack addArrangedSubview:_launchStatusLabel];

    // —— 大启动钮（ScalingActionButton 语义：primary 底 / onPrimary 字 /
    // 28 圆角 / 高 48 / 播放图标 + 三态文案；"zl2_home_launch" 为向导锚点）——
    _launchButton = [[UIControl alloc] init];
    _launchButton.accessibilityIdentifier = @"zl2_home_launch";
    _launchButton.layer.cornerRadius = [ZL2Theme radiusXL];   // 28（spec 定稿）
    _launchButton.translatesAutoresizingMaskIntoConstraints = NO;
    _launchButton.isAccessibilityElement = YES;
    [_launchButton addTarget:self
                      action:@selector(launchButtonTapped)
            forControlEvents:UIControlEventTouchUpInside];
    [_launchStack addArrangedSubview:_launchButton];

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
    _ame_launchContentStack = launchContent;   // ★Task406 换边反排引用
    [_launchButton addSubview:launchContent];

    // —— 插件功能直达 chip（★ Task328：插件效果可见性第三刀；无贡献行时
    //    塌缩隐藏 = 零回归）——
    _pluginChipButton = [[UIControl alloc] init];
    _pluginChipButton.backgroundColor = [ZL2Theme surfaceContainerHigh];
    _pluginChipButton.layer.cornerRadius = [ZL2Theme radiusXL];
    _pluginChipButton.translatesAutoresizingMaskIntoConstraints = NO;
    _pluginChipButton.isAccessibilityElement = YES;
    _pluginChipButton.accessibilityTraits = UIAccessibilityTraitButton;
    _pluginChipButton.accessibilityIdentifier = @"zl2_home_plugin_chip";
    _pluginChipButton.hidden = YES;   // 初始塌缩，viewWillAppear 计数刷新后放行（防首建闪现）
    [_pluginChipButton addTarget:self
                          action:@selector(ame328_pluginChipTapped)
                forControlEvents:UIControlEventTouchUpInside];
    [_launchStack addArrangedSubview:_pluginChipButton];

    // 停靠边提示（★Task404 恢复：功能回滚则提示语同步回滚——b78a16c 曾称其
    // 「谎言提示」只因当时切换代码已先行被 73c10b7 摘除，功能恢复后语句为真）
    _menuHintLabel = [[UILabel alloc] init];
    // ★Task408 回滚：3dc220d 曾改文案「长按卡片空白处调整顺序」并配排序长按，
    // 与换边手势同面冲突（用户第 16 轮复诉「停靠边也无法调节」）；回原键原文案。
    _menuHintLabel.text = localize(@"ame369.home.menu_dock_hint", @"长按菜单可切换停靠边");
    _menuHintLabel.font = [ZL2Theme fontLabelMedium];
    _menuHintLabel.textColor = [ZL2Theme onSurfaceVariant];
    _menuHintLabel.textAlignment = NSTextAlignmentCenter;
    _menuHintLabel.numberOfLines = 1;
    _menuHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_launchStack addArrangedSubview:_menuHintLabel];

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
    _ame_pluginContentStack = pluginChipContent;   // ★Task406 换边反排引用
    [_pluginChipButton addSubview:pluginChipContent];

    [_pluginChipButton.heightAnchor constraintEqualToConstant:34].active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [pluginChipContent.centerXAnchor constraintEqualToAnchor:_pluginChipButton.centerXAnchor],
        [pluginChipContent.centerYAnchor constraintEqualToAnchor:_pluginChipButton.centerYAnchor],
        [pluginChipContent.leadingAnchor constraintGreaterThanOrEqualToAnchor:_pluginChipButton.leadingAnchor constant:12],
        [_pluginChipButton.trailingAnchor constraintGreaterThanOrEqualToAnchor:pluginChipContent.trailingAnchor constant:12],
    ]];

    // ★Task406 卡尾四钮原钉持引用（ame_applyPanelMirror 换边时整组卸/立）；
    // ★Task409 第五钉：管理↔删除相邻链——左停靠镜像把两钮分钉卡两侧后
    // 此链仍要求相邻 = 超定无解（卡宽=18pt 才可满足）→ AutoLayout 随机
    // 断钉 = 「镜像显示有问题」实体（管理钮消失/错位），随镜像面同卸同立。
    _ame_pinManageLeading = [_accountManageButton.leadingAnchor constraintEqualToAnchor:_accountCard.leadingAnchor constant:12];
    _ame_pinDeleteTrailing = [_accountDeleteButton.trailingAnchor constraintEqualToAnchor:_accountCard.trailingAnchor constant:-12];
    _ame_pinSettingsTrailing = [_versionSettingsButton.trailingAnchor constraintEqualToAnchor:_versionCard.trailingAnchor constant:-12];
    _ame_pinRefreshChain = [_versionRefreshButton.trailingAnchor constraintEqualToAnchor:_versionSettingsButton.leadingAnchor constant:-4];
    _ame_pinFooterChain = [_accountManageButton.trailingAnchor constraintEqualToAnchor:_accountDeleteButton.leadingAnchor constant:-6];

    [NSLayoutConstraint activateConstraints:@[
        // ★ Task401 面板背板：钉栏容器四边（面板 = 原右边栏整块灰面板）
        [_panelBackdrop.topAnchor constraintEqualToAnchor:_actionMenu.topAnchor],
        [_panelBackdrop.bottomAnchor constraintEqualToAnchor:_actionMenu.bottomAnchor],
        [_panelBackdrop.leadingAnchor constraintEqualToAnchor:_actionMenu.leadingAnchor],
        [_panelBackdrop.trailingAnchor constraintEqualToAnchor:_actionMenu.trailingAnchor],

        // 中段滚动区：四边内缩 8pt（面板四周留灰边 = 卡间隙同律，用户规格
        // 「每个卡片中间都要留点间隙（右侧栏距离屏幕边缘的距离）」）；
        // 底缘锚启动卡顶（- 卡间隙）
        [_menuScrollView.topAnchor constraintEqualToAnchor:_actionMenu.topAnchor constant:ZL2HomeCardGap],
        [_menuScrollView.leadingAnchor constraintEqualToAnchor:_actionMenu.leadingAnchor constant:ZL2HomeCardGap],
        [_menuScrollView.trailingAnchor constraintEqualToAnchor:_actionMenu.trailingAnchor constant:-ZL2HomeCardGap],
        [_menuScrollView.bottomAnchor constraintEqualToAnchor:_actionMenu.bottomAnchor constant:-ZL2HomeCardGap],

        // 滚动内容：三边钉 contentLayoutGuide + 底缘 ≥ 内容底（短内容不滚动），
        // 宽 = 视口宽（fill）
        [_menuStack.topAnchor constraintEqualToAnchor:_menuScrollView.contentLayoutGuide.topAnchor],
        [_menuStack.leadingAnchor constraintEqualToAnchor:_menuScrollView.contentLayoutGuide.leadingAnchor],
        [_menuStack.trailingAnchor constraintEqualToAnchor:_menuScrollView.contentLayoutGuide.trailingAnchor],
        [_menuScrollView.contentLayoutGuide.bottomAnchor constraintEqualToAnchor:_menuStack.bottomAnchor],
        [_menuStack.widthAnchor constraintEqualToAnchor:_menuScrollView.frameLayoutGuide.widthAnchor],

        // 启动卡内布局（四边 8pt 同律）
        [_launchStack.topAnchor constraintEqualToAnchor:_launchCard.topAnchor constant:ZL2HomeCardPadding],
        [_launchStack.bottomAnchor constraintEqualToAnchor:_launchCard.bottomAnchor constant:-ZL2HomeCardPadding],
        [_launchStack.leadingAnchor constraintEqualToAnchor:_launchCard.leadingAnchor constant:ZL2HomeCardPadding],
        [_launchStack.trailingAnchor constraintEqualToAnchor:_launchCard.trailingAnchor constant:-ZL2HomeCardPadding],

        // ① 瓦片卡内布局（瓦片行四边 8pt）
        [_quickNavWrap.topAnchor constraintEqualToAnchor:_quickNavCard.topAnchor constant:ZL2HomeCardPadding],
        [_quickNavWrap.bottomAnchor constraintEqualToAnchor:_quickNavCard.bottomAnchor constant:-ZL2HomeCardPadding],
        [_quickNavWrap.leadingAnchor constraintEqualToAnchor:_quickNavCard.leadingAnchor constant:ZL2HomeCardPadding],
        [_quickNavWrap.trailingAnchor constraintEqualToAnchor:_quickNavCard.trailingAnchor constant:-ZL2HomeCardPadding],

        // ② 账户卡内布局：横排滚轮（高 = 视口定高 88；宽吃满卡内）+ 卡尾动作行
        [_accountFlow.topAnchor constraintEqualToAnchor:_accountCard.topAnchor constant:ZL2HomeCardPadding],
        [_accountFlow.leadingAnchor constraintEqualToAnchor:_accountCard.leadingAnchor constant:ZL2HomeCardPadding],
        [_accountFlow.trailingAnchor constraintEqualToAnchor:_accountCard.trailingAnchor constant:-ZL2HomeCardPadding],
        [_accountFlow.heightAnchor constraintEqualToConstant:ZL2HomeAccountWheelH],
        [_accountManageButton.topAnchor constraintEqualToAnchor:_accountFlow.bottomAnchor constant:6],
        _ame_pinManageLeading,   // ★Task406 管理钮贴左原钉（换边镜像可卸）
        [_accountManageButton.heightAnchor constraintEqualToConstant:ZL2HomeCardFooterHeight],
        [_accountManageButton.bottomAnchor constraintEqualToAnchor:_accountCard.bottomAnchor constant:-4],
        _ame_pinDeleteTrailing,  // ★Task406 删除钮贴右原钉（换边镜像可卸）
        [_accountManageButton.widthAnchor constraintEqualToAnchor:_accountDeleteButton.widthAnchor],
        _ame_pinFooterChain,   // ★Task409 相邻链原钉化（换边镜像可卸，防超定断钉）
        [_accountDeleteButton.centerYAnchor constraintEqualToAnchor:_accountManageButton.centerYAnchor],
        [_accountDeleteButton.heightAnchor constraintEqualToConstant:ZL2HomeCardFooterHeight],
        [_accountSpinner.centerXAnchor constraintEqualToAnchor:_accountCard.centerXAnchor],
        [_accountSpinner.centerYAnchor constraintEqualToAnchor:_accountManageButton.centerYAnchor],

        // ③ 版本卡内布局：竖排滚轮（高 = 五个正常实例版本信息行）+ 卡尾动作行
        [_versionFlow.topAnchor constraintEqualToAnchor:_versionCard.topAnchor constant:ZL2HomeCardPadding],
        [_versionFlow.leadingAnchor constraintEqualToAnchor:_versionCard.leadingAnchor constant:ZL2HomeCardPadding],
        [_versionFlow.trailingAnchor constraintEqualToAnchor:_versionCard.trailingAnchor constant:-ZL2HomeCardPadding],
        [_versionFlow.heightAnchor constraintEqualToConstant:_versionFlow.viewportHeight],
        [_versionSettingsButton.topAnchor constraintEqualToAnchor:_versionFlow.bottomAnchor constant:6],
        _ame_pinSettingsTrailing,   // ★Task406 齿轮贴右原钉（换边镜像可卸）
        [_versionSettingsButton.widthAnchor constraintEqualToConstant:ZL2HomeCardFooterHeight],
        [_versionSettingsButton.heightAnchor constraintEqualToConstant:ZL2HomeCardFooterHeight],
        [_versionSettingsButton.bottomAnchor constraintEqualToAnchor:_versionCard.bottomAnchor constant:-4],
        _ame_pinRefreshChain,    // ★Task406 刷新↔齿轮链条原钉（换边镜像可卸）
        [_versionRefreshButton.centerYAnchor constraintEqualToAnchor:_versionSettingsButton.centerYAnchor],
        [_versionRefreshButton.widthAnchor constraintEqualToConstant:ZL2HomeCardFooterHeight],
        [_versionRefreshButton.heightAnchor constraintEqualToConstant:ZL2HomeCardFooterHeight],

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
    ]];

    // ★ Task401 r4：面板灰棱视图挂四卡窗宿主（drawRect 绘制期自取帧）
    [_panelBackdrop ame401_setHostCards:@[_quickNavCard, _accountCard, _versionCard, _launchCard]];
}

#pragma mark - ★ Task378 五入口快航瓦片（★ Task400 驻右栏顶卡：用户规格「五个按钮在顶上」）

/// 快航瓦片区（★ Task392 单行×5：一行 文件/下载/设置/联机/AI，fillEqually
///   均分 + 6pt 等间距；★ Task400 入驻顶卡 quickNavCard——surfaceContainer/
///   radiusXL 卡片语言由卡承担，瓦片本体透明）。对称留白纪律（用户规格
///   「每个按钮与就近右侧栏边界的距离应保持一致」）：行内 fillEqually
///   均分 + 6pt 等间距 + 卡内 8pt 对称内边距 → 每枚瓦片到就近边界距离
///   一致。着色走 ZL2Theme 动态令牌（系统深浅自适应），无写死颜色。
- (void)ame378_buildQuickNav {
    __weak typeof(self) weakSelf = self;

    // 图标沿用顶栏 RailItem×5 原符号（认知连续）；标题复用四表既有键
    // （ame369.shell.tab.* / ame369.common.multiplayer / ame192.ai.title，零新增 i18n）
    ZL2HomeTapControl *filesTile =
        [self ame378_quickNavTileWithSymbol:@"folder.fill"
                                   fallback:@"folder"
                                      title:localize(@"ame369.shell.tab.files", @"文件")
                                     action:^{
            [weakSelf ame378_openFileManagerSheet];
        }];
    ZL2HomeTapControl *downloadsTile =
        [self ame378_quickNavTileWithSymbol:@"arrow.down.circle.fill"
                                   fallback:@"arrow.down.circle"
                                      title:localize(@"ame369.shell.tab.downloads", @"下载")
                                     action:^{
            [weakSelf ame378_navigateToPage:1];
        }];
    ZL2HomeTapControl *settingsTile =
        [self ame378_quickNavTileWithSymbol:@"gearshape.fill"
                                   fallback:@"gearshape"
                                      title:localize(@"ame369.shell.tab.settings", @"设置")
                                     action:^{
            [weakSelf ame378_navigateToPage:4];
        }];
    ZL2HomeTapControl *multiplayerTile =
        [self ame378_quickNavTileWithSymbol:@"person.2.fill"
                                   fallback:@"person.2"
                                      title:localize(@"ame369.common.multiplayer", @"多人联机")
                                     action:^{
            [weakSelf ame378_navigateToPage:5];
        }];
    NSString *ame378_aiTitle = localize(@"ame192.ai.title", nil);
    if (ame378_aiTitle.length == 0) ame378_aiTitle = @"AI";
    ZL2HomeTapControl *aiTile =
        [self ame378_quickNavTileWithSymbol:@"sparkles"
                                   fallback:@"sparkles"
                                      title:ame378_aiTitle
                                     action:^{
            [weakSelf ame378_navigateToPage:6];
        }];

    // ★ Task392：五瓦片单行化（用户规格“改成一行的”）——原两行 3+2 拆包退役，
    //   五瓦片直接一行 fillEqually 均分 + 6pt 等间距（对称留白纪律不变：
    //   menuStack 左右对称 10pt 内边距同值沿用）。释放的一行纵向空间由
    //   弹性占位自然吸收（启动组仍钉列底，“其余 UI 相应改变”零结构变动）
    _quickNavWrap = [[UIStackView alloc] initWithArrangedSubviews:@[filesTile, downloadsTile, settingsTile, multiplayerTile, aiTile]];
    _quickNavWrap.axis = UILayoutConstraintAxisHorizontal;
    _quickNavWrap.alignment = UIStackViewAlignmentCenter;
    _quickNavWrap.distribution = UIStackViewDistributionFillEqually;
    _quickNavWrap.spacing = ZL2HomeQuickNavGap;
    _quickNavWrap.translatesAutoresizingMaskIntoConstraints = NO;
    // 向导引导锚点：沿用原顶栏右簇 id（WelcomeViewController coach mark
    // ame111_findById 按此 id 探测，顶栏退役后锚定本瓦片区，引导语义不变）
    _quickNavWrap.accessibilityIdentifier = @"zl2_shell_topbar_rail";
    // ★ Task400：瓦片行入驻顶卡（卡片化重构——quickNavCard 承担卡片语言，
    //   瓦片本体透明；约束由 ame_buildActionMenu 统一挂）
    [_quickNavCard addSubview:_quickNavWrap];
}

/// 快航瓦片工厂：图标（★ Task392：27.5pt = 55÷2，用户规格“缩小两倍”）+ 标签
/// 竖排居中。窄屏五行等分后长标签（“多人联机”）按比例缩排优先于截断
/// （“其余 UI 相应改变”）。点击高亮语义由 ZL2HomeTapControl touchUpInside
/// 承担（与卡内小钮同源）。
- (ZL2HomeTapControl *)ame378_quickNavTileWithSymbol:(NSString *)symbol
                                            fallback:(NSString *)fallback
                                               title:(NSString *)title
                                              action:(void (^)(void))action {
    ZL2HomeTapControl *tile = [[ZL2HomeTapControl alloc] init];
    tile.backgroundColor = [UIColor clearColor];
    tile.layer.cornerRadius = [ZL2Theme radiusS];
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    tile.isAccessibilityElement = YES;
    tile.accessibilityTraits = UIAccessibilityTraitButton;
    tile.accessibilityLabel = title;

    UIImage *ame378_image = ZL2HomeSystemImage(symbol, fallback);
    if (ame378_image) ame378_image = [ame378_image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImageView *ame378_icon = [[UIImageView alloc] initWithImage:ame378_image];
    ame378_icon.tintColor = [ZL2Theme onSurface];            // 系统深浅自适应主色（标题级）
    ame378_icon.contentMode = UIViewContentModeScaleAspectFit;
    ame378_icon.translatesAutoresizingMaskIntoConstraints = NO;
    ame378_icon.userInteractionEnabled = NO;
    [tile addSubview:ame378_icon];

    UILabel *ame378_label = [[UILabel alloc] init];
    ame378_label.font = [ZL2Theme fontLabelMedium];
    ame378_label.textColor = [ZL2Theme onSurfaceVariant];    // 系统深浅自适应次色（简介级）
    ame378_label.text = title;
    ame378_label.numberOfLines = 1;
    ame378_label.lineBreakMode = NSLineBreakByTruncatingTail;
    ame378_label.textAlignment = NSTextAlignmentCenter;
    // ★ Task392：窄屏（iPhone 240pt 栏宽五行等分 ≈ 39pt/瓦）长标签缩排优先：
    //   0.7 比例下「多人联机」完整可读，不截断；iPad 栏宽（≥300pt）全尺寸。
    ame378_label.adjustsFontSizeToFitWidth = YES;
    ame378_label.minimumScaleFactor = 0.7;
    ame378_label.translatesAutoresizingMaskIntoConstraints = NO;
    ame378_label.userInteractionEnabled = NO;
    [tile addSubview:ame378_label];

    [NSLayoutConstraint activateConstraints:@[
        [tile.heightAnchor constraintEqualToConstant:ZL2HomeQuickNavTileHeight],
        [ame378_icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [ame378_icon.topAnchor constraintEqualToAnchor:tile.topAnchor constant:10],
        [ame378_icon.widthAnchor constraintEqualToConstant:ZL2HomeQuickNavIconSize],
        [ame378_icon.heightAnchor constraintEqualToConstant:ZL2HomeQuickNavIconSize],
        [ame378_label.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [ame378_label.topAnchor constraintEqualToAnchor:ame378_icon.bottomAnchor constant:2],
        [ame378_label.leadingAnchor constraintGreaterThanOrEqualToAnchor:tile.leadingAnchor constant:1],
        [ame378_label.trailingAnchor constraintLessThanOrEqualToAnchor:tile.trailingAnchor constant:-1],
    ]];

    tile.ame_action = action;
    return tile;
}

/// 瓦片切页：壳导航总线同口径（本页既有导航协议，页面间零直连）
- (void)ame378_navigateToPage:(NSInteger)index {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2ShellNavigate"
                                                        object:nil
                                                      userInfo:@{@"index": @(index)}];
}

/// 目录瓦片直达：壳通知接线（原顶栏文件夹项 ame_openFileManagerSheet 由壳
/// 统一承接——smoke 预览窄链接面零新增类依赖，Task378 r2）
- (void)ame378_openFileManagerSheet {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2ShellOpenFileManager"
                                                        object:nil];
}

/// 小图标钮工厂：32×32 / 18pt 模板图标（菜单卡内刷新/设置两钮共用）
- (ZL2HomeTapControl *)ame_iconButtonWithSymbol:(NSString *)symbol
                                       fallback:(NSString *)fallback
                                           a11y:(NSString *)a11y {
    ZL2HomeTapControl *button = [[ZL2HomeTapControl alloc] init];
    button.backgroundColor = [UIColor clearColor];
    button.layer.cornerRadius = [ZL2Theme radiusXL];
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

- (ZL2HomeTapControl *)ame_accountActionButtonWithSymbol:(NSString *)symbol
                                                 fallback:(NSString *)fallback
                                                    title:(NSString *)title {
    ZL2HomeTapControl *button = [[ZL2HomeTapControl alloc] init];
    button.backgroundColor = [ZL2Theme surfaceContainerHigh];
    button.layer.cornerRadius = [ZL2Theme radiusS];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.isAccessibilityElement = YES;
    button.accessibilityTraits = UIAccessibilityTraitButton;
    button.accessibilityLabel = title;

    UIImage *image = [ZL2HomeSizedImage(symbol, fallback, 14)
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImageView *icon = [[UIImageView alloc] initWithImage:image];
    icon.tintColor = [ZL2Theme onSurface];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [ZL2Theme fontLabelMedium];
    label.textColor = [ZL2Theme onSurface];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.75;

    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[icon, label]];
    content.axis = UILayoutConstraintAxisHorizontal;
    content.alignment = UIStackViewAlignmentCenter;
    content.spacing = 5;
    content.userInteractionEnabled = NO;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [button addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
        [content.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:button.leadingAnchor constant:6],
        [content.trailingAnchor constraintLessThanOrEqualToAnchor:button.trailingAnchor constant:-6],
        [icon.widthAnchor constraintEqualToConstant:14],
        [icon.heightAnchor constraintEqualToConstant:14],
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
    label.text = localize(@"ame369.common.no_versions", @"没有安装版本");
    label.font = [ZL2Theme fontBodyMedium];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.userInteractionEnabled = NO;

    ZL2HomeTapControl *downloadButton = [[ZL2HomeTapControl alloc] init];
    downloadButton.backgroundColor = [ZL2Theme primary];
    downloadButton.layer.cornerRadius = [ZL2Theme radiusXL];
    downloadButton.translatesAutoresizingMaskIntoConstraints = NO;
    downloadButton.isAccessibilityElement = YES;
    downloadButton.accessibilityTraits = UIAccessibilityTraitButton;

    UILabel *downloadLabel = [[UILabel alloc] init];
    downloadLabel.text = localize(@"ame369.home.go_download", @"去下载");
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

#pragma mark - 固定右栏

// ★Task405 退役：extractPersistentRightSidebar（0d97c34 提取机制）整块拆除。
// 提取会让 actionMenu 脱离主页层级：后续长按换边对 menu 与 self.view 重建的
// 双支线约束变为跨层级，与壳层 containerTrailing 冲突 = 换边 bug 实体；且常驻
// 使右栏在子页可见 = 切页不隐藏。退役后换边在主页内自治，约束链同层无冲突。

/// 恢复持久化停靠边（缺省 = 右侧；脏值回退默认。★Task404 恢复原实现；
/// ★Task408 再恢复——3dc220d「重写主页右侧四卡栏」曾改死右侧并清除持久化
/// 键，用户第 16 轮复诉「停靠边也无法调节」。同轮退役四卡排序长按：与换边
/// 长按同面冲突（排序 0.45s 先行劫持 = 换边实体不可达）；排序持久化读写
/// 保留（历史排序仍尊重），重挂待专属编辑模式再议）
- (void)ame_restoreMenuSide {
    NSString *side = [[NSUserDefaults standardUserDefaults] stringForKey:ZL2HomeMenuSideDefaultsKey];
    self.ame_menuOnRight = ![side isEqualToString:@"left"];
}

/// 长按菜单面板 = 切换停靠边（★Task404 原实现原样回装；镜像随
/// ame_applySideConstraintsAnimated → ame_applyPanelMirror 链自动生效）
- (void)ame_handleMenuLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    self.ame_menuOnRight = !self.ame_menuOnRight;
    [[NSUserDefaults standardUserDefaults] setObject:(self.ame_menuOnRight ? @"right" : @"left")
                                              forKey:ZL2HomeMenuSideDefaultsKey];
    NSLog(@"[Ame404] menu side toggled right=%d", self.ame_menuOnRight);
    [self ame_applySideConstraintsAnimated:YES];
}

/// ★Task406 停靠镜像（第14轮规格「切换停靠边之后转盘和按钮是不是要镜像」）：
/// 面板停靠左 = 卡尾四钮换钉（管理➕贴右/🗑·⚙贴左/↻贴齿轮右）+ 启动钮与
/// 插件 chip 内容组反排（图标落尾位）+ 版本滚轮条目镜像重建（图标右挂、
/// 文字右对齐）。账户横排条目全居中无水平不对称，免重建。幂等：镜像态未
/// 变直接返回；镜像重钉仅替换卡尾四枚水平钉，纵钉/尺寸钉原样保留。
- (void)ame_applyPanelMirror {
    BOOL ame_left = !self.ame_menuOnRight;
    if (self.ame_panelMirrorLeft == ame_left && self.ame_mirrorConstraints != nil) return;
    self.ame_panelMirrorLeft = ame_left;

    if (self.ame_mirrorConstraints.count > 0) {
        [NSLayoutConstraint deactivateConstraints:self.ame_mirrorConstraints];
    }
    NSMutableArray<NSLayoutConstraint *> *ame_pins = [NSMutableArray array];
    if (self.ame_pinManageLeading) [ame_pins addObject:self.ame_pinManageLeading];
    if (self.ame_pinDeleteTrailing) [ame_pins addObject:self.ame_pinDeleteTrailing];
    if (self.ame_pinSettingsTrailing) [ame_pins addObject:self.ame_pinSettingsTrailing];
    if (self.ame_pinRefreshChain) [ame_pins addObject:self.ame_pinRefreshChain];
    if (self.ame_pinFooterChain) [ame_pins addObject:self.ame_pinFooterChain];   // ★Task409 相邻链随镜像面卸/立
    if (ame_pins.count > 0) [NSLayoutConstraint deactivateConstraints:ame_pins];

    NSMutableArray<NSLayoutConstraint *> *ame_m = [NSMutableArray array];
    if (!ame_left) {
        // 右停靠 = 原钉复位（引用复立，零新建零对峙）
        [ame_m addObjectsFromArray:ame_pins];
    } else {
        [ame_m addObjectsFromArray:@[
            [self.accountManageButton.trailingAnchor constraintEqualToAnchor:self.accountCard.trailingAnchor constant:-12],
            [self.accountDeleteButton.leadingAnchor constraintEqualToAnchor:self.accountCard.leadingAnchor constant:12],
            [self.versionSettingsButton.leadingAnchor constraintEqualToAnchor:self.versionCard.leadingAnchor constant:12],
            [self.versionRefreshButton.leadingAnchor constraintEqualToAnchor:self.versionSettingsButton.trailingAnchor constant:4],
        ]];
    }
    [NSLayoutConstraint activateConstraints:ame_m];
    self.ame_mirrorConstraints = ame_m;

    [self ame_setLaunchContentReversed:ame_left];
    [self ame_setPluginContentReversed:ame_left];

    NSLog(@"[Ame406] panel mirror left=%d", ame_left);

    // ★Task409 对称重建（原 ame_left && 单向条件 = 切回右停靠镜像行永不
    // 还原，右停靠长期残留图标右挂 = 「镜像显示有问题」实体二）：镜像态
    // 每次翻转都强制版本条目按当前停靠侧重建。
    if (self.versionFlow.ame_itemsCount > 0) {
        // 版本条目水平不对称（icon-leading）→ 清免重建守卫强制镜像重建
        // （setSelectedIndex animated:NO 瞬时定位，零动画）
        self.ame400_versionRowNames = nil;
        [self ame_refreshVersionCard];
    }
}

// 启动钮内容组反排（图标 ↔ 文案换位；约束不动，stack arranged 重排）
- (void)ame_setLaunchContentReversed:(BOOL)reversed {
    if (self.ame_launchContentReversed == reversed || self.ame_launchContentStack == nil) return;
    self.ame_launchContentReversed = reversed;
    UIView *ame_icon = self.launchIconView;
    [self.ame_launchContentStack removeArrangedSubview:ame_icon];
    if (reversed) {
        [self.ame_launchContentStack addArrangedSubview:ame_icon];
    } else {
        [self.ame_launchContentStack insertArrangedSubview:ame_icon atIndex:0];
    }
}

// 插件 chip 内容组反排（同上）
- (void)ame_setPluginContentReversed:(BOOL)reversed {
    if (self.ame_pluginContentReversed == reversed || self.ame_pluginContentStack == nil) return;
    self.ame_pluginContentReversed = reversed;
    UIView *ame_icon = self.pluginChipIconView;
    [self.ame_pluginContentStack removeArrangedSubview:ame_icon];
    if (reversed) {
        [self.ame_pluginContentStack addArrangedSubview:ame_icon];
    } else {
        [self.ame_pluginContentStack insertArrangedSubview:ame_icon atIndex:0];
    }
}

/// 重建双栏约束组：ActionMenu 宽 = 容器 0.28（优先级 999）clamp[220, 300]，
/// 内容区吃余量；停靠左/右只换 leading/trailing 挂接（★Task404 恢复双支线，
/// 对向挂接保留后期追加的 8pt 缝：右支 content.trailing = menu.leading − 8，
/// 左支镜像 content.leading = menu.trailing + 8）。
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
        // [内容区][菜单] —— 菜单贴右（★ Task392：卡边离屏 8pt——「其边框距离屏幕
        //   边缘的空隙也要和屏幕一致」：与上下安全区 8pt 同值，四边统一）
        [constraints addObjectsFromArray:@[
            [menu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
            [content.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [content.trailingAnchor constraintEqualToAnchor:menu.leadingAnchor constant:-8],
        ]];
    } else {
        // [菜单][内容区] —— 菜单贴左（★ Task392：同上，四边统一 8pt；★Task404
        //   恢复原左停靠支线，缝 8pt 与右支镜像）
        [constraints addObjectsFromArray:@[
            [menu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
            [content.leadingAnchor constraintEqualToAnchor:menu.trailingAnchor constant:8],
            [content.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        ]];
    }

    [NSLayoutConstraint activateConstraints:constraints];
    self.ame_sideConstraints = constraints;
    [self ame_applyPanelMirror];   // ★Task406 卡尾四钮/内容组/版本条目随停靠边镜像

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
                                 text:localize(@"ame369.home.set_current_instance", @"设为当前实例")
                          destructive:NO
                              action:^{
            [ZL2M3BottomSheet dismissWithContentView:sheetStack];
            [weakSelf ame_selectProfileNamed:profileName];
        }]];

    // ② 打开版本详情（info.circle，SF1.0）——容器由壳接线，本页只发通知
    [sheetStack addArrangedSubview:
        [self ame_sheetRowWithSymbol:@"info.circle"
                             fallback:nil
                                 text:localize(@"ame369.home.open_version_details", @"打开版本详情")
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
    // ★ Task400：数据先行（版本滚轮以 ame_rows 为数据源——原序卡刷新在前/
    //   行模型重建在后，滚轮化后刷新依赖行模型，重建序前移；语义不变：
    //   壳侧手动调 / viewWillAppear 回来时保证网格与滚轮一致）
    [self ame_rebuildData];
    [self ame_rebuildGrid];
    [self ame_refreshAccountCard];
    [self ame_refreshVersionCard];
    [self ame_refreshLaunchButton];
}

// —— 账户封面流（★ Task400/401：原头像+名称卡原地横排五枚封面流——数据源
//    扫描与账户页 reloadAccounts 同口径（Task180 去重/坏文件过滤）；初始落定
//    = 当前选中账户（accountId 精确比对，同名账户也能正确区分）；无账户 =
//    单条「未登录」占位（登录入口 = 卡尾管理钮 / 无账号点启动续登录链）——
- (void)ame_refreshAccountCard {
    [self ame400_reloadAccountList];

    NSString *ame400_selectedId = nil;
    BaseAuthenticator *ame400_current = BaseAuthenticator.current;   // +current 返回 id，先转型（CI 实锤：.authData 直取编译雷）
    NSDictionary *ame400_currentData = [ame400_current isKindOfClass:[BaseAuthenticator class]] ? ame400_current.authData : nil;
    if ([ame400_currentData isKindOfClass:[NSDictionary class]]) {
        ame400_selectedId = ame400_currentData[@"accountId"] ?: ame400_currentData[@"username"];
    }

    // ★ Task401：条目键序未变时免重建（只重定位选中）——选中链回扫
    //   （UpdateAccountInfo）或 viewWillAppear 重入时不再拆建滚轮，
    //   消除吸附落定后重建复位导致的视觉回跳
    NSMutableArray<NSString *> *ame400_keys = [NSMutableArray array];
    for (NSDictionary *ame400_accountData in self.ame400_accountList) {
        [ame400_keys addObject:ame400_accountData[@"accountId"] ?: ame400_accountData[@"username"] ?: @""];
    }
    if (self.ame400_accountKeys != nil
        && [ame400_keys isEqualToArray:self.ame400_accountKeys]
        && self.accountFlow.ame_itemsCount == ame400_keys.count) {
        // 选中定位：找不到当前账户键时回退 0 位（勿把 NSNotFound 铸给 setSelectedIndex）
        NSInteger ame400_sel = 0;
        if (ame400_selectedId.length > 0) {
            NSUInteger ame400_found = [ame400_keys indexOfObject:ame400_selectedId];
            if (ame400_found != NSNotFound) ame400_sel = (NSInteger)ame400_found;
        }
        [self.accountFlow setSelectedIndex:ame400_sel animated:NO];
        return;
    }

    NSMutableArray<UIView *> *ame400_items = [NSMutableArray array];
    __block NSUInteger ame400_selectedIdx = 0;   // 枚举块内赋值（Task393 CI 实锤：缺 __block 编译雷）

    if (self.ame400_accountList.count == 0) {
        [ame400_items addObject:[self ame400_signedOutFlowItem]];
    } else {
        [self.ame400_accountList enumerateObjectsUsingBlock:^(NSDictionary *ame400_accountData, NSUInteger idx, BOOL *stop) {
            [ame400_items addObject:[self ame400_accountFlowItemForData:ame400_accountData]];
            NSString *ame400_key = ame400_accountData[@"accountId"] ?: ame400_accountData[@"username"];
            if (ame400_selectedId.length > 0 && [ame400_selectedId isEqualToString:ame400_key]) {
                ame400_selectedIdx = idx;
            }
        }];
    }

    self.ame400_accountKeys = ame400_keys;
    [self.accountFlow configureItems:ame400_items];
    [self.accountFlow setSelectedIndex:(NSInteger)ame400_selectedIdx animated:NO];
}

// —— 版本封面流（★ Task400/401：原版本选择卡原地竖排封面流——占五个正常
//    实例版本信息高度（用户规格「实例版本也一样改，占用的比例算五个正常的
//    实例版本信息高度」）；初始落定 = 当前选中实例；空注册表 = 单条
//    「选择版本」占位（空态卡引导下载）——
- (void)ame_refreshVersionCard {
    // ★ Task401：行名序未变时免重建（只重定位选中）——滚轮落定 → 选用 →
    //   SelectedProfileChanged 回环刷新时不再拆建滚轮（Task400 实锤回跳
    //   病灶之一：吸附提交回调内同步全量拆建 = 新条目重置到选中位相），
    //   选中状态由 setSelectedIndex 程序化定位承接（零视觉跳动）
    NSMutableArray<NSString *> *ame400_names = [NSMutableArray array];
    for (NSDictionary *ame400_row in self.ame_rows) {
        [ame400_names addObject:ame400_row[@"name"] ?: @""];
    }
    if (self.ame400_versionRowNames != nil
        && [ame400_names isEqualToArray:self.ame400_versionRowNames]
        && self.versionFlow.ame_itemsCount == ame400_names.count) {
        NSUInteger ame400_selIdx = 0;
        for (NSUInteger ame400_i = 0; ame400_i < self.ame_rows.count; ame400_i++) {
            if ([self.ame_rows[ame400_i][@"isSelected"] boolValue]) { ame400_selIdx = ame400_i; break; }
        }
        [self.versionFlow setSelectedIndex:(NSInteger)ame400_selIdx animated:NO];
        return;
    }

    NSMutableArray<UIView *> *ame400_items = [NSMutableArray array];
    __block NSUInteger ame400_selectedIdx = 0;   // 枚举块内赋值（Task393 CI 实锤：缺 __block 编译雷）

    if (self.ame_rows.count == 0) {
        [ame400_items addObject:[self ame400_emptyVersionFlowItem]];
    } else {
        [self.ame_rows enumerateObjectsUsingBlock:^(NSDictionary *ame400_row, NSUInteger idx, BOOL *stop) {
            [ame400_items addObject:[self ame400_versionFlowItemForRow:ame400_row]];
            if ([ame400_row[@"isSelected"] boolValue]) ame400_selectedIdx = idx;
        }];
    }

    self.ame400_versionRowNames = ame400_names;
    [self.versionFlow configureItems:ame400_items];
    [self.versionFlow setSelectedIndex:(NSInteger)ame400_selectedIdx animated:NO];
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

// 账户管理入口（★ Task400：原账号卡点击语义收口至账户卡尾管理小钮）
- (void)accountCardTapped {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowAccountManager" object:nil];
}

- (void)ame_requestAccountAction:(NSString *)notification {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2ShellNavigate" object:nil userInfo:@{@"index": @3}];
    [[NSNotificationCenter defaultCenter] postNotificationName:notification object:nil];
}

- (void)handleSidebarReorder:(UILongPressGestureRecognizer *)gesture {
    UIView *card = gesture.view;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CGPoint touch = [gesture locationInView:card];
        UIView *hit = [card hitTest:touch withEvent:nil];
        for (UIView *cursor = hit; cursor && cursor != card; cursor = cursor.superview) {
            if ([cursor isKindOfClass:UIControl.class] ||
                [cursor isKindOfClass:AmeFlowSelectView.class]) return;
        }
        self.draggedSidebarCard = card;
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
        return;
    }
    if (gesture.state == UIGestureRecognizerStateChanged && self.draggedSidebarCard == card) {
        CGPoint point = [gesture locationInView:self.menuStack];
        for (UIView *other in self.menuStack.arrangedSubviews) {
            if (other == card || other.hidden) continue;
            if (CGRectContainsPoint(other.frame, point)) {
                NSUInteger target = [self.menuStack.arrangedSubviews indexOfObject:other];
                [self.menuStack removeArrangedSubview:card];
                [self.menuStack insertArrangedSubview:card atIndex:target];
                [UIView animateWithDuration:0.2 animations:^{ [self.menuStack layoutIfNeeded]; }];
                [self.panelBackdrop setNeedsDisplay];
                [self saveSidebarCardOrder];
                break;
            }
        }
    }
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        self.draggedSidebarCard = nil;
    }
}

- (void)restoreSidebarCardOrder {
    NSArray<NSString *> *saved = [NSUserDefaults.standardUserDefaults
        stringArrayForKey:ZL2SidebarCardOrderDefaultsKey];
    if (saved.count != 4) return;
    NSDictionary<NSString *, UIView *> *cards = @{
        self.quickNavCard.accessibilityIdentifier: self.quickNavCard,
        self.accountCard.accessibilityIdentifier: self.accountCard,
        self.versionCard.accessibilityIdentifier: self.versionCard,
        self.launchCard.accessibilityIdentifier: self.launchCard,
    };
    for (NSUInteger index = 0; index < saved.count; index++) {
        UIView *card = cards[saved[index]];
        if (!card) return;
        [self.menuStack removeArrangedSubview:card];
        [self.menuStack insertArrangedSubview:card atIndex:index];
    }
}

- (void)saveSidebarCardOrder {
    NSMutableArray<NSString *> *order = [NSMutableArray arrayWithCapacity:4];
    for (UIView *card in self.menuStack.arrangedSubviews) {
        if (card.accessibilityIdentifier.length > 0) [order addObject:card.accessibilityIdentifier];
    }
    if (order.count == 4) {
        [NSUserDefaults.standardUserDefaults setObject:order forKey:ZL2SidebarCardOrderDefaultsKey];
    }
}

// ★ Task400：versionCardTapped 退役（版本滚轮原地驻卡内，拖拽即选择；
//   管理入口 = 卡尾齿轮钮 versionSettingsTapped 不变）

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

#pragma mark - ★ Task400 右栏原地封面流（账户/版本双滚轮 + 账户选中链）

// 账户数据源扫描（账户页 reloadAccounts 同口径 1:1：POJAV_HOME/accounts/*.json
// + Task180 双保险——accountId 去重 + 解析失败文件过滤）
- (void)ame400_reloadAccountList {
    if (self.ame400_accountList == nil) {
        self.ame400_accountList = [NSMutableArray array];
    } else {
        [self.ame400_accountList removeAllObjects];
    }

    NSString *ame400_listPath = [NSString stringWithFormat:@"%s/accounts", getenv("POJAV_HOME")];
    NSFileManager *ame400_fm = [NSFileManager defaultManager];
    NSArray *ame400_files = [ame400_fm contentsOfDirectoryAtPath:ame400_listPath error:nil];
    NSMutableSet *ame400_seenIds = [NSMutableSet set];
    for (NSString *ame400_file in ame400_files) {
        NSString *ame400_path = [ame400_listPath stringByAppendingPathComponent:ame400_file];
        BOOL ame400_isDir = NO;
        [ame400_fm fileExistsAtPath:ame400_path isDirectory:(&ame400_isDir)];
        if (!ame400_isDir && [ame400_file hasSuffix:@".json"]) {
            NSDictionary *ame400_data = parseJSONFromFile(ame400_path);
            if (ame400_data == nil || ame400_data[@"NSErrorObject"] != nil) {
                NSLog(@"[ZL2Home] skipping unreadable account file: %@", ame400_file);
                continue;
            }
            NSString *ame400_key = ame400_data[@"accountId"] ?: [ame400_file stringByDeletingPathExtension];
            if ([ame400_seenIds containsObject:ame400_key]) continue;
            [ame400_seenIds addObject:ame400_key];
            [self.ame400_accountList addObject:ame400_data];
        }
    }
}

// 未登录占位条目（原账号卡「未登录」+ 加号占位同款语义；单条不可换选——
// 滚轮 onSettle 只在下标变化时回调，恒居中零误触；★ Task401 横排条目 =
// 图标上/名称下竖排小卡）
- (UIView *)ame400_signedOutFlowItem {
    UIView *ame400_item = [[UIView alloc] init];

    UIImageView *ame400_avatar = [[UIImageView alloc] init];
    UIImage *ame400_placeholder = ZL2HomeSystemImage(@"plus.circle.fill", @"plus.circle");
    ame400_avatar.image = [ame400_placeholder imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    ame400_avatar.tintColor = [ZL2Theme onSurfaceVariant];
    ame400_avatar.contentMode = UIViewContentModeScaleAspectFit;
    ame400_avatar.userInteractionEnabled = NO;
    ame400_avatar.translatesAutoresizingMaskIntoConstraints = NO;
    [ame400_item addSubview:ame400_avatar];

    UILabel *ame400_nameLabel = [[UILabel alloc] init];
    ame400_nameLabel.font = [ZL2Theme fontLabelMedium];
    ame400_nameLabel.textColor = [ZL2Theme onSurface];
    ame400_nameLabel.text = localize(@"i18n_str_357", nil);   // 未登录（旧账号卡同键）
    ame400_nameLabel.numberOfLines = 1;
    ame400_nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    ame400_nameLabel.textAlignment = NSTextAlignmentCenter;
    // ★ Task407 转盘字体恒定：条目随封面流 |d| 缩放时标签框同步缩窄，
    //   adjustsFontSizeToFitWidth 会真实缩小字号 = 「转盘转的时候字体自动
    //   展开和缩小」。改恒定字号 + TruncatingTail 截断（版本轮条目同口径）。
    ame400_nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ame400_nameLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:ame400_nameLabel];

    [NSLayoutConstraint activateConstraints:@[
        [ame400_avatar.topAnchor constraintEqualToAnchor:ame400_item.topAnchor constant:10],
        [ame400_avatar.centerXAnchor constraintEqualToAnchor:ame400_item.centerXAnchor],
        [ame400_avatar.widthAnchor constraintEqualToConstant:ZL2HomeAccountEntryAvatar],
        [ame400_avatar.heightAnchor constraintEqualToConstant:ZL2HomeAccountEntryAvatar],
        [ame400_nameLabel.topAnchor constraintEqualToAnchor:ame400_avatar.bottomAnchor constant:6],
        [ame400_nameLabel.centerXAnchor constraintEqualToAnchor:ame400_item.centerXAnchor],
        [ame400_nameLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:ame400_item.leadingAnchor constant:1],
        [ame400_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-1],
    ]];
    return ame400_item;
}

// 账户条目（★ Task401 横排五枚：原头像+名称卡同一呈现语言竖排小卡——
// 头像上/名称/类型下居中；用户规格「用原来的样式横排五个」；条目底透明
// （卡窗即背景，选中零装饰）；MC 头像圆角 = 1 物理像素超小圆角（用户
// 规格「圆角大小占用正常头像一个像素」））
- (UIView *)ame400_accountFlowItemForData:(NSDictionary *)accountData {
    UIView *ame400_item = [[UIView alloc] init];

    UIImageView *ame400_avatarView = [[UIImageView alloc] init];
    UIImage *ame400_placeholder = ZL2HomeSystemImage(@"person.crop.circle.fill", @"person.circle.fill");
    ame400_avatarView.image = [ame400_placeholder imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    ame400_avatarView.tintColor = [ZL2Theme onSurfaceVariant];
    ame400_avatarView.contentMode = UIViewContentModeScaleAspectFill;
    // ★ Task400：MC 头像 1 物理像素超小圆角（1pt ÷ 屏幕 scale；原圆形口径退役）
    ame400_avatarView.layer.cornerRadius = 1.0 / [UIScreen mainScreen].scale;
    ame400_avatarView.layer.masksToBounds = YES;
    ame400_avatarView.userInteractionEnabled = NO;
    ame400_avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    [ame400_item addSubview:ame400_avatarView];

    NSString *ame400_displayName = accountData[@"username"] ?: @"";
    if ([ame400_displayName hasPrefix:@"Demo."]) {
        ame400_displayName = [ame400_displayName substringFromIndex:5];
    }

    UILabel *ame400_nameLabel = [[UILabel alloc] init];
    ame400_nameLabel.font = [ZL2Theme fontLabelMedium];
    ame400_nameLabel.textColor = [ZL2Theme onSurface];
    ame400_nameLabel.text = ame400_displayName;
    ame400_nameLabel.numberOfLines = 1;
    ame400_nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    ame400_nameLabel.textAlignment = NSTextAlignmentCenter;
    // ★ Task407 转盘字体恒定（原「窄槽位长名缩排优先」判例退役）：封面流
    //   条目随 |d| 缩放时缩字属性令字号随拖动泵动，恒定字号 + 截断替代。
    ame400_nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ame400_nameLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:ame400_nameLabel];

    UILabel *ame400_typeLabel = [[UILabel alloc] init];
    ame400_typeLabel.font = [ZL2Theme fontLabelMedium];
    ame400_typeLabel.textColor = [ZL2Theme onSurfaceVariant];
    ame400_typeLabel.text = [self ame_typeTextForAccountData:accountData];
    ame400_typeLabel.numberOfLines = 1;
    ame400_typeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    ame400_typeLabel.textAlignment = NSTextAlignmentCenter;
    // ★ Task407 转盘字体恒定（同 nameLabel：去缩字，恒定字号 + 截断）
    ame400_typeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ame400_typeLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:ame400_typeLabel];

    [NSLayoutConstraint activateConstraints:@[
        [ame400_avatarView.topAnchor constraintEqualToAnchor:ame400_item.topAnchor constant:8],
        [ame400_avatarView.centerXAnchor constraintEqualToAnchor:ame400_item.centerXAnchor],
        [ame400_avatarView.widthAnchor constraintEqualToConstant:ZL2HomeAccountEntryAvatar],
        [ame400_avatarView.heightAnchor constraintEqualToConstant:ZL2HomeAccountEntryAvatar],
        [ame400_nameLabel.topAnchor constraintEqualToAnchor:ame400_avatarView.bottomAnchor constant:4],
        [ame400_nameLabel.centerXAnchor constraintEqualToAnchor:ame400_item.centerXAnchor],
        [ame400_nameLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:ame400_item.leadingAnchor constant:1],
        [ame400_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-1],
        [ame400_typeLabel.topAnchor constraintEqualToAnchor:ame400_nameLabel.bottomAnchor constant:1],
        [ame400_typeLabel.centerXAnchor constraintEqualToAnchor:ame400_item.centerXAnchor],
        [ame400_typeLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:ame400_item.leadingAnchor constant:1],
        [ame400_typeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-1],
    ]];

    // 头像异步取（AvatarManager 三层回退链；弱引用条目，回调晚到不吊命已拆条目）
    __weak UIImageView *ame400_weakAvatar = ame400_avatarView;
    [[AvatarManager sharedManager] ame185_fetchAvatarForAuthData:accountData
                                                      completion:^(UIImage *image) {
        if (image && ame400_weakAvatar) {
            ame400_weakAvatar.image = image;   // 默认渲染，1px 超小圆角裁切
            ame400_weakAvatar.tintColor = nil;
        }
    }];
    return ame400_item;
}

// 空注册表占位条目（原版本卡「选择版本」空态同款语义；单条不可换选，
// 齿轮钮/空态卡承接下载引导）
- (UIView *)ame400_emptyVersionFlowItem {
    UIView *ame400_item = [[UIView alloc] init];

    UIImageView *ame400_iconView = [[UIImageView alloc] init];
    UIImage *ame400_fallback = ZL2HomeSystemImage(@"gamecontroller.fill", @"gamecontroller");
    ame400_iconView.image = [ame400_fallback imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    ame400_iconView.tintColor = [ZL2Theme onSurfaceVariant];
    ame400_iconView.contentMode = UIViewContentModeScaleAspectFit;
    ame400_iconView.userInteractionEnabled = NO;
    ame400_iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [ame400_item addSubview:ame400_iconView];

    UILabel *ame400_nameLabel = [[UILabel alloc] init];
    ame400_nameLabel.font = [ZL2Theme fontLabelLarge];
    ame400_nameLabel.textColor = [ZL2Theme onSurfaceVariant];
    ame400_nameLabel.text = localize(@"ame369.home.select_version", @"选择版本");
    ame400_nameLabel.numberOfLines = 1;
    ame400_nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    ame400_nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ame400_nameLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:ame400_nameLabel];

    UILabel *ame400_infoLabel = [[UILabel alloc] init];
    ame400_infoLabel.font = [ZL2Theme fontLabelMedium];
    ame400_infoLabel.textColor = [ZL2Theme onSurfaceVariant];
    ame400_infoLabel.text = @"";
    ame400_infoLabel.numberOfLines = 1;
    ame400_infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ame400_infoLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:ame400_infoLabel];

    BOOL ame_mir = !self.ame_menuOnRight;   // ★Task406 停靠左 = 条目镜像（图标右挂/文字右对齐）
    NSLayoutConstraint *ame_iconEdge = ame_mir
        ? [ame400_iconView.trailingAnchor constraintEqualToAnchor:ame400_item.trailingAnchor constant:-14]
        : [ame400_iconView.leadingAnchor constraintEqualToAnchor:ame400_item.leadingAnchor constant:14];
    NSLayoutConstraint *ame_nameChain = ame_mir
        ? [ame400_nameLabel.trailingAnchor constraintEqualToAnchor:ame400_iconView.leadingAnchor constant:-10]
        : [ame400_nameLabel.leadingAnchor constraintEqualToAnchor:ame400_iconView.trailingAnchor constant:10];
    NSLayoutConstraint *ame_nameEdge = ame_mir
        ? [ame400_nameLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:ame400_item.leadingAnchor constant:14]
        : [ame400_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-14];
    NSLayoutConstraint *ame_infoChain = ame_mir
        ? [ame400_infoLabel.trailingAnchor constraintEqualToAnchor:ame400_nameLabel.trailingAnchor]
        : [ame400_infoLabel.leadingAnchor constraintEqualToAnchor:ame400_nameLabel.leadingAnchor];
    NSLayoutConstraint *ame_infoEdge = ame_mir
        ? [ame400_infoLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:ame400_item.leadingAnchor constant:14]
        : [ame400_infoLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-14];
    if (ame_mir) {
        ame400_nameLabel.textAlignment = NSTextAlignmentRight;
        ame400_infoLabel.textAlignment = NSTextAlignmentRight;
    }

    [NSLayoutConstraint activateConstraints:@[
        ame_iconEdge,
        [ame400_iconView.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor],
        [ame400_iconView.widthAnchor constraintEqualToConstant:40],
        [ame400_iconView.heightAnchor constraintEqualToConstant:40],
        ame_nameChain,
        [ame400_nameLabel.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor constant:-10],
        ame_nameEdge,
        ame_infoChain,
        [ame400_infoLabel.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor constant:10],
        ame_infoEdge,
    ]];
    return ame400_item;
}

// 版本条目（★ Task400：横排 = 加载器图标 40 + 实例名/信息行，条目高 64 =
//   原版本选择卡同族口径（「五个正常的实例版本信息高度」）；条目底透明
//   （卡面即背景）；信息行三态与实例卡 ame_configureWithRow 同一语义）
- (UIView *)ame400_versionFlowItemForRow:(NSDictionary *)row {
    NSString *profileName = row[@"name"];
    NSString *versionId = row[@"versionId"];
    NSString *loader = row[@"loader"];
    NSString *mcVersion = row[@"mcVersion"];
    BOOL valid = [row[@"valid"] boolValue];

    UIView *ame400_item = [[UIView alloc] init];

    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.userInteractionEnabled = NO;
    [ame400_item addSubview:iconView];

    // 实例图标：加载器图标（原版本卡同款）；取不到 → gamecontroller 兜底
    if (loader.length > 0) {
        [ModLoaderIconHelper configureImageView:iconView
                                      forLoader:loader
                                 traitCollection:self.traitCollection];
    } else {
        UIImage *fallbackIcon = ZL2HomeSystemImage(@"gamecontroller.fill", @"gamecontroller");
        iconView.image = [fallbackIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        iconView.tintColor = [ZL2Theme onSurfaceVariant];
    }

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.font = [ZL2Theme fontLabelLarge];
    nameLabel.textColor = [ZL2Theme onSurface];
    nameLabel.text = profileName;
    nameLabel.numberOfLines = 1;
    nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:nameLabel];

    UILabel *infoLabel = [[UILabel alloc] init];
    infoLabel.font = [ZL2Theme fontLabelMedium];
    infoLabel.textColor = [ZL2Theme onSurfaceVariant];
    infoLabel.numberOfLines = 1;
    infoLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    infoLabel.userInteractionEnabled = NO;
    [ame400_item addSubview:infoLabel];

    // 信息行：与实例卡同款三态（无效 = error 色引导文案）
    if (!valid) {
        if (versionId.length == 0) {
            infoLabel.text = localize(@"ame351.instance.no_version", nil);
        } else {
            infoLabel.text = localize(@"ame369.common.invalid_version", @"该版本无效");
        }
        infoLabel.textColor = [ZL2Theme error];
    } else {
        if (mcVersion.length > 0 && loader.length > 0) {
            infoLabel.text = [NSString stringWithFormat:@"MC %@ · %@",
                              mcVersion, [ModLoaderIconHelper displayNameForLoader:loader]];
        } else if (mcVersion.length > 0) {
            infoLabel.text = [NSString stringWithFormat:@"MC %@", mcVersion];
        } else if (loader.length > 0) {
            infoLabel.text = [ModLoaderIconHelper displayNameForLoader:loader];
        } else {
            infoLabel.text = @"";
        }
    }

    BOOL ame_mir = !self.ame_menuOnRight;   // ★Task406 停靠左 = 条目镜像（同实条目）
    NSLayoutConstraint *ame_iconEdge = ame_mir
        ? [iconView.trailingAnchor constraintEqualToAnchor:ame400_item.trailingAnchor constant:-14]
        : [iconView.leadingAnchor constraintEqualToAnchor:ame400_item.leadingAnchor constant:14];
    NSLayoutConstraint *ame_nameChain = ame_mir
        ? [nameLabel.trailingAnchor constraintEqualToAnchor:iconView.leadingAnchor constant:-10]
        : [nameLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:10];
    NSLayoutConstraint *ame_nameEdge = ame_mir
        ? [nameLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:ame400_item.leadingAnchor constant:14]
        : [nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-14];
    NSLayoutConstraint *ame_infoChain = ame_mir
        ? [infoLabel.trailingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor]
        : [infoLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor];
    NSLayoutConstraint *ame_infoEdge = ame_mir
        ? [infoLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:ame400_item.leadingAnchor constant:14]
        : [infoLabel.trailingAnchor constraintLessThanOrEqualToAnchor:ame400_item.trailingAnchor constant:-14];
    if (ame_mir) {
        nameLabel.textAlignment = NSTextAlignmentRight;
        infoLabel.textAlignment = NSTextAlignmentRight;
    }

    [NSLayoutConstraint activateConstraints:@[
        ame_iconEdge,
        [iconView.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:40],
        [iconView.heightAnchor constraintEqualToConstant:40],
        ame_nameChain,
        [nameLabel.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor constant:-10],
        ame_nameEdge,
        ame_infoChain,
        [infoLabel.centerYAnchor constraintEqualToAnchor:ame400_item.centerYAnchor constant:10],
        ame_infoEdge,
    ]];
    return ame400_item;
}

// 选用实例（Task393 原方法保留：写 selected + save + post
// @"SelectedProfileChanged"；本页监听该通知刷新网格与滚轮——原地滚轮的
// 选用提交点 = versionFlow.onSettle）
- (void)ame393_selectProfileAtIndex:(NSUInteger)index {
    if (index >= self.ame_rows.count) return;
    NSString *profileName = self.ame_rows[index][@"name"];
    if (![profileName isKindOfClass:[NSString class]] || profileName.length == 0) return;
    NSString *selected = PLProfiles.current.selectedProfileName;
    if ([profileName isEqualToString:selected]) return;
    PLProfiles.current.selectedProfileName = profileName;
    [PLProfiles.current save];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectedProfileChanged" object:nil];
}

// —— 账户选中链（★ Task400：账户页 selectAccountAtIndex 同款 1:1——第三方
//    Task128 会话校验/stale 优雅降级、微软/本地 loadSavedName+refreshToken
//    全链；锁滚轮 + spinner 占位；收尾 = 重建滚轮 + 发 @"UpdateAccountInfo"
//    （主页 pendingLaunchAfterLogin 续启动契约不变）——
- (void)ame400_selectAccountAtIndex:(NSUInteger)index {
    if (self.accountFlow.interactionLocked) return;
    if (index >= self.ame400_accountList.count) return;
    NSDictionary *ame400_accountData = self.ame400_accountList[index];

    // 优先用 accountId 加载；若 accountId 缺失（旧格式账户未迁移），回退
    // 到 username 触发迁移（旧链同款）
    NSString *ame400_loadKey = ame400_accountData[@"accountId"];
    if (ame400_loadKey.length == 0) {
        ame400_loadKey = ame400_accountData[@"username"];
    }

    self.accountFlow.interactionLocked = YES;
    [self.accountSpinner startAnimating];

    if (ZL2AccountsSharedIsThirdParty(ame400_accountData)) {
        // 第三方：Task128 zl2 同款 isSessionValidated——本会话已通过服务端
        // 校验直接选中；否则 refresh，成功选中、失败优雅降级（stale token
        // 仍选中 + toast 提示重新登录）
        ThirdPartyAuthenticator *ame400_auth = [ThirdPartyAuthenticator loadSavedName:ame400_loadKey];
        if ([ZL2AccountsSharedValidatedSet() containsObject:ame400_loadKey]) {
            [self ame400_finishAccountSelection];
        } else {
            __weak typeof(self) weakSelf = self;
            [ame400_auth refreshTokenWithCallback:^(id status, BOOL success) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (success) {
                        [ZL2AccountsSharedValidatedSet() addObject:ame400_loadKey];
                        [weakSelf ame400_handleAuthResult:status success:YES];
                    } else {
                        // Task128 优雅回退：refresh 失败仍选中（current 已由
                        // loadSavedName 设置 + selected_account 持久化）
                        [ZL2AccountsSharedValidatedSet() addObject:ame400_loadKey];
                        setPrefObject(@"internal.selected_account", ame400_loadKey);
                        [weakSelf ame400_finishAccountSelection];
                        [NMToast showMessage:[NSString stringWithFormat:@"%@\n%@",
                            localize(@"login.3rdparty.stale.title", nil),
                            localize(@"login.3rdparty.stale.message", nil)]
                                      duration:6.0];
                    }
                });
            }];
        }
    } else {
        // 微软/本地：loadSavedName + refreshTokenWithCallback → 共用收尾
        __weak typeof(self) weakSelf = self;
        [[BaseAuthenticator loadSavedName:ame400_loadKey] refreshTokenWithCallback:^(id status, BOOL success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf ame400_handleAuthResult:status success:success];
            });
        }];
    }
}

// 认证收尾（账户页 handleAuthResult 同款：成功 toast/演示弹窗/finish；
// 失败错误弹窗——present 到本页）
- (void)ame400_handleAuthResult:(id)status success:(BOOL)success {
    if (status != nil) {
        if (success) {
            NSString *ame400_message = nil;
            if ([status isKindOfClass:NSError.class]) {
                ame400_message = [(NSError *)status localizedDescription];
            } else if ([status isKindOfClass:NSString.class]) {
                ame400_message = (NSString *)status;
            }
            if (ame400_message.length > 0) {
                [NMToast showMessage:[NSString stringWithFormat:@"%@：%@",
                    localize(@"login.title", @"账户"), ame400_message]
                              duration:6.0];
            }
            if ([status isKindOfClass:NSString.class] && [status isEqualToString:@"DEMO"]) {
                // 演示模式警告仍需用户知悉（影响后续离线体验预期），保留弹窗
                [self ame400_showDemoDialog];
            }
            [self ame400_finishAccountSelection];
        } else {
            [self ame400_handleAuthFailure:status];
        }
    } else if (success) {
        // 成功登录，无消息
        [self ame400_finishAccountSelection];
    }
}

- (void)ame400_handleAuthFailure:(id)status {
    // 认证失败：恢复交互并展示错误（账户页 handleAuthFailure 同款，含
    // AFNetworking 响应体细节）
    self.accountFlow.interactionLocked = NO;
    [self.accountSpinner stopAnimating];
    if ([status isKindOfClass:[NSError class]]) {
        NSData *ame400_errorData = ((NSError *)status).userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
        if (ame400_errorData) {
            NSString *ame400_errorStr = [[NSString alloc] initWithData:ame400_errorData
                                                               encoding:NSUTF8StringEncoding];
            NSLog(@"[MSA] Error: %@", ame400_errorStr);
            [self ame400_showErrorDialog:ame400_errorStr];
        } else {
            [self ame400_showErrorDialog:[status localizedDescription]];
        }
    } else if ([status isKindOfClass:NSString.class]) {
        [self ame400_showErrorDialog:status];
    } else {
        [self ame400_showErrorDialog:localize(@"login.error.invalid_response", nil)];
    }
}

- (void)ame400_showDemoDialog {
    UIAlertController *ame400_alert = [UIAlertController
        alertControllerWithTitle:localize(@"login.warn.title.demomode", nil)
                         message:localize(@"login.warn.message.demomode", nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    [ame400_alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:ame400_alert animated:YES completion:nil];
}

- (void)ame400_showErrorDialog:(NSString *)message {
    UIAlertController *ame400_alert = [UIAlertController
        alertControllerWithTitle:localize(@"Error", nil)
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [ame400_alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:ame400_alert animated:YES completion:nil];
}

// 选中/登录/刷新成功收尾：恢复交互 + 重建滚轮 + 发 @"UpdateAccountInfo"
//（账户页 finishSelection 等价物——setSelectedIndex 程序化滚动不回调
// onSettle，重建零回环）
- (void)ame400_finishAccountSelection {
    self.accountFlow.interactionLocked = NO;
    [self.accountSpinner stopAnimating];
    [self ame_refreshAccountCard];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"UpdateAccountInfo"
                                                        object:nil
                                                      userInfo:nil];
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
