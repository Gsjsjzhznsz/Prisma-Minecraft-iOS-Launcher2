//
// ZL2ShellViewController.m — ZL2 壳实现（7.0-UI-10-b 起家；Task378 起默认 bare 壳）
//
// 【历史规格存档】以下 TopBar 结构对应注释为 7.0-UI-10-b~377 顶栏形态的
// 设计文档——★ Task378 起顶栏整体退役（bare 壳），本段仅作溯源存档，
// 不再描述现役结构。
//
// ★ Task378（用户两轮复诉）：①全局文本颜色根修——白黑双重叠（Task227~251
//   描边字体链）整体退役，全部文本回归系统深浅语义色（BackgroundManager）；
//   ②顶栏退役——topbar 骨架改 bare 壳（本文件 ame_buildBareShell），五入口
//   按钮迁移主页右侧栏顶部（ZL2HomeViewController quickNav，2.5x 瓦片，
//   前三后二）；nav（navigationview）骨架与门禁锚点逐字保留。
//
// ZL2 MainScreen.kt 顶栏结构对应（ref/ZalithLauncher2/ZalithLauncher/src/main/
// java/com/movtery/zalithlauncher/ui/screens/main/MainScreen.kt L168-246 实证）：
//   Surface(backgroundColor) { Column { TopBar(fillMaxWidth().height(40.dp))
//   + Box(fillMaxWidth().weight(1f)) { NavigationUI(...) } } }
//   ——无 NavigationRail、无底栏。iOS 对应：topBar（内容 40pt；iPhone 竖放时
//   safeAreaInsets.top 区域由 topBar 容器向上延伸补 surface 底色，内容带钉
//   safeArea 下缘）+ container（余下全部；子页懒建缓存 + 首显 attach +
//   0.18s crossDissolve 机制自 7.0-UI-8/9 平移不变）。
// TopBar 内部（同文件 L248-483 已审计）：
//   · 左簇 backCenter：AnimatedVisibility(!inLauncherScreen) 内 12dp + [←返回]
//     + [🏠主页] → iOS leftCluster（横 Stack spacing 4 + 前导 12 边距，返回/
//     主页各 32×32 图标钮）。iOS 适配语义：仅当前页 != 主页时整簇显示
//     （0.18s alpha/hidden 塌缩动画）；返回钮 = 当前页 nav 可 pop 时
//     popViewControllerAnimated:（子页 push 层的系统返回栏仍按各页
//     viewWillAppear/viewWillDisappear 既有约定工作，顶栏返回是辅助手势），
//     不可 pop 时收起返回钮只留主页钮（ZL2 返回键恒显 + onBackPressed 兜底，
//     iOS 侧以显隐表达同一语义）；主页钮 = showPageAtIndex:0。
//   · 标题 title：titleMedium 左对齐，start = backCenter.end + 16dp，
//     Crossfade → iOS titleLabel（fontTitleMedium，跟左簇 16pt，0.18s 交叉
//     过渡；子页 push 态显示「页名 - 子页名」，对应 MainScreen.kt L358-362
//     的 parent + " - " + child）。主页标题 = CFBundleDisplayName（兜底
//     @"Prisma Launcher"，对应 L345 LAUNCHER_IDENTIFIER 位）。
//   · 右簇 endButtons：end margin 12dp、spacing 8dp → iOS rightCluster
//     （trailing 12 边距、spacing 8）。
//     a) 任务胶囊（AnimatedVisibility：任务运行且未展开时；宽 120dp，
//        LinearProgressIndicator + assignment 图标）→ iOS taskPill
//        （surfaceContainerHigh 底 radiusXL 全圆，高 28 宽 120：UIProgressView
//        track outlineVariant / bar primary，取 DownloadTaskManager 第一个
//        活动任务 progress 负值截 0 + doc.plaintext 图标 template + 活动任务
//        数 fontLabelMedium；仅 hasActiveTasks 时显示——iOS 侧无任务菜单
//        展开态；点击 = PLTaskProgressViewController presentForTaskId: 第一
//        个活动任务）。
//     b) TopBarRailItem（= ui/components/_SimpleRail.kt TextRailItem：图标
//        恒显 + 选中时文字 AnimatedVisibility）→ iOS RailItem（图标 22pt
//        template 恒显 + 选中态文字 fontLabelMedium 宽度 0 ↔ 实宽 0.18s
//        展开/收起，未选宽 0 裁剪；选中 primary / 未选 onSurfaceVariant）。
//        📁文件按钮与联机 RailItem iOS 侧本轮省略（文件管理器/联机页尚未有
//        可嵌页面），待功能域落地后补位。
//   · iOS 侧 RailItem×5（ZL2 顶栏无版本/账户直达；Task318 起新增第 5 项 AI）：
//     文件夹(瞬时) / 多人联机(5) / 下载(1) / 设置(4) / AI 助手(6)，与 ZL2 右侧组同序排列。
//
// 页面 index 映射（.h 契约：0...6，越界忽略）：
//   0 主页 ZL2HomeViewController（不包 nav；顶栏标题 = CFBundleDisplayName）
//   1 下载 ZL2DownloadViewController（UINavigationController 包）
//   2 版本 ZL2VersionsViewController（UINavigationController 包）
//   3 账户 ZL2AccountsViewController（UINavigationController 包）
//   4 设置 ZL2SettingsViewController（UINavigationController 包）
//   5 多人联机 MultiplayerViewController（7.0-UI-14；UINavigationController 包）
//   6 AI 助手 AIViewController（Task318 入口恢复；UINavigationController 包）
//
// 通知契约（消费方，7.0-UI-8 三件原样保留 + 顶栏新增两件）：
//   @"ShowHomePage"                              → 切主页（旧启动链）
//   @"ShowAccountManager"                        → 切账户页（FCL 风格）
//   ZL2ShellNavigateNotification                 → userInfo[@"index"] 切页（0...6
//                                                  越界忽略；Task318 起新增 6=AI 助手）
//   DownloadTaskManagerDidUpdateTaskNotification → 任务胶囊刷新（manager 全部
//     变更均经 postUpdateForTask 派发；防御性回主线程后刷 UI）+ viewWillAppear
//     补刷
//   UINavigationControllerDelegate.didShow → 返回钮显隐与
//     「页名 - 子页名」标题跟随当前 nav 栈深刷新（非当前子 nav 时忽略；
//     DidShow 通知常量在 SDK 非公开——CI 实证 undeclared，改走公开 delegate）
//
// 红线遵守：iOS 14.0+（无 button.configuration/UIMenu 等 iOS15+ API；
//   AnimatedVisibility 以 UIStackView hidden 塌缩 + 宽度约束动画等价实现）；
//   颜色/字体/圆角一律 ZL2Theme 动态令牌（无 traitCollection 分支）；新建
//   视图逐一 translatesAutoresizingMaskIntoConstraints=NO；无 viewWithTag
//   身份查找（点击载荷统一 ame_action block + 构造参数）；dealloc 统一移除
//   全部通知观察者。ZL2RailView.m 本体不删不改（CMake 照旧编译），壳不再
//   使用（旧 .h 断言方法 railWidthForSizeClass: 数值冻结保留）。
//

