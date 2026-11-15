//
// ZL2SettingPages.m — ZL2 设置子页实现（7.0-UI-13-S 八屏；Task344 扩容十屏：+AI/+调试，旧设置 83 项全量迁移）
//
// 结构：每屏 = 垂直滚动 + 分组「连体卡片」（ZL2SettingCards 家族：组卡外
// 圆角 28 / 内圆角 4 / 组间 2pt / 行内 padding 16 / 行高 ≥56 / 底
// surfaceContainer）。底部「更多设置」Action 行 push 对应旧页，旧页长尾
// 功能全部可达（全逻辑兜底契约）。
//
// 八屏 → 真实偏好键映射（唯一事实源；读侧与旧页同一 API，写侧同一 set
// API，写后按旧页先例 post 对应刷新通知）：
//
// ① 渲染器屏
//   video.renderer                 渲染器（全局默认；getRendererKeys/Names
//                                  同一取值域；读前 ame142_migrateRendererStorage）
//   video.resolution               分辨率缩放 %（25–150；PLProfiles 回退链的
//                                  全局兜底键，SurfaceViewController Task159 口径）
//   video.fullscreen_airplay       全屏输出（外接显示器）
//   更多设置 → LauncherPreferencesViewController
//
// ② 游戏屏
//   profile["allocatedMemory"]     内存分配（当前实例；PLProfiles.selectedProfile
//                                  写 + save；滑条上限 = ame173_safeHeapCeilingMB
//                                  +512，ProfileSettings Task173 同款）
//   java.jvm_preset                JVM 预设（memory/normal/performance/custom；
//                                  Task255/256 单一事实源）
//   java.jvm_preset_custom_args    自定义 JVM 参数（预设=custom 时注入）
//   java.java_args                 JVM 启动参数（全局）
//   internal.isolated              版本隔离（实例 plist 键；写后 toggleIsolatedPref(NO)
//                                  重算应用——LauncherPreferences 既有契约）
//   更多设置 → LauncherPreferencesViewController
//
// ③ 控制屏（旧「触控设置」页顶层项，TouchControllerPreferencesViewController 同键族）
//   control.mod_touch_mode         虚拟按键 / 触控布局（★Task428 6.6 更名：
//                                  0 禁用/1 UDP/2 静态库；写入同
//                                  步 mod_touch_enable/mod_touch_user_off
//                                  哨兵 + java.env_variables UDP 环境变量
//                                  ——旧页 updateTouchControllerSetting 全链；
//                                  本组保持控制屏首组/首行）
//   control.mod_touch_vibrate_enable        震动反馈
//   control.mod_touch_vibrate_intensity     震动强度（1–3）
//   control.mod_touch_moveview_enable       移动视角
//   control.mod_touch_hide_controls         屏蔽启动器控件
//   general.gesture_tap_action              点击动作（int 0 左/1 右/2 无，默认 0）
//   general.gesture_longpress_action        长按动作（int 同上，默认 1）
//   general.gesture_longpress_delay         长按延迟（float 秒 0.2–1.0，默认 0.30）
//   general.gyro_invert_y                   反转 Y 轴（BOOL 默认 NO）
//   general.gyro_sample_rate                陀螺仪采样率（float Hz 5–50，默认 20）
//   general.gyro_smoothing                  陀螺仪平滑强度（int 0–100，默认 30）
//   ——★Task428 gesture_*/gyro_* 键名契约：并行工程师的运行时手势/陀螺仪
//     层按同名键读，逐字一致不可改
//   完整触控设置 → TouchControllerPreferencesViewController（写后 post
//   TouchControllerSettingsChanged——Task224 广播契约；落地页退役属后续任务）
//
// ④ 手柄屏（iOS 真实手柄键族；无造假开关）
//   control.controller_type        控制器风格（xbox/playstation）
//   control.default_gamepad_ctrl   手柄映射配置文件（编辑入口 → 旧页）
//   手柄映射配置 → LauncherPrefContCfgViewController
//
// ⑤ 启动器屏
//   general.ui_theme               深浅模式（dark/light/auto；写后 set
//                                  ui_theme_explicit + post UIThemeChanged——
//                                  旧页 Task161 显式选择契约）
//   general.app_language           应用语言（system + bundle 全部 .lproj；
//                                  写后 post AppLanguageChanged）
//   BackgroundManager.uiEffect     界面效果（毛玻璃/半透明；defaults 键
//                                  background_ui_effect；写后 refreshUIEffect
//                                  + post BackgroundUIEffectChanged）
//   BackgroundManager.uiOpacity    背景不透明度（0.1–1.0；写后 refreshUIEffect）
//   BackgroundManager.blurIntensity 背景模糊强度（0–1；写后 refreshUIEffect）
//   download.fileSource / download.assetSearchSource / download.assetDownloadSource
//   download.modLoaderSource       下载源策略（official_first/mirror_first/
//                                  speed_first；写后 PLMirrorCenter 测速跟上
//                                  ——mod_mirror 行 Task138 同款）
//   背景设置 → BackgroundSettingsViewController；壁纸画廊 →
//   BingWallpaperGalleryViewController；更多设置 → LauncherPreferences
//   ViewController（ui_layout 行不露出：ZL2 壳唯一）
//   ★Task428 新行：general.festival_effects 节日彩蛋（BOOL 默认 YES，
//   ZL2FestivalEffects 消费）；general.download_threads 下载并发数
//   （int 0=自动 16-64 自适应 / 8-64 手动）；「校验并补全游戏文件」入口 =
//   PLGameIntegrityService +sharedService/
//   runInteractiveVerifyAndRepairFromViewController:（运行时软链调用，
//   头文件由并行工程师实装）
//   ★Task428 注册注记（Setter 静默丢弃族——Task142/143/230/334 同判例）：
//   PLPreferences setObject: 只写已注册键。本轮八新键
//     general.download_threads=@(0)、general.gesture_tap_action=@(0)、
//     general.gesture_longpress_action=@(1)、
//     general.gesture_longpress_delay=@(0.30)、general.gyro_invert_y=@(NO)、
//     general.gyro_sample_rate=@(20.0)、general.gyro_smoothing=@(30)、
//     general.festival_effects=@(YES)
//   需在 PLPreferences.m defaultPrefForGlobal: 的 general 节注册
//   （该文件不在本任务写权内，注册面归并行工程师/主控合流）；注册前
//   写值会被静默丢弃，读侧缺键回退默认不受影响（本文件读全部已带
//   getPrefObject 判空默认链）。
//   ★Task429 新行：general.mirror_mode 下载镜像三态（int 默认 0；
//   0=自动（大陆 BMCLAPI 优先，Task428 4.1 大陆探测默认档语义）/
//   1=官方 / 2=手动 BMCLAPI；服务侧消费由镜像服务层接）；注册片段
//   scripts/task429_prefs_BC.json（Setter 静默丢弃族同判例）。
//   ★Task429 S1 新行：general.proxy_mode 下载代理三态（int 默认 0；
//   0=关 / 1=HTTP / 2=SOCKS5）+ general.proxy_host / general.proxy_port
//   （字符串承载，运行期按 1-65535 校验）。生效面：PLDownloadClient 会话
//   connectionProxyDictionary（HTTP 双键族）+ 游戏侧 AMETHYST_SOCKS5_PROXY
//   环境变量（与 MultiplayerManager 联机通道同键双通道一致，物化逻辑单一
//   事实源在 PLDownloadClient +ame429_s1_syncProxyEnvFromPrefs——本页各代理
//   行落值即调用）。注册片段 scripts/task429_prefs_S1.json（同判例）。
//
// ⑥ Java 管理屏（LauncherPrefManageJREViewController 同枚举口径）
//   java.java_homes                默认 Java（@0 字典按 tag：1_16_5_older/
//                                  1_17_newer/1_26_newer；"自动" = 删键回
//                                  getSelectedJavaHome 的 minVersion 搜索语义）
//   运行时枚举 = bundle + POJAV_HOME 的 java_runtimes/*（release 文件
//   JAVA_VERSION 解析，同旧页 javaVersionForPath）
//   执行 Jar 文件 = 文档选择器 → 守卫链 → 全屏模态 JavaGUIViewController
//   （7.0-UI-9-d 原样平移：requiredJavaVersion 解析 + getSelectedJavaHome
//   预检；模态专用页，禁裸 push）
//   完整 Java 管理 → LauncherPrefManageJREViewController（导入/删除）
//
// ⑦ 控制管理屏（Task77 custom.json 出厂默认）
//   control.default_ctrl           控制布局 json（$POJAV_HOME/controlmap/*.json
//                                  单选；恢复默认 = 写回 custom.json）
//   键位调整 → CustomControlsViewController（全屏画布编辑器，旧设置页
//   openChildPaneAtIndexPath 同款 nav 模态呈现）；控件仓库 →
//   ControlRepoViewController；更多设置 → LauncherPreferencesViewController
//
// ⑧ 关于屏（★Task428 9.1 四块 MD3 重做：关于启动器 / 鸣谢 / 依赖库 /
//   已加载插件——每块「区头标签 + 连体组卡」，不再 push 老关于页）
//   CFBundleShortVersionString / CFBundleVersion   版本号 / 构建号
//   ame415_buildTag（BuildTag.h）构建代际行（Task421 单一事实源同源字面量）
//   general.auto_update_check      启动时自动检查更新（Task125 语义）
//   检查更新 = 复用仓内既有 UpdateChecker 正式版检查（loading 弹窗 +
//   结果弹窗 + openReleasePage；报告 9.1「既有机制优先复用」口径）
//   项目主页（二代仓库）/ QQ 群（复制）/ 作者与团队（about.credits.*
//   原文复用，与 AboutViewController/README 口径一致）
//   鸣谢块：ZalithLauncher2/PojavLauncher/FCL/HMCL/Modrinth/CurseForge/
//   BMCLAPI/logshare.cn/PCL（名称+一句话定位；许可信息不确切不写）
//   依赖库块：AGENTS.md「核心依赖」权威清单八项
//   已加载插件块：AmePluginManager installedPluginIds + manifestForPlugin
//   （名称/版本/描述 + AmePluginRuntime isRunning 运行态；空态占位）
//
// i18n 纪律（task248 闸2 同源）：触发词方法调用（initWithTitle:/setTitle:
// 等）所在行禁带 CJK 字面量——行卡标题/副文本一律先构造后经 .title /
// .subtitle 属性赋值（属性点语法不在审计触发面）；有既有键的文案走
// localize()（键已核 en/zh-Hans/zh-CN/zh-Hant 四表齐备）；无键文案
// （ZL2 域口径）在属性行硬编码中文。
//

#import "ZL2SettingPages.h"
#import "ZL2SettingCards.h"
#import "ZL2Theme.h"
#import "ZL2M3Kit.h"
// localize 在 utils.h
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "PLMirrorCenter.h"
#import "PLDownloadClient.h"   // ★Task429 S1：代理行落值即物化（ame429_s1_syncProxyEnvFromPrefs 单一事实源）
#import "BackgroundManager.h"
#import "UpdateChecker.h"
#import "utils.h"

#import "LauncherPreferencesViewController.h"
#import "LauncherPrefGameDirViewController.h"  // Task316：游戏目录/实例选择器
#import "FileLayoutService.h"                 // Task316：跨启动器导入
#import "ZL2PluginListViewController.h"        // Task317：插件管理入口
#import "ZL2PluginRepoViewController.h"       // Task318：内置插件仓库入口
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "BackgroundSettingsViewController.h"
#import "BingWallpaperGalleryViewController.h"
#import "TouchControllerPreferencesViewController.h"
#import "LauncherPrefContCfgViewController.h"
#import "LauncherPrefManageJREViewController.h"
#import "ControlRepoViewController.h"
#import "CustomControlsViewController.h"
// ★Task428：关于页四块重做后不再 push 老关于页（AboutViewController 仍由
//   欢迎页/旧设置页入口可达），本文件对其的依赖解除，import 随 moreRow 退役
#import "JavaGUIViewController.h"
#import "AmePluginRuntime.h"   // Task327：插件贡献行渲染（allContributedRows/invokeRowTap）
#import "AmePluginManager.h"   // ★Task428：关于页已加载插件块（installedPluginIds/manifestForPlugin 枚举）
#import "BuildTag.h"           // ★Task428：关于页构建代际行（ame415_buildTag 单一事实源，直接用 static 字面量）
#import "LiquidGlassCompat.h"  // ★ Ame361：界面风格/缩放/透明度统一走 LGC 中枢（消费方同源）
#import "AI/AiSettings.h"      // ★ Ame361：AI 安全模式/Markdown 直连 AiSettings（NSUserDefaults 同源）

// ★ Task344 旧设置全量迁移：新增外部消费面
#import "AI/AIProviderConfigViewController.h"
#import "AI/AISessionListViewController.h"
#import "AI/AISystemPromptEditorViewController.h"
#import "StikDebugViewController.h"
#import "DataExportViewController.h"
#import "DataTransferService.h"
#import "CurseForgeAPIKeyViewController.h"
#import "CustomIconManager.h"

// ★Task429：主题动态取色（8.1 主题色板行 + CUSTOM 取色弹层入口）
#import "ZL2DynamicPalette.h"
#import "ZL2ThemeCustomSheet.h"

// ★Task428（1.2）：PLProfiles 新增类方法的本地前置声明（PLProfiles.h 不在
//   授权清单内；全局隔离档行消费翻转计算 + 下沉执行）。签名勿漂移。
@interface PLProfiles (Ame428Task428Settings)
+ (NSArray<NSDictionary *> *)ame428_computeGlobalFlipsFrom:(NSInteger)oldG to:(NSInteger)newG;
+ (NSDictionary *)ame428_executeIsolationDataMoveForVid:(NSString *)vid
                                            toIsolated:(BOOL)toIsolated reason:(NSString *)reason;
@end

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <stdlib.h>
#import <QuartzCore/QuartzCore.h>   // Task344：CAMetalLayer developerHUD 探测
#import "UIKit+hook.h"              // Task344：realUIIdiom（陀螺仪面 TV 闸）

// 内容列最大宽（照抄 ZL2SettingsViewController 旧枢纽：iPad 居中，iPhone 占满减边距）
static const CGFloat ame_pageContentMaxWidth = 520;

// 本启动器的 QQ 群号（AboutViewController ame217 同源字面量）
static NSString *ame217_qqGroupNumber(void) {
    return @"1126547426";
}

// JVM 预设键域（游戏屏 buildGroups/refreshState 共用）
static NSArray *ame_gamePagePresetKeys(void) {
    return @[@"memory", @"normal", @"performance", @"custom"];
}

// 安全取串：偏好对象 → NSString（nil/类型不符回退 fallback）
static NSString *ame_pages_stringOr(id value, NSString *fallback) {
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return value;
    }
    return fallback;
}

// Task344：游戏会话闸（旧 LauncherPreferencesViewController whenNotInGame
// 同口径——可见 VC 是 SurfaceViewController 即视为在游戏中；行卡不建灰禁
// 面板，直接不响应/不展示实时态）
static BOOL ame_pages_whenNotInGame(void) {
    UIViewController *visibleVC = currentVC();
    return ![visibleVC isKindOfClass:NSClassFromString(@"SurfaceViewController")];
}

// Task344：hex 颜色往返（旧 VC colorFromHexString/hexStringFromColor 平移）
static UIColor *ame_pages_colorFromHex(id hex) {
    if (![hex isKindOfClass:[NSString class]] || [(NSString *)hex length] == 0) return nil;
    NSString *clean = [(NSString *)hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&rgb]) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static NSString *ame_pages_hexFromColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"%02X%02X%02X",
            (unsigned)(r * 255), (unsigned)(g * 255), (unsigned)(b * 255)];
}

#pragma mark - 基类（滚动骨架 + 组卡装配 + push 助手）

@interface ZL2SettingPage ()
@property (nonatomic, strong, readwrite) UIStackView *groupsStack;
@property (nonatomic, strong) UILabel *pageTitleLabel;
@end

@implementation ZL2SettingPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.alwaysBounceVertical = YES;
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];

    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.alignment = UIStackViewAlignmentFill;
    contentStack.spacing = 16;
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:contentStack];

    // 页首大标题（M3 顶栏位，左对齐；self.title 由枢纽建页时给定）
    _pageTitleLabel = [[UILabel alloc] init];
    _pageTitleLabel.text = self.title ?: @"";
    _pageTitleLabel.font = [ZL2Theme fontTitleLarge];
    _pageTitleLabel.textColor = [ZL2Theme onSurface];
    _pageTitleLabel.numberOfLines = 1;
    _pageTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentStack addArrangedSubview:_pageTitleLabel];

    // 组卡栈：组间距 2pt（spec：连体组卡之间的呼吸缝）
    _groupsStack = [[UIStackView alloc] init];
    _groupsStack.axis = UILayoutConstraintAxisVertical;
    _groupsStack.alignment = UIStackViewAlignmentFill;
    _groupsStack.spacing = [ZL2SettingCardGroup preferredGroupSpacing];
    _groupsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [contentStack addArrangedSubview:_groupsStack];

    UILayoutGuide *contentLG = scrollView.contentLayoutGuide;
    UILayoutGuide *frameLG = scrollView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        // ★ Task412 安全区（第 20 轮复诉①「md3界面上面不会留点安全区域」）：
        //   顶入 safeArea = 大标题不再钻进状态栏带（IMG_0592「设置」实锤）；
        //   底/侧保持全出血（滚动到底仍是 edge-to-edge）
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [contentStack.topAnchor constraintEqualToAnchor:contentLG.topAnchor constant:24],
        [contentLG.bottomAnchor constraintGreaterThanOrEqualToAnchor:contentStack.bottomAnchor constant:24],
        [contentStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:contentLG.leadingAnchor constant:20],
        [contentStack.trailingAnchor constraintLessThanOrEqualToAnchor:contentLG.trailingAnchor constant:-20],
        [contentStack.centerXAnchor constraintEqualToAnchor:frameLG.centerXAnchor],
        [contentStack.widthAnchor constraintLessThanOrEqualToConstant:ame_pageContentMaxWidth],
    ]];
    // iPhone 占满可用宽（frame-40）；与 ≤520 上限联立后宽屏收敛到 520
    NSLayoutConstraint *fillWidth = [contentStack.widthAnchor constraintEqualToAnchor:frameLG.widthAnchor
                                                                             constant:-40];
    fillWidth.priority = 999;
    fillWidth.active = YES;

    [self ame_buildGroups];
}

- (void)ame_addGroup:(UIView *)group {
    [self.groupsStack addArrangedSubview:group];
}

- (void)ame_push:(UIViewController *)vc titled:(NSString *)fallbackTitle {
    if (!vc.title) vc.title = fallbackTitle;
    [self.navigationController pushViewController:vc animated:YES];
}

// ★ Task344：present 统一入口（原 ZL2LauncherSettingsPage 私有实现上移基类
//   ——新 AI/调试屏与游戏屏弹窗共用；壳内宿主导航可达，兼底顶栈 present）
- (void)ame_presentVC:(UIViewController *)vc {
    UIViewController *host = self.navigationController ?: self;
    while (host.presentedViewController) host = host.presentedViewController;
    [host presentViewController:vc animated:YES completion:nil];
}

- (void)ame_refreshState {
    // 子页按需覆写
}

- (void)ame_buildGroups {
    // 子页覆写
}

- (void)ame_rebuildGroups {
    for (UIView *group in [self.groupsStack.arrangedSubviews copy]) {
        [self.groupsStack removeArrangedSubview:group];
        [group removeFromSuperview];
    }
    [self ame_buildGroups];
}

@end

#pragma mark - ① 渲染器屏

@interface ZL2RendererSettingsPage ()
@property (nonatomic, strong) ZL2SettingRowList *rendererRow;
@property (nonatomic, strong) ZL2SettingRowSlider *resolutionRow;
@property (nonatomic, strong) ZL2SettingRowSwitch *fullscreenRow;
@end

@implementation ZL2RendererSettingsPage

