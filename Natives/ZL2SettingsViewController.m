//
// ZL2SettingsViewController.m — ZL2 风格设置枢纽页实现（7.0-UI-9-d）
//
// 对标：ZalithLauncher2 ui/screens/content/SettingsScreen.kt——左轨 8 类
// （Renderer/Game/Control/Gamepad/Launcher/JavaManager/ControlManager/
// AboutInfo）+ 右侧 SettingsCardColumn 拼接圆角组卡。本仓设置子页未按 ZL2
// 八类拆分，禁止造假轨道——本页做成 ZL2 视觉的「分组枢纽列表」：M3 组卡
// （surfaceContainer 底 + radiusM 圆角 + 行连续拼圆角 + 0.5pt outlineVariant
// 分隔线左右 inset 16），行高 52（图标 20pt + fontBodyLarge 标题 + 14pt
// chevron），组名不显示文本（组本身无标题，纯拼卡），组间 8pt 间距。
//
// 分组-行-目标 VC 全表（init 签名逐一对过真实 .h / 既有调用点）：
//   组「启动器」
//     完整设置       → LauncherPreferencesViewController（init，ZL2Shell 同款）
//     背景设置       → BackgroundSettingsViewController（init）
//     壁纸画廊       → BingWallpaperGalleryViewController（+galleryController
//                     工厂，按设备宽度预配置网格——此类无公开裸 init 用法）
//   组「游戏与控制」
//     控制配置       → LauncherPrefContCfgViewController（init）
//     触控设置       → TouchControllerPreferencesViewController（init）
//     游戏目录       → LauncherPrefGameDirViewController（init）
//   组「Java 与运行」
//     Java 管理      → LauncherPrefManageJREViewController（init）
//     执行 Jar 文件   → 文档选择器 → 守卫链 → 全屏模态 JavaGUIViewController
//                     （filepath 必填且页内 dismiss 走 presentingViewController
//                     ——模态专用页，裸 push/无路径必崩或黑屏，故本行是全页
//                     唯一非 push 行，交互与旧右面板 executeJar 入口一致）
//   组「数据与维护」
//     数据导出       → DataExportViewController（init；Task223 头注即"push 进本页"）
//     清理游戏文件    → CleanupViewController（init + ame255_versionScanner 注入
//                     [VersionManagerViewController ame256_scanVersionsForCleanup]
//                     ——单一扫描口径，与版本管理页/主页清理磁贴共用）
//     CurseForge API Key → CurseForgeAPIKeyViewController（init）
//   组「关于」
//     关于           → AboutViewController（init）
//   （检查更新行省略——spec 可选项：AboutViewController 已内置"检查更新 +
//   启动时自动检查"（Task217 迁移入关于页），UpdateChecker 完成回调 UI 需
//   复刻 About 整条流程，重复入口且超出低成本行装配范畴，故不纳入。）
//
// 执行 Jar 守卫链（1:1 对齐 LauncherRightPanelViewController
// enterModInstallerWithPath: L1321-1369 的精简安全子集）：
//   ①requiredJavaVersion 解析失败 → 提示（getter 内部已自带错误弹窗）；
//   ②getSelectedJavaHome(@"execute_jar", ver) 为空 → 提示（防 present 黑屏）；
//   ③二次 JVM 崩溃守卫由 JavaGUIViewController.viewDidLoad 自带兜底（其注释
//   明言"未来新增直接 alloc 本 VC 的调用方"即本类这类入口，不重复实现）；
//   ④JIT 引导链（invokeAfterJITEnabled，宿主 VC 私有 ~250 行复杂引导）本轮
//   不复制——未启用 JIT 的环境执行 Jar 可能降速/异常，待 JIT 引导抽成公共
//   服务后接入（见 worklog 7.0-UI-9-d 风险注记）。
//
// 通知面：无监听、无发送（纯静态枢纽，无动态状态，dealloc 无需清理）。
//
// 红线遵守：iOS 14.0+（initForOpeningContentTypes:asCopy: 恰为 iOS 14 API，
// 无更高；SF 符号全带旧名 fallback——gearshape.fill 为 iOS 14 的 SF2 符号，
// 兜底 SF1.0 的 gear）；颜色/字体/圆角一律 ZL2Theme 动态令牌（无
// traitCollection 分支）；全部新建视图 translatesAutoresizingMaskIntoConstraints
// = NO；行身份 = flatRows 数组下标（UIControl.tag 仅作下标载荷，不经
// viewWithTag: 查找——ZL2Home 同判例）；文案硬编码中文与 ZL2HomeViewController
// 同判例（7.0-UI-8 待办③：待 i18n 轮次收编）。
//