#import "ZL2ShellViewController.h"
#import "ZL2Theme.h"
#import "ZL2VersionIndex.h"          // 7.0-UI-11：启动链版本索引服务（warmUp）
#import "ZL2HomeViewController.h"
#import "ZL2DownloadViewController.h"
#import "ZL2VersionsViewController.h"
#import "ZL2AccountsViewController.h"
#import "ZL2SettingsViewController.h"
#import "ZL2VersionDetailViewController.h"  // 7.0-UI-13：版本详情容器（主页卡/版本列表设置钮 push 目标）
#import "MultiplayerViewController.h"      // 7.0-UI-14：多人联机页（顶栏联机项，页面 5）
#import "FolderBrowserViewController.h"    // 7.0-UI-14：文件浏览器（顶栏文件夹项 PageSheet）
#import "DownloadTaskManager.h"           // manager 单例 + DownloadTaskItem + 更新通知常量
#import "PLTaskProgressViewController.h"  // 统一进度页（胶囊点开）
#import "AI/AIViewController.h"          // Task318：AI 助手入口恢复（7.0-UI-8 旧壳退役后
#import "AI/AiSessionStore.h"           //   顶栏 RailItem 第 5 项重挂；旧壳 showAIPage 同参）
#import "utils.h"                       // Task318：localize（AI 顶栏项文案四表键，缺头=隐式声明雷）
#import "BackgroundManager.h"            // ★ Task349：壁纸描边字体视图树级豁免（ame230_setViewTreeStrokeExempt）
#import "ZL2BackgroundHost.h"             // ★Task429：ZL2 页背景层（8.3 双层毛玻璃，仅背景挂载区域消费）
#import "ZL2FestivalEffects.h"          // ★Task428：8.2 节日彩蛋复活（当日节日粒子层挂窗 + 问候横幅）
#import "TouchControllerPreferencesViewController.h"   // ★Task428：6.6 右上角切换簇虚拟按键直达
#import "ZL2AnimationKit.h"               // ★Task429：MD3 动效体系（壳层切页 fade+offset + 子 nav 转场接入）

#include <stdlib.h>

NSString * const ZL2ShellNavigateNotification = @"ZL2ShellNavigate";

#pragma mark - 几何/动画常量（ZL2 TopBar spec 对应）

static const CGFloat ZL2ShellClusterButtonSize = 32.0;  // 返回/主页钮 32×32
static const CGFloat ZL2ShellRailItemIconSize = 24.0;   // 图标 24pt（★Task410 22→24：开关钮图标随 rail 主元素同步放大）
static const CGFloat ZL2ShellPillWidth = 120.0;         // 任务胶囊宽 120dp
static const CGFloat ZL2ShellPillHeight = 28.0;         // 任务胶囊高
static const CGFloat ZL2ShellAnimateDuration = 0.24;    // 全壳动画时长（★Task395：0.18→0.24 淡入淡出感知增强）

// ★ Task347 NavigationView 骨架常量（WinUI 布局溯源：4pt 栅格）
static const CGFloat ZL2ShellPaneWidth = 280.0;         // 窗格宽（WinUI open 320 紧凑化）
static const CGFloat ZL2ShellPaneCompactWidth = 64.0;   // ★ Task376 折叠态图标栏宽（WinUI compact）
static const CGFloat ZL2ShellHeaderHeight = 64.0;       // 大标题内容区头高（★Task413 安全区二轮 52→64，呼吸带加高一档）
static const CGFloat ZL2ShellRegularMinWidth = 640.0;   // ≥ 此宽常驻窗格（窄屏抽屉）

// SF Symbols 取图兜底（ZL2HomeViewController 同款静态 helper）：基名优先，
// 取不到走同族旧名，仍取不到为 nil（调用方以模板渲染前自判）
static UIImage *ZL2ShellSystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

// ★ Task405：alpha 包围盒自测量——把图栅格化成 1pt=1px 位图后逐像素扫
// 非透明区（premultiplied 下 alpha=0 ⇒ RGBA 全 0、alpha≥8 ⇒ 至少一字节≥8，
// 与通道序无关），返回字形实测最大边（pt）。位图不可读/非常规格式安全返回
// 0 = 调用方原样放行（不劣化于 404）。
static CGFloat ZL2ShellMeasureGlyphBBox(UIImage *image) {
    if (image.size.width < 1.0 || image.size.height < 1.0) return 0.0;
    UIGraphicsImageRendererFormat *ame_fmt = [[UIGraphicsImageRendererFormat alloc] init];
    ame_fmt.scale = 1.0;   // 1px = 1pt，坐标系直读
    ame_fmt.opaque = NO;
    UIGraphicsImageRenderer *ame_renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:image.size format:ame_fmt];
    UIImage *ame_snapshot = [ame_renderer imageWithActions:^(UIGraphicsImageRendererContext *ame_ctx) {
        [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    }];
    CGImageRef ame_cg = ame_snapshot.CGImage;
    if (!ame_cg || CGImageGetBitsPerComponent(ame_cg) != 8) return 0.0;
    CFDataRef ame_data = CGDataProviderCopyData(CGImageGetDataProvider(ame_cg));
    if (!ame_data) return 0.0;
    const UInt8 *ame_bytes = CFDataGetBytePtr(ame_data);
    size_t ame_w = CGImageGetWidth(ame_cg), ame_h = CGImageGetHeight(ame_cg);
    size_t ame_bpr = CGImageGetBytesPerRow(ame_cg);
    size_t ame_bpp = CGImageGetBitsPerPixel(ame_cg) / 8;
    if (!ame_bytes || ame_bpp < 4) { CFRelease(ame_data); return 0.0; }
    CGFloat ame_minX = ame_w, ame_minY = ame_h, ame_maxX = -1, ame_maxY = -1;
    for (size_t y = 0; y < ame_h; y++) {
        const UInt8 *ame_row = ame_bytes + y * ame_bpr;
        for (size_t x = 0; x < ame_w; x++) {
            const UInt8 *ame_px = ame_row + x * ame_bpp;
            if (ame_px[0] >= 8 || ame_px[1] >= 8 || ame_px[2] >= 8 || ame_px[3] >= 8) {
                if (x < ame_minX) ame_minX = x;
                if (x > ame_maxX) ame_maxX = x;
                if (y < ame_minY) ame_minY = y;
                if (y > ame_maxY) ame_maxY = y;
            }
        }
    }
    CFRelease(ame_data);
    if (ame_maxX < ame_minX || ame_maxY < ame_minY) return 0.0;
    return MAX(ame_maxX - ame_minX + 1, ame_maxY - ame_minY + 1);
}