- (void)ame_buildGroups {
    __weak typeof(self) weakSelf = self;

    // --- 组 1：渲染器 ---
    // 渲染器（全局默认；实例页可单独覆盖——Task150 分层语义）
    ame142_migrateRendererStorage();   // 读前迁移（幂等，Task142 分层归一）
    NSArray<NSString *> *rendererKeys = getRendererKeys(YES);
    NSArray<NSString *> *rendererNames = getRendererNames(YES);
    NSString *current = ame_pages_stringOr(getPrefObject(@"video.renderer"), @"auto");
    NSInteger currentIdx = (NSInteger)[rendererKeys indexOfObject:current];
    if (currentIdx < 0) currentIdx = (NSInteger)[rendererKeys indexOfObject:@"auto"];
    if (currentIdx < 0) currentIdx = 0;

    ZL2SettingRowList *rendererRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:rendererNames optionKeys:rendererKeys];
    rendererRow.title = localize(@"ame369.setpg.renderer_global.title", @"渲染器（全局默认）");
    rendererRow.subtitle = localize(@"ame369.setpg.renderer_global.subtitle", @"各实例可在版本设置的实例页单独覆盖");
    [rendererRow ame_reloadSelectedIndex:currentIdx];
    rendererRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= rendererKeys.count) return;
        setPrefString(@"video.renderer", rendererKeys[index]);
    };
    self.rendererRow = rendererRow;

    // 分辨率缩放（全局兜底键 video.resolution；各实例显式值优先——Task159）
    NSInteger resolution = (NSInteger)getPrefFloat(@"video.resolution");
    if (resolution <= 0) resolution = 100;
    ZL2SettingRowSlider *resolutionRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil
                                   minimum:25 maximum:150 suffix:@"%"];
    resolutionRow.title = localize(@"ame369.setpg.resolution_scale", @"分辨率缩放");
    resolutionRow.subtitle = localize(@"ame369.setpg.resolution_scale.subtitle", @"渲染分辨率百分比（各实例可单独覆盖）");
    [resolutionRow ame_setValue:resolution];
    resolutionRow.onValueChanged = ^(NSInteger value) {
        setPrefFloat(@"video.resolution", (float)value);
    };
    self.resolutionRow = resolutionRow;

    // 全屏输出（外接显示器；video.fullscreen_airplay 出厂默认 YES）
    id fullscreenRaw = getPrefObject(@"video.fullscreen_airplay");
    BOOL fullscreenOn = fullscreenRaw ? [fullscreenRaw boolValue] : YES;
    ZL2SettingRowSwitch *fullscreenRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    fullscreenRow.title = localize(@"ame369.setpg.fullscreen_external", @"全屏输出（外接显示器）");
    fullscreenRow.subtitle = localize(@"ame369.setpg.fullscreen_external.subtitle", @"连接外接屏幕时以全屏显示游戏画面");
    [fullscreenRow ame_setOn:fullscreenOn];
    fullscreenRow.onToggle = ^(BOOL on) {
        setPrefBool(@"video.fullscreen_airplay", on);
    };
    self.fullscreenRow = fullscreenRow;

    ZL2SettingCardGroup *group1 = [[ZL2SettingCardGroup alloc] init];
    [group1 ame_addRows:@[rendererRow, resolutionRow, fullscreenRow]];
    [self ame_addGroup:group1];

    // ── ★ Task344 旧设置全量迁移：video 分区渲染增强四项 ──
    ZL2SettingCardGroup *videoGroup = [[ZL2SettingCardGroup alloc] init];
    // FSR 档位（video.fsr1_setting，0-4 五档；Task78 补齐 Performance 档）
    NSArray<NSString *> *fsrKeys = @[@"0", @"1", @"2", @"3", @"4"];
    NSArray<NSString *> *fsrNames = @[
        localize(@"preference.title.mg_fsr1_setting-0", nil),
        localize(@"preference.title.mg_fsr1_setting-1", nil),
        localize(@"preference.title.mg_fsr1_setting-2", nil),
        localize(@"preference.title.mg_fsr1_setting-3", nil),
        localize(@"preference.title.mg_fsr1_setting-4", nil),
    ];
    ZL2SettingRowList *fsrRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:fsrNames optionKeys:fsrKeys];
    fsrRow.title = localize(@"preference.title.fsr1_setting", nil);
    fsrRow.subtitle = localize(@"preference.detail.fsr1_setting", nil);
    // ★ Ame361：存储键重映射 mobileglues.*（旧页 Task83 同款——消费方
    //   JavaLauncher/MobileGlues 读 mobileglues.fsr1_setting；写错段
    //   video.fsr1_setting 未注册被静默丢弃 = FSR 档位不生效根因）。
    //   注册表默认为 NSNumber（@(0)），双态解析（旧页 ame130 同款）：
    //   NSString 直用 / NSNumber stringValue / nil 回退出厂默认。
    id ame361_fsrRaw = getPrefObject(@"mobileglues.fsr1_setting");
    NSString *ame361_fsrVal = [ame361_fsrRaw isKindOfClass:[NSString class]]
        ? ame361_fsrRaw
        : ([ame361_fsrRaw isKindOfClass:[NSNumber class]] ? [(NSNumber *)ame361_fsrRaw stringValue] : nil);
    [fsrRow ame_reloadSelectedIndex:(NSInteger)[fsrKeys indexOfObject:
        ame361_fsrVal ?: @"0"]];
    fsrRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= fsrKeys.count) return;
        setPrefString(@"mobileglues.fsr1_setting", fsrKeys[index]);
    };
    // RCAS 锐化（video.fsr_rcas_sharpness，-1/0.1..1 七档）
    NSArray<NSString *> *rcasKeys = @[@"-1", @"0.1", @"0.2", @"0.3", @"0.5", @"0.7", @"1"];
    NSMutableArray<NSString *> *rcasNames = [NSMutableArray array];
    for (NSUInteger ri = 0; ri < rcasKeys.count; ri++) {
        [rcasNames addObject:localize(
            [NSString stringWithFormat:@"preference.title.mg_fsr_rcas-%@", @(ri)], nil)];
    }
    ZL2SettingRowList *rcasRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:rcasNames optionKeys:rcasKeys];
    rcasRow.title = localize(@"preference.title.fsr_rcas_sharpness", nil);
    rcasRow.subtitle = localize(@"preference.detail.fsr_rcas_sharpness", nil);
    // ★ Ame361：同款重映射 mobileglues.fsr_rcas_sharpness（旧页 Task130；
    //   注册默认 @0.2 为 NSNumber，双态解析同上）
    id ame361_rcasRaw = getPrefObject(@"mobileglues.fsr_rcas_sharpness");
    NSString *ame361_rcasVal = [ame361_rcasRaw isKindOfClass:[NSString class]]
        ? ame361_rcasRaw
        : ([ame361_rcasRaw isKindOfClass:[NSNumber class]] ? [(NSNumber *)ame361_rcasRaw stringValue] : nil);
    [rcasRow ame_reloadSelectedIndex:(NSInteger)[rcasKeys indexOfObject:
        ame361_rcasVal ?: @"0.2"]];
    rcasRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= rcasKeys.count) return;
        setPrefString(@"mobileglues.fsr_rcas_sharpness", rcasKeys[index]);
    };
    // 垂直同步禁用
    ZL2SettingRowSwitch *vsyncRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    vsyncRow.title = localize(@"preference.title.disable_game_vsync", nil);
    vsyncRow.subtitle = localize(@"preference.detail.disable_game_vsync", nil);
    [vsyncRow ame_setOn:getPrefBool(@"video.disable_game_vsync")];
    vsyncRow.onToggle = ^(BOOL on) {
        setPrefBool(@"video.disable_game_vsync", on);
    };
    // 性能 HUD（仅 Metal developerHUD 可用设备展示）
    ZL2SettingRowSwitch *hudRow = nil;
    if ([CAMetalLayer instancesRespondToSelector:@selector(developerHUDProperties)]) {
        hudRow = [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
        hudRow.title = localize(@"preference.title.performance_hud", nil);
        hudRow.subtitle = localize(@"preference.detail.performance_hud", nil);
        [hudRow ame_setOn:getPrefBool(@"video.performance_hud")];
        hudRow.onToggle = ^(BOOL on) {
            setPrefBool(@"video.performance_hud", on);
        };
        [videoGroup ame_addRows:@[fsrRow, rcasRow, vsyncRow, hudRow]];
    } else {
        [videoGroup ame_addRows:@[fsrRow, rcasRow, vsyncRow]];
    }
    [self ame_addGroup:videoGroup];

    // ── ★ Task344 旧设置全量迁移：MobileGlues 高级九项 ──
    ZL2SettingCardGroup *mgGroup = [[ZL2SettingCardGroup alloc] init];
    // 渲染后端（getRendererFamilyKeys/Names 与旧页同取值域）
    NSArray<NSString *> *familyKeys = getRendererFamilyKeys();
    NSArray<NSString *> *familyNames = getRendererFamilyNames();
    ZL2SettingRowList *backendRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:familyNames optionKeys:familyKeys];
    backendRow.title = localize(@"preference.title.renderer_backend", nil);
    backendRow.subtitle = localize(@"preference.detail.renderer_backend", nil);
    [backendRow ame_reloadSelectedIndex:(NSInteger)[familyKeys indexOfObject:
        ame_pages_stringOr(getPrefObject(@"mobileglues.renderer_backend"), @"auto")]];
    backendRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= familyKeys.count) return;
        setPrefString(@"mobileglues.renderer_backend", familyKeys[index]);
    };
    [mgGroup ame_addRow:backendRow];
    // GL 无错误模式（0/1/2 三档）
    NSArray<NSString *> *noErrKeys = @[@"0", @"1", @"2"];
    NSArray<NSString *> *noErrNames = @[
        localize(@"preference.title.mg_enable_no_error-0", nil),
        localize(@"preference.title.mg_enable_no_error-1", nil),
        localize(@"preference.title.mg_enable_no_error-2", nil),
    ];
    ZL2SettingRowList *noErrRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:noErrNames optionKeys:noErrKeys];
    noErrRow.title = localize(@"preference.title.enable_no_error", nil);
    noErrRow.subtitle = localize(@"preference.detail.enable_no_error", nil);
    [noErrRow ame_reloadSelectedIndex:(NSInteger)[noErrKeys indexOfObject:
        ame_pages_stringOr(getPrefObject(@"mobileglues.enable_no_error"), @"0")]];
    noErrRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= noErrKeys.count) return;
        setPrefString(@"mobileglues.enable_no_error", noErrKeys[index]);
    };
    [mgGroup ame_addRow:noErrRow];
    // 扩展开关三件
    ZL2SettingRowSwitch *timerQueryRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    timerQueryRow.title = localize(@"preference.title.enable_ext_timer_query", nil);
    timerQueryRow.subtitle = localize(@"preference.detail.enable_ext_timer_query", nil);
    [timerQueryRow ame_setOn:getPrefBool(@"mobileglues.enable_ext_timer_query")];
    timerQueryRow.onToggle = ^(BOOL on) {
        setPrefBool(@"mobileglues.enable_ext_timer_query", on);
    };
    ZL2SettingRowSwitch *computeRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    computeRow.title = localize(@"preference.title.enable_ext_compute_shader", nil);
    computeRow.subtitle = localize(@"preference.detail.enable_ext_compute_shader", nil);
    [computeRow ame_setOn:getPrefBool(@"mobileglues.enable_ext_compute_shader")];
    computeRow.onToggle = ^(BOOL on) {
        setPrefBool(@"mobileglues.enable_ext_compute_shader", on);
    };
    ZL2SettingRowSwitch *dsaRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    dsaRow.title = localize(@"preference.title.enable_ext_direct_state_access", nil);
    dsaRow.subtitle = localize(@"preference.detail.enable_ext_direct_state_access", nil);
    [dsaRow ame_setOn:getPrefBool(@"mobileglues.enable_ext_direct_state_access")];
    dsaRow.onToggle = ^(BOOL on) {
        setPrefBool(@"mobileglues.enable_ext_direct_state_access", on);
    };
    [mgGroup ame_addRows:@[timerQueryRow, computeRow, dsaRow]];
    // GLSL 缓存上限（0-256MB 滑条）
    ZL2SettingRowSlider *glslRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil
                                   minimum:0 maximum:256 suffix:@"MB"];
    glslRow.title = localize(@"preference.title.max_glsl_cache_size", nil);
    glslRow.subtitle = localize(@"preference.detail.max_glsl_cache_size", nil);
    [glslRow ame_setValue:(NSInteger)getPrefFloat(@"mobileglues.max_glsl_cache_size")];
    glslRow.onValueChanged = ^(NSInteger value) {
        setPrefFloat(@"mobileglues.max_glsl_cache_size", (float)value);
    };
    [mgGroup ame_addRow:glslRow];
    // 多重绘制模式（0/1/2）
    NSArray<NSString *> *mdKeys = @[@"0", @"1", @"2"];
    NSArray<NSString *> *mdNames = @[
        localize(@"preference.title.mg_multidraw_mode-0", nil),
        localize(@"preference.title.mg_multidraw_mode-1", nil),
        localize(@"preference.title.mg_multidraw_mode-2", nil),
    ];
    ZL2SettingRowList *mdRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:mdNames optionKeys:mdKeys];
    mdRow.title = localize(@"preference.title.multidraw_mode", nil);
    mdRow.subtitle = localize(@"preference.detail.multidraw_mode", nil);
    [mdRow ame_reloadSelectedIndex:(NSInteger)[mdKeys indexOfObject:
        ame_pages_stringOr(getPrefObject(@"mobileglues.multidraw_mode"), @"0")]];
    mdRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= mdKeys.count) return;
        setPrefString(@"mobileglues.multidraw_mode", mdKeys[index]);
    };
    [mgGroup ame_addRow:mdRow];
    // ANGLE 深度清除修正
    ZL2SettingRowSwitch *angleRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    angleRow.title = localize(@"preference.title.angle_depth_clear_fix_mode", nil);
    angleRow.subtitle = localize(@"preference.detail.angle_depth_clear_fix_mode", nil);
    [angleRow ame_setOn:getPrefBool(@"mobileglues.angle_depth_clear_fix_mode")];
    angleRow.onToggle = ^(BOOL on) {
        setPrefBool(@"mobileglues.angle_depth_clear_fix_mode", on);
    };
    [mgGroup ame_addRow:angleRow];
    // 自定义 GL 版本（0=关闭 + 4.0..4.6）
    NSArray<NSString *> *glvKeys = @[@"0", @"4.0", @"4.1", @"4.2", @"4.3", @"4.4", @"4.5", @"4.6"];
    NSArray<NSString *> *glvNames = @[
        localize(@"preference.title.mg_custom_gl_version-0", nil),
        localize(@"preference.title.mg_custom_gl_version-4.0", nil),
        localize(@"preference.title.mg_custom_gl_version-4.1", nil),
        localize(@"preference.title.mg_custom_gl_version-4.2", nil),
        localize(@"preference.title.mg_custom_gl_version-4.3", nil),
        localize(@"preference.title.mg_custom_gl_version-4.4", nil),
        localize(@"preference.title.mg_custom_gl_version-4.5", nil),
        localize(@"preference.title.mg_custom_gl_version-4.6", nil),
    ];
    ZL2SettingRowList *glvRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:glvNames optionKeys:glvKeys];
    glvRow.title = localize(@"preference.title.custom_gl_version", nil);
    glvRow.subtitle = localize(@"preference.detail.custom_gl_version", nil);
    [glvRow ame_reloadSelectedIndex:(NSInteger)[glvKeys indexOfObject:
        ame_pages_stringOr(getPrefObject(@"mobileglues.custom_gl_version"), @"0")]];
    glvRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= glvKeys.count) return;
        setPrefString(@"mobileglues.custom_gl_version", glvKeys[index]);
    };
    [mgGroup ame_addRow:glvRow];
    [self ame_addGroup:mgGroup];

    // --- 组 4：更多设置（长尾兜底契约）---
    ZL2SettingCardGroup *group2 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *moreRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    moreRow.title = localize(@"ame369.setpg.more_video_graphics", @"更多视频与图形设置");
    moreRow.subtitle = localize(@"ame369.setpg.more_video_graphics.subtitle", @"FSR 档位、MobileGlues、音频等完整分区");
    moreRow.onTap = ^{
        [weakSelf ame_push:[[LauncherPreferencesViewController alloc] init] titled:localize(@"ame369.common.more_settings", @"更多设置")];
    };
    [group2 ame_addRow:moreRow];
    [self ame_addGroup:group2];
}

- (void)ame_refreshState {
    // Task344：新行族（FSR/MobileGlues）一并随切轨刷新——全量重建最简一致
    //（rendererRow/resolutionRow/fullscreenRow 在 ame_buildGroups 内重读重挂）
    [self ame_rebuildGroups];
}

@end

#pragma mark - ② 游戏屏

@interface ZL2GameSettingsPage ()
@property (nonatomic, strong) ZL2SettingRowSlider *memoryRow;
@property (nonatomic, strong) ZL2SettingRowEnum *presetRow;
@property (nonatomic, strong) ZL2SettingRowInput *customArgsRow;
@property (nonatomic, strong) ZL2SettingRowInput *javaArgsRow;
@property (nonatomic, strong) ZL2SettingRowSwitch *isolationRow;
@end

@implementation ZL2GameSettingsPage

- (void)ame_buildGroups {
    __weak typeof(self) weakSelf = self;

    // --- 组 1：内存与 JVM ---
    // 内存分配：当前实例（Task141：启动内存由实例拉条决定，全局行已退役）。
    // 滑条上限 = 安全堆顶 + 512（ProfileSettings Task173 同款）。
    NSInteger memoryCap = (NSInteger)ame173_safeHeapCeilingMB() + 512;
    if (memoryCap < 1024) memoryCap = 1024;
    NSMutableDictionary *profile = [[[PLProfiles current] selectedProfile] mutableCopy]
        ?: [NSMutableDictionary dictionary];
    NSInteger memory = [profile[@"allocatedMemory"] integerValue];
    if (memory <= 0) memory = MIN(memoryCap / 2, 2048);
    memory = MAX(256, MIN(memoryCap, memory));

    NSString *profileName = [[PLProfiles current] selectedProfileName] ?: @"default";
    ZL2SettingRowSlider *memoryRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil
                                   minimum:256 maximum:memoryCap suffix:@"MB"];
    memoryRow.title = localize(@"ame369.common.memory", @"内存分配");
    memoryRow.subtitle = [NSString stringWithFormat:
        localize(@"ame369.setpg.memory_heap_fmt", @"当前实例「%@」的 JVM 堆上限（MB）"), profileName];
    [memoryRow ame_setValue:memory];
    memoryRow.onValueChanged = ^(NSInteger value) {
        // 与 ProfileSettings.saveSettings 同一写路径：实例字典 + save
        NSMutableDictionary *live = [[PLProfiles current] selectedProfile];
        if (!live) return;
        live[@"allocatedMemory"] = @(value);
        [[PLProfiles current] save];
    };
    self.memoryRow = memoryRow;

    // JVM 预设（全局档；Task255/256：memory/normal/performance/custom）
    NSArray<NSString *> *presetKeys = @[@"memory", @"normal", @"performance", @"custom"];
    NSArray<NSString *> *presetNames = @[
        localize(@"jvm.preset.memory", nil),
        localize(@"jvm.preset.normal", nil),
        localize(@"jvm.preset.performance", nil),
        localize(@"jvm.preset.custom", nil),
    ];
    ZL2SettingRowEnum *presetRow =
        [[ZL2SettingRowEnum alloc] initWithTitle:@"" subtitle:nil options:presetNames];
    presetRow.title = localize(@"preference.title.jvm_preset", nil);
    presetRow.subtitle = localize(@"ame369.setpg.gc_preset.subtitle", @"GC 策略档位（实例覆写 → 全局 → normal）");
    NSString *preset = ame_pages_stringOr(getPrefObject(@"java.jvm_preset"), @"normal");
    [presetRow ame_reloadSelectedIndex:(NSInteger)[presetKeys indexOfObject:preset]];
    presetRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= presetKeys.count) return;
        setPrefString(@"java.jvm_preset", presetKeys[index]);
    };
    self.presetRow = presetRow;

    // 自定义 JVM 参数（预设 = 自定义时注入；Task255）
    ZL2SettingRowInput *customArgsRow =
        [[ZL2SettingRowInput alloc] initWithTitle:@"" subtitle:nil
                              placeholder:@"-XX:+UseZGC …"
                                     text:ame_pages_stringOr(getPrefObject(@"java.jvm_preset_custom_args"), @"")];
    customArgsRow.title = localize(@"preference.title.jvm_preset_custom_args", nil);
    customArgsRow.subtitle = localize(@"ame369.setpg.custom_args.subtitle", @"预设选「自定义」时注入");
    customArgsRow.onTextChanged = ^(NSString *text) {
        setPrefString(@"java.jvm_preset_custom_args", text);
    };
    self.customArgsRow = customArgsRow;

    // JVM 启动参数（全局；实例页可覆盖——PLProfiles resolveKey 回退链）
    ZL2SettingRowInput *javaArgsRow =
        [[ZL2SettingRowInput alloc] initWithTitle:@"" subtitle:nil
                              placeholder:nil
                                     text:ame_pages_stringOr(getPrefObject(@"java.java_args"), @"")];
    javaArgsRow.title = localize(@"preference.title.java_args", nil);
    javaArgsRow.subtitle = localize(@"ame369.setpg.java_args.subtitle", @"附加到启动命令（留空使用默认）");
    javaArgsRow.onTextChanged = ^(NSString *text) {
        setPrefString(@"java.java_args", text);
    };
    self.javaArgsRow = javaArgsRow;

    ZL2SettingCardGroup *group1 = [[ZL2SettingCardGroup alloc] init];
    [group1 ame_addRows:@[memoryRow, presetRow, customArgsRow, javaArgsRow]];
    [self ame_addGroup:group1];

    // --- 组 2：实例 ---
    // 版本隔离（internal.isolated——实例 plist 键；写后 toggleIsolatedPref(NO)
    // 重算应用，LauncherPreferences 既有契约；重启后完全生效）
    ZL2SettingRowSwitch *isolationRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    isolationRow.title = localize(@"ame369.setpg.version_isolation", @"版本隔离");
    isolationRow.subtitle = localize(@"ame369.setpg.version_isolation.subtitle", @"当前游戏目录使用独立偏好集（重启启动器后完全生效）");
    [isolationRow ame_setOn:getPrefBool(@"internal.isolated")];
    isolationRow.onToggle = ^(BOOL on) {
        [weakSelf ame_writeInstanceIsolation:on];
    };
    self.isolationRow = isolationRow;

    ZL2SettingCardGroup *group2 = [[ZL2SettingCardGroup alloc] init];
    [group2 ame_addRow:isolationRow];
    [self ame_addGroup:group2];

    // ── ★ Task344 旧设置全量迁移：音频/兼容组（video+general 跨分区收拢）──
    ZL2SettingCardGroup *audioGroup = [[ZL2SettingCardGroup alloc] init];
    // 静音其他音频（游戏会话压低/暂停系统音源）
    ZL2SettingRowSwitch *silenceOtherRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    silenceOtherRow.title = localize(@"preference.title.silence_other_audio", nil);
    silenceOtherRow.subtitle = localize(@"preference.detail.silence_other_audio", nil);
    [silenceOtherRow ame_setOn:getPrefBool(@"video.silence_other_audio")];
    silenceOtherRow.onToggle = ^(BOOL on) {
        setPrefBool(@"video.silence_other_audio", on);
    };
    // 静音键跟随（静音拨片按下时游戏跟随静音）
    ZL2SettingRowSwitch *silenceSwitchRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    silenceSwitchRow.title = localize(@"preference.title.silence_with_switch", nil);
    silenceSwitchRow.subtitle = localize(@"preference.detail.silence_with_switch", nil);
    [silenceSwitchRow ame_setOn:getPrefBool(@"video.silence_with_switch")];
    silenceSwitchRow.onToggle = ^(BOOL on) {
        setPrefBool(@"video.silence_with_switch", on);
    };
    // 麦克风
    ZL2SettingRowSwitch *micRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    micRow.title = localize(@"preference.title.allow_microphone", nil);
    micRow.subtitle = localize(@"preference.detail.allow_microphone", nil);
    [micRow ame_setOn:getPrefBool(@"video.allow_microphone")];
    micRow.onToggle = ^(BOOL on) {
        setPrefBool(@"video.allow_microphone", on);
    };
    // 远古版本内存兼容轨（JavaLauncher 消费，默认 ON）
    ZL2SettingRowSwitch *legacyCompatRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    legacyCompatRow.title = localize(@"preference.title.legacy_compatibility", nil);
    legacyCompatRow.subtitle = localize(@"preference.detail.legacy_compatibility", nil);
    [legacyCompatRow ame_setOn:getPrefBool(@"general.legacy_compatibility")];
    legacyCompatRow.onToggle = ^(BOOL on) {
        setPrefBool(@"general.legacy_compatibility", on);
    };
    // Cosmetica 皮肤披风
    ZL2SettingRowSwitch *cosmeticaRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    cosmeticaRow.title = localize(@"preference.title.cosmetica", nil);
    cosmeticaRow.subtitle = localize(@"preference.detail.cosmetica", nil);
    [cosmeticaRow ame_setOn:getPrefBool(@"general.cosmetica")];
    cosmeticaRow.onToggle = ^(BOOL on) {
        setPrefBool(@"general.cosmetica", on);
    };
    [audioGroup ame_addRows:@[silenceOtherRow, silenceSwitchRow, micRow,
                              legacyCompatRow, cosmeticaRow]];
    [self ame_addGroup:audioGroup];
    // 内存限制帮助（说明弹窗 + 教程直达；旧页 showMemoryLimitHelp 平移）
    ZL2SettingCardGroup *memHelpGroup = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *memHelpRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    memHelpRow.title = localize(@"preference.title.memory_limit_help", nil);
    memHelpRow.subtitle = localize(@"preference.detail.memory_limit_help", nil);
    memHelpRow.onTap = ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:localize(@"mem_help.title", @"关于内存限制")
                             message:localize(@"mem_help.message",
                                 @"·扩展内存限制权限，使用GetMoreRAM开启\n"
                                  "让iOS为启动器分配更多内存空间，通常能分配6GB内存\n\n"
                                  "·扩展虚拟内存权限，开启方式见下\n"
                                  "让iOS为启动器分配更多内存寻址，通常能分配7GB内存并提升稳定性\n\n"
                                  "推荐使用付费开发者证书，安装软件自动开启上述权限且支持开启JIT")
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"mem_help.button", @"付费开发者证书")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            NSURL *url = [NSURL URLWithString:@"https://b23.tv/WtgrPJM"];
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
        [weakSelf ame_presentVC:alert];
    };
    [memHelpGroup ame_addRow:memHelpRow];
    [self ame_addGroup:memHelpGroup];

    // --- 组 3：更多设置 ---
    ZL2SettingCardGroup *group3 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *moreRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    moreRow.title = localize(@"ame369.setpg.more_game", @"更多游戏设置");
    moreRow.subtitle = localize(@"ame369.setpg.more_game.subtitle", @"Java 版本、环境变量、调试等完整分区");
    moreRow.onTap = ^{
        [weakSelf ame_push:[[LauncherPreferencesViewController alloc] init] titled:localize(@"ame369.common.more_settings", @"更多设置")];
    };
    [group3 ame_addRow:moreRow];
    [self ame_addGroup:group3];
}

// 版本隔离写入：直接落实例 plist 的 internal.isolated（PLPreferences
// toggleIsolationForced 的读取源），再 toggleIsolatedPref(NO) 重算应用
- (void)ame_writeInstanceIsolation:(BOOL)on {
    const char *gameDir = getenv("POJAV_GAME_DIR");
    if (!gameDir) return;   // 环境未就绪：放弃写入（不造假成功）
    NSString *instancePath = [NSString stringWithFormat:@"%s/launcher_preferences.plist", gameDir];
    NSMutableDictionary *dict =
        [[NSMutableDictionary dictionaryWithContentsOfFile:instancePath] mutableCopy]
            ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *internalSection =
        [[dict objectForKey:@"internal"] mutableCopy] ?: [NSMutableDictionary dictionary];
    internalSection[@"isolated"] = @(on);
    dict[@"internal"] = internalSection;
    [dict writeToFile:instancePath atomically:YES];
    toggleIsolatedPref(NO);
    NSLog(@"[ZL2Settings] instance isolation -> %d (%@)", on, instancePath);
}

- (void)ame_refreshState {
    // Task344：音频/兼容组随切轨刷新——全量重建（与内存/隔离行同链）
    [self ame_rebuildGroups];
}

@end

#pragma mark - ③ 控制屏

@interface ZL2ControlSettingsPage ()
@property (nonatomic, strong) ZL2SettingRowList *modeRow;
@property (nonatomic, strong) ZL2SettingRowSwitch *vibrateRow;
@property (nonatomic, strong) ZL2SettingRowSlider *intensityRow;
@property (nonatomic, strong) ZL2SettingRowSwitch *moveViewRow;
@property (nonatomic, strong) ZL2SettingRowSwitch *hideControlsRow;
// ★ Task344：自定义鼠标指针图片选择（旧页 openMousePointerPicker 平移）
@property (nonatomic, assign) BOOL ame344_pickingMousePointer;
@end

@interface ZL2ControlSettingsPage () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end

@implementation ZL2ControlSettingsPage