#import "ZL2SettingsViewController.h"
#import "ZL2Theme.h"
#import "LauncherPreferencesViewController.h"
#import "BackgroundSettingsViewController.h"
#import "BingWallpaperGalleryViewController.h"
#import "LauncherPrefContCfgViewController.h"
#import "TouchControllerPreferencesViewController.h"
#import "LauncherPrefGameDirViewController.h"
#import "LauncherPrefManageJREViewController.h"
#import "JavaGUIViewController.h"
#import "DataExportViewController.h"
#import "CleanupViewController.h"
#import "CurseForgeAPIKeyViewController.h"
#import "AboutViewController.h"
#import "VersionManagerViewController.h"   // +ame256_scanVersionsForCleanup（清理扫描注入）
#import "LauncherPreferences.h"            // getSelectedJavaHome（执行 Jar 的 JRE 预检）
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "utils.h"                          // localize()

// 内容列最大宽（照抄 ZL2HomeViewController：iPad 横屏居中，iPhone 占满减边距）
static const CGFloat ame_settingsContentMaxWidth = 520;

// 组卡行高与分隔线规格（spec：行高 52；分隔线 0.5pt，左右 inset 16）
static const CGFloat ame_settingsRowHeight = 52;
static const CGFloat ame_settingsSeparatorHeight = 0.5;

// SF Symbols 取图兜底（ZL2Home 同款判例：符号名异常时降级旧名而非空白）
static UIImage *ame_settingsSystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

#pragma mark - 行模型（.m 私有，harness 无需感知）

// 行 = 标题 + 图标（主名/兜底名）+ 动作块。动作块以 page 入参回传本页
//（块内不捕获 self），flatRows→row→block 零保留环。
@interface ZL2SettingsRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, copy, nullable) NSString *iconFallback;
@property (nonatomic, copy) void (^perform)(ZL2SettingsViewController *page);
+ (instancetype)rowWithTitle:(NSString *)title
                        icon:(NSString *)iconName
                    fallback:(nullable NSString *)iconFallback
                     perform:(void (^)(ZL2SettingsViewController *page))perform;
@end

@implementation ZL2SettingsRow

+ (instancetype)rowWithTitle:(NSString *)title
                        icon:(NSString *)iconName
                    fallback:(nullable NSString *)iconFallback
                     perform:(void (^)(ZL2SettingsViewController *page))perform {
    ZL2SettingsRow *row = [[ZL2SettingsRow alloc] init];
    row.title = title;
    row.iconName = iconName;
    row.iconFallback = iconFallback;
    row.perform = perform;
    return row;
}

@end

#pragma mark - 私有扩展

@interface ZL2SettingsViewController () <UIDocumentPickerDelegate>

// 布局
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UILabel *pageTitleLabel;
@property (nonatomic, strong) UIStackView *groupsStack;

// 行注册表：组卡顺序展开的扁平数组；行 UIControl.tag = 扁平下标（仅载荷，
// 不经 viewWithTag: 查找身份）
@property (nonatomic, copy) NSArray<ZL2SettingsRow *> *flatRows;

@end

@implementation ZL2SettingsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [ZL2Theme surface];
    [self buildViews];
}