// ★ Task405：字形填充保底。404 验收的是「画布尺寸」——若符号引擎返回
// 「大画布小字形」（画布达标、字形缩在中间），尺寸闸漏网 = 四轮复诉仍欠
// 尺的最后一种可能形态。本轮改包围盒验收：字形实测宽 < 请求点数 90% 即
// 按包围盒等比放大重绘至铺满 pointSize 方形画布（bbox 外全为透明区，溢出
// 画布的裁剪零损失）——字形视觉尺寸从此只由 pointSize 参数决定，符号引擎
// 任何形态的欠尺（小画布 / 大画布小字形 / 配置被无视）都逃不掉。
// ame405_bboxOut 非空时回填字形实测最大边（pt）供 [Ame404] 装机日志判读。
static UIImage *ZL2ShellForceGlyphFill(UIImage *image, CGFloat pointSize, CGFloat *ame405_bboxOut) {
    if (!image || pointSize <= 0.0) return image;
    CGFloat ame_bbox = ZL2ShellMeasureGlyphBBox(image);
    if (ame405_bboxOut) *ame405_bboxOut = ame_bbox;
    if (ame_bbox <= 0.0 || ame_bbox >= pointSize * 0.9) return image;   // 达标/测不出：原样放行
    CGFloat ame_scale = MIN((pointSize * 0.96) / ame_bbox, 4.0);        // 放大上限防病态
    if (ame_scale <= 1.0) return image;
    UIGraphicsImageRendererFormat *ame_fmt = [[UIGraphicsImageRendererFormat alloc] init];
    ame_fmt.scale = 0;   // device native scale
    UIGraphicsImageRenderer *ame_renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(pointSize, pointSize)
                                               format:ame_fmt];
    CGRect ame_rect = CGRectMake(pointSize / 2.0 - image.size.width * ame_scale / 2.0,
                                 pointSize / 2.0 - image.size.height * ame_scale / 2.0,
                                 image.size.width * ame_scale,
                                 image.size.height * ame_scale);
    return [ame_renderer imageWithActions:^(UIGraphicsImageRendererContext *ame_ctx) {
        [image drawInRect:ame_rect];
    }];
}

// ★ Task403：符号配置版取图（视觉字形随 pointSize 重生成）。根因实证
//（IMG_0572 像素级测量）：裸 systemImageNamed: 默认配置的视觉字形仅 ~11pt，
// 且 SF Symbol 自带内边距——改 frame 约束（Task402 的 20→26）只放大容器
// 不放大字形，三轮复诉「折叠图标跟着缩/没变大」的真根因。修法 = frame 与
// 符号配置点数同源联动（ame_setCompact 单点驱动，无第二常量可漂移）。
// ★ Task405：404 的「画布尺寸验收」升级为包围盒自测量（ZL2ShellForceGlyphFill）。
static UIImage *ZL2ShellSystemImageSizedEx(NSString *name, NSString *fallback, CGFloat pointSize,
                                            CGFloat *ame405_bboxOut);

static UIImage *ZL2ShellSystemImageSized(NSString *name, NSString *fallback, CGFloat pointSize) {
    return ZL2ShellSystemImageSizedEx(name, fallback, pointSize, NULL);
}

static UIImage *ZL2ShellSystemImageSizedEx(NSString *name, NSString *fallback, CGFloat pointSize,
                                            CGFloat *ame405_bboxOut) {
    UIImageSymbolConfiguration *config =
        [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                        weight:UIImageSymbolWeightMedium];
    UIImage *image = [UIImage systemImageNamed:name withConfiguration:config];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback withConfiguration:config];
    if (!image) return nil;
    return ZL2ShellForceGlyphFill(image, pointSize, ame405_bboxOut);
}

#pragma mark - 私有点击控件：ame_action block 载荷通道（零 tag / 零 delegate）

@interface ZL2ShellTapControl : UIControl
@property(nonatomic, copy) void (^ame_action)(void);
@end

@implementation ZL2ShellTapControl

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // ★ Task382：基类统一 translates=NO 根修——本类子类（窗格开关钮/
        //   汉堡/返回/任务胶囊）全部 initWithFrame:CGRectZero 建立后仅靠
        //   显式约束定位，而 translates 默认 YES 会按 0×0 初帧生成 w=0/h=0
        //   遮罩约束，与显式尺寸约束同列为 required → 冲突时引擎静默破弃
        //   尺寸约束（约束冲突告警走系统统一日志不进 App stdout，装机
        //   latestlog 无告警但有 toggle={{0,0},{0,0}} 实锤）→ 折叠开关钮
        //   永久零尺寸不可点 = 用户三轮复诉「折叠侧边栏还是没有」根因。
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self addTarget:self
                 action:@selector(ame_fireAction)
       forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)ame_fireAction {
    if (self.ame_action) self.ame_action();
}

@end

#pragma mark - 顶栏图标钮（返回/主页，32×32 居中 22pt 模板图标）

#pragma mark - 任务进度胶囊（LinearProgressIndicator + assignment 等价）

@interface ZL2ShellTaskPill : ZL2ShellTapControl
- (void)ame_setProgress:(double)progress count:(NSInteger)count;
@end

@interface ZL2ShellTaskPill ()
@property(nonatomic, strong) UIProgressView *progressView;
@property(nonatomic, strong) UIImageView *iconView;
@property(nonatomic, strong) UILabel *countLabel;
@end

@implementation ZL2ShellTaskPill

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.backgroundColor = [ZL2Theme surfaceContainerHigh];
        // radiusXL（28）> 高/2：CoreAnimation 渲染收敛为全圆胶囊（ZL2Download 同判例）
        self.layer.cornerRadius = [ZL2Theme radiusXL];
        self.hidden = YES;   // 显隐由壳侧 ame_refreshTaskPill 按 hasActiveTasks 派生
        self.alpha = 0.0;

        _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _progressView.trackTintColor = [ZL2Theme outlineVariant];
        _progressView.progressTintColor = [ZL2Theme primary];
        _progressView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_progressView];

        // assignment 类图标（SF1.0 档：doc.plaintext + fallback doc.text.fill）
        UIImage *image = ZL2ShellSystemImage(@"doc.plaintext", @"doc.text.fill");
        if (image) image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        _iconView = [[UIImageView alloc] initWithImage:image];
        _iconView.tintColor = [ZL2Theme onSurfaceVariant];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.userInteractionEnabled = NO;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_iconView];

        _countLabel = [[UILabel alloc] init];
        _countLabel.font = [ZL2Theme fontLabelMedium];
        _countLabel.textColor = [ZL2Theme onSurface];
        _countLabel.numberOfLines = 1;
        _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_countLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:ZL2ShellPillWidth],
            [self.heightAnchor constraintEqualToConstant:ZL2ShellPillHeight],

            [_progressView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
            [_progressView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_progressView.widthAnchor constraintEqualToConstant:56.0],
            [_progressView.heightAnchor constraintEqualToConstant:3.0],

            [_iconView.leadingAnchor constraintEqualToAnchor:_progressView.trailingAnchor constant:8.0],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:14.0],
            [_iconView.heightAnchor constraintEqualToConstant:14.0],

            [_countLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:4.0],
            [_countLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_countLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-10.0],
        ]];

        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