- (void)ame_buildGroups {
    __weak typeof(self) weakSelf = self;

    // --- 组 1：虚拟按键 / 触控布局（TouchController 组，控制屏首组/首行）---
    // ★Task428（6.6 入口更名升位）：组首行语义由「通信方式」改为
    //   「虚拟按键 / 触控布局」（ZL2 上游控制页主入口口径）；旧键
    //   preference.touchcontroller.mode.title / ame369.setpg.tc_channel.subtitle
    //   保留不删（「完整触控设置」旧页仍在消费，不动）。
    NSArray<NSString *> *modeNames = @[
        localize(@"preference.touchcontroller.mode.disabled", nil),
        localize(@"preference.touchcontroller.mode.udp", nil),
        localize(@"preference.touchcontroller.mode.staticlib", nil),
    ];
    ZL2SettingRowList *modeRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:modeNames optionKeys:@[@"0", @"1", @"2"]];
    modeRow.title = localize(@"ame428.control.tc_section", @"虚拟按键 / 触控布局");
    modeRow.subtitle = localize(@"ame428.control.tc_section.subtitle", @"TouchController 模组通道，驱动游戏内虚拟按键与触控布局（禁用 / UDP / 静态库）");
    // 有效态 = mod_touch_enable && mod_touch_mode（旧页同口径）
    BOOL enabled = getPrefBool(@"control.mod_touch_enable");
    NSInteger mode = getPrefInt(@"control.mod_touch_mode");
    if (mode < 0 || mode > 2) mode = 0;
    [modeRow ame_reloadSelectedIndex:(enabled ? mode : 0)];
    modeRow.onSelect = ^(NSInteger index) {
        [weakSelf ame_applyTouchControllerMode:index];
    };
    self.modeRow = modeRow;

    ZL2SettingRowSwitch *vibrateRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    vibrateRow.title = localize(@"preference.touchcontroller.vibrate.enable", nil);
    [vibrateRow ame_setOn:getPrefBool(@"control.mod_touch_vibrate_enable")];
    vibrateRow.onToggle = ^(BOOL on) {
        setPrefBool(@"control.mod_touch_vibrate_enable", on);
    };
    self.vibrateRow = vibrateRow;

    ZL2SettingRowSlider *intensityRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil
                                   minimum:1 maximum:3 suffix:@""];
    intensityRow.title = localize(@"preference.touchcontroller.vibrate.intensity", nil);
    intensityRow.valueTextBlock = ^NSString *(NSInteger value) {
        switch (value) {
            case 1: return localize(@"preference.touchcontroller.vibrate.intensity.light", nil);
            case 2: return localize(@"preference.touchcontroller.vibrate.intensity.medium", nil);
            case 3: return localize(@"preference.touchcontroller.vibrate.intensity.heavy", nil);
            default: return nil;   // 回退缺省数值格式
        }
    };
    [intensityRow ame_setValue:MAX(1, MIN(3, getPrefInt(@"control.mod_touch_vibrate_intensity")))];
    intensityRow.onValueChanged = ^(NSInteger value) {
        setPrefInt(@"control.mod_touch_vibrate_intensity", value);
    };
    self.intensityRow = intensityRow;

    ZL2SettingRowSwitch *moveViewRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    moveViewRow.title = localize(@"preference.touchcontroller.moveview.enable", nil);
    [moveViewRow ame_setOn:getPrefBool(@"control.mod_touch_moveview_enable")];
    moveViewRow.onToggle = ^(BOOL on) {
        setPrefBool(@"control.mod_touch_moveview_enable", on);
    };
    self.moveViewRow = moveViewRow;

    ZL2SettingRowSwitch *hideControlsRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    hideControlsRow.title = localize(@"preference.touchcontroller.hide_controls", nil);
    [hideControlsRow ame_setOn:getPrefBool(@"control.mod_touch_hide_controls")];
    hideControlsRow.onToggle = ^(BOOL on) {
        setPrefBool(@"control.mod_touch_hide_controls", on);
    };
    self.hideControlsRow = hideControlsRow;

    ZL2SettingCardGroup *group1 = [[ZL2SettingCardGroup alloc] init];
    [group1 ame_addRows:@[modeRow, vibrateRow, intensityRow, moveViewRow, hideControlsRow]];
    [self ame_addGroup:group1];

    // ── ★Task428：触控手势小节（点击/长按动作映射 + 长按延迟；
    //   general.gesture_* 键名契约由并行工程师的运行时手势层按同名键
    //   消费，逐字一致不可改；注册要求见文件头 ★Task428 注册注记）──
    ZL2SettingCardGroup *ame428_gestureGroup = [[ZL2SettingCardGroup alloc] init];
    NSArray<NSString *> *ame428_gestureOptNames = @[
        localize(@"ame428.control.gesture.opt.left", @"鼠标左键"),
        localize(@"ame428.control.gesture.opt.right", @"鼠标右键"),
        localize(@"ame428.control.gesture.opt.none", @"无操作"),
    ];
    NSArray<NSString *> *ame428_gestureOptKeys = @[@"0", @"1", @"2"];
    // 点击动作（general.gesture_tap_action；int 0=左键 1=右键 2=无操作；默认 0）
    id ame428_tapRaw = getPrefObject(@"general.gesture_tap_action");
    NSInteger ame428_tap = ame428_tapRaw ? [ame428_tapRaw intValue] : 0;
    if (ame428_tap < 0 || ame428_tap > 2) ame428_tap = 0;
    ZL2SettingRowList *ame428_tapRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:ame428_gestureOptNames optionKeys:ame428_gestureOptKeys];
    ame428_tapRow.title = localize(@"ame428.control.gesture.tap", @"点击动作");
    [ame428_tapRow ame_reloadSelectedIndex:ame428_tap];
    ame428_tapRow.onSelect = ^(NSInteger index) {
        setPrefInt(@"general.gesture_tap_action", index);
    };
    // 长按动作（general.gesture_longpress_action；默认 1=右键）
    id ame428_lpRaw = getPrefObject(@"general.gesture_longpress_action");
    NSInteger ame428_lp = ame428_lpRaw ? [ame428_lpRaw intValue] : 1;
    if (ame428_lp < 0 || ame428_lp > 2) ame428_lp = 1;
    ZL2SettingRowList *ame428_lpRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:ame428_gestureOptNames optionKeys:ame428_gestureOptKeys];
    ame428_lpRow.title = localize(@"ame428.control.gesture.longpress", @"长按动作");
    [ame428_lpRow ame_reloadSelectedIndex:ame428_lp];
    ame428_lpRow.onSelect = ^(NSInteger index) {
        setPrefInt(@"general.gesture_longpress_action", index);
    };
    // 长按延迟（general.gesture_longpress_delay；float 秒 0.2–1.0 默认 0.30；
    //   整数滑条 2–10 以 0.1s 步进承载，徽章按秒显示）
    id ame428_delayRaw = getPrefObject(@"general.gesture_longpress_delay");
    float ame428_delay = ame428_delayRaw ? [ame428_delayRaw floatValue] : 0.30f;
    if (ame428_delay < 0.2f || ame428_delay > 1.0f) ame428_delay = 0.30f;
    ZL2SettingRowSlider *ame428_delayRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil
                                   minimum:2 maximum:10 suffix:@""];
    ame428_delayRow.title = localize(@"ame428.control.gesture.longpress_delay", @"长按延迟");
    ame428_delayRow.subtitle = localize(@"ame428.control.gesture.longpress_delay.subtitle", @"触发长按动作需按住的时长（秒）");
    ame428_delayRow.valueTextBlock = ^NSString *(NSInteger value) {
        return [NSString stringWithFormat:@"%.1f s", (double)value / 10.0];
    };
    [ame428_delayRow ame_setValue:(NSInteger)lroundf(ame428_delay * 10.0f)];
    ame428_delayRow.onValueChanged = ^(NSInteger value) {
        setPrefFloat(@"general.gesture_longpress_delay", (float)value / 10.0f);
    };
    [ame428_gestureGroup ame_addRows:@[ame428_tapRow, ame428_lpRow, ame428_delayRow]];
    [self ame_addGroup:ame428_gestureGroup];

    // ── ★ Task344 旧设置全量迁移：键鼠与控件组（旧 control 分区主体）──
    ZL2SettingCardGroup *kbGroup = [[ZL2SettingCardGroup alloc] init];
    // 键位调整入口（画布编辑器，旧 childPane 平移；模态 nav 与控制管理屏同款）
    ZL2SettingRowAction *editorRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    editorRow.title = localize(@"preference.title.custom_controls", nil);
    editorRow.subtitle = localize(@"ame369.setpg.canvas_editor.subtitle", @"全屏画布编辑器（添加/拖动/缩放控件）");
    editorRow.onTap = ^{
        CustomControlsViewController *editor = [[CustomControlsViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
        nav.modalInPresentation = YES;
        [weakSelf presentViewController:nav animated:YES completion:nil];
    };
    [kbGroup ame_addRow:editorRow];
    // 滑动热栏（TouchController 启用时灰禁——旧页 enableCondition 同口径）
    ZL2SettingRowSwitch *hotbarRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    hotbarRow.title = localize(@"preference.title.slideable_hotbar", nil);
    hotbarRow.subtitle = localize(@"preference.detail.slideable_hotbar", nil);
    [hotbarRow ame_setOn:getPrefBool(@"control.slideable_hotbar")];
    hotbarRow.onToggle = ^(BOOL on) {
        setPrefBool(@"control.slideable_hotbar", on);
    };
    if (!getPrefBool(@"control.mod_touch_enable")) {
        [kbGroup ame_addRow:hotbarRow];   // 重建式刷新：TC 开启后重进本页即消失
    }
    // 手势鼠标 / 手势热栏 / Fluid 移动垫 / 虚拟鼠标
    ZL2SettingRowSwitch *gestureMouseRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    gestureMouseRow.title = localize(@"preference.title.gesture_mouse", nil);
    gestureMouseRow.subtitle = localize(@"preference.detail.gesture_mouse", nil);
    [gestureMouseRow ame_setOn:getPrefBool(@"control.gesture_mouse")];
    gestureMouseRow.onToggle = ^(BOOL on) {
        setPrefBool(@"control.gesture_mouse", on);
    };
    ZL2SettingRowSwitch *gestureHotbarRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    gestureHotbarRow.title = localize(@"preference.title.gesture_hotbar", nil);
    gestureHotbarRow.subtitle = localize(@"preference.detail.gesture_hotbar", nil);
    [gestureHotbarRow ame_setOn:getPrefBool(@"control.gesture_hotbar")];
    gestureHotbarRow.onToggle = ^(BOOL on) {
        setPrefBool(@"control.gesture_hotbar", on);
    };
    ZL2SettingRowSwitch *fluidRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    fluidRow.title = localize(@"preference.title.fluid_button_slide", nil);
    fluidRow.subtitle = localize(@"preference.detail.fluid_button_slide", nil);
    [fluidRow ame_setOn:getPrefBool(@"control.fluid_button_slide")];
    fluidRow.onToggle = ^(BOOL on) {
        setPrefBool(@"control.fluid_button_slide", on);
    };
    ZL2SettingRowSwitch *virtMouseRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    virtMouseRow.title = localize(@"preference.title.virtmouse_enable", nil);
    virtMouseRow.subtitle = localize(@"preference.detail.virtmouse_enable", nil);
    [virtMouseRow ame_setOn:getPrefBool(@"control.virtmouse_enable")];
    virtMouseRow.onToggle = ^(BOOL on) {
        setPrefBool(@"control.virtmouse_enable", on);
    };
    [kbGroup ame_addRows:@[gestureMouseRow, gestureHotbarRow, fluidRow, virtMouseRow]];
    // 四滑条：按钮缩放/鼠标缩放/鼠标速度/长按阈值
    ZL2SettingRowSlider *buttonScaleRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil minimum:50 maximum:500 suffix:@"%"];
    buttonScaleRow.title = localize(@"preference.title.button_scale", nil);
    buttonScaleRow.subtitle = localize(@"preference.detail.button_scale", nil);
    [buttonScaleRow ame_setValue:(NSInteger)getPrefFloat(@"control.button_scale")];
    buttonScaleRow.onValueChanged = ^(NSInteger value) {
        setPrefFloat(@"control.button_scale", (float)value);
    };
    ZL2SettingRowSlider *mouseScaleRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil minimum:25 maximum:300 suffix:@"%"];
    mouseScaleRow.title = localize(@"preference.title.mouse_scale", nil);
    mouseScaleRow.subtitle = localize(@"preference.detail.mouse_scale", nil);
    [mouseScaleRow ame_setValue:(NSInteger)getPrefFloat(@"control.mouse_scale")];
    mouseScaleRow.onValueChanged = ^(NSInteger value) {
        setPrefFloat(@"control.mouse_scale", (float)value);
    };
    ZL2SettingRowSlider *mouseSpeedRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil minimum:25 maximum:300 suffix:@"%"];
    mouseSpeedRow.title = localize(@"preference.title.mouse_speed", nil);
    mouseSpeedRow.subtitle = localize(@"preference.detail.mouse_speed", nil);
    [mouseSpeedRow ame_setValue:(NSInteger)getPrefFloat(@"control.mouse_speed")];
    mouseSpeedRow.onValueChanged = ^(NSInteger value) {
        setPrefFloat(@"control.mouse_speed", (float)value);
    };
    ZL2SettingRowSlider *pressRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil minimum:100 maximum:1000 suffix:@"ms"];
    pressRow.title = localize(@"preference.title.press_duration", nil);
    pressRow.subtitle = localize(@"preference.detail.press_duration", nil);
    [pressRow ame_setValue:(NSInteger)getPrefFloat(@"control.press_duration")];
    pressRow.onValueChanged = ^(NSInteger value) {
        setPrefFloat(@"control.press_duration", (float)value);
    };
    [kbGroup ame_addRows:@[buttonScaleRow, mouseScaleRow, mouseSpeedRow, pressRow]];
    [self ame_addGroup:kbGroup];

    // ── ★ Task344：键盘/触感/陀螺仪组 ──
    ZL2SettingCardGroup *kbdGroup = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowSwitch *twoFingerRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    twoFingerRow.title = localize(@"preference.title.two_finger_keyboard", nil);
    twoFingerRow.subtitle = localize(@"preference.detail.two_finger_keyboard", nil);
    [twoFingerRow ame_setOn:getPrefBool(@"control.two_finger_keyboard")];
    twoFingerRow.onToggle = ^(BOOL on) {
        setPrefBool(@"control.two_finger_keyboard", on);
    };
    ZL2SettingRowSwitch *sdlKbdRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    sdlKbdRow.title = localize(@"preference.title.auto_keyboard_sdl", nil);
    sdlKbdRow.subtitle = localize(@"preference.detail.auto_keyboard_sdl", nil);
    [sdlKbdRow ame_setOn:getPrefBool(@"control.auto_keyboard_sdl")];
    sdlKbdRow.onToggle = ^(BOOL on) {
        setPrefBool(@"control.auto_keyboard_sdl", on);
    };
    ZL2SettingRowSwitch *hapticsRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    hapticsRow.title = localize(@"preference.title.disable_haptics", nil);
    hapticsRow.subtitle = localize(@"preference.detail.disable_haptics", nil);
    [hapticsRow ame_setOn:getPrefBool(@"control.disable_haptics")];
    hapticsRow.onToggle = ^(BOOL on) {
        setPrefBool(@"control.disable_haptics", on);
    };
    [kbdGroup ame_addRows:@[twoFingerRow, sdlKbdRow, hapticsRow]];
    // 陀螺仪三件（TV 无陀螺仪——旧页 enableCondition 同口径）
    if (realUIIdiom != UIUserInterfaceIdiomTV) {
        ZL2SettingRowSwitch *gyroRow =
            [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
        gyroRow.title = localize(@"preference.title.gyroscope_enable", nil);
        gyroRow.subtitle = localize(@"preference.detail.gyroscope_enable", nil);
        [gyroRow ame_setOn:getPrefBool(@"control.gyroscope_enable")];
        gyroRow.onToggle = ^(BOOL on) {
            setPrefBool(@"control.gyroscope_enable", on);
        };
        ZL2SettingRowSwitch *gyroInvertRow =
            [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
        gyroInvertRow.title = localize(@"preference.title.gyroscope_invert_x_axis", nil);
        gyroInvertRow.subtitle = localize(@"preference.detail.gyroscope_invert_x_axis", nil);
        [gyroInvertRow ame_setOn:getPrefBool(@"control.gyroscope_invert_x_axis")];
        gyroInvertRow.onToggle = ^(BOOL on) {
            setPrefBool(@"control.gyroscope_invert_x_axis", on);
        };
        ZL2SettingRowSlider *gyroSensRow =
            [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil minimum:50 maximum:300 suffix:@"%"];
        gyroSensRow.title = localize(@"preference.title.gyroscope_sensitivity", nil);
        gyroSensRow.subtitle = localize(@"preference.detail.gyroscope_sensitivity", nil);
        [gyroSensRow ame_setValue:(NSInteger)getPrefFloat(@"control.gyroscope_sensitivity")];
        gyroSensRow.onValueChanged = ^(NSInteger value) {
            setPrefFloat(@"control.gyroscope_sensitivity", (float)value);
        };
        // ★Task428：陀螺仪补三行（反转 Y / 采样率 / 平滑强度；general.gyro_*
        //   键名契约由并行工程师的陀螺仪运行时按同名键消费，与既有
        //   control.gyroscope_* 键族并行不混淆；注册要求见文件头
        //   ★Task428 注册注记）
        ZL2SettingRowSwitch *gyroInvertYRow =
            [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
        gyroInvertYRow.title = localize(@"ame428.control.gyro.invert_y", @"反转 Y 轴");
        [gyroInvertYRow ame_setOn:getPrefBool(@"general.gyro_invert_y")];
        gyroInvertYRow.onToggle = ^(BOOL on) {
            setPrefBool(@"general.gyro_invert_y", on);
        };
        // 采样率（general.gyro_sample_rate；float Hz 5–50 默认 20.0）
        id ame428_rateRaw = getPrefObject(@"general.gyro_sample_rate");
        float ame428_rate = ame428_rateRaw ? [ame428_rateRaw floatValue] : 20.0f;
        if (ame428_rate < 5.0f || ame428_rate > 50.0f) ame428_rate = 20.0f;
        ZL2SettingRowSlider *gyroRateRow =
            [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil
                                   minimum:5 maximum:50 suffix:@" Hz"];
        gyroRateRow.title = localize(@"ame428.control.gyro.sample_rate", @"采样率");
        [gyroRateRow ame_setValue:(NSInteger)lroundf(ame428_rate)];
        gyroRateRow.onValueChanged = ^(NSInteger value) {
            setPrefFloat(@"general.gyro_sample_rate", (float)value);
        };
        // 平滑强度（general.gyro_smoothing；int 0–100 默认 30）
        id ame428_smoothRaw = getPrefObject(@"general.gyro_smoothing");
        NSInteger ame428_smooth = ame428_smoothRaw ? [ame428_smoothRaw intValue] : 30;
        if (ame428_smooth < 0 || ame428_smooth > 100) ame428_smooth = 30;
        ZL2SettingRowSlider *gyroSmoothRow =
            [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil
                                   minimum:0 maximum:100 suffix:@"%"];
        gyroSmoothRow.title = localize(@"ame428.control.gyro.smoothing", @"平滑强度");
        [gyroSmoothRow ame_setValue:ame428_smooth];
        gyroSmoothRow.onValueChanged = ^(NSInteger value) {
            setPrefInt(@"general.gyro_smoothing", value);
        };
        [kbdGroup ame_addRows:@[gyroRow, gyroInvertRow, gyroSensRow,
                                gyroInvertYRow, gyroRateRow, gyroSmoothRow]];
    }
    [self ame_addGroup:kbdGroup];

    // ── ★ Task344：指针/可见性/实例工具组 ──
    ZL2SettingCardGroup *miscGroup = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *pointerRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    pointerRow.title = localize(@"preference.title.custom_mouse_pointer", nil);
    pointerRow.subtitle = localize(@"preference.detail.custom_mouse_pointer", nil);
    pointerRow.onTap = ^{
        [weakSelf ame344_openMousePointerPicker];
    };
    ZL2SettingRowAction *pointerResetRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    pointerResetRow.title = localize(@"preference.title.reset_mouse_pointer", nil);
    pointerResetRow.subtitle = localize(@"preference.detail.reset_mouse_pointer", nil);
    pointerResetRow.onTap = ^{
        NSString *path = [NSString stringWithFormat:@"%s/controlmap/mouse_pointer.png", getenv("POJAV_HOME")];
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        [NSNotificationCenter.defaultCenter postNotificationName:@"MousePointerUpdated" object:nil];
        [weakSelf ame344_showNotice:localize(@"i18n_str_393", nil)];
    };
    ZL2SettingRowSwitch *hwHideRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    hwHideRow.title = localize(@"preference.title.hardware_hide", nil);
    hwHideRow.subtitle = localize(@"preference.detail.hardware_hide", nil);
    [hwHideRow ame_setOn:getPrefBool(@"control.hardware_hide")];
    hwHideRow.onToggle = ^(BOOL on) {
        setPrefBool(@"control.hardware_hide", on);
    };
    ZL2SettingRowSwitch *recHideRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    recHideRow.title = localize(@"preference.title.recording_hide", nil);
    recHideRow.subtitle = localize(@"preference.detail.recording_hide", nil);
    [recHideRow ame_setOn:getPrefBool(@"control.recording_hide")];
    recHideRow.onToggle = ^(BOOL on) {
        setPrefBool(@"control.recording_hide", on);
    };
    ZL2SettingRowSwitch *ctrlUpdRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    ctrlUpdRow.title = localize(@"preference.title.auto_control_update_check", nil);
    ctrlUpdRow.subtitle = localize(@"preference.detail.auto_control_update_check", nil);
    [ctrlUpdRow ame_setOn:getPrefBool(@"control.auto_control_update_check")];
    ctrlUpdRow.onToggle = ^(BOOL on) {
        setPrefBool(@"control.auto_control_update_check", on);
    };
    [miscGroup ame_addRows:@[pointerRow, pointerResetRow, hwHideRow, recHideRow, ctrlUpdRow]];
    // 跨实例疾跑切换（Task229 全链平移）
    ZL2SettingRowAction *sprintRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    sprintRow.title = localize(@"preference.title.mc_toggle_sprint", nil);
    sprintRow.subtitle = localize(@"preference.detail.mc_toggle_sprint", nil);
    sprintRow.onTap = ^{
        [weakSelf ame229_toggleSprintTapped];
    };
    ZL2SettingRowAction *keybindRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    keybindRow.title = localize(@"preference.title.keybind_sync", nil);
    keybindRow.subtitle = localize(@"preference.detail.keybind_sync", nil);
    keybindRow.onTap = ^{
        [weakSelf ame229_syncKeybindsAcrossInstances];
    };
    [miscGroup ame_addRows:@[sprintRow, keybindRow]];
    [self ame_addGroup:miscGroup];

    // --- 组 2：完整触控设置（长尾兜底）---
    ZL2SettingCardGroup *group2 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *fullRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    fullRow.title = localize(@"ame369.setpg.full_touch", @"完整触控设置");
    fullRow.subtitle = localize(@"ame369.setpg.full_touch.subtitle", @"通信模式说明、关于 TouchController");
    fullRow.onTap = ^{
        [weakSelf ame_push:[[TouchControllerPreferencesViewController alloc] init] titled:localize(@"ame369.setpg.touch_settings", @"触控设置")];
    };
    [group2 ame_addRow:fullRow];
    [self ame_addGroup:group2];
}

// 通信方式写入 = TouchControllerPreferencesViewController
// updateTouchControllerSetting: 的等价迁移（enable/mode/user_off 哨兵 +
// java.env_variables UDP 通道 + Task224 广播）
- (void)ame_applyTouchControllerMode:(NSInteger)mode {
    if (mode == 0) {
        setPrefBool(@"control.mod_touch_enable", NO);
        setPrefInt(@"control.mod_touch_mode", 0);
        // Task223：全局页手动关闭 = 明确用户意图，落哨兵防启动链自动回开
        setPrefBool(@"control.mod_touch_user_off", YES);
        [self ame_removeUDPEnv];
    } else if (mode == 1) {
        setPrefBool(@"control.mod_touch_enable", YES);
        setPrefInt(@"control.mod_touch_mode", 1);
        setPrefBool(@"control.mod_touch_user_off", NO);
        [self ame_addUDPEnv];
    } else {
        setPrefBool(@"control.mod_touch_enable", YES);
        setPrefInt(@"control.mod_touch_mode", 2);
        setPrefBool(@"control.mod_touch_user_off", NO);
        [self ame_removeUDPEnv];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TouchControllerSettingsChanged" object:nil];
}

- (void)ame_addUDPEnv {
    NSString *currentEnv = ame_pages_stringOr(getPrefObject(@"java.env_variables"), @"");
    if ([currentEnv containsString:@"TOUCH_CONTROLLER_PROXY=12450"]) return;
    NSString *newEnv = currentEnv.length > 0
        ? [currentEnv stringByAppendingString:@" TOUCH_CONTROLLER_PROXY=12450"]
        : @"TOUCH_CONTROLLER_PROXY=12450";
    setPrefString(@"java.env_variables", newEnv);
}

- (void)ame_removeUDPEnv {
    NSString *currentEnv = ame_pages_stringOr(getPrefObject(@"java.env_variables"), @"");
    if (currentEnv.length == 0) return;
    NSString *newEnv = [currentEnv stringByReplacingOccurrencesOfString:
                        @" TOUCH_CONTROLLER_PROXY=12450" withString:@""];
    if ([newEnv isEqualToString:@"TOUCH_CONTROLLER_PROXY=12450"]) newEnv = @"";
    setPrefString(@"java.env_variables", newEnv);
}

- (void)ame_refreshState {
    // Task344：控制全量迁移后行族随外部变化重建（TC 模式/热栏灰禁/陀螺仪面）
    [self ame_rebuildGroups];
}

#pragma mark - Task344 旧 control 分区助手（旧 VC 平移）

// 轻反馈（旧 showSuccessMessage 形态收敛为无标题 alert）
- (void)ame344_showNotice:(NSString *)text {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:text
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                              style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// 自定义鼠标指针（旧 openMousePointerPicker 平移）
- (void)ame344_openMousePointerPicker {
    self.ame344_pickingMousePointer = YES;
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    [self ame_presentVC:picker];
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:^{
        UIImage *image = info[UIImagePickerControllerOriginalImage];
        if (!image) return;
        if (!self.ame344_pickingMousePointer) return;
        self.ame344_pickingMousePointer = NO;
        NSString *path = [NSString stringWithFormat:@"%s/controlmap/mouse_pointer.png", getenv("POJAV_HOME")];
        NSData *pngData = UIImagePNGRepresentation(image);
        [NSFileManager.defaultManager createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                                withIntermediateDirectories:YES attributes:nil error:nil];
        BOOL ok = [pngData writeToFile:path atomically:YES];
        if (ok) {
            [NSNotificationCenter.defaultCenter postNotificationName:@"MousePointerUpdated" object:nil];
            [self ame344_showNotice:localize(@"i18n_str_369", nil)];
        } else {
            [self ame344_showNotice:localize(@"i18n_str_370", nil)];
        }
    }];
}

// 跨实例 options.txt 全集（旧 ame229_allInstanceOptionsPaths 1:1 平移）
- (NSArray<NSString *> *)ame229_allInstanceOptionsPaths {
    const char *home = getenv("POJAV_HOME");
    if (home == NULL || home[0] == '\0') return @[];
    NSString *instancesRoot = [NSString stringWithFormat:@"%s/instances", home];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *inst in [fm contentsOfDirectoryAtPath:instancesRoot error:nil]) {
        NSString *instDir = [instancesRoot stringByAppendingPathComponent:inst];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:instDir isDirectory:&isDir] || !isDir) continue;
        // 新隔离布局：instances/<inst>/versions/<ver>/game/options.txt
        NSString *versionsDir = [instDir stringByAppendingPathComponent:@"versions"];
        for (NSString *ver in [fm contentsOfDirectoryAtPath:versionsDir error:nil]) {
            NSString *opt = [[versionsDir stringByAppendingPathComponent:ver]
                stringByAppendingPathComponent:@"game/options.txt"];
            if ([fm fileExistsAtPath:opt]) [out addObject:opt];
        }
        // 兼容旧布局：实例根直接挂 options.txt
        NSString *optRoot = [instDir stringByAppendingPathComponent:@"options.txt"];
        if ([fm fileExistsAtPath:optRoot] && ![out containsObject:optRoot]) {
            [out addObject:optRoot];
        }
        // Task270 (M6)：custom_gamedir 第二层（ame269 整合包实例）
        NSString *customRoot = [instDir stringByAppendingPathComponent:@"custom_gamedir"];
        BOOL customIsDir = NO;
        if ([fm fileExistsAtPath:customRoot isDirectory:&customIsDir] && customIsDir) {
            for (NSString *customId in [fm contentsOfDirectoryAtPath:customRoot error:nil]) {
                if ([customId hasPrefix:@"."]) continue;
                NSString *optCustom = [[customRoot stringByAppendingPathComponent:customId]
                    stringByAppendingPathComponent:@"options.txt"];
                if ([fm fileExistsAtPath:optCustom] && ![out containsObject:optCustom]) {
                    [out addObject:optCustom];
                }
            }
        }
    }
    // mtime 降序（最近玩的在前）
    [out sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSDate *da = [fm attributesOfItemAtPath:a error:nil].fileModificationDate ?: [NSDate distantPast];
        NSDate *db = [fm attributesOfItemAtPath:b error:nil].fileModificationDate ?: [NSDate distantPast];
        return [db compare:da];
    }];
    return out;
}