// 根页导航栏约定：本页隐藏系统栏；push 子页 / present 全屏页时由
// viewWillDisappear 恢复，返回本页时 viewWillAppear 再隐藏（系统栏在
// push 时显示，子页标题/返回手势依赖它）
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:NO];
}

// 通知/KVO 均未注册，无需 dealloc 清理

#pragma mark - Layout

- (void)buildViews {
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.backgroundColor = [ZL2Theme surface];
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    _contentStack = [[UIStackView alloc] init];
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.alignment = UIStackViewAlignmentFill;
    _contentStack.spacing = 16;
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:_contentStack];

    // ① 页头：大标题「设置」（M3 顶栏位，左对齐）
    _pageTitleLabel = [[UILabel alloc] init];
    _pageTitleLabel.text = @"设置";
    _pageTitleLabel.font = [ZL2Theme fontTitleLarge];
    _pageTitleLabel.textColor = [ZL2Theme onSurface];
    _pageTitleLabel.numberOfLines = 1;
    _pageTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _pageTitleLabel.isAccessibilityElement = YES;
    _pageTitleLabel.accessibilityLabel = @"设置";
    [_contentStack addArrangedSubview:_pageTitleLabel];

    // ② 分组枢纽卡（组间 8pt：与内容列 16pt 垂直节奏不同，独立子栈承载）
    _groupsStack = [[UIStackView alloc] init];
    _groupsStack.axis = UILayoutConstraintAxisVertical;
    _groupsStack.alignment = UIStackViewAlignmentFill;
    _groupsStack.spacing = 8;
    _groupsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentStack addArrangedSubview:_groupsStack];

    // 组卡顺序落栈，同时把行展开为扁平下标注册表
    NSArray<NSArray<ZL2SettingsRow *> *> *groups = [self ame_rowGroups];
    NSMutableArray<ZL2SettingsRow *> *flat = [NSMutableArray array];
    for (NSArray<ZL2SettingsRow *> *rows in groups) {
        NSUInteger base = flat.count;
        [flat addObjectsFromArray:rows];
        [self ame_addGroupCardWithRows:rows flatBase:base];
    }
    self.flatRows = flat;

    // 宽度方案照抄 ZL2HomeViewController.buildViews（999 等式正定项）：
    // iPhone 占满可用宽（frame-40）；与 <=520 上限联立后宽屏由求解器收敛到
    // 520（999 误差最小解），centerX 居中；两侧 inequality 保底 >=20
    UILayoutGuide *contentLG = _scrollView.contentLayoutGuide;
    UILayoutGuide *frameLG = _scrollView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_contentStack.topAnchor constraintEqualToAnchor:contentLG.topAnchor constant:24],
        [contentLG.bottomAnchor constraintGreaterThanOrEqualToAnchor:_contentStack.bottomAnchor constant:24],
        [_contentStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:contentLG.leadingAnchor constant:20],
        [contentLG.trailingAnchor constraintGreaterThanOrEqualToAnchor:_contentStack.trailingAnchor constant:20],
        [_contentStack.centerXAnchor constraintEqualToAnchor:frameLG.centerXAnchor],
        [_contentStack.widthAnchor constraintLessThanOrEqualToConstant:ame_settingsContentMaxWidth],
    ]];
    NSLayoutConstraint *fillWidth = [_contentStack.widthAnchor constraintEqualToAnchor:frameLG.widthAnchor
                                                                              constant:-40];
    fillWidth.priority = 999;
    fillWidth.active = YES;
}

#pragma mark - 组卡装配