- (void)ame_setProgress:(double)progress count:(NSInteger)count {
    [self.progressView setProgress:(float)progress animated:NO];
    self.countLabel.text = [NSString stringWithFormat:@"%ld", (long)count];
    self.accessibilityLabel = [NSString stringWithFormat:localize(@"ame369.shell.dl_tasks_fmt", @"下载任务进行中，共 %ld 个"), (long)count];
}

@end

#pragma mark - 壳本体

@interface ZL2ShellViewController () <UINavigationControllerDelegate>
@property(nonatomic, strong) UIView *topBar;                          // ★ Task378 退役占位（恒 nil；保留声明以兼容 (self.topBar ?: self.contentHeader) 门禁锚点表达式）
@property(nonatomic, strong) ZL2ShellTaskPill *taskPill;              // 任务胶囊（nav 骨架内容区头专属）
@property(nonatomic, strong) UIView *container;                       // 子页挂载区
// ★Task405 退役：persistentRightSidebar 常驻右栏属性随 0d97c34 提取机制一并拆除
//（用户第13轮复诉「右侧边栏切页面不会隐藏了」——右栏回归主页私有，切页即随主页隐藏）
@property(nonatomic, strong) NSLayoutConstraint *containerTrailing;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, UIViewController *> *childCache;
@property(nonatomic, assign) NSInteger currentIndex;

// ★Task477 导航合并退役（用户钦定「保留二代侧边栏，删除其他2代」）：
//   一代 ame347 抽屉 pane + 二代 ame411 悬浮簇全量清场（属性/构建/刷新/
//   宽窄态/抽屉几何/指示条），bare 唯一骨架；主页 rail 二代（Task475/476
//   ZL2 图标 rail）= 全局唯一切换器，子页返回走系统导航栏。ame347 结构
//   令牌链（ZL2Theme/桥/Runtime）保留 = 插件 API 面零触碰，壳层消费退役。
//   Task463 折叠面（设置页 41 组）零污染（本手术不触碰 SettingCards/Settings）。
@property(nonatomic, assign) BOOL ame347_navMode;                     // 结构令牌读数（仅日志语义；消费退役 ★Task477）
@property(nonatomic, strong) UIView *contentHeader;                   // （taskPill 刷新链锚表达式保留：(self.topBar ?: self.contentHeader)）
// ★Task414 MD3 bare 顶带（第 23 轮复诉④「md3上面的安全区依旧没有，反而fui
//   插件上面为什么有安全区」：bare 无头带 = 主页网格/右栏几乎贴状态栏，fui
//   navigationview 有 64pt 头带 = 顶部口径不一致；本带对齐 fui：状态栏区
//   surface 色全出血 + 头带 64（大标题 + 胶囊同行），容器自带下起，页内容
//   不再钻状态栏；胶囊入带右上 = 不再压主页右栏顶卡）
@property(nonatomic, strong) UIView *bareHeaderView;                  // bare 顶带（状态栏区+64 呼吸带）
@property(nonatomic, strong) UILabel *bareTitleLabel;                 // bare 顶带大标题（fui headerTitle 同源口径）
// ★Task429：ZL2 页背景层（8.3；仅背景挂载区域消费，两骨架共用内容宿主）
@property(nonatomic, strong) ZL2BackgroundHost *ame429_backgroundHost;
@end

@implementation ZL2ShellViewController

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if (self) {
        _childCache = [NSMutableDictionary dictionary];
        _currentIndex = -1;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];

    // ★ Task349：壁纸描边字体（Task227/232 全局 setText:/drawTextInRect: 交换）
    //   视图树级豁免。装机 IMG_0522 实锤：hasBackground 设备上 ZL2 全壳满屏
    //   白底黑边幽灵字（含大标题/卡片/胶囊）——根因 = ZL2 壳所有表面均为
    //   ZL2Theme 不透明动态色（dynamicProvider alpha=1.0），壁纸从不在壳内容
    //   后透出，描边可读性处理在 opaque 面上纯损耗。树级豁免（ame230
    //   superview 链上溯 16 层）覆盖壳内全部页面/卡片/单元格；欢迎向导
    //   （Task230）/文件浏览器（Task229）/模态呈现页（独立窗口容器）既有
    //   豁免链不受影响。
    ame230_setViewTreeStrokeExempt(self.view, YES);

    // 7.0-UI-11：版本索引服务预热（远程清单在途拉取，启动链查找免竞态等待）
    [[ZL2VersionIndex sharedIndex] warmUp];

    // ★ Task347：结构令牌链保留（插件覆盖 + Task346 根重建杠杆 = 换蓝图
    //   即时整壳重建）；★Task477 导航合并退役：navigationview 抽屉（一代）
    //   消费面退役 = bare 唯一骨架，令牌值仅存日志语义。
    self.ame347_navMode = [[ZL2Theme ame347_shellLayout]
                           isEqualToString:@"navigationview"];
    if (self.ame347_navMode) {
        NSLog(@"[Task477] navigationview token present but drawer retired -- bare shell enforced");
    }
    [self ame_buildBareShell];   // ★ Task378：顶栏骨架退役 = 无栏 bare 壳；★Task477 唯一骨架

    // ★Task429：ZL2 页背景挂载（8.3——两骨架共用内容宿主 self.container，
    //   骨架分支后单点安装；详见 ame429_installBackgroundHost 注记）
    [self ame429_installBackgroundHost];
    // ★Task452（「打开即闪退」判读轮）：首帧链分段签名——stderr 无缓冲 +
    //   管道读取线程毫秒级排水（Task441 判例 N+28 取证口径），装机死亡点
    //   被夹在 [背景宿主安装 → 主页构建 → autoCheck] 静默带内；逐段落
    //   NSLog 签名，下轮日志尾最后一签名即钉出崩段（Task171 证据链同型）。
    NSLog(@"[Task452] open: shell background-host installed (nav=%d)", (int)self.ame347_navMode);

    // 右上角快捷入口已移除；主页右栏是五个入口的唯一位置。

    // 通知契约：旧启动链（ShowHomePage）+ FCL 账户契约（ShowAccountManager）
    // + ZL2 程序化切页（ZL2ShellNavigate）+ 任务胶囊 / nav 栈深跟随
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_showHome)
                                                 name:@"ShowHomePage"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_showAccount)
                                                 name:@"ShowAccountManager"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_onNavigate:)
                                                 name:ZL2ShellNavigateNotification
                                               object:nil];
    // 7.0-UI-13：版本详情打开契约（主页版本卡长按 / 版本列表页设置钮经壳统一接线，
    // 页面间零直连——ZL2 壳导航总线同口径）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_openVersionDetail:)
                                                 name:@"ZL2OpenVersionDetail"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_taskManagerDidChange:)
                                                 name:DownloadTaskManagerDidUpdateTaskNotification
                                               object:nil];
    // ★ Task378 r2：目录瓦片接线（主页右侧栏快航 → 文件浏览器 PageSheet）——
    //   原顶栏文件夹项 ame_openFileManagerSheet 的壳统一承接通道，smoke 预览
    //   窄链接面零新增类依赖（主页不直连 FolderBrowserViewController）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame_openFileManagerSheet)
                                                 name:@"ZL2ShellOpenFileManager"
                                               object:nil];

    [self showPageAtIndex:0];
    NSLog(@"[Task452] open: shell viewDidLoad done (index=%ld)", (long)self.currentIndex);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 任务胶囊状态补刷（spec：viewWillAppear 刷新）+ 顶栏态自愈（跨屏返回等）
    [self ame_refreshTaskPill];
    [self ame_refreshTopBarStateAnimated:NO];
}