- (nullable NSArray<NSString *> *)ame229_linesOfOptions:(NSString *)path {
    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding error:nil];
    if (content.length == 0) return nil;
    return [content componentsSeparatedByString:@"\n"];
}

- (NSDictionary<NSString *, NSString *> *)ame229_keybindsOfOptions:(NSString *)path {
    NSArray<NSString *> *lines = [self ame229_linesOfOptions:path];
    if (lines == nil) return @{};
    NSMutableDictionary<NSString *, NSString *> *out = [NSMutableDictionary dictionary];
    for (NSString *ln in lines) {
        if (![ln hasPrefix:@"key_key."]) continue;
        NSRange c = [ln rangeOfString:@":"];
        if (c.location == NSNotFound || c.location + 1 >= ln.length) continue;
        [out setObject:[ln substringFromIndex:c.location + 1]
                forKey:[ln substringToIndex:c.location]];
    }
    return out;
}

- (BOOL)ame229_writeToggleSprint:(BOOL)present toOptions:(NSString *)path {
    NSArray<NSString *> *lines = [self ame229_linesOfOptions:path];
    if (lines == nil) return NO;
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    BOOL wrote = NO;
    for (NSString *ln in lines) {
        if ([ln hasPrefix:@"toggleSprint:"]) {
            [out addObject:present ? @"toggleSprint:true" : @"toggleSprint:false"];
            wrote = YES;
        } else {
            [out addObject:ln];
        }
    }
    if (!wrote) {
        [out addObject:present ? @"toggleSprint:true" : @"toggleSprint:false"];
    }
    NSString *newContent = [out componentsJoinedByString:@"\n"];
    BOOL ok = [newContent writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    if (ok) {
        NSLog(@"[ZL2Settings] Task229 toggleSprint %@ -> %@", present ? @"true" : @"false", path);
    }
    return ok;
}

// 跨实例疾跑切换（旧 mc_toggle_sprint action 1:1 平移）
- (void)ame229_toggleSprintTapped {
    BOOL anyOn = NO;
    for (NSString *p in [self ame229_allInstanceOptionsPaths]) {
        for (NSString *ln in [self ame229_linesOfOptions:p] ?: @[]) {
            if ([ln hasPrefix:@"toggleSprint:true"]) { anyOn = YES; break; }
        }
        if (anyOn) break;
    }
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:localize(@"ame229.sprint.title", nil)
                         message:anyOn ? localize(@"ame229.sprint.on.desc", nil)
                                       : localize(@"ame229.sprint.off.desc", nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    NSString *onTitle = localize(@"ame229.sprint.turn_on", nil);
    NSString *offTitle = localize(@"ame229.sprint.turn_off", nil);
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:anyOn ? offTitle : onTitle
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a) {
        BOOL enable = !anyOn;
        NSInteger wrote = 0, total = 0;
        for (NSString *p in [weakSelf ame229_allInstanceOptionsPaths]) {
            total++;
            if ([weakSelf ame229_writeToggleSprint:enable toOptions:p]) wrote++;
        }
        NSLog(@"[ZL2Settings] Task229 toggleSprint written %ld/%ld instance options.txt (enable=%d)",
              (long)wrote, (long)total, (int)enable);
        [weakSelf ame344_showNotice:[NSString stringWithFormat:
            localize(@"ame229.sprint.result", nil), (long)wrote]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                               style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// 跨实例键位同步（旧 ame229_syncKeybindsAcrossInstances 1:1 平移）
- (void)ame229_syncKeybindsAcrossInstances {
    NSArray<NSString *> *paths = [self ame229_allInstanceOptionsPaths];
    if (paths.count < 2) {
        [self ame344_showNotice:localize(@"ame229.keybind.sync.one_instance", nil)];
        return;
    }
    // 源选择：优先“非默认键位行最多”的档，并列取 mtime 最新（已降序）
    NSString *source = nil;
    NSInteger bestCount = 0;
    for (NSString *p in paths) {
        NSArray<NSString *> *lines = [self ame229_linesOfOptions:p];
        if (lines == nil) continue;
        NSInteger cnt = 0;
        for (NSString *ln in lines) {
            if ([ln hasPrefix:@"key_key."]) cnt++;
        }
        if (cnt > bestCount) { bestCount = cnt; source = p; }
    }
    if (source == nil || bestCount == 0) {
        [self ame344_showNotice:localize(@"ame229.keybind.sync.no_bindings", nil)];
        return;
    }
    NSDictionary *sourceBindings = [self ame229_keybindsOfOptions:source];
    if (sourceBindings.count == 0) {
        [self ame344_showNotice:localize(@"ame229.keybind.sync.no_bindings", nil)];
        return;
    }
    NSInteger syncedFiles = 0, addedRows = 0;
    for (NSString *p in paths) {
        if ([p isEqualToString:source]) continue;
        NSArray<NSString *> *lines = [self ame229_linesOfOptions:p];
        if (lines == nil) continue;
        NSMutableSet *existing = [NSMutableSet set];
        NSMutableArray<NSString *> *out = [NSMutableArray arrayWithArray:lines];
        for (NSString *ln in lines) {
            NSRange c = [ln rangeOfString:@":"];
            if (c.location != NSNotFound) {
                [existing addObject:[ln substringToIndex:c.location]];
            }
        }
        NSInteger before = out.count;
        for (NSString *key in sourceBindings) {
            if (![existing containsObject:key]) {
                NSString *row = [NSString stringWithFormat:@"%@:%@", key, sourceBindings[key]];
                if (out.count > 0 && [out.lastObject isEqualToString:@""]) {
                    [out insertObject:row atIndex:out.count - 1];
                } else {
                    [out addObject:row];
                }
            }
        }
        if (out.count > before) {
            NSString *newContent = [out componentsJoinedByString:@"\n"];
            if ([newContent writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
                syncedFiles++;
                addedRows += (out.count - before);
            }
        }
    }
    NSLog(@"[ZL2Settings] Task229 keybind sync: source=%@ (%ld binding rows) -> %ld file(s), %ld row(s) added",
          source, (long)bestCount, (long)syncedFiles, (long)addedRows);
    NSString *msg = [NSString stringWithFormat:localize(@"ame229.keybind.sync.done", nil),
                     (long)syncedFiles, (long)addedRows];
    [self ame344_showNotice:msg];
}

@end

#pragma mark - ④ 手柄屏

@interface ZL2GamepadSettingsPage ()
@property (nonatomic, strong) ZL2SettingRowEnum *typeRow;
@property (nonatomic, strong) ZL2SettingRowAction *mappingRow;
@property (nonatomic, strong) ZL2SettingRowSlider *scrollRow;
@end

@implementation ZL2GamepadSettingsPage

- (void)ame_buildGroups {
    __weak typeof(self) weakSelf = self;

    // --- 组 1：手柄（iOS 真实键族：controller_type / default_gamepad_ctrl）---
    // Task316（6.5.5 新功能 UI 适配）：手柄类型三选对齐 Task311 语义——
    // 任天堂选项即 Switch 键面交换（control.nintendo_layout=YES，
    // ControllerInput ame310 消费点零改动）；旧壳手柄配置弹窗同口径。
    NSArray<NSString *> *typeKeys = @[@"xbox", @"playstation", @"nintendo"];
    NSArray<NSString *> *typeNames = @[
        localize(@"controller_configurator.title.type.xbox", nil),
        localize(@"controller_configurator.title.type.playstation", nil),
        localize(@"controller_configurator.title.type.nintendo", nil),
    ];
    ZL2SettingRowEnum *typeRow =
        [[ZL2SettingRowEnum alloc] initWithTitle:@"" subtitle:nil options:typeNames];
    typeRow.title = localize(@"ame369.setpg.gamepad_type", @"手柄类型");
    typeRow.subtitle = localize(@"ame369.setpg.gamepad_type.subtitle", @"面键图标风格；选任天堂即交换 A/B、X/Y 键面（Switch 布局）");
    NSString *type = ame_pages_stringOr(getPrefObject(@"control.controller_type"), @"xbox");
    [typeRow ame_reloadSelectedIndex:(NSInteger)[typeKeys indexOfObject:type]];
    typeRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= typeKeys.count) return;
        NSString *key = typeKeys[index];
        setPrefString(@"control.controller_type", key);
        setPrefBool(@"control.nintendo_layout", [key isEqualToString:@"nintendo"]);
    };
    self.typeRow = typeRow;

    ZL2SettingRowAction *mappingRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    mappingRow.title = localize(@"preference.title.default_gamepad_ctrl", nil);
    mappingRow.subtitle = localize(@"ame369.setpg.mapping.subtitle", @"编辑当前映射文件（按键 → 键位）");
    mappingRow.onTap = ^{
        [weakSelf ame_push:[[LauncherPrefContCfgViewController alloc] init]
                   titled:localize(@"preference.title.default_gamepad_ctrl", nil)];
    };
    self.mappingRow = mappingRow;

    // Task316（6.5.5 新功能 UI 适配）：模拟滚轮速度（Task310 键鼠优化，
    // 触屏滚动按钮/手柄滚动键统一系数口 scrollStep:；GCMouse 真滚轮不过此口）
    ZL2SettingRowSlider *scrollRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil
                                   minimum:25 maximum:300 suffix:@"%"];
    scrollRow.title = localize(@"ame369.setpg.scroll_speed", @"模拟滚轮速度");
    scrollRow.subtitle = localize(@"ame369.setpg.scroll_speed.subtitle", @"滚动按钮/手柄滚轮键的滚动速度（真滚轮不受影响）");
    scrollRow.onValueChanged = ^(NSInteger value) {
        setPrefFloat(@"control.scroll_speed", (float)value);
    };
    self.scrollRow = scrollRow;

    ZL2SettingCardGroup *group1 = [[ZL2SettingCardGroup alloc] init];
    [group1 ame_addRows:@[typeRow, mappingRow, scrollRow]];
    [self ame_addGroup:group1];

    // --- 组 2：更多设置 ---
    ZL2SettingCardGroup *group2 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *moreRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    moreRow.title = localize(@"ame369.setpg.more_control_gamepad", @"更多控制与手柄设置");
    moreRow.subtitle = localize(@"ame369.setpg.more_control_gamepad.subtitle", @"键位调整、自定义鼠标、陀螺仪等完整分区");
    moreRow.onTap = ^{
        [weakSelf ame_push:[[LauncherPreferencesViewController alloc] init] titled:localize(@"ame369.common.more_settings", @"更多设置")];
    };
    [group2 ame_addRow:moreRow];
    [self ame_addGroup:group2];

    [self ame_refreshState];
}

- (void)ame_refreshState {
    NSString *type = ame_pages_stringOr(getPrefObject(@"control.controller_type"), @"xbox");
    [self.typeRow ame_reloadSelectedIndex:(NSInteger)[@[@"xbox", @"playstation", @"nintendo"] indexOfObject:type]];
    self.mappingRow.detailText =
        ame_pages_stringOr(getPrefObject(@"control.default_gamepad_ctrl"), nil);
    [self.scrollRow ame_setValue:(NSInteger)getPrefFloat(@"control.scroll_speed")];  // Task316
}

@end

#pragma mark - ⑤ 启动器屏

@interface ZL2LauncherSettingsPage ()
// ★ Task385：深浅模式选择行退役——fui 插件两态开关 = 全应用
// 唯一明暗模式开关（开 = 跟随系统实时换装，关 = 恢复默认跟随系统）；
// 原 ZL2 设置页/旧 FCL 设置页两处原生深/浅/自动选择器一并下线（一页
// 三开关复诉），底层 pref 链（PLPreferences/SceneDelegate 迁移与映射）
// 原样保留 = 兼容零风险。
// ★ Task396：深浅模式选择行恢复（用户复诉「我的深浅主题切换怎么不见了」）——
// Task385 收敛时把 MD3 侧入口全拔，fui 开关一关即无任何明暗入口 = 删过头。
// 终态口径：MD3（fui 关）= 本行唯一明暗入口；fui 开 = fui 两态开关唯一
//（两入口各自模式内各一个，不再同屏叠加）。底层链（PLPreferences/
// SceneDelegate UIThemeChanged 迁移与映射）原样保留。
@property (nonatomic, strong) ZL2SettingRowEnum *themeRow;
// ★Task429：主题色板行（切轨刷新引用；general.theme_mode 三新键之一）
@property (nonatomic, strong) ZL2SettingRowList *ame429_paletteRow;
@property (nonatomic, strong) ZL2SettingRowList *languageRow;
@property (nonatomic, strong) ZL2SettingRowList *effectRow;
@property (nonatomic, strong) ZL2SettingRowSlider *opacityRow;
@property (nonatomic, strong) ZL2SettingRowSlider *blurRow;
// ★Task428：节日彩蛋开关（切轨刷新引用；general.festival_effects）
@property (nonatomic, strong) ZL2SettingRowSwitch *festivalRow;
@property (nonatomic, strong) NSArray<ZL2SettingRowList *> *sourceRows;
@property (nonatomic, strong) NSArray<NSString *> *sourceRowKeys;   // 与 sourceRows 对齐
// ★ Task327：插件贡献行动态组（viewWillAppear 重建——插件启停/装载变化即反映）
@property (nonatomic, strong) UIView *ame327_pluginHeader;
@property (nonatomic, strong) ZL2SettingCardGroup *ame327_pluginGroup;
// ★ Task344：自定义颜色选择（旧页 openColorPickerForKey 平移）
@property (nonatomic, copy) NSString *ame344_pickingColorKey;
@end

@interface ZL2LauncherSettingsPage () <UIDocumentPickerDelegate, UIColorPickerViewControllerDelegate>
@end

@implementation ZL2LauncherSettingsPage

#pragma mark - Task316 跨启动器数据导入（文档选择器 → FileLayoutService）

- (void)ame316_pickExternalFolder {
    __weak typeof(self) weakSelf = self;
    if (@available(iOS 14.0, *)) {
        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder]];
        picker.delegate = self;
        [weakSelf ame_presentVC:picker];
    } else {
        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.folder"]
                                                                  inMode:UIDocumentPickerModeOpen];
        picker.delegate = self;
        [weakSelf ame_presentVC:picker];
    }
}


- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *report = [FileLayoutService ame316_importExternalLauncherFolder:urls[0] error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *body = report ?: localize(@"ame369.setpg.import_failed_body", @"导入失败：无法读取所选文件夹（安全作用域被拒或路径无效）。");
            [ZL2M3Dialog showTitle:localize(@"ame369.setpg.import_result", @"导入结果")
                              body:body
                      confirmTitle:localize(@"OK", nil)
                       destructive:NO
                        onConfirm:nil
                         onCancel:nil];
        });
    });
}

// bundle 内全部语言码（ame202_availableLanguageCodes 同口径：xx.lproj 枚举，
// Base.lproj 除外，dispatch_once 缓存）
+ (NSArray<NSString *> *)ame_availableLanguageCodes {
    static NSArray *codes = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *list = [NSMutableArray array];
        for (NSString *path in [NSBundle.mainBundle pathsForResourcesOfType:@"lproj"
                                                                inDirectory:nil]) {
            NSString *name = path.lastPathComponent;
            if ([name hasSuffix:@".lproj"] && name.length > 6 &&
                ![name isEqualToString:@"Base.lproj"]) {
                [list addObject:[name substringToIndex:name.length - 6]];
            }
        }
        [list sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        codes = [list copy];
    });
    return codes;
}

// 语言码 → 原生显示名（ame202_languageDisplayName 同款思路：原生名优先，
// 未知码回退裸码；语言名是其自身语言书写的字面量，非 UI 硬编码文案）
+ (NSString *)ame_languageDisplayName:(NSString *)code {
    static NSDictionary *native = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        native = @{
            @"de": @"Deutsch",        @"en": @"English",       @"es": @"Español",
            @"fr": @"Français",       @"it": @"Italiano",      @"ja": @"日本語",
            @"ko": @"한국어",          @"ru": @"Русский",       @"th": @"ไทย",
            @"tr": @"Türkçe",         @"uk": @"Українська",    @"vi": @"Tiếng Việt",
            @"zh": @"中文",           @"zh-Hans": @"简体中文", @"zh-Hant": @"繁體中文",
            @"zh-CN": @"简体中文 (zh-CN)",
        };
    });
    NSString *name = native[code];
    return name ?: code;
}

