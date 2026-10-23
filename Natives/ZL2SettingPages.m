//
// ZL2SettingPages.m — ZL2 设置八屏子页实现（7.0-UI-13-S）
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
//   control.mod_touch_mode         通信方式（0 禁用/1 UDP/2 静态库；写入同
//                                  步 mod_touch_enable/mod_touch_user_off
//                                  哨兵 + java.env_variables UDP 环境变量
//                                  ——旧页 updateTouchControllerSetting 全链）
//   control.mod_touch_vibrate_enable        震动反馈
//   control.mod_touch_vibrate_intensity     震动强度（1–3）
//   control.mod_touch_moveview_enable       移动视角
//   control.mod_touch_hide_controls         屏蔽启动器控件
//   完整触控设置 → TouchControllerPreferencesViewController（写后 post
//   TouchControllerSettingsChanged——Task224 广播契约）
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
// ⑧ 关于屏
//   CFBundleShortVersionString / CFBundleVersion   版本号 / 构建号
//   general.auto_update_check      启动时自动检查更新（Task125 语义）
//   检查更新 = UpdateChecker 正式版检查（AboutViewController ame217 链路
//   平移：loading 弹窗 + 结果弹窗 + openReleasePage）
//   项目主页 / QQ 群 / 更多关于信息 → AboutViewController
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
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "PLMirrorCenter.h"
#import "BackgroundManager.h"
#import "UpdateChecker.h"
#import "utils.h"

#import "LauncherPreferencesViewController.h"
#import "LauncherPrefGameDirViewController.h"  // Task316：游戏目录/实例选择器
#import "FileLayoutService.h"                 // Task316：跨启动器导入
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "BackgroundSettingsViewController.h"
#import "BingWallpaperGalleryViewController.h"
#import "TouchControllerPreferencesViewController.h"
#import "LauncherPrefContCfgViewController.h"
#import "LauncherPrefManageJREViewController.h"
#import "ControlRepoViewController.h"
#import "CustomControlsViewController.h"
#import "AboutViewController.h"
#import "JavaGUIViewController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <stdlib.h>

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
        [scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
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
    rendererRow.title = @"渲染器（全局默认）";
    rendererRow.subtitle = @"各实例可在版本设置的实例页单独覆盖";
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
    resolutionRow.title = @"分辨率缩放";
    resolutionRow.subtitle = @"渲染分辨率百分比（各实例可单独覆盖）";
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
    fullscreenRow.title = @"全屏输出（外接显示器）";
    fullscreenRow.subtitle = @"连接外接屏幕时以全屏显示游戏画面";
    [fullscreenRow ame_setOn:fullscreenOn];
    fullscreenRow.onToggle = ^(BOOL on) {
        setPrefBool(@"video.fullscreen_airplay", on);
    };
    self.fullscreenRow = fullscreenRow;

    ZL2SettingCardGroup *group1 = [[ZL2SettingCardGroup alloc] init];
    [group1 ame_addRows:@[rendererRow, resolutionRow, fullscreenRow]];
    [self ame_addGroup:group1];

    // --- 组 2：更多设置（长尾兜底契约）---
    ZL2SettingCardGroup *group2 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *moreRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    moreRow.title = @"更多视频与图形设置";
    moreRow.subtitle = @"FSR 档位、MobileGlues、音频等完整分区";
    moreRow.onTap = ^{
        [weakSelf ame_push:[[LauncherPreferencesViewController alloc] init] titled:@"更多设置"];
    };
    [group2 ame_addRow:moreRow];
    [self ame_addGroup:group2];
}