// ★Task428：8.2 节日彩蛋复活——主壳就绪点挂窗。当日有节日且偏好
//   general.festival_effects（BOOL 默认 YES）开启时，window 顶层挂
//   ZL2FestivalEffects 粒子层（雪/雨/烟花/萤火/爱心/蝙蝠；挂载幂等，
//   重复 appear 零叠加）；顶部问候横幅另行走 ame428_presentFestivalGreeting
//   （不受特效开关影响——问候是文案层，特效开关只管粒子）。
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // ★Task452：首帧完成签名（进程级一次）——装机日志见此行 = 首帧已落地，
    //   崩段在后帧/前台链（Task289 frost/节日彩蛋/前景激活）。
    static BOOL ame452_appearMarked = NO;
    if (!ame452_appearMarked) {
        ame452_appearMarked = YES;
        NSLog(@"[Task452] open: home did appear (first frame landed)");
    }
    [ZL2FestivalEffects attachToWindow:self.view.window];
    [self ame428_presentFestivalGreeting];
}

// ★Task428：游戏换根（ios_uikit_bridge 同步换根 SurfaceViewController）时
//   粒子视图是 window 直接子视图、不会随旧根视图移除——必须在此显式摘除，
//   否则雪/烟花会飘进游戏画面。全屏模态覆盖同样触发本回调（粒子暂停，
//   dismiss 后 viewDidAppear 重新幂等挂回）。
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [ZL2FestivalEffects detach];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ★ Task379：外观 trait 变化 → 插件事件面 appearance.changed（fluent 色板
//   实时跟随系统明暗的桥；窗口 overrideUserInterfaceStyle 偏好切换同样
//   经此传播——root VC trait 随窗口联动）
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    // ★ Task379 r1：iOS 17 trait 注册 API 世代的老外观差异比较选择器在
    //   Xcode 26.3 / iPhoneOS26.2 SDK 下 "no visible @interface"（CI run
    //   41445634927 + 41445630882 双红实锤）——改 userInterfaceStyle 直比
    //   （iOS 12 稳定面，语义等价：仅明暗变化即发；previous 为 nil 不误发）。
    if (!previousTraitCollection) return;
    UIUserInterfaceStyle ame379_style = self.traitCollection.userInterfaceStyle;
    if (ame379_style == previousTraitCollection.userInterfaceStyle) return;
    BOOL ame379_dark = (ame379_style == UIUserInterfaceStyleDark);
    // ★ Task380：进程级明暗去重——Task346 根重建杠杆在每次令牌落表后整壳
    //   重建，新建壳 VC 首次 trait 解析同样走本回调（style 与自身 previous
    //   不同、但与进程上一次广播值相同），事件面被同值事件灌满 → JS 重应用
    //   令牌 → 再触发重建 → 无限反馈环（装机 latestlog 00:10:37 起 ~10 次/秒
    //   实锤：全界面拆建中完全不可点击）。根修 = 广播前比对进程级上次广播
    //   值，同值不重播；真翻转（系统明暗切换/外观偏好切换）值必不同，不受
    //   影响。与 JS 侧 v2.5.1 去重、ZL2Theme 重建冷却构成三层防回环。
    static BOOL ame380_hasLastDark = NO;
    static BOOL ame380_lastDark = NO;
    if (ame380_hasLastDark && ame379_dark == ame380_lastDark) return;
    ame380_hasLastDark = YES;
    ame380_lastDark = ame379_dark;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"AmeAppearanceTraitChanged"
                                                        object:nil
                                                      userInfo:@{@"dark": @(ame379_dark)}];
    NSLog(@"[Ame380] appearance broadcast dark=%d (dedup armed)", ame379_dark);
}

#pragma mark - ★ Task378 bare 壳构建（顶栏退役：容器直铺 + 子页自带导航栏）

// 顶栏（ZL2 TopBar：返回/主页左簇 + 标题 + 任务胶囊 + RailItem×5）整体退役：
//   · 五入口按钮迁移至主页右侧栏顶部（ZL2HomeViewController quickNav 瓦片，
//     22pt 图标 ×2.5 = 55pt，第一行 文件/下载/设置、第二行 联机/AI）；
//   · 任务胶囊随顶栏退役（下载进度由下载页/主页侧栏状态行承担）；
//   · 标题与返回由各子页 UINavigationController 自带导航栏承担（7.0-UI-8
//     既有约定：子页 push 层系统返回栏本就独立工作，顶栏返回仅为辅助手势）；
//   · 主页内部自理 safeArea（ActionMenu/内容区挂 safe 锚）；bare 容器全屏直铺。
- (void)ame_buildBareShell {
    // ★Task414 顶带（对齐 fui contentHeader 口径）：状态栏区 surface 全出血
    //   + 64pt 呼吸带（大标题行 + 右上胶囊同行），容器自带下起
    self.bareHeaderView = [[UIView alloc] init];
    self.bareHeaderView.translatesAutoresizingMaskIntoConstraints = NO;
    self.bareHeaderView.backgroundColor = [ZL2Theme surface];
    [self.view addSubview:self.bareHeaderView];

    self.bareTitleLabel = [[UILabel alloc] init];
    self.bareTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.bareTitleLabel.font = [ZL2Theme fontHeadline];
    self.bareTitleLabel.textColor = [ZL2Theme onSurface];
    self.bareTitleLabel.numberOfLines = 1;
    self.bareTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.bareHeaderView addSubview:self.bareTitleLabel];

    self.container = [[UIView alloc] init];
    self.container.translatesAutoresizingMaskIntoConstraints = NO;
    self.container.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.container];

    self.containerTrailing = [self.container.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.bareHeaderView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.bareHeaderView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bareHeaderView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        // 与 nav 骨架 contentHeader 同款 safeArea 延伸语义：头底 = safeArea 顶 + 64
        [self.bareHeaderView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                                                        constant:ZL2ShellHeaderHeight],
        // 大标题（fui headerTitle 同源几何：centerY = safeArea 顶 + 32）
        [self.bareTitleLabel.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16.0],
        [self.bareTitleLabel.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:32.0],
        // ★Task477 簇退役：标题尾缘让位改安全区右缘（原簇 leading 锚拆除）
        [self.bareTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16.0],

        [self.container.topAnchor constraintEqualToAnchor:self.bareHeaderView.bottomAnchor],
        [self.container.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        self.containerTrailing,
        [self.container.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

#pragma mark - ★Task429 8.3 ZL2 页背景挂载（唯一背景挂载区域）

// 挂载方案：ZL2BackgroundHost 插入内容宿主 self.container 最底层
//（insertSubview:atIndex:0——子页 attach 经 addSubview 恒在其上），读
// BackgroundManager 既有管线：壁纸 Task223 降采样直取 / 透明度 uiOpacity /
// 毛玻璃 blurIntensity 三令牌零新键；可见性经 Task111 透明化管线
//（makeViewControllerTransparent:，hasBackground 守卫幂等）透出壳层树。
// 首装即刷（含当前子页 attach 前的壳层树），此后壁纸/效果变化由宿主
// 自身的双通知刷新面接管（Ame223WallpaperChanged / BackgroundUIEffectChanged）。
- (void)ame429_installBackgroundHost {
    if (self.container == nil) return;   // 骨架未建防御守卫
    self.ame429_backgroundHost = [[ZL2BackgroundHost alloc] initWithFrame:CGRectZero];
    [self.container insertSubview:self.ame429_backgroundHost atIndex:0];
    [NSLayoutConstraint activateConstraints:@[
        [self.ame429_backgroundHost.topAnchor constraintEqualToAnchor:self.container.topAnchor],
        [self.ame429_backgroundHost.leadingAnchor constraintEqualToAnchor:self.container.leadingAnchor],
        [self.ame429_backgroundHost.trailingAnchor constraintEqualToAnchor:self.container.trailingAnchor],
        [self.ame429_backgroundHost.bottomAnchor constraintEqualToAnchor:self.container.bottomAnchor],
    ]];
    [self.ame429_backgroundHost ame429_refreshWithOwnerViewController:self];
}

- (void)ame428_openTouchControllerSheet {
    TouchControllerPreferencesViewController *ame428_vc = [[TouchControllerPreferencesViewController alloc] init];
    UINavigationController *ame428_nav = [[UINavigationController alloc] initWithRootViewController:ame428_vc];
    ame428_nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:ame428_nav animated:YES completion:nil];
}
#pragma mark - 通知

- (void)ame_showHome {
    [self showPageAtIndex:0];
}

// 7.0-UI-13：版本详情打开（userInfo[@"profile"] = 实例名；当前活动 nav 上 push）
- (void)ame_openVersionDetail:(NSNotification *)note {
    NSString *profile = [[note userInfo] objectForKey:@"profile"];
    if (![profile isKindOfClass:[NSString class]] || profile.length == 0) return;
    UINavigationController *nav = [self ame_currentNav];
    if (!nav) return;
    ZL2VersionDetailViewController *vc =
        [[ZL2VersionDetailViewController alloc] initWithProfileName:profile];
    [nav pushViewController:vc animated:YES];
}

- (void)ame_showAccount {
    [self showPageAtIndex:3];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2AccountsRequestAdd"
                                                            object:nil];
    });
}