- (void)ame_buildGroups {
    __weak typeof(self) weakSelf = self;

    // --- 组 1：外观 ---
    // ★ Task396：深浅模式行恢复（三态：深/浅/跟随系统；general.ui_theme +
    //   显式选择标记 + UIThemeChanged 通知，Task161 契约原样）——用户上一轮
    //   复诉的"一页三切换"经 fui 收敛（Task385）与本轮五钮/瓦片收敛后已
    //   不复存在，本行回填为 MD3 模式唯一明暗入口。
    NSArray<NSString *> *themeKeys = @[@"dark", @"light", @"auto"];
    NSArray<NSString *> *themeNames = @[
        localize(@"i18n_str_380", nil),
        localize(@"i18n_str_381", nil),
        localize(@"i18n_str_382", nil),
    ];
    ZL2SettingRowEnum *themeRow =
        [[ZL2SettingRowEnum alloc] initWithTitle:@"" subtitle:nil options:themeNames];
    themeRow.title = localize(@"i18n_str_379", nil);
    NSString *theme = ame_pages_stringOr(getPrefObject(@"general.ui_theme"), @"auto");
    [themeRow ame_reloadSelectedIndex:(NSInteger)[themeKeys indexOfObject:theme]];
    themeRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= themeKeys.count) return;
        setPrefString(@"general.ui_theme", themeKeys[index]);
        setPrefBool(@"general.ui_theme_explicit", YES);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"UIThemeChanged"
                                                            object:themeKeys[index]];
    };
    self.themeRow = themeRow;

    // ★Task429：主题色板行（PDF 第五版 §8.1 动态主题模式选择，深浅三态行
    //   近邻；列表 = embermire/跟随背景/五预设/CUSTOM）。键值域与
    //   ZL2DynamicPalette Ame429ThemeMode 逐一对应（mode 2 = embermire 动态
    //   重演内部占位，UI 不直达；UI 直达模式 0/1/3..8）。注册片段
    //   scripts/task429_prefs_F.json（Setter 静默丢弃族同判例——PLPreferences.m
    //   非本工位写权；注册前写值静默丢弃，读侧缺键回退默认 0 = embermire）。
    NSArray<NSString *> *ame429_paletteLabels = @[
        localize(@"ame429.f.palette.embermire", @"Embermire（默认）"),
        localize(@"ame429.f.palette.follow", @"跟随背景"),
        localize(@"ame429.f.palette.frozenlake", @"冻湖蓝"),
        localize(@"ame429.f.palette.forest", @"森绿"),
        localize(@"ame429.f.palette.dusk", @"暮紫"),
        localize(@"ame429.f.palette.crimson", @"绯红"),
        localize(@"ame429.f.palette.amber", @"琥珀"),
        localize(@"ame429.f.palette.custom", @"自定义…"),
    ];
    NSArray<NSNumber *> *ame429_paletteModes = @[@0, @1, @3, @4, @5, @6, @7, @8];
    ZL2SettingRowList *ame429_paletteRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                  options:ame429_paletteLabels optionKeys:nil];
    ame429_paletteRow.title = localize(@"ame429.f.palette.title", @"主题色板");
    ame429_paletteRow.subtitle = localize(@"ame429.f.palette.subtitle", @"跟随背景自动取色，或选择预设色板");
    {
        // 现值回显（mode → UI 列表位；mode 2 重演占位归位 embermire 位）
        NSInteger ame429_mode = [[ZL2DynamicPalette shared] themeMode];
        NSUInteger ame429_uiIndex = 0;   // 默认 embermire 位
        for (NSUInteger i = 0; i < ame429_paletteModes.count; i++) {
            if (ame429_paletteModes[i].integerValue == ame429_mode) {
                ame429_uiIndex = i;
                break;
            }
        }
        [ame429_paletteRow ame_reloadSelectedIndex:(NSInteger)ame429_uiIndex];
    }
    ame429_paletteRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= ame429_paletteModes.count) return;
        NSInteger ame429_mode = ame429_paletteModes[index].integerValue;
        if (ame429_mode == (NSInteger)Ame429ThemeModeCustom) {
            // 自定义 → 弹 ZL2ThemeCustomSheet（确认钮写三键触发生效链；
            // 本行不落键，防未选种子即写 mode 8）
            ZL2ThemeCustomSheet *ame429_sheet = [[ZL2ThemeCustomSheet alloc] init];
            [ame429_sheet ame429_presentFromViewController:weakSelf];
            return;
        }
        setPrefInt(@"general.theme_mode", ame429_mode);
        // 生效链：HCT 色板 → 推 ZL2Theme 活动覆盖层 → Task346 根重建
        // （跟随背景模式内部先落 embermire 再后台取色补推）
        [[ZL2DynamicPalette shared] ame429_reloadAndApply];
    };
    self.ame429_paletteRow = ame429_paletteRow;

    // 应用语言（general.app_language；system + 全部内置语言，写后广播重载）
    NSArray<NSString *> *builtinCodes = [ZL2LauncherSettingsPage ame_availableLanguageCodes];
    NSArray<NSString *> *langCodes =
        [@[@"system"] arrayByAddingObjectsFromArray:builtinCodes];
    NSMutableArray<NSString *> *langNames =
        [NSMutableArray arrayWithObject:localize(@"i18n_str_382", nil)];
    for (NSString *code in builtinCodes) {
        [langNames addObject:[ZL2LauncherSettingsPage ame_languageDisplayName:code]];
    }
    ZL2SettingRowList *languageRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:langNames optionKeys:langCodes];
    languageRow.title = localize(@"i18n_str_2068", nil);
    languageRow.subtitle = localize(@"ame369.setpg.language.subtitle", @"切换后界面立即重载（未翻译语言回退并标记）");
    NSString *language = ame_pages_stringOr(getPrefObject(@"general.app_language"), @"system");
    [languageRow ame_reloadSelectedIndex:(NSInteger)[langCodes indexOfObject:language]];
    languageRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= langCodes.count) return;
        setPrefString(@"general.app_language", langCodes[index]);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"AppLanguageChanged"
                                                            object:langCodes[index]];
    };
    self.languageRow = languageRow;

    // 界面效果（BackgroundManager.uiEffect；毛玻璃/半透明两档）
    BackgroundManager *bg = [BackgroundManager sharedManager];
    NSArray<NSString *> *effectNames = @[
        localize(@"i18n_str_67", nil),
        localize(@"i18n_str_68", nil),
    ];
    ZL2SettingRowList *effectRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:effectNames
                              optionKeys:@[@"blur", @"translucent"]];
    effectRow.title = localize(@"ame369.setpg.interface_effects", @"界面效果");
    effectRow.subtitle = localize(@"background.effect.footer", nil);
    [effectRow ame_reloadSelectedIndex:(bg.uiEffect == BackgroundUIEffectBlur ? 0 : 1)];
    effectRow.onSelect = ^(NSInteger index) {
        BackgroundManager *manager = [BackgroundManager sharedManager];
        manager.uiEffect = (index == 0) ? BackgroundUIEffectBlur : BackgroundUIEffectTranslucent;
        [manager refreshUIEffect];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundUIEffectChanged" object:nil];
    };
    self.effectRow = effectRow;

    // 背景不透明度（uiOpacity 0.1–1.0 → 10–100%；拖动即改 + refreshUIEffect）
    ZL2SettingRowSlider *opacityRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil
                                   minimum:10 maximum:100 suffix:@"%"];
    opacityRow.title = localize(@"ame369.setpg.bg_opacity", @"背景不透明度");
    [opacityRow ame_setValue:(NSInteger)round(bg.uiOpacity * 100.0)];
    opacityRow.onValueChanged = ^(NSInteger value) {
        [BackgroundManager sharedManager].uiOpacity = value / 100.0;
        [[BackgroundManager sharedManager] refreshUIEffect];
    };
    self.opacityRow = opacityRow;

    // 背景模糊强度（blurIntensity 0–1 → 0–100%）
    ZL2SettingRowSlider *blurRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil
                                   minimum:0 maximum:100 suffix:@"%"];
    blurRow.title = localize(@"ame369.setpg.bg_blur", @"背景模糊强度");
    [blurRow ame_setValue:(NSInteger)round(bg.blurIntensity * 100.0)];
    blurRow.onValueChanged = ^(NSInteger value) {
        // setter 内部落 Task256 blurUserSet 标记（模糊=0 为真实意图）
        [BackgroundManager sharedManager].blurIntensity = value / 100.0;
        [[BackgroundManager sharedManager] refreshUIEffect];
    };
    self.blurRow = blurRow;

    // ★Task428：节日彩蛋（general.festival_effects；BOOL 默认 YES——键缺省
    //   视为开，ZL2FestivalEffects attachToWindow 消费同口径；注册要求见
    //   文件头 ★Task428 注册注记）
    id ame428_festivalRaw = getPrefObject(@"general.festival_effects");
    BOOL ame428_festivalOn = ame428_festivalRaw ? [ame428_festivalRaw boolValue] : YES;
    ZL2SettingRowSwitch *festivalRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    festivalRow.title = localize(@"ame428.festival_effects.title", @"节日彩蛋");
    festivalRow.subtitle = localize(@"ame428.festival_effects.subtitle", @"节日期间在主界面播放主题特效（雪 / 烟花 / 萤火等）");
    [festivalRow ame_setOn:ame428_festivalOn];
    festivalRow.onToggle = ^(BOOL on) {
        setPrefBool(@"general.festival_effects", on);
    };
    self.festivalRow = festivalRow;

    ZL2SettingCardGroup *group1 = [[ZL2SettingCardGroup alloc] init];
    // ★ Task396：深浅模式行恢复后外观组五行（深浅/语言/效果/透明度/模糊）
    // ★Task428：+ 节日彩蛋行（外观/个性化组第 6 行）
    // ★Task429：+ 主题色板行（深浅行近邻第 2 位；8.1 动态主题模式选择）
    [group1 ame_addRows:@[themeRow, ame429_paletteRow, languageRow, effectRow, opacityRow, blurRow, festivalRow]];
    [self ame_addGroup:group1];
    // ★ Task328：插件贡献行动态组上移（Task327 挂页尾 = 用户不可达面重现——
    //   四内置插件已装载而用户仍报"没看到任何功能"：组在第 3 屏外）。上移到
    //   外观组之后第 2 位，进入首屏可视域。
    [self ame327_rebuildPluginRowsGroup];

    // ── ★ Task344 旧设置全量迁移：外观进阶组（旧 general 分区核心）──
    ZL2SettingCardGroup *advGroup = [[ZL2SettingCardGroup alloc] init];
    // 界面风格（★ Ame361：读写改走 LGC 中枢 = NSUserDefaults prisma.
    // interface_style，消费方 LiquidGlassCompat 同源——原 PLPreferences
    // general.interface_style 未注册被静默丢弃 = 新UI修改回退根因之一；
    // 写后延迟一拍重铺——Task226 闪退根修纪律）
    NSArray<NSString *> *styleKeys = @[@"auto", @"native", @"liquid_glass", @"pseudo_glass"];
    NSArray<NSString *> *styleNames = @[
        localize(@"prisma.interface_style.auto", nil),
        localize(@"prisma.interface_style.native", nil),
        localize(@"prisma.interface_style.liquid_glass", nil),
        localize(@"prisma.interface_style.pseudo_glass", nil),
    ];
    ZL2SettingRowList *styleRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:styleNames optionKeys:styleKeys];
    styleRow.title = localize(@"preference.title.interface_style", nil);
    styleRow.subtitle = localize(@"preference.detail.interface_style", nil);
    [styleRow ame_reloadSelectedIndex:(NSInteger)[styleKeys indexOfObject:
        LGCStringFromInterfaceStyle(LGCStoredInterfaceStyle())]];
    styleRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= styleKeys.count) return;
        // ★ Ame361：LGCSetStoredInterfaceStyle 落 NSUserDefaults 并广播
        //   LGCInterfaceStyleChangedNotification（全局风格链即时重铺）
        LGCSetStoredInterfaceStyle(LGCInterfaceStyleFromString(styleKeys[index]));
        // Task226：弹层收起事务先落地，重铺在干净事务边界执行
        dispatch_async(dispatch_get_main_queue(), ^{
            [[BackgroundManager sharedManager] refreshUIEffect];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundUIEffectChanged" object:nil];
        });
    };
    [advGroup ame_addRow:styleRow];
    // 伪玻璃透明度（Task263/276：游戏内也可调，不灰禁）
    // ★ Ame361：读写改走 LGC 中枢（prisma.pseudo_glass_transparency，
    //   0-100% ↔ 0.0-1.0 换算与旧页 Task263 同款）
    ZL2SettingRowSlider *pseudoRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil minimum:0 maximum:100 suffix:@"%"];
    pseudoRow.title = localize(@"preference.title.pseudo_glass_transparency", nil);
    pseudoRow.subtitle = localize(@"preference.detail.pseudo_glass_transparency", nil);
    [pseudoRow ame_setValue:(NSInteger)round(LGCPseudoGlassTransparency() * 100.0)];
    pseudoRow.onValueChanged = ^(NSInteger value) {
        LGCSetPseudoGlassTransparency((CGFloat)value / 100.0);
    };
    // 界面缩放 / 文字缩放（85-125 / 85-130，旧页同域）
    // ★ Ame361：读写改走 LGC 中枢（prisma.ui_scale / prisma.text_scale，
    //   百分比 ↔ 倍率换算 + 步进钳制 + 广播均由 LGC 层承担）
    ZL2SettingRowSlider *uiScaleRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil minimum:85 maximum:125 suffix:@"%"];
    uiScaleRow.title = localize(@"preference.title.ui_scale", nil);
    uiScaleRow.subtitle = localize(@"preference.detail.ui_scale", nil);
    [uiScaleRow ame_setValue:(NSInteger)round(LGCUIScaleMultiplier() * 100.0)];
    uiScaleRow.onValueChanged = ^(NSInteger value) {
        LGCSetUIScaleMultiplier((CGFloat)value / 100.0);
    };
    ZL2SettingRowSlider *textScaleRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil minimum:85 maximum:130 suffix:@"%"];
    textScaleRow.title = localize(@"preference.title.text_scale", nil);
    textScaleRow.subtitle = localize(@"preference.detail.text_scale", nil);
    [textScaleRow ame_setValue:(NSInteger)round(LGCTextScaleMultiplier() * 100.0)];
    textScaleRow.onValueChanged = ^(NSInteger value) {
        LGCSetTextScaleMultiplier((CGFloat)value / 100.0);
    };
    [advGroup ame_addRows:@[pseudoRow, uiScaleRow, textScaleRow]];
    // 旧壳侧栏隐藏（新壳无侧栏语义——保留键写入兼容但标注现状）
    ZL2SettingRowSwitch *sidebarRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    sidebarRow.title = localize(@"preference.title.hidden_sidebar", nil);
    sidebarRow.subtitle = localize(@"preference.detail.hidden_sidebar", nil);
    [sidebarRow ame_setOn:getPrefBool(@"general.hidden_sidebar")];
    sidebarRow.onToggle = ^(BOOL on) {
        setPrefBool(@"general.hidden_sidebar", on);
    };
    [advGroup ame_addRow:sidebarRow];
    // 自定义三色（强调/文字/卡片，UIColorPicker 平移）+ 一键还原
    ZL2SettingRowAction *accentRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    accentRow.title = localize(@"i18n_str_383", nil);
    accentRow.subtitle = localize(@"preference.detail.custom_accent_color", nil);
    accentRow.onTap = ^{ [weakSelf ame344_openColorPickerForKey:@"general.accent_color" title:localize(@"i18n_str_383", nil)]; };
    ZL2SettingRowAction *textColorRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    textColorRow.title = localize(@"i18n_str_384", nil);
    textColorRow.subtitle = localize(@"preference.detail.custom_text_color", nil);
    textColorRow.onTap = ^{ [weakSelf ame344_openColorPickerForKey:@"general.text_color" title:localize(@"i18n_str_384", nil)]; };
    ZL2SettingRowAction *cardColorRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    cardColorRow.title = localize(@"i18n_str_385", nil);
    cardColorRow.subtitle = localize(@"preference.detail.custom_card_color", nil);
    cardColorRow.onTap = ^{ [weakSelf ame344_openColorPickerForKey:@"general.card_color" title:localize(@"i18n_str_385", nil)]; };
    ZL2SettingRowAction *resetColorsRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    resetColorsRow.title = localize(@"i18n_str_386", nil);
    resetColorsRow.subtitle = localize(@"ame369.setpg.reset_colors.subtitle", @"恢复强调色/文字色/卡片色出厂默认");
    resetColorsRow.onTap = ^{
        setPrefObject(@"general.accent_color", @"");
        setPrefObject(@"general.text_color", @"");
        setPrefObject(@"general.card_color", @"");
        [[NSNotificationCenter defaultCenter] postNotificationName:@"LauncherAppearanceChanged" object:nil];
    };
    [advGroup ame_addRows:@[accentRow, textColorRow, cardColorRow, resetColorsRow]];
    // 应用图标（默认/自定义图库两态；CustomIconManager 链平移）
    NSArray<NSString *> *iconKeys = @[@"AppIcon-Light", @"CustomIcon"];
    NSArray<NSString *> *iconNames = @[
        localize(@"preference.title.appicon-default", nil),
        localize(@"preference.title.appicon-custom", nil),
    ];
    ZL2SettingRowList *iconRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:iconNames optionKeys:iconKeys];
    iconRow.title = localize(@"preference.title.appicon", nil);
    iconRow.subtitle = localize(@"preference.detail.appicon", nil);
    BOOL hasCustom = [[CustomIconManager sharedManager] hasCustomIcon];
    [iconRow ame_reloadSelectedIndex:(hasCustom ? 1 : 0)];
    iconRow.onSelect = ^(NSInteger index) {
        if (index == 0) {
            [[CustomIconManager sharedManager] removeCustomIcon];
            [UIApplication.sharedApplication setAlternateIconName:nil completionHandler:nil];
        } else {
            if (![[CustomIconManager sharedManager] hasCustomIcon]) {
                [weakSelf ame_presentVC:([UIAlertController
                    alertControllerWithTitle:localize(@"i18n_str_388", nil)
                                      message:localize(@"i18n_str_389", nil)
                               preferredStyle:UIAlertControllerStyleAlert])];
                return;
            }
            [[CustomIconManager sharedManager] setCustomIconWithCompletion:^(BOOL success, NSError * _Nullable error) {
                if (!success && error) {
                    NSLog(@"[ZL2Settings] appicon error: %@", error);
                }
            }];
        }
    };
    [advGroup ame_addRow:iconRow];
    [self ame_addGroup:advGroup];

    // --- 组 2：下载源（download.* 四分类真键；值域 official/mirror/speed_first）---
    NSArray<NSString *> *sourceKeys = @[@"official_first", @"mirror_first", @"speed_first"];
    NSArray<NSString *> *sourceNames = @[
        localize(@"preference.title.mirror_policy-official_first", nil),
        localize(@"preference.title.mirror_policy-mirror_first", nil),
        localize(@"preference.title.mirror_policy-speed_first", nil),
    ];
    NSDictionary<NSString *, NSString *> *sourceTitles = @{
        @"download.mod_mirror":           localize(@"ame369.setpg.src.mod_mirror", @"模组镜像源"),
        @"download.fileSource":          localize(@"ame369.setpg.src.file", @"文件下载源"),
        @"download.assetSearchSource":   localize(@"ame369.setpg.src.asset_search", @"资源搜索源"),
        @"download.assetDownloadSource": localize(@"ame369.setpg.src.asset_download", @"资源下载源"),
        @"download.modLoaderSource":     localize(@"ame369.setpg.src.modloader", @"加载器下载源"),
    };
    NSMutableArray<ZL2SettingRowList *> *sourceRows = [NSMutableArray array];
    NSMutableArray<NSString *> *sourceRowKeys = [NSMutableArray array];
    for (NSString *prefKey in sourceTitles) {
        ZL2SettingRowList *row =
            [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                     options:sourceNames optionKeys:sourceKeys];
        row.title = sourceTitles[prefKey];
        // ★ Ame361：mod_mirror 是虚键（PLPreferences 未注册，Setter 静默
        //   丢弃 = 回退根因之一）——对齐旧页 Task138 粗控协议：读写均落
        //   已注册主键 assetSearchSource，写时同步 assetDownloadSource。
        NSString *ame361_readKey = [prefKey isEqualToString:@"download.mod_mirror"]
            ? @"download.assetSearchSource" : prefKey;
        // 显示兜底（Task218 口径）：缺值/非法值 → 出厂默认 speed_first
        NSString *value = ame_pages_stringOr(getPrefObject(ame361_readKey), @"speed_first");
        BOOL valid = [sourceKeys containsObject:value];
        [row ame_reloadSelectedIndex:
            valid ? (NSInteger)[sourceKeys indexOfObject:value]
                  : (NSInteger)[sourceKeys indexOfObject:@"speed_first"]];
        row.onSelect = ^(NSInteger index) {
            if (index < 0 || (NSUInteger)index >= sourceKeys.count) return;
            if ([prefKey isEqualToString:@"download.mod_mirror"]) {
                // ★ Ame361：粗控一体写入（旧页 Task138 同款：模组 API 搜索
                //   与文件下载同属 MCIM 体系，双键同步变更）
                setPrefString(@"download.assetSearchSource", sourceKeys[index]);
                setPrefString(@"download.assetDownloadSource", sourceKeys[index]);
            } else {
                setPrefString(prefKey, sourceKeys[index]);
            }
            // speed_first 测速引擎立即跟上（mod_mirror 行 Task138 同款）
            [PLMirrorCenter startSpeedProbesIfNeeded];
        };
        [sourceRows addObject:row];
        [sourceRowKeys addObject:prefKey];
    }
    self.sourceRows = [sourceRows copy];
    self.sourceRowKeys = [sourceRowKeys copy];

    ZL2SettingCardGroup *group2 = [[ZL2SettingCardGroup alloc] init];
    [group2 ame_addRows:[sourceRows copy]];
    [self ame_addGroup:group2];

    // ── ★ Task344 旧设置全量迁移：下载完整性与公告组 ──
    ZL2SettingCardGroup *miscGroup = [[ZL2SettingCardGroup alloc] init];
    // 下载完整性校验（general.check_sha）
    ZL2SettingRowSwitch *shaRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    shaRow.title = localize(@"preference.title.check_sha", nil);
    shaRow.subtitle = localize(@"preference.detail.check_sha", nil);
    [shaRow ame_setOn:getPrefBool(@"general.check_sha")];
    shaRow.onToggle = ^(BOOL on) {
        setPrefBool(@"general.check_sha", on);
    };
    // ★Task428：校验并补全游戏文件（PLGameIntegrityService 契约入口——
    //   +sharedService / -runInteractiveVerifyAndRepairFromViewController:；
    //   运行时软链调用，见 ame428_runIntegrityVerify）
    ZL2SettingRowAction *integrityRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    integrityRow.title = localize(@"ame428.integrity.verify", @"校验并补全游戏文件");
    integrityRow.subtitle = localize(@"ame428.integrity.verify.subtitle", @"对照清单校验当前游戏目录，自动补全缺失或损坏的文件");
    integrityRow.onTap = ^{
        [weakSelf ame428_runIntegrityVerify];
    };
    // ★Task428（1.2）：全局隔离默认档（general.isolation_default；HMCL 语义
    //   三态：0=自动 MODDED / 1=始终 ALWAYS / 2=从不 NEVER）。位置按任务书
    //   放 check_sha/完整性组附近。改档导致某版本有效隔离翻转时走
    //   确认框 + 一次性下沉（ame428_applyGlobalIsolation…）；取消 = 不改档。
    //   行值回滚由 ame_reloadSelectedIndex 承接（List 行自带徽章同步）。
    ZL2SettingRowList *isoRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:@[
                                     localize(@"ame428.iso.global.auto", @"自动（有模组/加载器的版本隔离）"),
                                     localize(@"ame428.iso.global.always", @"始终隔离"),
                                     localize(@"ame428.iso.global.never", @"从不隔离"),
                                 ] optionKeys:@[@"0", @"1", @"2"]];
    isoRow.title = localize(@"ame428.iso.global.title", @"版本隔离默认");
    isoRow.subtitle = localize(@"ame428.iso.global.subtitle", @"新版本未单独设置时遵循的全局默认；每版本可在版本详情页覆盖");
    {
        NSInteger ame428_g = getPrefInt(@"general.isolation_default");
        if (ame428_g < 0 || ame428_g > 2) ame428_g = 0;
        [isoRow ame_reloadSelectedIndex:ame428_g];
    }
    isoRow.onSelect = ^(NSInteger index) {
        if (index < 0 || index > 2) return;
        NSInteger ame428_old = getPrefInt(@"general.isolation_default");
        if (ame428_old < 0 || ame428_old > 2) ame428_old = 0;
        if (ame428_old == index) return;
        [weakSelf ame428_applyGlobalIsolationFrom:ame428_old to:index row:isoRow];
    };
    // 多线程下载（general.multi_threaded）
    ZL2SettingRowSwitch *mtRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    mtRow.title = localize(@"i18n_str_387", nil);
    mtRow.subtitle = localize(@"preference.detail.multi_threaded", nil);
    [mtRow ame_setOn:getPrefBool(@"general.multi_threaded")];
    mtRow.onToggle = ^(BOOL on) {
        setPrefBool(@"general.multi_threaded", on);
    };
    // ★Task428：下载并发数（general.download_threads；int 0=自动（16-64
    //   自适应）/ 8-64 手动；键名契约由并行工程师的下载引擎按同名键消费；
    //   注册要求见文件头 ★Task428 注册注记）。
    //   整数滑条 0-64 承载：0 档徽章显「自动」，1-7 非法档夹到 8。
    id ame428_threadsRaw = getPrefObject(@"general.download_threads");
    NSInteger ame428_threads = ame428_threadsRaw ? [ame428_threadsRaw intValue] : 0;
    if (ame428_threads != 0 && (ame428_threads < 8 || ame428_threads > 64)) ame428_threads = 0;
    ZL2SettingRowSlider *dlThreadRow =
        [[ZL2SettingRowSlider alloc] initWithTitle:@"" subtitle:nil
                                   minimum:0 maximum:64 suffix:@""];
    dlThreadRow.title = localize(@"ame428.download_threads.title", @"下载并发数");
    dlThreadRow.subtitle = localize(@"ame428.download_threads.subtitle", @"同时下载的文件数；0 为自动");
    dlThreadRow.valueTextBlock = ^NSString *(NSInteger value) {
        if (value <= 0) {
            return localize(@"ame428.download_threads.auto", @"自动（16-64 自适应）");
        }
        if (value < 8) value = 8;   // 1-7 非法档：徽章按实际落值显示
        return [NSString stringWithFormat:@"%ld", (long)value];
    };
    [dlThreadRow ame_setValue:ame428_threads];
    dlThreadRow.onValueChanged = ^(NSInteger value) {
        if (value > 0 && value < 8) value = 8;
        setPrefInt(@"general.download_threads", value);
    };
    // ★Task429（PDF 13.2）：下载镜像三态选择器（general.mirror_mode；int
    //   0=自动（大陆 BMCLAPI 优先，Task428 4.1 大陆探测默认档语义）/ 1=官方 /
    //   2=手动（BMCLAPI））。落位「下载并发数」行后（下载域聚簇）；组件口径 =
    //   本页既有 ZL2SettingRowList（isoRow 同款 M3 行内选择器）；服务侧消费由
    //   镜像服务层另行接（PLMirrorCenter）。键注册片段见
    //   scripts/task429_prefs_BC.json——PLPreferences.m 非本工位写权（Setter
    //   静默丢弃族同判例）：未注册期写值被丢弃，读侧缺键回退默认 0 不受影响。
    ZL2SettingRowList *ame429_mirrorRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:@[
                                     localize(@"ame429.bc.mirror.auto", @"自动（大陆 BMCLAPI 优先）"),
                                     localize(@"ame429.bc.mirror.official", @"官方"),
                                     localize(@"ame429.bc.mirror.manual", @"手动（BMCLAPI）"),
                                 ] optionKeys:@[@"0", @"1", @"2"]];
    ame429_mirrorRow.title = localize(@"ame429.bc.mirror.title", @"下载镜像");
    ame429_mirrorRow.subtitle = localize(@"ame429.bc.mirror.subtitle", @"游戏文件下载走官方源还是 BMCLAPI 镜像");
    {
        NSInteger ame429_mode = getPrefInt(@"general.mirror_mode");
        if (ame429_mode < 0 || ame429_mode > 2) ame429_mode = 0;
        [ame429_mirrorRow ame_reloadSelectedIndex:ame429_mode];
    }
    ame429_mirrorRow.onSelect = ^(NSInteger index) {
        if (index < 0 || index > 2) return;
        setPrefInt(@"general.mirror_mode", index);
    };
    // ★Task429 S1（PDF 六 §4.4）：下载代理三态 + 主机 + 端口（general.proxy_mode/
    //   general.proxy_host/general.proxy_port——注册片段 scripts/task429_prefs_S1.json，
    //   Setter 静默丢弃族同判例：注册前写值被丢弃，读侧缺键回退默认不受影响）。
    //   落位紧随镜像行（下载域聚簇）；组件口径 = 本页既有 ZL2SettingRowList /
    //   ZL2SettingRowInput。生效面单一事实源 = PLDownloadClient
    //   +ame429_s1_syncProxyEnvFromPrefs / +ame429_s1_connectionProxyDictionaryFromPrefs：
    //   三行任一落值即物化游戏侧 AMETHYST_SOCKS5_PROXY 环境变量（mode==2 且
    //   host/port 合法 → setenv，否则 unsetenv；与 MultiplayerManager 联机通道
    //   同键双通道一致）；启动器下载会话代理在会话构造点注入（会话固化 =
    //   下轮进程生效，行注记已声明）。最小追加：仅新增三行与数组登记，
    //   不触碰并行工位行。
    ZL2SettingRowList *ame429_s1_proxyModeRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:@[
                                     localize(@"ame429.s1.proxy.off", @"关闭"),
                                     localize(@"ame429.s1.proxy.http", @"HTTP"),
                                     localize(@"ame429.s1.proxy.socks", @"SOCKS5"),
                                 ] optionKeys:@[@"0", @"1", @"2"]];
    ame429_s1_proxyModeRow.title = localize(@"ame429.s1.proxy.title", @"下载代理");
    ame429_s1_proxyModeRow.subtitle = localize(@"ame429.s1.proxy.subtitle", @"启动器下载与游戏内网络（SOCKS5）的代理通道");
    {
        NSInteger ame429_s1_mode = getPrefInt(@"general.proxy_mode");
        if (ame429_s1_mode < 0 || ame429_s1_mode > 2) ame429_s1_mode = 0;
        [ame429_s1_proxyModeRow ame_reloadSelectedIndex:ame429_s1_mode];
    }
    ame429_s1_proxyModeRow.onSelect = ^(NSInteger index) {
        if (index < 0 || index > 2) return;
        setPrefInt(@"general.proxy_mode", index);
        [PLDownloadClient ame429_s1_syncProxyEnvFromPrefs];
    };
    ZL2SettingRowInput *ame429_s1_proxyHostRow =
        [[ZL2SettingRowInput alloc] initWithTitle:@"" subtitle:nil
                              placeholder:localize(@"ame429.s1.proxy.host.placeholder", @"例如 127.0.0.1")
                                     text:ame_pages_stringOr(getPrefObject(@"general.proxy_host"), @"")];
    ame429_s1_proxyHostRow.title = localize(@"ame429.s1.proxy.host.title", @"代理主机");
    ame429_s1_proxyHostRow.subtitle = localize(@"ame429.s1.proxy.host.subtitle", @"主机名或 IP；留空 = 不启用代理");
    ame429_s1_proxyHostRow.onTextChanged = ^(NSString *text) {
        setPrefString(@"general.proxy_host", text ?: @"");
        [PLDownloadClient ame429_s1_syncProxyEnvFromPrefs];
    };
    ZL2SettingRowInput *ame429_s1_proxyPortRow =
        [[ZL2SettingRowInput alloc] initWithTitle:@"" subtitle:nil
                              placeholder:localize(@"ame429.s1.proxy.port.placeholder", @"例如 1080")
                                     text:ame_pages_stringOr(getPrefObject(@"general.proxy_port"), @"")];
    ame429_s1_proxyPortRow.title = localize(@"ame429.s1.proxy.port.title", @"代理端口");
    ame429_s1_proxyPortRow.subtitle = localize(@"ame429.s1.proxy.port.subtitle", @"1-65535；非法值视为未配置");
    ame429_s1_proxyPortRow.onTextChanged = ^(NSString *text) {
        setPrefString(@"general.proxy_port", text ?: @"");
        [PLDownloadClient ame429_s1_syncProxyEnvFromPrefs];
    };
    // CurseForge API Key（表单页模态，旧页同款）
    ZL2SettingRowAction *cfKeyRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    cfKeyRow.title = localize(@"preference.title.curseforge_api_key", nil);
    cfKeyRow.subtitle = localize(@"preference.detail.curseforge_api_key", nil);
    cfKeyRow.onTap = ^{
        CurseForgeAPIKeyViewController *vc = [[CurseForgeAPIKeyViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [weakSelf ame_presentVC:nav];
    };
    // ★Task429：+ ame429_mirrorRow（下载镜像三态，紧随下载并发数行）
    // ★Task429 S1：+ 代理三行（下载代理/代理主机/代理端口，紧随镜像行）
    [miscGroup ame_addRows:@[shaRow, integrityRow, isoRow, mtRow, dlThreadRow, ame429_mirrorRow,
                             ame429_s1_proxyModeRow, ame429_s1_proxyHostRow, ame429_s1_proxyPortRow,
                             cfKeyRow]];
    // 调试日志（general.debug_logging；游戏会话下轮生效——Task205 口径）
    ZL2SettingRowSwitch *dbgLogRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    dbgLogRow.title = localize(@"preference.title.debug_logging", nil);
    dbgLogRow.subtitle = localize(@"preference.detail.debug_logging", nil);
    [dbgLogRow ame_setOn:getPrefBool(@"general.debug_logging")];
    dbgLogRow.onToggle = ^(BOOL on) {
        debugLogEnabled = on;
        NSLog(@"[Debugging] Debug log enabled: %@ (renderer diagnostics verbose from next game session)", on ? @"YES" : @"NO");
    };
    // 公告预览等级（full/summary/title_only）
    NSArray<NSString *> *apvKeys = @[@"full", @"summary", @"title_only"];
    NSArray<NSString *> *apvNames = @[
        localize(@"i18n_str_390", nil),
        localize(@"i18n_str_391", nil),
        localize(@"i18n_str_392", nil),
    ];
    ZL2SettingRowList *apvRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:apvNames optionKeys:apvKeys];
    apvRow.title = localize(@"preference.title.announcement_preview_level", nil);
    apvRow.subtitle = localize(@"preference.detail.announcement_preview_level", nil);
    [apvRow ame_reloadSelectedIndex:(NSInteger)[apvKeys indexOfObject:
        ame_pages_stringOr(getPrefObject(@"general.announcement_preview_level"), @"full")]];
    apvRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= apvKeys.count) return;
        setPrefString(@"general.announcement_preview_level", apvKeys[index]);
    };
    [miscGroup ame_addRows:@[dbgLogRow, apvRow]];
    [self ame_addGroup:miscGroup];

    // ── ★ Task344 旧设置全量迁移：数据管理组（导出/导入/兄弟迁移/重置）──
    ZL2SettingCardGroup *dataGroup = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *exportRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    exportRow.title = localize(@"preference.title.data_export", nil);
    exportRow.subtitle = localize(@"preference.detail.data_export", nil);
    exportRow.onTap = ^{
        [weakSelf ame_push:[[DataExportViewController alloc] init]
                   titled:localize(@"preference.title.data_export", nil)];
    };
    ZL2SettingRowAction *importRow2 =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    importRow2.title = localize(@"preference.title.data_import", nil);
    importRow2.subtitle = localize(@"preference.detail.data_import", nil);
    importRow2.onTap = ^{
        [[DataTransferService sharedService] importDataFromViewController:weakSelf];
    };
    ZL2SettingRowAction *siblingRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    siblingRow.title = localize(@"preference.title.data_sibling_import", nil);
    siblingRow.subtitle = localize(@"preference.detail.data_sibling_import", nil);
    siblingRow.onTap = ^{
        [weakSelf ame261_siblingImportTapped];
    };
    ZL2SettingRowAction *eraseDemoRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    eraseDemoRow.title = localize(@"preference.title.erase_demo_data", nil);
    eraseDemoRow.subtitle = localize(@"ame369.setpg.erase_demo.subtitle", @"删除内置演示账户的全部游戏数据");
    eraseDemoRow.errorState = YES;
    eraseDemoRow.onTap = ^{
        NSString *demoPath = [NSString stringWithFormat:@"%s/.demo", getenv("POJAV_HOME")];
        BOOL hasDemo = [NSFileManager.defaultManager contentsOfDirectoryAtPath:demoPath error:nil].count > 0;
        if (!hasDemo || !ame_pages_whenNotInGame()) return;
        [ZL2M3Dialog showTitle:localize(@"preference.title.erase_demo_data", nil)
                          body:localize(@"preference.title.confirm.erase_demo_data", nil)
                  confirmTitle:localize(@"OK", nil)
                   destructive:YES
                    onConfirm:^{
            NSError *error;
            if ([NSFileManager.defaultManager removeItemAtPath:demoPath error:&error]) {
                [NSFileManager.defaultManager createDirectoryAtPath:demoPath
                                        withIntermediateDirectories:YES attributes:nil error:nil];
            } else {
                NSLog(@"[ZL2Settings] erase_demo_data error: %@", error);
            }
        }
                      onCancel:nil];
    };
    ZL2SettingRowAction *resetWarnRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    resetWarnRow.title = localize(@"preference.title.reset_warnings", nil);
    resetWarnRow.subtitle = localize(@"ame369.setpg.reset_warnings.subtitle", @"重新显示此前永久关闭的安全提示");
    resetWarnRow.onTap = ^{
        resetWarnings();
    };
    ZL2SettingRowAction *resetSetRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    resetSetRow.title = localize(@"preference.title.reset_settings", nil);
    resetSetRow.subtitle = localize(@"ame369.setpg.reset_prefs.subtitle", @"所有自定义首选项恢复出厂");
    resetSetRow.errorState = YES;
    resetSetRow.onTap = ^{
        [ZL2M3Dialog showTitle:localize(@"preference.title.reset_settings", nil)
                          body:localize(@"preference.title.confirm.reset_settings", nil)
                  confirmTitle:localize(@"OK", nil)
                   destructive:YES
                    onConfirm:^{
            loadPreferences(YES);
            [weakSelf ame_rebuildGroups];
        }
                      onCancel:nil];
    };
    [dataGroup ame_addRows:@[exportRow, importRow2, siblingRow, eraseDemoRow, resetWarnRow, resetSetRow]];
    [self ame_addGroup:dataGroup];

    // --- 组 3：入口 ---
    ZL2SettingCardGroup *group3 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *backgroundRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    backgroundRow.title = localize(@"ame369.setpg.background", @"背景设置");
    backgroundRow.onTap = ^{
        [weakSelf ame_push:[[BackgroundSettingsViewController alloc] init] titled:localize(@"ame369.setpg.background", @"背景设置")];
    };
    ZL2SettingRowAction *galleryRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    galleryRow.title = localize(@"ame369.setpg.wallpaper_gallery", @"壁纸画廊");
    galleryRow.onTap = ^{
        // 工厂方法返回按设备宽度预配置网格布局的 UICollectionViewController
        [weakSelf ame_push:[BingWallpaperGalleryViewController galleryController] titled:localize(@"ame369.setpg.wallpaper_gallery", @"壁纸画廊")];
    };
    ZL2SettingRowAction *moreRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    moreRow.title = localize(@"ame369.setpg.more_launcher", @"更多启动器设置");
    moreRow.subtitle = localize(@"ame369.setpg.more_launcher.subtitle", @"界面缩放、强调色、公告、数据导出等完整分区");
    moreRow.onTap = ^{
        [weakSelf ame_push:[[LauncherPreferencesViewController alloc] init] titled:localize(@"ame369.common.more_settings", @"更多设置")];
    };
    // Task316（文件层桌面/安卓同构）：游戏目录/实例切换入口 + 跨启动器导入
    ZL2SettingRowAction *gameDirRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    gameDirRow.title = localize(@"ame369.setpg.gamedir_instances", @"游戏目录与实例");
    gameDirRow.subtitle = localize(@"ame369.setpg.gamedir_instances.subtitle", @"查看/切换实例目录（instances），切换后重启生效");
    gameDirRow.onTap = ^{
        [weakSelf ame_push:[[LauncherPrefGameDirViewController alloc] init]
                   titled:localize(@"preference.title.game_directory", nil)];
    };
    ZL2SettingRowAction *importRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    importRow.title = localize(@"ame369.setpg.import_external", @"导入外部启动器数据");
    importRow.subtitle = localize(@"ame369.setpg.import_external.subtitle", @"识别 .minecraft / HMCL·PCL / MultiMC·Prism / 安卓启动器目录，合入当前实例");
    importRow.onTap = ^{
        [weakSelf ame316_pickExternalFolder];
    };
    // Task317：插件管理入口（列表/安装/权限授权/启停）
    ZL2SettingRowAction *pluginRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    pluginRow.title = localize(@"ame317.list.title", nil);
    pluginRow.subtitle = localize(@"ame317.settings.entry_subtitle", nil);
    pluginRow.onTap = ^{
        [weakSelf ame_push:[[ZL2PluginListViewController alloc] init]
                   titled:localize(@"ame317.list.title", nil)];
    };
    // Task318：内置插件仓库（随包预置插件浏览/一键安装）
    ZL2SettingRowAction *repoRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    repoRow.title = localize(@"ame318.repo.title", nil);
    repoRow.subtitle = localize(@"ame318.repo.entry_subtitle", nil);
    repoRow.onTap = ^{
        [weakSelf ame_push:[[ZL2PluginRepoViewController alloc] init]
                   titled:localize(@"ame318.repo.title", nil)];
    };
    [group3 ame_addRows:@[backgroundRow, galleryRow, gameDirRow, importRow, pluginRow, repoRow, moreRow]];
    [self ame_addGroup:group3];
    // ★ Task327：插件贡献行动态组（Task318 ame.addLauncherRow 的消费端）
    //   ★ Task328：构建点已上移至外观组之后（首屏可视域），见彼处注释
}