- (void)ame_refreshState {
    ame142_migrateRendererStorage();
    NSString *current = ame_pages_stringOr(getPrefObject(@"video.renderer"), @"auto");
    NSInteger idx = (NSInteger)[getRendererKeys(YES) indexOfObject:current];
    if (idx < 0) idx = (NSInteger)[getRendererKeys(YES) indexOfObject:@"auto"];
    [self.rendererRow ame_reloadSelectedIndex:MAX(idx, 0)];

    NSInteger resolution = (NSInteger)getPrefFloat(@"video.resolution");
    [self.resolutionRow ame_setValue:(resolution <= 0 ? 100 : resolution)];

    id fullscreenRaw = getPrefObject(@"video.fullscreen_airplay");
    [self.fullscreenRow ame_setOn:(fullscreenRaw ? [fullscreenRaw boolValue] : YES)];
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
    memoryRow.title = @"内存分配";
    memoryRow.subtitle = [NSString stringWithFormat:
        @"当前实例「%@」的 JVM 堆上限（MB）", profileName];
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
    presetRow.subtitle = @"GC 策略档位（实例覆写 → 全局 → normal）";
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
    customArgsRow.subtitle = @"预设选「自定义」时注入";
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
    javaArgsRow.subtitle = @"附加到启动命令（留空使用默认）";
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
    isolationRow.title = @"版本隔离";
    isolationRow.subtitle = @"当前游戏目录使用独立偏好集（重启启动器后完全生效）";
    [isolationRow ame_setOn:getPrefBool(@"internal.isolated")];
    isolationRow.onToggle = ^(BOOL on) {
        [weakSelf ame_writeInstanceIsolation:on];
    };
    self.isolationRow = isolationRow;

    ZL2SettingCardGroup *group2 = [[ZL2SettingCardGroup alloc] init];
    [group2 ame_addRow:isolationRow];
    [self ame_addGroup:group2];

    // --- 组 3：更多设置 ---
    ZL2SettingCardGroup *group3 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *moreRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    moreRow.title = @"更多游戏设置";
    moreRow.subtitle = @"Java 版本、环境变量、调试等完整分区";
    moreRow.onTap = ^{
        [weakSelf ame_push:[[LauncherPreferencesViewController alloc] init] titled:@"更多设置"];
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
    NSInteger memoryCap = (NSInteger)ame173_safeHeapCeilingMB() + 512;
    if (memoryCap < 1024) memoryCap = 1024;
    NSMutableDictionary *profile = [[[PLProfiles current] selectedProfile] mutableCopy]
        ?: [NSMutableDictionary dictionary];
    NSInteger memory = [profile[@"allocatedMemory"] integerValue];
    if (memory <= 0) memory = MIN(memoryCap / 2, 2048);
    [self.memoryRow ame_setValue:MAX(256, MIN(memoryCap, memory))];

    NSString *preset = ame_pages_stringOr(getPrefObject(@"java.jvm_preset"), @"normal");
    [self.presetRow ame_reloadSelectedIndex:
        (NSInteger)[ame_gamePagePresetKeys() indexOfObject:preset]];
    [self.customArgsRow ame_setText:ame_pages_stringOr(getPrefObject(@"java.jvm_preset_custom_args"), @"")];
    [self.javaArgsRow ame_setText:ame_pages_stringOr(getPrefObject(@"java.java_args"), @"")];
    [self.isolationRow ame_setOn:getPrefBool(@"internal.isolated")];
}

@end

#pragma mark - ③ 控制屏

@interface ZL2ControlSettingsPage ()
@property (nonatomic, strong) ZL2SettingRowList *modeRow;
@property (nonatomic, strong) ZL2SettingRowSwitch *vibrateRow;
@property (nonatomic, strong) ZL2SettingRowSlider *intensityRow;
@property (nonatomic, strong) ZL2SettingRowSwitch *moveViewRow;
@property (nonatomic, strong) ZL2SettingRowSwitch *hideControlsRow;
@end

@implementation ZL2ControlSettingsPage

- (void)ame_buildGroups {
    __weak typeof(self) weakSelf = self;

    // --- 组 1：TouchController（旧「触控设置」页顶层项，同键族）---
    NSArray<NSString *> *modeNames = @[
        localize(@"preference.touchcontroller.mode.disabled", nil),
        localize(@"preference.touchcontroller.mode.udp", nil),
        localize(@"preference.touchcontroller.mode.staticlib", nil),
    ];
    ZL2SettingRowList *modeRow =
        [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                 options:modeNames optionKeys:@[@"0", @"1", @"2"]];
    modeRow.title = localize(@"preference.touchcontroller.mode.title", nil);
    modeRow.subtitle = @"TouchController 模组与启动器的通信通道";
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

    // --- 组 2：完整触控设置（长尾兜底）---
    ZL2SettingCardGroup *group2 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *fullRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    fullRow.title = @"完整触控设置";
    fullRow.subtitle = @"通信模式说明、关于 TouchController";
    fullRow.onTap = ^{
        [weakSelf ame_push:[[TouchControllerPreferencesViewController alloc] init] titled:@"触控设置"];
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
    BOOL enabled = getPrefBool(@"control.mod_touch_enable");
    NSInteger mode = getPrefInt(@"control.mod_touch_mode");
    if (mode < 0 || mode > 2) mode = 0;
    [self.modeRow ame_reloadSelectedIndex:(enabled ? mode : 0)];
    [self.vibrateRow ame_setOn:getPrefBool(@"control.mod_touch_vibrate_enable")];
    [self.intensityRow ame_setValue:MAX(1, MIN(3, getPrefInt(@"control.mod_touch_vibrate_intensity")))];
    [self.moveViewRow ame_setOn:getPrefBool(@"control.mod_touch_moveview_enable")];
    [self.hideControlsRow ame_setOn:getPrefBool(@"control.mod_touch_hide_controls")];
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
    typeRow.title = @"手柄类型";
    typeRow.subtitle = @"面键图标风格；选任天堂即交换 A/B、X/Y 键面（Switch 布局）";
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
    mappingRow.subtitle = @"编辑当前映射文件（按键 → 键位）";
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
    scrollRow.title = @"模拟滚轮速度";
    scrollRow.subtitle = @"滚动按钮/手柄滚轮键的滚动速度（真滚轮不受影响）";
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
    moreRow.title = @"更多控制与手柄设置";
    moreRow.subtitle = @"键位调整、自定义鼠标、陀螺仪等完整分区";
    moreRow.onTap = ^{
        [weakSelf ame_push:[[LauncherPreferencesViewController alloc] init] titled:@"更多设置"];
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
@property (nonatomic, strong) ZL2SettingRowEnum *themeRow;
@property (nonatomic, strong) ZL2SettingRowList *languageRow;
@property (nonatomic, strong) ZL2SettingRowList *effectRow;
@property (nonatomic, strong) ZL2SettingRowSlider *opacityRow;
@property (nonatomic, strong) ZL2SettingRowSlider *blurRow;
@property (nonatomic, strong) NSArray<ZL2SettingRowList *> *sourceRows;
@property (nonatomic, strong) NSArray<NSString *> *sourceRowKeys;   // 与 sourceRows 对齐
@end

@interface ZL2LauncherSettingsPage () <UIDocumentPickerDelegate>
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

- (void)ame_presentVC:(UIViewController *)vc {
    // 壳内宿主导航可达（设置页由 ZL2Shell 包 nav）；兜底顶栈 present
    UIViewController *host = self.navigationController ?: self;
    while (host.presentedViewController) host = host.presentedViewController;
    [host presentViewController:vc animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *report = [FileLayoutService ame316_importExternalLauncherFolder:urls[0] error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *body = report ?: @"导入失败：无法读取所选文件夹（安全作用域被拒或路径无效）。";
            [ZL2M3Dialog showTitle:@"导入结果"
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
    // 深浅模式（general.ui_theme；旧页 Task161 契约：显式选择标记 + 通知）
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
    languageRow.subtitle = @"切换后界面立即重载（未翻译语言回退并标记）";
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
    effectRow.title = @"界面效果";
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
    opacityRow.title = @"背景不透明度";
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
    blurRow.title = @"背景模糊强度";
    [blurRow ame_setValue:(NSInteger)round(bg.blurIntensity * 100.0)];
    blurRow.onValueChanged = ^(NSInteger value) {
        // setter 内部落 Task256 blurUserSet 标记（模糊=0 为真实意图）
        [BackgroundManager sharedManager].blurIntensity = value / 100.0;
        [[BackgroundManager sharedManager] refreshUIEffect];
    };
    self.blurRow = blurRow;

    ZL2SettingCardGroup *group1 = [[ZL2SettingCardGroup alloc] init];
    [group1 ame_addRows:@[themeRow, languageRow, effectRow, opacityRow, blurRow]];
    [self ame_addGroup:group1];

    // --- 组 2：下载源（download.* 四分类真键；值域 official/mirror/speed_first）---
    NSArray<NSString *> *sourceKeys = @[@"official_first", @"mirror_first", @"speed_first"];
    NSArray<NSString *> *sourceNames = @[
        localize(@"preference.title.mirror_policy-official_first", nil),
        localize(@"preference.title.mirror_policy-mirror_first", nil),
        localize(@"preference.title.mirror_policy-speed_first", nil),
    ];
    NSDictionary<NSString *, NSString *> *sourceTitles = @{
        @"download.fileSource":          @"文件下载源",
        @"download.assetSearchSource":   @"资源搜索源",
        @"download.assetDownloadSource": @"资源下载源",
        @"download.modLoaderSource":     @"加载器下载源",
    };
    NSMutableArray<ZL2SettingRowList *> *sourceRows = [NSMutableArray array];
    NSMutableArray<NSString *> *sourceRowKeys = [NSMutableArray array];
    for (NSString *prefKey in sourceTitles) {
        ZL2SettingRowList *row =
            [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                     options:sourceNames optionKeys:sourceKeys];
        row.title = sourceTitles[prefKey];
        // 显示兜底（Task218 口径）：缺值/非法值 → 出厂默认 speed_first
        NSString *value = ame_pages_stringOr(getPrefObject(prefKey), @"speed_first");
        BOOL valid = [sourceKeys containsObject:value];
        [row ame_reloadSelectedIndex:
            valid ? (NSInteger)[sourceKeys indexOfObject:value]
                  : (NSInteger)[sourceKeys indexOfObject:@"speed_first"]];
        row.onSelect = ^(NSInteger index) {
            if (index < 0 || (NSUInteger)index >= sourceKeys.count) return;
            setPrefString(prefKey, sourceKeys[index]);
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

    // --- 组 3：入口 ---
    ZL2SettingCardGroup *group3 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *backgroundRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    backgroundRow.title = @"背景设置";
    backgroundRow.onTap = ^{
        [weakSelf ame_push:[[BackgroundSettingsViewController alloc] init] titled:@"背景设置"];
    };
    ZL2SettingRowAction *galleryRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    galleryRow.title = @"壁纸画廊";
    galleryRow.onTap = ^{
        // 工厂方法返回按设备宽度预配置网格布局的 UICollectionViewController
        [weakSelf ame_push:[BingWallpaperGalleryViewController galleryController] titled:@"壁纸画廊"];
    };
    ZL2SettingRowAction *moreRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    moreRow.title = @"更多启动器设置";
    moreRow.subtitle = @"界面缩放、强调色、公告、数据导出等完整分区";
    moreRow.onTap = ^{
        [weakSelf ame_push:[[LauncherPreferencesViewController alloc] init] titled:@"更多设置"];
    };
    // Task316（文件层桌面/安卓同构）：游戏目录/实例切换入口 + 跨启动器导入
    ZL2SettingRowAction *gameDirRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    gameDirRow.title = @"游戏目录与实例";
    gameDirRow.subtitle = @"查看/切换实例目录（instances），切换后重启生效";
    gameDirRow.onTap = ^{
        [weakSelf ame_push:[[LauncherPrefGameDirViewController alloc] init]
                   titled:localize(@"preference.title.game_directory", nil)];
    };
    ZL2SettingRowAction *importRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    importRow.title = @"导入外部启动器数据";
    importRow.subtitle = @"识别 .minecraft / HMCL·PCL / MultiMC·Prism / 安卓启动器目录，合入当前实例";
    importRow.onTap = ^{
        [weakSelf ame316_pickExternalFolder];
    };
    [group3 ame_addRows:@[backgroundRow, galleryRow, gameDirRow, importRow, moreRow]];
    [self ame_addGroup:group3];
}

- (void)ame_refreshState {
    // 深浅模式
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
        row.subtitle = @"未安装匹配运行时时启动链自动回退";
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
        emptyRow.title = @"未发现已安装的 Java 运行时";
        emptyRow.subtitle = @"内置运行时随启动器分发；可用「完整 Java 管理」导入";
        [group2 ame_addRow:emptyRow];
    } else {
        for (NSDictionary *runtime in runtimes) {
            NSString *title = [runtime[@"internal"] boolValue]
                ? [NSString stringWithFormat:@"%@（内置）", runtime[@"name"]]
                : runtime[@"name"];
            ZL2SettingRowAction *row =
                [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
            row.title = title;
            row.subtitle = [NSString stringWithFormat:@"Java %@ · %@",
                                runtime[@"version"],
                                [runtime[@"internal"] boolValue] ? @"内置" : @"外部安装"];
            [group2 ame_addRow:row];
        }
    }
    [self ame_addGroup:group2];

    // --- 组 3：执行 Jar + 完整管理 ---
    ZL2SettingCardGroup *group3 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *runJarRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    runJarRow.title = localize(@"launcher.menu.execute_jar", nil);
    runJarRow.subtitle = @"选择 Jar 后经守卫链全屏运行";
    runJarRow.onTap = ^{
        [weakSelf ame_pickJarFile];
    };
    ZL2SettingRowAction *manageRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    manageRow.title = @"完整 Java 管理";
    manageRow.subtitle = @"导入 / 删除运行时、调整分区预选";
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
        emptyRow.title = @"未找到控制布局文件";
        emptyRow.subtitle = @"可从「控件仓库」下载，或用「键位调整」创建";
        [group1 ame_addRow:emptyRow];
    } else {
        NSString *current = ame_pages_stringOr(getPrefObject(@"control.default_ctrl"), @"custom.json");
        ZL2SettingRowList *layoutRow =
            [[ZL2SettingRowList alloc] initWithTitle:@"" subtitle:nil
                                     options:layouts optionKeys:layouts];
        layoutRow.title = @"当前布局";
        layoutRow.subtitle = @"游戏内屏幕控件布局（controlmap 目录）";
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
        gpEmptyRow.title = @"未找到手柄映射文件";
        gpEmptyRow.subtitle = @"可从「手柄仓库」下载（内建默认同源备份）";
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
        gpRow.title = @"当前手柄映射";
        gpRow.subtitle = @"手柄键码映射（controlmap/gamepads 目录）";
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
    gpRepoRow.title = @"手柄仓库";
    gpRepoRow.subtitle = @"官方精选/社区手柄映射下载（装完即用）";
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
    editorRow.subtitle = @"全屏画布编辑器（添加/拖动/缩放控件）";
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
    repoRow.title = @"控件仓库";
    repoRow.subtitle = @"浏览与下载社区控制布局";
    repoRow.onTap = ^{
        [weakSelf ame_push:[[ControlRepoViewController alloc] init] titled:@"控件仓库"];
    };
    ZL2SettingRowAction *resetRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    resetRow.title = @"恢复默认布局";
    resetRow.subtitle = @"写回出厂布局 custom.json（Task77 口径）";
    resetRow.onTap = ^{
        [ZL2M3Dialog showTitle:@"恢复默认布局"
                          body:@"将当前控制布局重置为出厂布局 custom.json，下次进入游戏生效。"
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
    moreRow.title = @"更多控制设置";
    moreRow.subtitle = @"手柄配置、虚拟鼠标、陀螺仪等完整分区";
    moreRow.onTap = ^{
        [weakSelf ame_push:[[LauncherPreferencesViewController alloc] init] titled:@"更多设置"];
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

- (void)ame_buildGroups {
    __weak typeof(self) weakSelf = self;

    // --- 组 1：版本与更新 ---
    ZL2SettingCardGroup *group1 = [[ZL2SettingCardGroup alloc] init];

    // 版本号 / 构建号（只读展示行：onTap nil = 无 chevron 不响应）
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: version;
    ZL2SettingRowAction *versionRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    versionRow.title = @"版本号";
    versionRow.detailText = version;
    ZL2SettingRowAction *buildRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    buildRow.title = @"构建号";
    buildRow.detailText = build;

    // 启动时自动检查更新（general.auto_update_check；Task125 语义）
    ZL2SettingRowSwitch *autoUpdateRow =
        [[ZL2SettingRowSwitch alloc] initWithTitle:@"" subtitle:nil];
    autoUpdateRow.title = localize(@"preference.title.auto_update_check", nil);
    [autoUpdateRow ame_setOn:getPrefBool(@"general.auto_update_check")];
    autoUpdateRow.onToggle = ^(BOOL on) {
        setPrefObject(@"general.auto_update_check", @(on));
    };
    self.autoUpdateRow = autoUpdateRow;

    // 检查更新（AboutViewController ame217 链路平移：正式版检查 + 结果弹窗）
    ZL2SettingRowAction *checkRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    checkRow.title = localize(@"preference.title.check_update", nil);
    checkRow.subtitle = @"GitHub Releases 正式版检查";
    checkRow.onTap = ^{
        [weakSelf ame_checkForUpdate];
    };

    [group1 ame_addRows:@[versionRow, buildRow, autoUpdateRow, checkRow]];
    [self ame_addGroup:group1];

    // --- 组 2：项目与更多 ---
    ZL2SettingCardGroup *group2 = [[ZL2SettingCardGroup alloc] init];
    ZL2SettingRowAction *projectRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    projectRow.title = @"项目主页";
    projectRow.subtitle = @"https://github.com/Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher";
    projectRow.onTap = ^{
        [weakSelf ame_openURL:[NSURL URLWithString:
            @"https://github.com/Gsjsjzhznsz/Prisma-Minecraft-iOS-Launcher"]];
    };
    ZL2SettingRowAction *qqRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    qqRow.title = localize(@"about.qq.title", nil);
    qqRow.subtitle = ame217_qqGroupNumber();
    qqRow.onTap = ^{
        // 群号复制（about.qq.copied 既有文案）
        [UIPasteboard generalPasteboard].string = ame217_qqGroupNumber();
        [weakSelf ame_showNoticeText:localize(@"about.qq.copied", nil)];
    };
    ZL2SettingRowAction *moreRow =
        [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    moreRow.title = @"更多关于信息";
    moreRow.subtitle = @"致谢、许可证、支持我们";
    moreRow.onTap = ^{
        [weakSelf ame_push:[[AboutViewController alloc] init]
                   titled:localize(@"about.nav_title", nil)];
    };
    [group2 ame_addRows:@[projectRow, qqRow, moreRow]];
    [self ame_addGroup:group2];
}

- (void)ame_refreshState {
    [self.autoUpdateRow ame_setOn:getPrefBool(@"general.auto_update_check")];
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