- (void)ame_onNavigate:(NSNotification *)note {
    NSInteger index = [note.userInfo[@"index"] integerValue];
    [self showPageAtIndex:index];
}

// manager 投递线程不定（addObserver:selector: 同步回调），统一回主线程刷胶囊
- (void)ame_taskManagerDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ame_refreshTaskPill];
    });
}

// 仅当前子 nav 的栈变化参与顶栏刷新（跨页导航不误触）
- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (navigationController != [self ame_currentNav]) return;
    [self ame_refreshTopBarStateAnimated:animated];
}

#pragma mark - 文件浏览器（顶栏文件夹钮 = ZL2 OpenFileManager 对应）

- (void)ame_openFileManagerSheet {
    const char *env = getenv("POJAV_GAME_DIR");
    NSString *gameDir = env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
    UINavigationController *nav = [FolderBrowserViewController wrappedControllerForPath:gameDir];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    UIViewController *presenter = self.presentedViewController ?: self;
    [presenter presentViewController:nav animated:YES completion:nil];
}

#pragma mark - 页面切换

- (void)showPageAtIndex:(NSInteger)index {
    if (index < 0 || index > 6) return; // Task318：6 = AI 助手（顶栏第 5 项）
    if (index == self.currentIndex) {
        [self ame_refreshTopBarStateAnimated:NO];  // 幂等自愈
        return;
    }

    UIViewController *next = [self ame_childForIndex:index];
    UIViewController *prev = [self ame_currentChild];

    [self ame_attachChildIfNeeded:next];
    // ★Task429：子页 attach 后重放背景刷新（新子页 viewDidLoad 落不透明基色
    //   会盖住背景层；幂等重放经 Task111 hasBackground 守卫把基色透出——
    //   宿主刷新面含透明化管线应用，背景缺席时为对称还原，零视觉变化）
    [self.ame429_backgroundHost ame429_refreshWithOwnerViewController:self];

    // ★Task405 退役：0d97c34 的「主页右栏提升到壳层常驻」整块拆除——提取后
    // actionMenu 脱离主页层级，长按换边（ame_applySideConstraintsAnimated:）
    // 会对已不在主页的 menu 与 self.view 重建跨层级约束，与壳层 containerTrailing
    // 正面冲突 = 「切换边有bug」实体；且常驻使右栏在全部子页可见 = 「切页面
    // 不会隐藏」回归。右栏回归主页私有后，切页随主页视图隐藏，换边在主页内
    // 自治（双支线约束 + 持久化 + 长按手势全部原样）。

    void (^apply)(void) = ^{
        prev.view.hidden = YES;
        next.view.hidden = NO;
    };
    // ★ Task395：切页 CrossDissolve 补 reduceMotion 尊重（辅助功能“减弱
    //   动态效果”开启时直落无动画，其余场景 0.24s 淡入淡出）
    // ★Task429：切页升级 fade+offset（全局杠杆 ①的壳层接线面）——prev 淡出
    //   +下移 8pt、next alpha 0→1 + 上移 8pt 归位（kAme429MotionStandard 档）。
    //   降级路径退回原 crossDissolve（Task395 语义原样保留）：reduceMotion
    //   或页面未挂窗时走旧路。入场页 hidden 同步翻开（防竞态）；退场页保持
    //   可见随动画淡出，completion 才补藏——补藏带 ame_currentChild 复核
    //   （快速连点换页后，旧批次的 completion 不误藏当前页）；入场/退场只动
    //   alpha 与 transform（与自动布局正交，缓存页复位零残留）。
    BOOL ame395_animate = !UIAccessibilityIsReduceMotionEnabled();  // C 函数形态（同上，CI 实锤）
    if (prev && prev.view.superview && ame395_animate && next.view.superview) {
        // 入场页先行可见（同步）；退场页保持可见随动画淡出，完成时再藏——
        // hidden 补藏带 ame_currentChild 复核（中途连点换页的旧批次不藏当前页）
        next.view.hidden = NO;
        next.view.alpha = 0.0;
        next.view.transform = CGAffineTransformMakeTranslation(0.0, 8.0);
        prev.view.alpha = 1.0;
        prev.view.transform = CGAffineTransformIdentity;
        __weak typeof(self) weakSelf = self;
        UIViewController *ame429_prev = prev;
        [UIView animateWithDuration:kAme429MotionStandard
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            next.view.alpha = 1.0;
            next.view.transform = CGAffineTransformIdentity;
            prev.view.alpha = 0.0;
            prev.view.transform = CGAffineTransformMakeTranslation(0.0, 8.0);
        } completion:^(BOOL finished) {
            // 复位缓存页（下次切回直显）；已被连点换页的旧批次才补藏
            ame429_prev.view.alpha = 1.0;
            ame429_prev.view.transform = CGAffineTransformIdentity;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && ame429_prev != [strongSelf ame_currentChild]) {
                ame429_prev.view.hidden = YES;
            }
        }];
    } else if (prev && prev.view.superview && ame395_animate) {
        [UIView transitionWithView:self.container
                          duration:ZL2ShellAnimateDuration
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:apply
                        completion:nil];
    } else {
        apply();
    }

    self.currentIndex = index;
    // ★Task432（移交⑥ 导航广播落地）：切页生效即广播 ZL2ShellNavigateNotification
    //   （既有常量 @selector 契约同字面量 @"ZL2ShellNavigate"，userInfo[@"index"] =
    //   @(index)，与 AmePluginBridge ui.nav / ZL2Home·Versions 程序化切页同口径）。
    //   此前侧边栏点按（rail item → showPageAtIndex）不广播，page.changed 事件面
    //   只覆盖主页瓦片/程序化切页 → fui 插件被迫 200ms 轮询自愈（Task431 移交⑤⑥）；
    //   本广播补齐事件面后，插件 v2.6.2 改订阅通知、轮询退役（保留一轮轻校验兜底）。
    //   幂等：同页重复切换在本方法顶部 index==currentIndex 早退，不重入此点；
    //   通知同步派发 ame_onNavigate 二次进入亦被同一早退拦截（自愈刷顶栏一次），
    //   无回环。
    [[NSNotificationCenter defaultCenter] postNotificationName:ZL2ShellNavigateNotification
                                                        object:nil
                                                      userInfo:@{@"index": @(index)}];
    [self ame_refreshTopBarStateAnimated:YES];
}