/// ★ Task327：插件贡献行动态组。数据源 = [AmePluginRuntime allContributedRows]
///   （每行 spec：id/title/subtitle/pluginName，由插件经 ame.addLauncherRow
///   贡献）；点按经 invokeRowTap: 转发回插件 JS。无贡献行时不建组（页面
///   零残留）；viewWillAppear 重建 = 插件启用/停用/装载即刻反映。
- (void)ame327_rebuildPluginRowsGroup {
    if (self.ame327_pluginHeader.superview) {
        [self.groupsStack removeArrangedSubview:self.ame327_pluginHeader];
        [self.ame327_pluginHeader removeFromSuperview];
        self.ame327_pluginHeader = nil;
    }
    if (self.ame327_pluginGroup.superview) {
        [self.groupsStack removeArrangedSubview:self.ame327_pluginGroup];
        [self.ame327_pluginGroup removeFromSuperview];
        self.ame327_pluginGroup = nil;
    }
    NSArray<NSDictionary *> *rows = [AmePluginRuntime allContributedRows];
    if (rows.count == 0) return;
    UILabel *header = [[UILabel alloc] init];
    // ★ Task328：标题带贡献行计数（"(N)" = 插件确实在跑的可见信号；计数
    //   经 ASCII 括号拼接而非格式化本地化串，避免译文含 % 的格式串雷）
    header.text = [NSString stringWithFormat:@"%@ (%ld)",
                   localize(@"ame327.plugin.rows.title", nil), (long)rows.count];
    header.font = [ZL2Theme fontLabelLarge];
    header.textColor = [ZL2Theme onSurfaceVariant];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.groupsStack addArrangedSubview:header];
    self.ame327_pluginHeader = header;

    ZL2SettingCardGroup *group = [[ZL2SettingCardGroup alloc] init];
    for (NSDictionary *spec in rows) {
        if (![spec isKindOfClass:[NSDictionary class]]) continue;
        NSString *rowId = [spec[@"id"] isKindOfClass:[NSString class]] ? spec[@"id"] : nil;
        if (rowId.length == 0) continue;
        // CI r0 实锤：&& 链不做类型收窄，id 上取 .length 编译雷——先收窄再取值
        NSString *rawTitle = [spec[@"title"] isKindOfClass:[NSString class]] ? spec[@"title"] : nil;
        NSString *title = rawTitle.length ? rawTitle : rowId;
        NSString *sub = [spec[@"subtitle"] isKindOfClass:[NSString class]] ? spec[@"subtitle"] : nil;
        NSString *pluginName = [spec[@"pluginName"] isKindOfClass:[NSString class]] ? spec[@"pluginName"] : nil;
        if (pluginName.length) {
            sub = sub.length
                ? [NSString stringWithFormat:@"%@ · %@", sub, pluginName]
                : [NSString stringWithFormat:@"%@", pluginName];
        }
        ZL2SettingRowAction *row = [[ZL2SettingRowAction alloc] initWithTitle:title subtitle:sub];
        __weak typeof(self) wself = self;
        row.onTap = ^{
            [AmePluginRuntime invokeRowTap:rowId];
            // 贡献行可能增删（个别插件点按后重组行集），0.4s 后重建动态组
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [wself ame327_rebuildPluginRowsGroup];
            });
        };
        [group ame_addRow:row];
    }
    [self ame_addGroup:group];
    self.ame327_pluginGroup = group;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // ★ Task327：插件启停/装载变化（管理页开关、详情页授权、仓库安装）回
    //   到本页即刻反映（贡献行集重建）
    [self ame327_rebuildPluginRowsGroup];
}

- (void)ame_refreshState {
    // ★ Task396：深浅模式行恢复，刷新面回归 深浅/语言/效果/透明度/模糊
    NSString *theme = ame_pages_stringOr(getPrefObject(@"general.ui_theme"), @"auto");
    [self.themeRow ame_reloadSelectedIndex:
        (NSInteger)[@[@"dark", @"light", @"auto"] indexOfObject:theme]];
    // 语言
    NSArray<NSString *> *langCodes =
        [@[@"system"] arrayByAddingObjectsFromArray:
            [ZL2LauncherSettingsPage ame_availableLanguageCodes]];
    NSString *language = ame_pages_stringOr(getPrefObject(@"general.app_language"), @"system");
    [self.languageRow ame_reloadSelectedIndex:(NSInteger)[langCodes indexOfObject:language]];
    // 效果与两滑条
    BackgroundManager *bg = [BackgroundManager sharedManager];
    [self.effectRow ame_reloadSelectedIndex:(bg.uiEffect == BackgroundUIEffectBlur ? 0 : 1)];
    [self.opacityRow ame_setValue:(NSInteger)round(bg.uiOpacity * 100.0)];
    [self.blurRow ame_setValue:(NSInteger)round(bg.blurIntensity * 100.0)];
    // 下载源
    NSArray<NSString *> *sourceKeys = @[@"official_first", @"mirror_first", @"speed_first"];
    for (NSUInteger i = 0; i < self.sourceRows.count && i < self.sourceRowKeys.count; i++) {
        NSString *value =
            ame_pages_stringOr(getPrefObject(self.sourceRowKeys[i]), @"speed_first");
        BOOL valid = [sourceKeys containsObject:value];
        [self.sourceRows[i] ame_reloadSelectedIndex:
            valid ? (NSInteger)[sourceKeys indexOfObject:value] : 2];
    }
    // ★Task428：节日彩蛋随切轨刷新（键缺省视为开，同建行口径）
    id ame428_festivalRaw = getPrefObject(@"general.festival_effects");
    [self.festivalRow ame_setOn:ame428_festivalRaw ? [ame428_festivalRaw boolValue] : YES];
    // ★Task429：主题色板随切轨刷新（mode → UI 列表位回显；mode 2 重演占位归位 embermire 位）
    {
        NSArray<NSNumber *> *ame429_modes = @[@0, @1, @3, @4, @5, @6, @7, @8];
        NSInteger ame429_mode = [[ZL2DynamicPalette shared] themeMode];
        NSUInteger ame429_uiIndex = 0;
        for (NSUInteger i = 0; i < ame429_modes.count; i++) {
            if (ame429_modes[i].integerValue == ame429_mode) {
                ame429_uiIndex = i;
                break;
            }
        }
        [self.ame429_paletteRow ame_reloadSelectedIndex:(NSInteger)ame429_uiIndex];
    }
}

#pragma mark - Task344 旧 general 分区助手（旧 VC 平移）

// ★Task428：校验并补全游戏文件（PLGameIntegrityService 契约：
//   +sharedService / -runInteractiveVerifyAndRepairFromViewController:）。
//   头文件由并行工程师实装、主控合流保证存在——此处按运行时软链调用
//   （NSClassFromString + performSelector），本文件先合入也不依赖
//   编译期符号；服务未就绪时明确提示而非静默。
- (void)ame428_runIntegrityVerify {
    Class ame428_svcClass = NSClassFromString(@"PLGameIntegrityService");
    if (ame428_svcClass == nil) {
        [self ame344_showNotice:localize(@"ame428.integrity.unavailable", @"校验服务在当前构建暂不可用")];
        return;
    }
    id ame428_shared = nil;
    if ([ame428_svcClass respondsToSelector:@selector(sharedService)]) {
        ame428_shared = [ame428_svcClass performSelector:@selector(sharedService)];
    }
    // ★Task429：入口保留（全局设置语义，PDF 3.3）；软链改调实例级新 API 传
    //   nil（= 全局当前档，与旧 selector 语义等价——服务侧旧方法已改为
    //   thin wrapper 兜底，两 selector 皆可命中，主用新键防旧键退役漂移）。
    if (ame428_shared != nil &&
        [ame428_shared respondsToSelector:@selector(runInteractiveVerifyAndRepairForProfile:fromViewController:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [ame428_shared performSelector:@selector(runInteractiveVerifyAndRepairForProfile:fromViewController:)
                            withObject:nil
                            withObject:self];
#pragma clang diagnostic pop
    } else if (ame428_shared != nil &&
        [ame428_shared respondsToSelector:@selector(runInteractiveVerifyAndRepairFromViewController:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [ame428_shared performSelector:@selector(runInteractiveVerifyAndRepairFromViewController:)
                              withObject:self];
#pragma clang diagnostic pop
    } else {
        [self ame344_showNotice:localize(@"ame428.integrity.unavailable", @"校验服务在当前构建暂不可用")];
    }
}

// ---------------------------------------------------------------------------
// ★Task428（1.2/1.4）：全局隔离档变更 = 翻转计算 + 确认 + 批量下沉/回迁。
//   翻转集合来自 PLProfiles ame428_computeGlobalFlips（A1 profile 唯一 vid
//   集，按 lastPlayed 降序——共享根数据归最近游玩的版本；多版本同时翻转
//   时第一顺位取得数据，其余执行期自然扑空跳过，迁移报告逐条留痕）。
//   取消 = 不改档（行值由调用方回滚）；确认 = 进度弹窗 → 后台逐个执行
//   （快照→copy 全→删源，中途失败恢复）→ 全部完成后才 setPrefInt 落档
//   + ReloadProfileList（首页/版本页同步刷新）。仅无翻转时静默直改。
// ---------------------------------------------------------------------------
- (void)ame428_applyGlobalIsolationFrom:(NSInteger)oldG to:(NSInteger)newG row:(ZL2SettingRowList *)row {
    if (oldG == newG) return;
    NSArray<NSDictionary *> *ame428_flips = [PLProfiles ame428_computeGlobalFlipsFrom:oldG to:newG];
    if (ame428_flips.count == 0) {
        setPrefInt(@"general.isolation_default", newG);
        return;
    }
    // 确认清单（逐版本：方向 + 将搬移条目）
    NSMutableArray<NSString *> *ame428_lines = [NSMutableArray array];
    NSMutableArray<NSString *> *ame428_moving = [NSMutableArray array];
    for (NSDictionary *ame428_f in ame428_flips) {
        NSArray<NSString *> *ame428_items = [ame428_f[@"items"] isKindOfClass:[NSArray class]]
            ? ame428_f[@"items"] : @[];
        if (ame428_items.count == 0) continue;   // 无候选：无需确认（执行期 noop）
        [ame428_moving addObject:ame428_f[@"vid"]];
        NSString *ame428_dir = ([ame428_f[@"to"] integerValue] == 1)
            ? localize(@"ame428.iso.flip.into", @"移入独立目录")
            : localize(@"ame428.iso.flip.outof", @"移回实例根目录");
        [ame428_lines addObject:[NSString stringWithFormat:
            @"· %@：%@（%@）", ame428_f[@"vid"], ame428_dir,
            [ame428_items componentsJoinedByString:@", "]]];
    }
    if (ame428_moving.count == 0) {
        setPrefInt(@"general.isolation_default", newG);
        return;
    }
    UIAlertController *ame428_alert = [UIAlertController
        alertControllerWithTitle:localize(@"ame428.iso.confirm.title", @"确认数据迁移")
                         message:[NSString stringWithFormat:
                             @"%@\n\n%@\n%@\n%@",
                             [NSString stringWithFormat:localize(@"ame428.iso.global.confirm", @"切换全局默认档将使以下版本的有效隔离状态翻转（共 %lu 个）："), (unsigned long)ame428_moving.count],
                             [ame428_lines componentsJoinedByString:@"\n"],
                             localize(@"ame428.iso.confirm.snapshot",
                                 @"每个版本搬移前会先做完整备份（Prisma2/backups/pre-isolation-<版本>-<时间>.zip），中途失败自动恢复，数据不会丢失。"),
                             localize(@"ame428.iso.confirm.cancel_note", @"取消则不作任何更改。")]
                          preferredStyle:UIAlertControllerStyleAlert];
    [ame428_alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                                     style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a) {
        // 取消：不改档——行徽章回滚到旧值（List 行选中态由 ame_reloadSelectedIndex 同步）
        NSInteger ame428_cur = getPrefInt(@"general.isolation_default");
        if (ame428_cur < 0 || ame428_cur > 2) ame428_cur = 0;
        [row ame_reloadSelectedIndex:ame428_cur];
    }]];
    [ame428_alert addAction:[UIAlertAction
        actionWithTitle:localize(@"ame428.iso.confirm.go", @"开始迁移")
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction *a) {
        UIAlertController *ame428_prog = [UIAlertController
            alertControllerWithTitle:localize(@"ame428.iso.confirm.title", @"确认数据迁移")
                             message:localize(@"ame428.iso.progress", @"正在迁移游戏数据…")
                      preferredStyle:UIAlertControllerStyleAlert];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self presentViewController:ame428_prog animated:NO completion:nil];
        });
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableArray<NSString *> *ame428_failed = [NSMutableArray array];
            for (NSDictionary *ame428_f in ame428_flips) {
                NSDictionary *ame428_r = [PLProfiles ame428_executeIsolationDataMoveForVid:ame428_f[@"vid"]
                    toIsolated:([ame428_f[@"to"] integerValue] == 1)
                        reason:[NSString stringWithFormat:@"global-default %ld->%ld", (long)oldG, (long)newG]];
                if (![ame428_r[@"ok"] boolValue]) {
                    [ame428_failed addObject:[NSString stringWithFormat:@"%@（%@）",
                        ame428_f[@"vid"], ame428_r[@"error"] ?: @"?"]];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [ame428_prog dismissViewControllerAnimated:NO completion:^{
                    if (ame428_failed.count == 0) {
                        setPrefInt(@"general.isolation_default", newG);
                        [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
                    } else {
                        // 有失败：不落档（保持旧档），失败明细入报告 + 弹窗
                        UIAlertController *ame428_fail = [UIAlertController
                            alertControllerWithTitle:localize(@"i18n_str_388", nil)
                                             message:[NSString stringWithFormat:
                                                 localize(@"ame428.iso.result.failed_fmt",
                                                     @"迁移未完成，数据已恢复原状：%@"),
                                                 [ame428_failed componentsJoinedByString:@"; "]]
                                  preferredStyle:UIAlertControllerStyleAlert];
                        [ame428_fail addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil)
                                                                         style:UIAlertActionStyleDefault handler:nil]];
                        [self presentViewController:ame428_fail animated:YES completion:nil];
                    }
                    NSInteger ame428_cur = getPrefInt(@"general.isolation_default");
                    if (ame428_cur < 0 || ame428_cur > 2) ame428_cur = 0;
                    [row ame_reloadSelectedIndex:ame428_cur];
                }];
            });
        });
    }]];
    [self presentViewController:ame428_alert animated:YES completion:nil];
}