// 组卡 = surfaceContainer 底 + radiusM 圆角；行连续拼圆角（无行间缝），
// 行间 0.5pt outlineVariant 分隔线左右 inset 16；行高 52，卡高 = 行数×52。
// 分隔线直接以卡顶为基准定位（i*52 - 0.25 跨行界 hairline），不链式依赖。
- (void)ame_addGroupCardWithRows:(NSArray<ZL2SettingsRow *> *)rows
                        flatBase:(NSUInteger)base {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [ZL2Theme surfaceContainer];
    card.layer.cornerRadius = [ZL2Theme radiusM];
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.groupsStack addArrangedSubview:card];

    NSUInteger count = rows.count;
    for (NSUInteger i = 0; i < count; i++) {
        UIControl *rowControl = [self ame_rowControlForRow:rows[i]
                                                 flatIndex:base + i];
        [card addSubview:rowControl];
        [NSLayoutConstraint activateConstraints:@[
            [rowControl.topAnchor constraintEqualToAnchor:card.topAnchor
                                                 constant:i * ame_settingsRowHeight],
            [rowControl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [rowControl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
            [rowControl.heightAnchor constraintEqualToConstant:ame_settingsRowHeight],
        ]];

        if (i > 0) {
            UIView *separator = [[UIView alloc] init];
            separator.backgroundColor = [ZL2Theme outlineVariant];
            separator.translatesAutoresizingMaskIntoConstraints = NO;
            separator.userInteractionEnabled = NO;
            [card addSubview:separator];
            [NSLayoutConstraint activateConstraints:@[
                [separator.topAnchor constraintEqualToAnchor:card.topAnchor
                                                    constant:i * ame_settingsRowHeight
                                                             - ame_settingsSeparatorHeight / 2],
                [separator.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
                [separator.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
                [separator.heightAnchor constraintEqualToConstant:ame_settingsSeparatorHeight],
            ]];
        }
    }

    [card.heightAnchor constraintEqualToConstant:count * ame_settingsRowHeight].active = YES;
}

// 行 = 图标 20pt onSurfaceVariant + 标题 fontBodyLarge onSurface + 尾部
// chevron.right 14pt onSurfaceVariant，左右内边距 16；UIControl 点击回调
//（子视图 UILabel/UIImageView 默认不拦截触摸）
- (UIControl *)ame_rowControlForRow:(ZL2SettingsRow *)row
                          flatIndex:(NSUInteger)index {
    UIControl *control = [[UIControl alloc] init];
    control.translatesAutoresizingMaskIntoConstraints = NO;
    control.tag = index;   // 扁平下标载荷（不经 viewWithTag: 查找身份）
    control.isAccessibilityElement = YES;
    control.accessibilityLabel = row.title;
    control.accessibilityTraits = UIAccessibilityTraitButton;

    UIImage *iconImage = ame_settingsSystemImage(row.iconName, row.iconFallback);
    UIImageView *iconView = [[UIImageView alloc]
        initWithImage:[iconImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    iconView.tintColor = [ZL2Theme onSurfaceVariant];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [control addSubview:iconView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = row.title;
    titleLabel.font = [ZL2Theme fontBodyLarge];
    titleLabel.textColor = [ZL2Theme onSurface];
    titleLabel.numberOfLines = 1;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [control addSubview:titleLabel];

    UIImage *chevronImage = ame_settingsSystemImage(@"chevron.right", @"chevron.forward");
    UIImageView *chevronView = [[UIImageView alloc]
        initWithImage:[chevronImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    chevronView.tintColor = [ZL2Theme onSurfaceVariant];
    chevronView.contentMode = UIViewContentModeScaleAspectFit;
    chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    [control addSubview:chevronView];

    [control addTarget:self
                action:@selector(ame_rowTapped:)
      forControlEvents:UIControlEventTouchUpInside];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.leadingAnchor constraintEqualToAnchor:control.leadingAnchor constant:16],
        [iconView.centerYAnchor constraintEqualToAnchor:control.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:20],
        [iconView.heightAnchor constraintEqualToConstant:20],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:12],
        [titleLabel.centerYAnchor constraintEqualToAnchor:control.centerYAnchor],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:chevronView.leadingAnchor constant:-8],

        [chevronView.trailingAnchor constraintEqualToAnchor:control.trailingAnchor constant:-16],
        [chevronView.centerYAnchor constraintEqualToAnchor:control.centerYAnchor],
        [chevronView.widthAnchor constraintEqualToConstant:14],
        [chevronView.heightAnchor constraintEqualToConstant:14],
    ]];
    return control;
}

#pragma mark - 行注册表（组名不落 UI，仅注释分界——对齐 ZL2：组本身无标题）

- (NSArray<NSArray<ZL2SettingsRow *> *> *)ame_rowGroups {
    // —— 组「启动器」——
    ZL2SettingsRow *fullSettings =
        [ZL2SettingsRow rowWithTitle:@"完整设置"
                                icon:@"gearshape.fill"
                            fallback:@"gear"
                             perform:^(ZL2SettingsViewController *page) {
        LauncherPreferencesViewController *vc = [[LauncherPreferencesViewController alloc] init];
        [page ame_pushChild:vc titled:@"完整设置"];
    }];
    ZL2SettingsRow *background =
        [ZL2SettingsRow rowWithTitle:@"背景设置"
                                icon:@"photo.on.rectangle"
                            fallback:@"photo"
                             perform:^(ZL2SettingsViewController *page) {
        BackgroundSettingsViewController *vc = [[BackgroundSettingsViewController alloc] init];
        [page ame_pushChild:vc titled:@"背景设置"];
    }];
    ZL2SettingsRow *wallpapers =
        [ZL2SettingsRow rowWithTitle:@"壁纸画廊"
                                icon:@"photo.stack"
                            fallback:@"photo.on.rectangle"
                             perform:^(ZL2SettingsViewController *page) {
        // 工厂方法返回按设备宽度预配置网格布局的 UICollectionViewController
        UIViewController *vc = [BingWallpaperGalleryViewController galleryController];
        [page ame_pushChild:vc titled:@"壁纸画廊"];
    }];

    // —— 组「游戏与控制」——
    ZL2SettingsRow *controlCfg =
        [ZL2SettingsRow rowWithTitle:@"控制配置"
                                icon:@"gamecontroller"
                            fallback:nil
                             perform:^(ZL2SettingsViewController *page) {
        LauncherPrefContCfgViewController *vc = [[LauncherPrefContCfgViewController alloc] init];
        [page ame_pushChild:vc titled:@"控制配置"];
    }];
    ZL2SettingsRow *touchPrefs =
        [ZL2SettingsRow rowWithTitle:@"触控设置"
                                icon:@"hand.tap"
                            fallback:@"hand.point.up.left"
                             perform:^(ZL2SettingsViewController *page) {
        TouchControllerPreferencesViewController *vc = [[TouchControllerPreferencesViewController alloc] init];
        [page ame_pushChild:vc titled:@"触控设置"];
    }];
    ZL2SettingsRow *gameDir =
        [ZL2SettingsRow rowWithTitle:@"游戏目录"
                                icon:@"folder"
                            fallback:nil
                             perform:^(ZL2SettingsViewController *page) {
        LauncherPrefGameDirViewController *vc = [[LauncherPrefGameDirViewController alloc] init];
        [page ame_pushChild:vc titled:@"游戏目录"];
    }];

    // —— 组「Java 与运行」——
    ZL2SettingsRow *javaManage =
        [ZL2SettingsRow rowWithTitle:@"Java 管理"
                                icon:@"wrench.and.screwdriver"
                            fallback:@"wrench"
                             perform:^(ZL2SettingsViewController *page) {
        LauncherPrefManageJREViewController *vc = [[LauncherPrefManageJREViewController alloc] init];
        [page ame_pushChild:vc titled:@"Java 管理"];
    }];
    // 执行 Jar 文件：JavaGUIViewController 为模态专用页（filepath 必填），走
    // 文档选择器特殊流而非 push——见文件头说明与本类 ame_pickJarFile/ame_runJarAtPath:
    ZL2SettingsRow *runJar =
        [ZL2SettingsRow rowWithTitle:@"执行 Jar 文件"
                                icon:@"play.circle"
                            fallback:@"play"
                             perform:^(ZL2SettingsViewController *page) {
        [page ame_pickJarFile];
    }];

    // —— 组「数据与维护」——
    ZL2SettingsRow *dataExport =
        [ZL2SettingsRow rowWithTitle:@"数据导出"
                                icon:@"square.and.arrow.up"
                            fallback:nil
                             perform:^(ZL2SettingsViewController *page) {
        DataExportViewController *vc = [[DataExportViewController alloc] init];
        [page ame_pushChild:vc titled:@"数据导出"];
    }];
    ZL2SettingsRow *cleanup =
        [ZL2SettingsRow rowWithTitle:@"清理游戏文件"
                                icon:@"trash"
                            fallback:nil
                             perform:^(ZL2SettingsViewController *page) {
        CleanupViewController *vc = [[CleanupViewController alloc] init];
        // 扫描器注入（CleanupViewController.h 契约）：单一扫描口径 =
        // VersionManager 类方法（.h 公开声明），版本管理页/主页磁贴同源
        vc.ame255_versionScanner = ^NSArray<NSDictionary *> *(void) {
            return [VersionManagerViewController ame256_scanVersionsForCleanup];
        };
        [page ame_pushChild:vc titled:@"清理游戏文件"];
    }];
    ZL2SettingsRow *curseForgeKey =
        [ZL2SettingsRow rowWithTitle:@"CurseForge API Key"
                                icon:@"key"
                            fallback:@"key.fill"
                             perform:^(ZL2SettingsViewController *page) {
        CurseForgeAPIKeyViewController *vc = [[CurseForgeAPIKeyViewController alloc] init];
        [page ame_pushChild:vc titled:@"CurseForge API Key"];
    }];

    // —— 组「关于」——（检查更新行省略，理由见文件头）
    ZL2SettingsRow *about =
        [ZL2SettingsRow rowWithTitle:@"关于"
                                icon:@"info.circle"
                            fallback:nil
                             perform:^(ZL2SettingsViewController *page) {
        AboutViewController *vc = [[AboutViewController alloc] init];
        [page ame_pushChild:vc titled:@"关于"];
    }];

    return @[ @[fullSettings, background, wallpapers],
              @[controlCfg, touchPrefs, gameDir],
              @[javaManage, runJar],
              @[dataExport, cleanup, curseForgeKey],
              @[about] ];
}

#pragma mark - 行点击

- (void)ame_rowTapped:(UIControl *)sender {
    NSUInteger index = (NSUInteger)sender.tag;   // 下标载荷 → flatRows 查行
    if (index >= self.flatRows.count) return;
    ZL2SettingsRow *row = self.flatRows[index];
    if (row.perform) row.perform(self);
}

// push 统一入口：子页大多在自身 viewDidLoad 设 self.title（后于本赋值执行，
// 自动覆盖兜底值）；未设标题的子页（游戏目录/控制配置/Java 管理等）沿用行名，
// 避免导航栏空白
- (void)ame_pushChild:(UIViewController *)vc titled:(NSString *)fallbackTitle {
    if (!vc.title) vc.title = fallbackTitle;
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 执行 Jar 文件（特殊流：文档选择器 → 守卫链 → 全屏模态）

// JavaGUIViewController filepath 必填且页内 dismiss 走 presentingViewController
//（模态专用页），裸 push/无路径会崩或黑屏——本行交互与旧右面板 executeJar
//（设置入口 → 文档选择器 → enterModInstallerWithPath:）一致
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
    //（精简安全子集：JVM 二次崩溃守卫由 JavaGUI 页自兜底、JIT 引导链不复制，
    // 见文件头说明）
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

#pragma mark - Alerts

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