#pragma mark - 顶栏态（左簇显隐 / 返回钮 / RailItem 选中 / 标题）

- (NSString *)ame_titleForIndex:(NSInteger)index {
    if (index == 0) {
        // ★ Task390：主页标题 = 应用名「Prisma Ⅱ」（ZL2 时代 "ZalithLauncher"
        //   字面退役；窗格头同 CFBundleDisplayName 口径）
        return @"Prisma Ⅱ";
    }
    // 功能页文案（ZL2 顶栏标题映射表，7.0-UI-14 对齐）
    switch (index) {
        case 1: return localize(@"ame369.shell.tab.downloads", @"下载");
        case 2: return localize(@"ame369.shell.tab.versions", @"版本");
        case 3: return localize(@"ame369.shell.tab.accounts", @"账户");
        case 4: return localize(@"ame369.shell.tab.settings", @"设置");
        case 5: return localize(@"ame369.shell.tab.terracotta", @"Terracotta | 陶瓦联机");
        default: return @"";
    }
}


- (void)ame_refreshTopBarStateAnimated:(BOOL)animated {
    // ★Task477：nav/簇刷新面随一代/二代退役摘除——bare 顶带大标题唯一刷新
    //   （ame_titleForIndex 同源口径：主页 = 应用名，子页 = 页名）；
    //   子页返回走各 UINavigationController 系统返回栏（7.0-UI-8 既有约定）。
    if (self.bareTitleLabel) {
        self.bareTitleLabel.text = [self ame_titleForIndex:self.currentIndex];
    }
}

- (void)ame_popCurrentIfPossible {
    UINavigationController *nav = [self ame_currentNav];
    if (nav && nav.viewControllers.count > 1) {
        [nav popViewControllerAnimated:YES];
    }
}

#pragma mark - 任务胶囊

- (void)ame_refreshTaskPill {
    if (!self.taskPill) return;   // ★ Task378：bare 壳无顶栏 = 无任务胶囊（nav 骨架专属）
    if (!self.isViewLoaded) return;

    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    BOOL active = [manager hasActiveTasks];

    // 活动任务数（Downloading + Pending，ZL2DownloadViewController 同口径）+
    // 首个活动任务 progress（0~1；负值=未知 → 截 0）
    NSInteger count = 0;
    double progress = 0.0;
    if (active) {
        count = (NSInteger)[manager tasksWithStates:@[
            @(DownloadTaskStateDownloading),
            @(DownloadTaskStatePending),
        ]].count;
        for (DownloadTaskItem *item in [manager allTasks]) {
            if (item.state == DownloadTaskStateDownloading ||
                item.state == DownloadTaskStatePending) {
                progress = item.progress;
                break;
            }
        }
        if (progress < 0.0) progress = 0.0;
    }
    [self.taskPill ame_setProgress:progress count:count];

    BOOL visibleNow = !self.taskPill.hidden;
    if (visibleNow == active) return;  // 显隐未变：内容已刷新到位

    void (^apply)(void) = ^{
        self.taskPill.hidden = !active;
        self.taskPill.alpha = active ? 1.0 : 0.0;
        // ★ Task347：动画上下文按骨架择一（topbar / nav 内容区头）
        (self.topBar ?: self.contentHeader).layoutIfNeeded;
    };
    if ((self.topBar ?: self.contentHeader).window) {
        [UIView animateWithDuration:ZL2ShellAnimateDuration animations:apply];
    } else {
        apply();
    }
}

- (void)ame_openTaskProgress {
    // ZL2Home/ZL2Download 同款用法：遍历 allTasks 取第一个活动任务的 taskId
    // → 统一进度页（presentForTaskId: 自带同屏去重/替换）
    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    NSString *taskId = nil;
    for (DownloadTaskItem *item in [manager allTasks]) {
        if (item.state == DownloadTaskStateDownloading ||
            item.state == DownloadTaskStatePending) {
            taskId = item.taskId;
            break;
        }
    }
    if (taskId.length == 0) {
        taskId = [manager allTasks].firstObject.taskId;  // 兜底（hasActiveTasks 恒真时不可达）
    }
    if (taskId.length > 0) {
        [PLTaskProgressViewController presentForTaskId:taskId];
    }
}

#pragma mark - Child 管理（懒建缓存 + 首显 attach，7.0-UI-8/9 机制平移不变）

- (UIViewController *)ame_currentChild {
    if (self.currentIndex < 0) return nil;
    return self.childCache[@(self.currentIndex)];
}

- (UINavigationController *)ame_currentNav {
    if (self.currentIndex <= 0) return nil;  // 主页不包 nav
    UIViewController *child = self.childCache[@(self.currentIndex)];
    if ([child isKindOfClass:[UINavigationController class]]) {
        return (UINavigationController *)child;
    }
    return nil;
}

- (void)ame_attachChildIfNeeded:(UIViewController *)child {
    if (child.parentViewController == self) return;
    [self addChildViewController:child];
    child.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.container addSubview:child.view];
    [NSLayoutConstraint activateConstraints:@[
        [child.view.leadingAnchor constraintEqualToAnchor:self.container.leadingAnchor],
        [child.view.trailingAnchor constraintEqualToAnchor:self.container.trailingAnchor],
        [child.view.topAnchor constraintEqualToAnchor:self.container.topAnchor],
        [child.view.bottomAnchor constraintEqualToAnchor:self.container.bottomAnchor],
    ]];
    [child didMoveToParentViewController:self];
}