// 自定义颜色选择（旧 openColorPickerForKey 平移；iOS 14+ UIColorPicker）
- (void)ame344_openColorPickerForKey:(NSString *)fullKey title:(NSString *)title {
    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
    picker.title = title;
    picker.delegate = self;
    UIColor *current = ame_pages_colorFromHex(getPrefObject(fullKey));
    if (current) picker.selectedColor = current;
    self.ame344_pickingColorKey = fullKey;
    [self ame_presentVC:picker];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    NSString *key = self.ame344_pickingColorKey;
    self.ame344_pickingColorKey = nil;
    if (!key) return;
    setPrefObject(key, ame_pages_hexFromColor(viewController.selectedColor));
    [[NSNotificationCenter defaultCenter] postNotificationName:@"LauncherAppearanceChanged" object:nil];
}

// 兄弟安装数据迁移入口（旧 ame261_siblingImportTapped 1:1 平移）
- (void)ame261_siblingImportTapped {
    NSArray<NSDictionary *> *ame261_siblings = [DataTransferService ame260_scanSiblingLauncherHomes];
    if (ame261_siblings.count == 0) {
        [self ame344_showNotice:localize(@"prefs.data_sibling.none", nil)];
        return;
    }
    NSDictionary *ame261_best = ame261_siblings.firstObject;
    NSString *ame261_src = ame261_best[@"path"];
    unsigned long long ame261_bytes = [ame261_best[@"bytes"] unsignedLongLongValue];
    NSString *ame261_sizeText = ame261_bytes >= (1ULL << 30)
        ? [NSString stringWithFormat:@"%.1f GB", (double)ame261_bytes / (double)(1ULL << 30)]
        : [NSString stringWithFormat:@"%llu MB", ame261_bytes / (1ULL << 20)];
    // Task321：来源身份标注（prisma1/prisma2/prisma-plugins/legacy）+ 数据量
    NSString *ame261_kind = ame261_best[@"kind"] ?: @"legacy";
    NSString *ame261_kindText = localize(
        [@"welcome.data.sibling.kind." stringByAppendingString:ame261_kind], nil);
    NSString *ame261_msg = [NSString stringWithFormat:
        localize(@"welcome.data.sibling.desc2", nil), ame261_kindText, ame261_sizeText];
    UIAlertController *ame261_confirm = [UIAlertController
        alertControllerWithTitle:localize(@"welcome.data.sibling.title", nil)
                         message:ame261_msg
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    void (^ame321_run)(Ame321SiblingMigrationMode) = ^(Ame321SiblingMigrationMode ame321_mode) {
        [DataTransferService.sharedService
            ame321_migrateFromSiblingHome:ame261_src mode:ame321_mode presenter:weakSelf
                               completion:^(BOOL ok, NSString *message) {
            UIAlertController *ame261_done = [UIAlertController
                alertControllerWithTitle:(ok ? localize(@"welcome.data.sibling.title", nil)
                                              : localize(@"i18n_str_108", nil))
                                 message:message
                          preferredStyle:UIAlertControllerStyleAlert];
            [ame261_done addAction:[UIAlertAction actionWithTitle
                :localize(@"i18n_str_44", @"OK") style:UIAlertActionStyleCancel handler:nil]];
            [weakSelf ame_presentVC:ame261_done];
        }];
    };
    [ame261_confirm addAction:[UIAlertAction actionWithTitle
        :localize(@"welcome.data.sibling.confirm.smart", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        ame321_run(Ame321SiblingMigrationModeSmart);
    }]];
    [ame261_confirm addAction:[UIAlertAction actionWithTitle
        :localize(@"welcome.data.sibling.confirm.overwrite", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        ame321_run(Ame321SiblingMigrationModeOverwrite);
    }]];
    [ame261_confirm addAction:[UIAlertAction actionWithTitle
        :localize(@"resman.common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self ame_presentVC:ame261_confirm];
}

// 轻反馈（与控制屏 ame344_showNotice 同形；本页独立实现避免跨页类别）
- (void)ame344_showNotice:(NSString *)text {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:text
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                              style:UIAlertActionStyleDefault handler:nil]];
    [self ame_presentVC:alert];
}

@end

#pragma mark - ⑥ Java 管理屏

@interface ZL2JavaManagerSettingsPage () <UIDocumentPickerDelegate>
@end

@implementation ZL2JavaManagerSettingsPage

- (void)ame_buildGroups {
    __weak typeof(self) weakSelf = self;

    // --- 组 1：默认 Java（java.java_homes @0 按 tag；"自动" = 删键回
    //     getSelectedJavaHome 的 minVersion 搜索语义）---
    NSMutableDictionary<NSString *, NSString *> *defaultPicks =
        [[getPrefObject(@"java.java_homes") objectForKey:@"0"] mutableCopy]
            ?: [NSMutableDictionary dictionary];

    // 可用运行时主版本（升序去重）
    NSMutableArray<NSNumber *> *majors = [NSMutableArray array];
    for (NSDictionary *runtime in [self ame_scanRuntimes]) {
        NSInteger major = [runtime[@"major"] integerValue];
        if (major > 0 && ![majors containsObject:@(major)]) [majors addObject:@(major)];
    }
    [majors sortUsingSelector:@selector(compare:)];

    NSArray<NSDictionary *> *tags = @[
        @{@"tag": @"1_16_5_older",
          @"title": localize(@"preference.manage_runtime.default.1165", nil),
          @"minVer": @8},
        @{@"tag": @"1_17_newer",
          @"title": localize(@"preference.manage_runtime.default.117", nil),
          @"minVer": @17},
        @{@"tag": @"1_26_newer",
          @"title": localize(@"preference.manage_runtime.default.126", nil),
          @"minVer": @8},   // 旧页同口径：row2 选择器 minVer 与 row0 相同
    ];
    ZL2SettingCardGroup *group1 = [[ZL2SettingCardGroup alloc] init];
    for (NSDictionary *tagDef in tags) {
        NSString *tag = tagDef[@"tag"];
        NSInteger minVer = [tagDef[@"minVer"] integerValue];

        NSMutableArray<NSString *> *optionKeys =
            [NSMutableArray arrayWithObject:@"auto"];
        NSMutableArray<NSString *> *optionNames =
            [NSMutableArray arrayWithObject:localize(@"preference.auto", nil)];
        for (NSNumber *major in majors) {
            if (major.integerValue < minVer) continue;
            [optionKeys addObject:major.stringValue];
            [optionNames addObject:[NSString stringWithFormat:@"Java %@", major.stringValue]];
        }

        ZL2SettingRowList *row =
            [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                     options:optionNames optionKeys:optionKeys];
        row.title = tagDef[@"title"];
        row.subtitle = localize(@"ame369.setpg.runtime_fallback.subtitle", @"未安装匹配运行时时启动链自动回退");
        NSString *picked = defaultPicks[tag];
        [row ame_reloadSelectedIndex:
            picked ? (NSInteger)[optionKeys indexOfObject:picked] : 0];
        row.onSelect = ^(NSInteger index) {
            if (index < 0 || (NSUInteger)index >= optionKeys.count) return;
            NSMutableDictionary *homes =
                [getPrefObject(@"java.java_homes") mutableCopy] ?: [NSMutableDictionary dictionary];
            NSMutableDictionary *zero =
                [homes[@"0"] mutableCopy] ?: [NSMutableDictionary dictionary];
            if ([optionKeys[index] isEqualToString:@"auto"]) {
                [zero removeObjectForKey:tag];
            } else {
                zero[tag] = optionKeys[index];
            }
            homes[@"0"] = zero;
            setPrefObject(@"java.java_homes", homes);
        };
        [group1 ame_addRow:row];
    }
    [self ame_addGroup:group1];

    // --- 组 2：已安装运行时（名称/版本/内外部标签；删除走旧页）---
    ZL2SettingCardGroup *group2 = [[ZL2SettingCardGroup alloc] init];
    NSArray<NSDictionary *> *runtimes = [self ame_scanRuntimes];
    if (runtimes.count == 0) {
        // 空态明确显示（不造假列表）
        ZL2SettingRowAction *emptyRow =
            [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
        emptyRow.title = localize(@"ame369.setpg.no_runtime", @"未发现已安装的 Java 运行时");
        emptyRow.subtitle = localize(@"ame369.setpg.no_runtime.subtitle", @"内置运行时随启动器分发；可用「完整 Java 管理」导入");
        [group2 ame_addRow:emptyRow];
    } else {
        for (NSDictionary *runtime in runtimes) {
            NSString *title = [runtime[@"internal"] boolValue]
                ? [NSString stringWithFormat:localize(@"ame369.common.builtin_fmt", @"%@（内置）"), runtime[@"name"]]
                : runtime[@"name"];
            ZL2SettingRowAction *row =
                [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
            row.title = title;
            row.subtitle = [NSString stringWithFormat:@"Java %@ · %@",
                                runtime[@"version"],
                                [runtime[@"internal"] boolValue] ? localize(@"ame369.common.builtin", @"内置") : localize(@"ame369.common.external", @"外部安装")];
            [group2 ame_addRow:row];
        }
    }
    [self ame_addGroup:group2];

    // --- 组 3：执行 Jar + 完整管理 ---
    ZL2SettingCardGroup *group3 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *runJarRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    runJarRow.title = localize(@"launcher.menu.execute_jar", nil);
    runJarRow.subtitle = localize(@"ame369.setpg.run_jar.subtitle", @"选择 Jar 后经守卫链全屏运行");
    runJarRow.onTap = ^{
        [weakSelf ame_pickJarFile];
    };
    ZL2SettingRowAction *manageRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    manageRow.title = localize(@"ame369.setpg.java_manager", @"完整 Java 管理");
    manageRow.subtitle = localize(@"ame369.setpg.java_manager.subtitle", @"导入 / 删除运行时、调整分区预选");
    manageRow.onTap = ^{
        [weakSelf ame_push:[[LauncherPrefManageJREViewController alloc] init]
                   titled:localize(@"preference.title.manage_runtime", nil)];
    };
    [group3 ame_addRows:@[runJarRow, manageRow]];
    [self ame_addGroup:group3];
}

- (void)ame_refreshState {
    [self ame_rebuildGroups];   // 运行时集合可在旧管理页变化 → 全量重建
}

#pragma mark 运行时枚举（LauncherPrefManageJREViewController 同口径）

- (NSArray<NSDictionary *> *)ame_scanRuntimes {
    NSMutableArray<NSDictionary *> *runtimes = [NSMutableArray array];
    NSString *internalPath =
        [NSString stringWithFormat:@"%@/java_runtimes", NSBundle.mainBundle.bundlePath];
    const char *home = getenv("POJAV_HOME");
    if (home) {
        NSString *externalPath = [NSString stringWithFormat:@"%s/java_runtimes", home];
        [self ame_scanRuntimesInPath:externalPath internal:NO into:runtimes];
    }
    [self ame_scanRuntimesInPath:internalPath internal:YES into:runtimes];
    [runtimes sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult byMajor = [a[@"major"] compare:b[@"major"]];
        if (byMajor != NSOrderedSame) return byMajor;
        return [a[@"name"] compare:b[@"name"]];
    }];
    return runtimes;
}

- (void)ame_scanRuntimesInPath:(NSString *)path internal:(BOOL)internal
                          into:(NSMutableArray<NSDictionary *> *)out {
    NSArray<NSString *> *files =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
    for (NSString *name in files) {
        NSString *runtimePath = [path stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:runtimePath isDirectory:&isDir] || !isDir) continue;
        NSString *fullVersion = [self ame_javaVersionForPath:runtimePath];
        if (!fullVersion) continue;   // 缺 release 文件 = 非运行时目录
        [out addObject:@{@"name": name,
                         @"version": fullVersion,
                         @"major": @([self ame_majorVersionForFullVersion:fullVersion]),
                         @"internal": @(internal)}];
    }
}

// release 文件 JAVA_VERSION="…" 解析（旧页 javaVersionForPath 精简平移；
// 解析失败返回 nil 由调用方过滤）
- (nullable NSString *)ame_javaVersionForPath:(NSString *)path {
    NSString *content = [NSString stringWithContentsOfFile:[path stringByAppendingPathComponent:@"release"]
                                                  encoding:NSUTF8StringEncoding error:nil];
    if (!content) return nil;
    NSRange marker = [content rangeOfString:@"JAVA_VERSION=\""];
    if (marker.location == NSNotFound) return nil;
    NSString *rest = [content substringFromIndex:NSMaxRange(marker)];
    NSRange end = [rest rangeOfString:@"\""];
    if (end.location == NSNotFound) return nil;
    return [rest substringToIndex:end.location];
}

- (NSInteger)ame_majorVersionForFullVersion:(NSString *)version {
    if ([version hasPrefix:@"1.8.0"]) return 8;
    return (NSInteger)[version componentsSeparatedByString:@"."][0].integerValue;
}

#pragma mark 执行 Jar 文件（7.0-UI-9-d 守卫链平移）

// JavaGUIViewController 为模态专用页（filepath 必填且页内 dismiss 走
// presentingViewController），裸 push/无路径必崩或黑屏——走文档选择器
- (void)ame_pickJarFile {
    // asCopy:YES 保证文件复制进沙盒，避免安全作用域 URL 导致 UZKArchive 读取失败
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[[UTType typeWithMIMEType:@"application/java-archive"]]
        asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    [self ame_runJarAtPath:urls.firstObject.path];
}

- (void)ame_runJarAtPath:(NSString *)path {
    // 守卫链对齐 LauncherRightPanelViewController.enterModInstallerWithPath:
    //（精简安全子集；JVM 二次崩溃守卫由 JavaGUI 页自兜底）
    JavaGUIViewController *vc = [[JavaGUIViewController alloc] init];
    vc.filepath = path;
    vc.hitEnterAfterWindowShown = NO;   // 设置页入口：手动执行（右面板同款）

    // requiredJavaVersion getter 同步解析 MANIFEST；失败路径 getter 已自带错误弹窗
    int requiredJavaVersion = vc.requiredJavaVersion;
    if (!requiredJavaVersion) {
        [self ame_showAlert:localize(@"i18n_str_427", nil)
                    message:[NSString stringWithFormat:localize(@"i18n_str_428", nil),
                                path.lastPathComponent ?: @""]];
        return;
    }

    // JRE 预检：execute_jar 标签未配置所需 JRE 时 present 必黑屏（旧链注释同款）
    NSString *javaHome = getSelectedJavaHome(@"execute_jar", requiredJavaVersion);
    if (!javaHome) {
        [self ame_showAlert:localize(@"i18n_str_429", nil)
                    message:[NSString stringWithFormat:localize(@"i18n_str_222", nil),
                                requiredJavaVersion, requiredJavaVersion]];
        return;
    }

    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)ame_showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - ⑦ 控制管理屏

@implementation ZL2ControlManagerSettingsPage

- (void)ame_buildGroups {
    __weak typeof(self) weakSelf = self;

    // --- 组 1：控制布局（control.default_ctrl；Task77 出厂 custom.json）---
    ZL2SettingCardGroup *group1 = [[ZL2SettingCardGroup alloc] init];
    NSArray<NSString *> *layouts = [self ame_scanLayouts];
    if (layouts.count == 0) {
        // 空态明确显示（controlmap 目录缺失/为空）
        ZL2SettingRowAction *emptyRow =
            [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
        emptyRow.title = localize(@"ame369.setpg.no_control_layout", @"未找到控制布局文件");
        emptyRow.subtitle = localize(@"ame369.setpg.no_control_layout.subtitle", @"可从「控件仓库」下载，或用「键位调整」创建");
        [group1 ame_addRow:emptyRow];
    } else {
        NSString *current = ame_pages_stringOr(getPrefObject(@"control.default_ctrl"), @"custom.json");
        ZL2SettingRowList *layoutRow =
            [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                     options:layouts optionKeys:layouts];
        layoutRow.title = localize(@"ame369.setpg.current_layout", @"当前布局");
        layoutRow.subtitle = localize(@"ame369.setpg.current_layout.subtitle", @"游戏内屏幕控件布局（controlmap 目录）");
        NSInteger idx = (NSInteger)[layouts indexOfObject:current];
        [layoutRow ame_reloadSelectedIndex:(idx >= 0 ? idx : 0)];
        layoutRow.onSelect = ^(NSInteger index) {
            if (index < 0 || (NSUInteger)index >= layouts.count) return;
            setPrefString(@"control.default_ctrl", layouts[index]);
        };
        [group1 ame_addRow:layoutRow];
    }
    [self ame_addGroup:group1];

    // --- 组 1.5：手柄映射（Task316 6.5.5 新功能 UI 适配：Task310/311
    //   手柄下载分类+本地 gamepads 清单进 ZL2 壳；落盘 controlmap/gamepads/
    //   <id>.json，选任天堂交换见「手柄」设置页手柄类型）---
    ZL2SettingCardGroup *gamepadGroup = [[ZL2SettingCardGroup alloc] init];
    NSArray<NSString *> *gamepads = [self ame_scanGamepads];
    if (gamepads.count == 0) {
        ZL2SettingRowAction *gpEmptyRow =
            [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
        gpEmptyRow.title = localize(@"ame369.setpg.no_gamepad_map", @"未找到手柄映射文件");
        gpEmptyRow.subtitle = localize(@"ame369.setpg.no_gamepad_map.subtitle", @"可从「手柄仓库」下载（内建默认同源备份）");
        gpEmptyRow.onTap = ^{
            ControlRepoViewController *repo = [[ControlRepoViewController alloc] init];
            repo.initialCategoryIndex = 2;  // 直达手柄分类
            [weakSelf ame_push:repo titled:localize(@"dl.controls.cat.gamepad", nil)];
        };
        [gamepadGroup ame_addRow:gpEmptyRow];
    } else {
        NSString *currentGp = ame_pages_stringOr(getPrefObject(@"control.default_gamepad_ctrl"), nil);
        ZL2SettingRowList *gpRow =
            [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                     options:gamepads optionKeys:gamepads];
        gpRow.title = localize(@"ame369.setpg.current_gamepad_map", @"当前手柄映射");
        gpRow.subtitle = localize(@"ame369.setpg.current_gamepad_map.subtitle", @"手柄键码映射（controlmap/gamepads 目录）");
        NSInteger gpIdx = currentGp ? (NSInteger)[gamepads indexOfObject:currentGp] : -1;
        [gpRow ame_reloadSelectedIndex:(gpIdx >= 0 ? gpIdx : 0)];
        gpRow.onSelect = ^(NSInteger index) {
            if (index < 0 || (NSUInteger)index >= gamepads.count) return;
            setPrefString(@"control.default_gamepad_ctrl", gamepads[index]);
        };
        [gamepadGroup ame_addRow:gpRow];
    }
    ZL2SettingRowAction *gpRepoRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    gpRepoRow.title = localize(@"ame369.common.gamepad_repo", @"手柄仓库");
    gpRepoRow.subtitle = localize(@"ame369.common.gamepad_repo.subtitle", @"官方精选/社区手柄映射下载（装完即用）");
    gpRepoRow.onTap = ^{
        ControlRepoViewController *repo = [[ControlRepoViewController alloc] init];
        repo.initialCategoryIndex = 2;  // 直达手柄分类
        [weakSelf ame_push:repo titled:localize(@"dl.controls.cat.gamepad", nil)];
    };
    [gamepadGroup ame_addRow:gpRepoRow];
    [self ame_addGroup:gamepadGroup];

    // --- 组 2：编辑与获取 ---
    ZL2SettingCardGroup *group2 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *editorRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    editorRow.title = localize(@"preference.title.custom_controls", nil);
    editorRow.subtitle = localize(@"ame369.setpg.canvas_editor.subtitle", @"全屏画布编辑器（添加/拖动/缩放控件）");
    editorRow.onTap = ^{
        // 旧设置页 openChildPaneAtIndexPath custom_controls 同款：nav 模态
        //（画布编辑器专用，非 push；页内自带关闭钮）
        CustomControlsViewController *editor = [[CustomControlsViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
        nav.modalInPresentation = YES;
        [weakSelf presentViewController:nav animated:YES completion:nil];
    };
    ZL2SettingRowAction *repoRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    repoRow.title = localize(@"ame369.common.control_repo", @"控件仓库");
    repoRow.subtitle = localize(@"ame369.common.control_repo.subtitle", @"浏览与下载社区控制布局");
    repoRow.onTap = ^{
        [weakSelf ame_push:[[ControlRepoViewController alloc] init] titled:localize(@"ame369.common.control_repo", @"控件仓库")];
    };
    ZL2SettingRowAction *resetRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    resetRow.title = localize(@"ame369.setpg.reset_layout", @"恢复默认布局");
    resetRow.subtitle = localize(@"ame369.setpg.reset_layout.subtitle", @"写回出厂布局 custom.json（Task77 口径）");
    resetRow.onTap = ^{
        [ZL2M3Dialog showTitle:localize(@"ame369.setpg.reset_layout", @"恢复默认布局")
                          body:localize(@"ame369.setpg.reset_layout.body", @"将当前控制布局重置为出厂布局 custom.json，下次进入游戏生效。")
                  confirmTitle:localize(@"OK", nil)
                   destructive:YES
                    onConfirm:^{
            setPrefString(@"control.default_ctrl", @"custom.json");
        }
                      onCancel:nil];
    };
    [group2 ame_addRows:@[editorRow, repoRow, resetRow]];
    [self ame_addGroup:group2];

    // --- 组 3：更多设置 ---
    ZL2SettingCardGroup *group3 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *moreRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    moreRow.title = localize(@"ame369.setpg.more_control", @"更多控制设置");
    moreRow.subtitle = localize(@"ame369.setpg.more_control.subtitle", @"手柄配置、虚拟鼠标、陀螺仪等完整分区");
    moreRow.onTap = ^{
        [weakSelf ame_push:[[LauncherPreferencesViewController alloc] init] titled:localize(@"ame369.common.more_settings", @"更多设置")];
    };
    [group3 ame_addRow:moreRow];
    [self ame_addGroup:group3];
}

- (void)ame_refreshState {
    [self ame_rebuildGroups];   // 布局文件集可在仓库页/编辑器变化 → 全量重建
}

// $POJAV_HOME/controlmap/*.json 枚举（升序；custom.json 置顶对齐出厂默认）
- (NSArray<NSString *> *)ame_scanLayouts {
    const char *home = getenv("POJAV_HOME");
    if (!home) return @[];
    NSString *dir = [NSString stringWithFormat:@"%s/controlmap", home];
    NSArray<NSString *> *files =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    NSMutableArray<NSString *> *layouts =
        [[files pathsMatchingExtensions:@[@"json"]] mutableCopy] ?: [NSMutableArray array];
    [layouts sortUsingSelector:@selector(compare:)];
    if ([layouts containsObject:@"custom.json"]) {
        [layouts removeObject:@"custom.json"];
        [layouts insertObject:@"custom.json" atIndex:0];
    }
    return layouts;
}

/// Task316：本地手柄映射清单（controlmap/gamepads/*.json，Task310/311 下载落盘处）
- (NSArray<NSString *> *)ame_scanGamepads {
    const char *home = getenv("POJAV_HOME");
    if (!home) return @[];
    NSString *dir = [NSString stringWithFormat:@"%s/controlmap/gamepads", home];
    NSArray<NSString *> *files =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    NSMutableArray<NSString *> *pads =
        [[files pathsMatchingExtensions:@[@"json"]] mutableCopy] ?: [NSMutableArray array];
    [pads sortUsingSelector:@selector(compare:)];
    return pads;
}

@end

#pragma mark - ⑧ 关于屏

@interface ZL2AboutSettingsPage ()
@property (nonatomic, strong) ZL2SettingRowSwitch *autoUpdateRow;
@end

@implementation ZL2AboutSettingsPage

// ★Task428：区头标签（ame327 插件贡献组同款视觉：fontLabelLarge +
//   onSurfaceVariant，连体组卡上方独立行）——四块结构每块「区头 + 组卡」；
//   上一组卡与区头之间 12pt 呼吸、区头与所属组卡之间 4pt（custom spacing
//   机制与 ZL2SettingsViewController 轨组分隔同款；首块无上一视图则不加）
- (void)ame428_addSectionHeader:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [ZL2Theme fontLabelLarge];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *ame428_prev = self.groupsStack.arrangedSubviews.lastObject;
    [self.groupsStack addArrangedSubview:label];
    if (ame428_prev != nil) {
        [self.groupsStack setCustomSpacing:12.0 afterView:ame428_prev];
    }
    [self.groupsStack setCustomSpacing:4.0 afterView:label];
}

- (void)ame_buildGroups {
    __weak typeof(self) weakSelf = self;

    // ════ ★Task428 块 1/4：关于启动器（版本与更新 / 链接 / 作者团队）════
    [self ame428_addSectionHeader:localize(@"ame428.about.section_launcher", @"关于启动器")];
    ZL2SettingCardGroup *group1 = [[ZL2SettingCardGroup alloc] init];

    // 版本号 / 构建号 / 构建代际（只读展示行：onTap nil = 无 chevron 不响应）。
    //   构建代际 = BuildTag.h ame415_buildTag 同源字面量（Task421 单一事实源，
    //   与关于老页版本行 / 预览卡角标恒等；static NSString *const 直接用）
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: version;
    ZL2SettingRowAction *versionRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    versionRow.title = localize(@"ame369.setpg.version_no", @"版本号");
    versionRow.detailText = version;
    ZL2SettingRowAction *buildRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    buildRow.title = localize(@"ame369.setpg.build_no", @"构建号");
    buildRow.detailText = build;
    ZL2SettingRowAction *tagRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    tagRow.title = localize(@"ame428.about.buildtag", @"构建代际");
    tagRow.detailText = ame415_buildTag;

    // 启动时自动检查更新（general.auto_update_check；Task125 语义）
    ZL2SettingRowSwitch *autoUpdateRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    autoUpdateRow.title = localize(@"preference.title.auto_update_check", nil);
    [autoUpdateRow ame_setOn:getPrefBool(@"general.auto_update_check")];
    autoUpdateRow.onToggle = ^(BOOL on) {
        setPrefObject(@"general.auto_update_check", @(on));
    };
    self.autoUpdateRow = autoUpdateRow;

    // 检查更新（复用仓内既有 UpdateChecker 正式版检查：loading 弹窗 + 结果
    //   弹窗 + openReleasePage，AboutViewController ame217 链路同源——
    //   报告 9.1「先找既有更新检查机制，有就复用」口径，零新网络代码）
    ZL2SettingRowAction *checkRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    checkRow.title = localize(@"preference.title.check_update", nil);
    checkRow.subtitle = localize(@"ame369.setpg.gh_check.subtitle", @"GitHub Releases 正式版检查");
    checkRow.onTap = ^{
        [weakSelf ame_checkForUpdate];
    };

    // 项目主页（打开二代仓库——本仓 README/插件仓库同源地址）
    ZL2SettingRowAction *projectRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    projectRow.title = localize(@"ame369.setpg.project_home", @"项目主页");
    projectRow.subtitle = @"https://github.com/Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2";
    projectRow.onTap = ^{
        [weakSelf ame_openURL:[NSURL URLWithString:
            @"https://github.com/Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher2"]];
    };

    // QQ 群（复制群号）
    ZL2SettingRowAction *qqRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    qqRow.title = localize(@"about.qq.title", nil);
    qqRow.subtitle = ame217_qqGroupNumber();
    qqRow.onTap = ^{
        // 群号复制（about.qq.copied 既有文案）
        [UIPasteboard generalPasteboard].string = ame217_qqGroupNumber();
        [weakSelf ame_showNoticeText:localize(@"about.qq.copied", nil)];
    };

    // 作者与团队（文案口径 = 老关于页 about.credits.body / about.credits.kxdw
    //   原文复用，与 AboutViewController / README 一致，零编造）
    ZL2SettingRowAction *teamRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    teamRow.title = localize(@"ame428.about.team", @"作者与团队");
    teamRow.subtitle = localize(@"about.credits.body", nil);
    ZL2SettingRowAction *kxdwRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    kxdwRow.title = localize(@"about.credits.kxdw", nil);

    [group1 ame_addRows:@[versionRow, buildRow, tagRow, autoUpdateRow, checkRow,
                          projectRow, qqRow, teamRow, kxdwRow]];
    [self ame_addGroup:group1];

    // ════ ★Task428 块 2/4：鸣谢（连体组卡列表：名称 + 一句话定位；开源
    //   许可只在确切时才写——本块一律项目定位描述，不写具体许可证）════
    [self ame428_addSectionHeader:localize(@"ame428.about.section_credits", @"鸣谢")];
    ZL2SettingCardGroup *creditGroup = [[ZL2SettingCardGroup alloc] init];
    NSArray<NSArray<NSString *> *> *ame428_credits = @[
        @[@"ZalithLauncher2", @"ame428.credit.zalith2"],
        @[@"PojavLauncher",   @"ame428.credit.pojav"],
        @[@"FCL",             @"ame428.credit.fcl"],
        @[@"HMCL",            @"ame428.credit.hmcl"],
        @[@"Modrinth",        @"ame428.credit.modrinth"],
        @[@"CurseForge",      @"ame428.credit.curseforge"],
        @[@"BMCLAPI",         @"ame428.credit.bmclapi"],
        @[@"logshare.cn",     @"ame428.credit.logshare"],
        @[@"PCL",             @"ame428.credit.pcl"],
    ];
    for (NSArray<NSString *> *ame428_credit in ame428_credits) {
        ZL2SettingRowAction *ame428_creditRow =
            [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
        ame428_creditRow.title = ame428_credit[0];
        ame428_creditRow.subtitle = localize(ame428_credit[1], nil);
        [creditGroup ame_addRow:ame428_creditRow];
    }
    [self ame_addGroup:creditGroup];

    // ════ ★Task428 块 3/4：依赖库（AGENTS.md「核心依赖」权威清单八项；
    //   图形适配 / AWT 支持 / 其他三族，描述只写仓内已证实的用途）════
    [self ame428_addSectionHeader:localize(@"ame428.about.section_deps", @"依赖库")];
    ZL2SettingCardGroup *depGroup = [[ZL2SettingCardGroup alloc] init];
    NSArray<NSArray<NSString *> *> *ame428_deps = @[
        @[@"MetalANGLE",      @"ame428.dep.metalangle"],
        @[@"GL4ES",           @"ame428.dep.gl4es"],
        @[@"Mesa 3D",         @"ame428.dep.mesa"],
        @[@"MobileGlues",     @"ame428.dep.mobileglues"],
        @[@"Caciocavallo",    @"ame428.dep.caciocavallo"],
        @[@"LWJGL",           @"ame428.dep.lwjgl"],
        @[@"OpenAL",          @"ame428.dep.openal"],
        @[@"TouchController", @"ame428.dep.touchcontroller"],
    ];
    for (NSArray<NSString *> *ame428_dep in ame428_deps) {
        ZL2SettingRowAction *ame428_depRow =
            [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
        ame428_depRow.title = ame428_dep[0];
        ame428_depRow.subtitle = localize(ame428_dep[1], nil);
        [depGroup ame_addRow:ame428_depRow];
    }
    [self ame_addGroup:depGroup];

    // ════ ★Task428 块 4/4：已加载插件（AmePluginManager installedPluginIds
    //   枚举 + manifestForPlugin: 取 manifest：名称/版本/描述三字段逐行展示；
    //   运行态经 AmePluginRuntime isRunning: 标注；空态明确占位不造假）════
    [self ame428_addSectionHeader:localize(@"ame428.about.section_plugins", @"已加载插件")];
    ZL2SettingCardGroup *pluginGroup = [[ZL2SettingCardGroup alloc] init];
    NSArray<NSString *> *ame428_pluginIds = [AmePluginManager installedPluginIds];
    if (ame428_pluginIds.count == 0) {
        ZL2SettingRowAction *emptyRow =
            [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
        emptyRow.title = localize(@"ame428.plugin.empty", @"暂无已安装插件");
        emptyRow.subtitle = localize(@"ame428.plugin.empty.subtitle", @"可在 启动器 → 插件仓库 浏览并一键安装");
        [pluginGroup ame_addRow:emptyRow];
    } else {
        for (NSString *ame428_pid in ame428_pluginIds) {
            AmePluginManifest *ame428_manifest = [AmePluginManager manifestForPlugin:ame428_pid];
            NSString *ame428_name = ame_pages_stringOr(ame428_manifest.name, ame428_pid);
            NSString *ame428_summary = ame_pages_stringOr(ame428_manifest.summary, nil);
            NSString *ame428_ver = ame_pages_stringOr(ame428_manifest.version, nil);
            // 尾注：版本 +（运行态，isRunning 实时判定）
            NSString *ame428_running = localize(@"ame428.plugin.running", @"运行中");
            NSString *ame428_detail = [AmePluginRuntime isRunning:ame428_pid]
                ? (ame428_ver.length > 0
                    ? [NSString stringWithFormat:@"%@ · %@", ame428_ver, ame428_running]
                    : ame428_running)
                : ame428_ver;
            ZL2SettingRowAction *ame428_pluginRow =
                [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
            ame428_pluginRow.title = ame428_name;
            ame428_pluginRow.subtitle = ame428_summary;
            ame428_pluginRow.detailText = ame428_detail;
            [pluginGroup ame_addRow:ame428_pluginRow];
        }
    }
    [self ame_addGroup:pluginGroup];
    // ★Task428：「更多关于信息」push 老关于页（moreRow）退役——四块信息
    //   本页全量自持；AboutViewController 仍可从欢迎页/旧设置页进入。
}

- (void)ame_refreshState {
    // ★Task428：四块全量重建（插件安装/卸载在外部页发生 → 切轨回来即反映；
    //   自动检查更新行随重建重读偏好——同控制/游戏屏刷新口径）
    [self ame_rebuildGroups];
}

#pragma mark 检查更新（AboutViewController ame217_checkForUpdate 平移）

- (void)ame_checkForUpdate {
    UIAlertController *loadingAlert = [UIAlertController
        alertControllerWithTitle:localize(@"check_update.checking", @"正在检查更新…")
                         message:nil
                  preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];

    [UpdateChecker checkForUpdateWithCompletion:^(UpdateInfo *info, NSError *error) {
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            if (error || info == nil) {
                [self ame_showUpdateAlertWithTitle:localize(@"check_update.failed", @"检查更新失败")
                                            message:error.localizedDescription ?: localize(@"i18n_str_97", nil)];
                return;
            }
            if (info.hasUpdate) {
                [self ame_showUpdateAvailableAlert:info];
            } else {
                [self ame_showUpdateAlertWithTitle:localize(@"check_update.up_to_date", @"已是最新版本")
                                            message:[NSString stringWithFormat:
                                                localize(@"check_update.current_version", @"当前版本 %@，已是最新正式版。"),
                                                info.currentVersion]];
            }
        }];
    }];
}

- (void)ame_showUpdateAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", @"好的")
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)ame_showUpdateAvailableAlert:(UpdateInfo *)info {
    NSString *title = [NSString stringWithFormat:localize(@"check_update.new_version_title",
                                                          localize(@"i18n_str_407", nil)), info.latestVersion];
    NSString *notes = info.releaseNotes ?: @"";
    if (notes.length > 500) {
        notes = [[notes substringToIndex:500] stringByAppendingString:@"…"];
    }
    NSString *message = [NSString stringWithFormat:@"%@\n\n%@",
                         localize(@"check_update.new_version_message", localize(@"i18n_str_408", nil)),
                         notes];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"check_update.download", @"前往下载")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [UpdateChecker openReleasePage];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", @"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark 小工具

- (void)ame_openURL:(NSURL *)url {
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

// 轻量反馈（复制成功等）；无独立 toast 组件，沿用既有 alert 形态（无标题）
- (void)ame_showNoticeText:(NSString *)text {
    [self ame_showUpdateAlertWithTitle:nil message:text];
}

@end

#pragma mark - ⑤b AI 屏（Task344 旧设置全量迁移：ai 分区入新UI）

@implementation ZL2AISettingsPage

- (void)ame_buildGroups {
    __weak typeof(self) weakSelf = self;

    // --- 组 1：提供商与会话（旧 ai 分区入口行平移）---
    ZL2SettingCardGroup *group1 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *providerRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    providerRow.title = localize(@"preference.title.provider_config", nil);
    providerRow.subtitle = localize(@"ame369.setpg.ai_provider.subtitle", @"配置 API 地址与密钥（OpenAI 兼容协议）");
    providerRow.onTap = ^{
        AIProviderConfigViewController *vc = [[AIProviderConfigViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [weakSelf ame_presentVC:nav];
    };
    ZL2SettingRowAction *sessionRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    sessionRow.title = localize(@"preference.title.session_list", nil);
    sessionRow.subtitle = localize(@"ame369.setpg.ai_sessions.subtitle", @"查看与继续历史 AI 对话");
    sessionRow.onTap = ^{
        AISessionListViewController *vc = [[AISessionListViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [weakSelf ame_presentVC:nav];
    };
    // 系统提示词（编辑器模态，旧页同款）
    ZL2SettingRowAction *promptRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    promptRow.title = localize(@"preference.title.system_prompt", nil);
    promptRow.subtitle = localize(@"ame369.setpg.ai_prompt.subtitle", @"自定义注入对话的系统级提示词");
    promptRow.onTap = ^{
        AISystemPromptEditorViewController *vc = [[AISystemPromptEditorViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [weakSelf ame_presentVC:nav];
    };
    [group1 ame_addRows:@[providerRow, sessionRow, promptRow]];
    [self ame_addGroup:group1];

    // --- 组 2：行为开关（安全模式三档 + Markdown 渲染）---
    ZL2SettingCardGroup *group2 = [[ZL2SettingCardGroup alloc] init];
    NSArray<NSString *> *safetyKeys = @[@"safe", @"ask", @"yolo"];
    NSArray<NSString *> *safetyNames = @[
        localize(@"ame189.ai.safety_safe", nil),
        localize(@"ame189.ai.safety_ask", nil),
        localize(@"ame189.ai.safety_yolo", nil),
    ];
    ZL2SettingRowList *safetyRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:safetyNames optionKeys:safetyKeys];
    safetyRow.title = localize(@"preference.title.safety_mode", nil);
    safetyRow.subtitle = localize(@"preference.detail.safety_mode", nil);
    // ★ Ame361：直连 AiSettings（NSUserDefaults ai.safety_mode，消费方
    //   AiSafetyManager 同源；旧页 Task189 闭包特判同款协议）——原
    //   PLPreferences ai.safety_mode 未注册被静默丢弃 = "新UI修改回退、
    //   旧页修改生效"双标根因。存储值 = 稳定 ID（safe/ask/yolo）。
    NSString *ame361_safety = @"safe";
    switch ([[AiSettings sharedSettings] safetyMode]) {
        case AiSafetyModeSafe:  ame361_safety = @"safe"; break;
        case AiSafetyModeAsk:   ame361_safety = @"ask";  break;
        case AiSafetyModeYOLO:  ame361_safety = @"yolo"; break;
    }
    [safetyRow ame_reloadSelectedIndex:(NSInteger)[safetyKeys indexOfObject:ame361_safety]];
    safetyRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= safetyKeys.count) return;
        NSString *k = safetyKeys[index];
        AiSafetyMode mode = [k isEqualToString:@"yolo"] ? AiSafetyModeYOLO
                          : [k isEqualToString:@"ask"]  ? AiSafetyModeAsk
                          : AiSafetyModeSafe;
        [[AiSettings sharedSettings] setSafetyMode:mode];
    };
    ZL2SettingRowSwitch *markdownRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    markdownRow.title = localize(@"preference.title.markdown_enabled", nil);
    markdownRow.subtitle = localize(@"ame369.setpg.ai_markdown.subtitle", @"AI 回复以 Markdown 格式渲染");
    // ★ Ame361：直连 AiSettings（消费方 AiSettings.markdownEnabled 同源）
    [markdownRow ame_setOn:[[AiSettings sharedSettings] markdownEnabled]];
    markdownRow.onToggle = ^(BOOL on) {
        [[AiSettings sharedSettings] setMarkdownEnabled:on];
    };
    [group2 ame_addRows:@[safetyRow, markdownRow]];
    [self ame_addGroup:group2];
}

- (void)ame_refreshState {
    [self ame_rebuildGroups];
}

@end

#pragma mark - ⑤c 调试屏（Task344 旧设置全量迁移：debug 分区入新UI）

@implementation ZL2DebugSettingsPage

- (void)ame_buildGroups {
    __weak typeof(self) weakSelf = self;

    // --- 组 1：JIT 调度（jit_enabler 八档 + 内置 JIT 管理入口）---
    ZL2SettingCardGroup *group1 = [[ZL2SettingCardGroup alloc] init];
    NSArray<NSString *> *jitKeys = @[
        @"auto", @"builtin", @"stikjit", @"sidestore",
        @"stosdebug", @"jitstreamer", @"trollstore", @"manual",
    ];
    NSArray<NSString *> *jitNames = @[
        localize(@"preference.debug.jit_enabler.auto", nil),
        localize(@"preference.debug.jit_enabler.builtin", nil),
        localize(@"preference.debug.jit_enabler.stikjit", nil),
        localize(@"preference.debug.jit_enabler.sidestore", nil),
        localize(@"preference.debug.jit_enabler.stosdebug", nil),
        localize(@"preference.debug.jit_enabler.jitstreamer", nil),
        localize(@"preference.debug.jit_enabler.trollstore", nil),
        localize(@"preference.debug.jit_enabler.manual", nil),
    ];
    ZL2SettingRowList *jitRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:jitNames optionKeys:jitKeys];
    jitRow.title = localize(@"preference.title.jit_enabler", nil);
    jitRow.subtitle = localize(@"preference.detail.jit_enabler", nil);
    [jitRow ame_reloadSelectedIndex:(NSInteger)[jitKeys indexOfObject:
        ame_pages_stringOr(getPrefObject(@"debug.jit_enabler"), @"auto")]];
    jitRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= jitKeys.count) return;
        setPrefString(@"debug.jit_enabler", jitKeys[index]);
    };
    [group1 ame_addRow:jitRow];
    // 内置 JIT 管理（Task291 配对文件 + 深链开启；表单模态旧页同款）
    ZL2SettingRowAction *stikRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    stikRow.title = localize(@"ame291.jit.pref_row", nil);
    stikRow.subtitle = localize(@"preference.detail.ame291_builtin_jit", nil);
    stikRow.onTap = ^{
        StikDebugViewController *jitVC = [[StikDebugViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:jitVC];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [weakSelf ame_presentVC:nav];
    };
    [group1 ame_addRow:stikRow];
    [self ame_addGroup:group1];

    // --- 组 2：JIT 故障面（四开关；后两件有前置条件——旧页 enableCondition 同口径）---
    ZL2SettingCardGroup *group2 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowSwitch *jit26Row =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    jit26Row.title = localize(@"preference.title.jit26_script_disable", nil);
    jit26Row.subtitle = localize(@"preference.detail.jit26_script_disable", nil);
    [jit26Row ame_setOn:getPrefBool(@"debug.jit26_script_disable")];
    jit26Row.onToggle = ^(BOOL on) {
        setPrefBool(@"debug.jit26_script_disable", on);
    };
    ZL2SettingRowSwitch *mirrorRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    mirrorRow.title = localize(@"preference.title.mirror_codecache_disable", nil);
    mirrorRow.subtitle = localize(@"preference.detail.mirror_codecache_disable", nil);
    [mirrorRow ame_setOn:getPrefBool(@"debug.mirror_codecache_disable")];
    mirrorRow.onToggle = ^(BOOL on) {
        setPrefBool(@"debug.mirror_codecache_disable", on);
    };
    [group2 ame_addRows:@[jit26Row, mirrorRow]];
    if (DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM) && ame_pages_whenNotInGame()) {
        ZL2SettingRowSwitch *universalRow =
            [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
        universalRow.title = localize(@"preference.title.debug_universal_script_jit", nil);
        universalRow.subtitle = localize(@"ame369.setpg.universal_jit.subtitle", @"通用 JIT 脚本（TXM 设备实验特性）");
        [universalRow ame_setOn:getPrefBool(@"debug.debug_universal_script_jit")];
        universalRow.onToggle = ^(BOOL on) {
            setPrefBool(@"debug.debug_universal_script_jit", on);
        };
        [group2 ame_addRow:universalRow];
        if (getPrefBool(@"debug.debug_universal_script_jit")) {
            ZL2SettingRowSwitch *attachedRow =
                [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
            attachedRow.title = localize(@"preference.title.debug_always_attached_jit", nil);
            attachedRow.subtitle = localize(@"preference.detail.debug_always_attached_jit", nil);
            [attachedRow ame_setOn:getPrefBool(@"debug.debug_always_attached_jit")];
            attachedRow.onToggle = ^(BOOL on) {
                setPrefBool(@"debug.debug_always_attached_jit", on);
            };
            [group2 ame_addRow:attachedRow];
        }
    }
    ZL2SettingRowSwitch *skipWaitRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    skipWaitRow.title = localize(@"preference.title.debug_skip_wait_jit", nil);
    skipWaitRow.subtitle = localize(@"preference.detail.debug_skip_wait_jit", nil);
    [skipWaitRow ame_setOn:getPrefBool(@"debug.debug_skip_wait_jit")];
    skipWaitRow.onToggle = ^(BOOL on) {
        setPrefBool(@"debug.debug_skip_wait_jit", on);
    };
    [group2 ame_addRow:skipWaitRow];
    [self ame_addGroup:group2];

    // --- 组 3：界面调试（三开关）---
    ZL2SettingCardGroup *group3 = [[ZL2SettingCardGroup alloc] init];
    // 隐藏 Home 指示器（有底部安全区的设备才有意义——旧页同口径）
    if (self.view.safeAreaInsets.bottom > 0) {
        ZL2SettingRowSwitch *homeRow =
            [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
        homeRow.title = localize(@"preference.title.debug_hide_home_indicator", nil);
        homeRow.subtitle = localize(@"preference.detail.debug_hide_home_indicator", nil);
        [homeRow ame_setOn:getPrefBool(@"debug.debug_hide_home_indicator")];
        homeRow.onToggle = ^(BOOL on) {
            setPrefBool(@"debug.debug_hide_home_indicator", on);
        };
        [group3 ame_addRow:homeRow];
    }
    ZL2SettingRowSwitch *ipadRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    ipadRow.title = localize(@"preference.title.debug_ipad_ui", nil);
    ipadRow.subtitle = localize(@"preference.detail.debug_ipad_ui", nil);
    [ipadRow ame_setOn:getPrefBool(@"debug.debug_ipad_ui")];
    ipadRow.onToggle = ^(BOOL on) {
        setPrefBool(@"debug.debug_ipad_ui", on);
    };
    ZL2SettingRowSwitch *autoCorrRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    autoCorrRow.title = localize(@"preference.title.debug_auto_correction", nil);
    autoCorrRow.subtitle = localize(@"preference.detail.debug_auto_correction", nil);
    [autoCorrRow ame_setOn:getPrefBool(@"debug.debug_auto_correction")];
    autoCorrRow.onToggle = ^(BOOL on) {
        setPrefBool(@"debug.debug_auto_correction", on);
    };
    [group3 ame_addRows:@[ipadRow, autoCorrRow]];
    [self ame_addGroup:group3];
}

- (void)ame_refreshState {
    [self ame_rebuildGroups];
}

@end