- (UIViewController *)ame_childForIndex:(NSInteger)index {
    UIViewController *cached = self.childCache[@(index)];
    if (cached) return cached;

    UIViewController *vc;
    switch (index) {
        case 0: {
            // 主页：ZL2 新写，单页无 push 需求（切页走通知契约），不包 nav
            vc = [[ZL2HomeViewController alloc] init];
            break;
        }
        case 1: {
            ZL2DownloadViewController *download = [[ZL2DownloadViewController alloc] init];
            vc = [[UINavigationController alloc] initWithRootViewController:download];
            break;
        }
        case 2: {
            ZL2VersionsViewController *versions = [[ZL2VersionsViewController alloc] init];
            vc = [[UINavigationController alloc] initWithRootViewController:versions];
            break;
        }
        case 3: {
            ZL2AccountsViewController *accounts = [[ZL2AccountsViewController alloc] init];
            vc = [[UINavigationController alloc] initWithRootViewController:accounts];
            break;
        }
        case 4: {
            ZL2SettingsViewController *settings = [[ZL2SettingsViewController alloc] init];
            vc = [[UINavigationController alloc] initWithRootViewController:settings];
            break;
        }
        case 5: {
            // 多人联机（ZL2 Multiplayer 入口；legacy FCL 式联机域承接）
            MultiplayerViewController *multiplayer =
                [[MultiplayerViewController alloc] initWithMode:MultiplayerVCModeLauncher];
            vc = [[UINavigationController alloc] initWithRootViewController:multiplayer];
            break;
        }
        case 6: {
            // AI 助手（Task318：7.0-UI-8 旧壳退役后入口恢复；1:1 旧壳 showAIPage
            //   判例 LauncherRootViewController L648-655：lastActiveSession + 包
            //   nav + prefersLargeTitles=NO；未配 Provider 时空态自带「去配置」引导）
            AIViewController *ai = [[AIViewController alloc]
                initWithSession:[[AiSessionStore sharedStore] lastActiveSession]];
            UINavigationController *aiNav =
                [[UINavigationController alloc] initWithRootViewController:ai];
            aiNav.navigationBar.prefersLargeTitles = NO;
            vc = aiNav;
            break;
        }
        default:
            return nil;
    }
    // 顶栏返回钮/标题跟随子 nav 栈深：UINavigationControllerDelegate 公开 API
    //（DidShow 通知常量在 SDK 非公开——CI 实证 undeclared，改走 delegate）
    // ★Task429：子 nav 转场接入 ZL2MotionTransition（全局杠杆 ①，一次接入
    //   下载/版本/账户/设置/联机/AI 六页全部 push/pop = 设置进出高频面）；
    //   delegate 位被转场器占用后，didShow 经 onDidShow 旁挂转发回壳层原
    //   消费方法（顶栏刷新语义不变；weak 防壳↔转场器保持环）。
    if ([vc isKindOfClass:[UINavigationController class]]) {
        __weak typeof(self) weakSelf = self;
        UINavigationController *ame429_nav = (UINavigationController *)vc;
        [ZL2MotionTransition installOnNavigationController:ame429_nav
                                                 onDidShow:^(UINavigationController *navVC, UIViewController *shown, BOOL animated) {
            [weakSelf navigationController:navVC didShowViewController:shown animated:animated];
        }];
    }
    self.childCache[@(index)] = vc;
    return vc;
}

// .h 契约零改动保留（harness/测试断言）：NavigationRail 已于 7.0-UI-10-b 退役
// 为顶栏，数值冻结为 ZL2RailView 同款（iPhone 88 / iPad 104）
+ (CGFloat)railWidthForSizeClass:(UIUserInterfaceIdiom)idiom {
    return (idiom == UIUserInterfaceIdiomPad) ? 104.0 : 88.0;
}

#pragma mark - ★Task428 8.2 节日问候横幅（顶部胶囊，自动消失）

// 进程级一次性哨兵：问候横幅每次冷启动只弹一次（Task346 根重建杠杆会整壳
// 重建换新壳实例，实例级哨兵会导致切主题/切语言后同一天二次弹幕）。
static BOOL sAme428GreetingShownThisLaunch = NO;

// ★Task428：当日有节日 → 顶部胶囊横幅（安全区下 8pt，ZL2Theme 令牌配色，
//   显示 localize(节日键)——键直接复用既有 i18n_str_324~340 问候文案零新增），
//   约 5 秒自动消失，出现/消失带 0.25s alpha 动画。壳层无既有顶部横幅/公告位
//   （Task378 顶栏退役后 bare/nav 两骨架顶部均为内容区头），自建胶囊横幅。
- (void)ame428_presentFestivalGreeting {
    if (sAme428GreetingShownThisLaunch) return;
    sAme428GreetingShownThisLaunch = YES;   // 非节日也置位：当日判定一次即足，避免每次 appear 重算
    NSString *festivalKey = [ZL2FestivalEffects todayFestivalKey];
    if (festivalKey.length == 0) return;

    UIView *capsule = [[UIView alloc] init];
    capsule.translatesAutoresizingMaskIntoConstraints = NO;
    capsule.backgroundColor = [ZL2Theme surfaceContainerHigh];
    capsule.layer.cornerRadius = [ZL2Theme radiusXL];   // 胶囊全圆（28 阶）
    capsule.layer.cornerCurve = kCACornerCurveContinuous;
    capsule.layer.shadowColor = [UIColor blackColor].CGColor;
    capsule.layer.shadowOpacity = 0.18;
    capsule.layer.shadowRadius = 12.0;
    capsule.layer.shadowOffset = CGSizeMake(0.0, 4.0);
    capsule.alpha = 0.0;                                 // 入场 0.25s 淡入

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = localize(festivalKey, nil);
    label.font = [ZL2Theme fontTitleMedium];
    label.textColor = [ZL2Theme onSurface];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;
    [capsule addSubview:label];
    [self.view addSubview:capsule];                      // 壳视图最顶（粒子层在 window 上、若开则飘于其上，无碍阅读）

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [capsule.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8.0],
        [capsule.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [capsule.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-32.0],
        [label.topAnchor constraintEqualToAnchor:capsule.topAnchor constant:10.0],
        [label.bottomAnchor constraintEqualToAnchor:capsule.bottomAnchor constant:-10.0],
        [label.leadingAnchor constraintEqualToAnchor:capsule.leadingAnchor constant:18.0],
        [label.trailingAnchor constraintEqualToAnchor:capsule.trailingAnchor constant:-18.0],
    ]];

    [UIView animateWithDuration:0.25 animations:^{
        capsule.alpha = 1.0;
    }];
    // 约 5 秒自动消失（0.25s 淡出后移除）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25
                         animations:^{ capsule.alpha = 0.0; }
                         completion:^(BOOL finished) { [capsule removeFromSuperview]; }];
    });
    NSLog(@"[Task428] festival greeting banner shown (key=%@)", festivalKey);
}

@end
