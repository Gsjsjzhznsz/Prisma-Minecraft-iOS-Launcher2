//
// ZL2VersionsViewController.m — ZL2 风格版本管理页实现（7.0-UI-9-b：
// 对标 ZalithLauncher 2 VersionsManageScreen / VersionItemLayout）
//
// 视觉对标（ZL2 ui/screens/content/elements/VersionsManageElements.kt）：
//   版本卡 = Surface(large 圆角) 横排 [RadioButton + 版本图标 34dp +
//   (版本名 labelLarge / 版本描述 labelMedium / 详情行 alpha 0.7) +
//   设置钮 + 更多菜单]；无效版本在详情行位置渲染 errorContainer 小标签
//   （ZL2 versions_manage_invalid 同语义）；顶部分类 chips（全部/原版/
//   可安装模组，带计数）。本页为静态 M3 移植：无滚吸浮层/玻璃/动效。
//
// 数据契约（全部取自旧 VersionManagerViewController.m 真实调用，无猜测字段）：
//   - 实例列表/排序：PLProfiles.current.profiles 键降序（loadProfiles 同款）
//   - 版本号：profile[@"lastVersionId"]（旧 VC L1518 同键）
//   - 描述行：profile[@"lastPlayed"] 经 formatLastPlayed 格式化
//     （i18n_str_1069「最后游玩：%@」，旧 VC L1550 同款实现）
//   - 加载器：不做元数据字段（注册表无 loader 键，旧 VC 已审计），从
//     lastVersionId 字符串识别——+[ModLoaderIconHelper detectLoaderFromVersionId:]
//     （旧 VC VMVersionCardCell L380 同款）与 +[ModpackExportService
//     parseVersionId:]（旧 VC isCurrentProfileModernVersion L1291 同款，
//     取 @"minecraft" 键）
//   - 无效版本：versions/<id>/<id>.json 不存在（路径口径 = 旧 VC
//     ame256_scanVersionsForCleanup L1996：POJAV_GAME_DIR 优先、
//     POJAV_HOME 兜底；本地 fileExists 实现以免链接整个旧 VC）
//
// 操作审计（「更多」菜单只移植旧 VC 真实存在的操作——ZL2 的
// 重命名/复制/导出/置顶在本仓旧 VC 中不存在，按铁律不移植、不虚构）：
//   - 选用   selectProfileNamed:（旧 VC L1884）：写 selectedProfileName +
//     save + post @"SelectedProfileChanged" + 重建（同名静默防抖）
//   - 编辑   editProfile:（旧 VC L1872）：push ProfileSettingsViewController
//     （[[alloc] init] + profileName 属性，1:1）
//   - 删除   deleteProfile:（旧 VC L1893）：至少保留一个实例守卫
//     （i18n_str_1092）→ 二次确认（i18n_str_457 / i18n_str_1093）→
//     删注册表条目 + 选中回退 firstObject + save + Task255 实体目录
//     连带删除（引用计数守卫，GAME_DIR/versions/<id> 优先、POJAV_HOME
//     兜底，失败 alert i18n_str_1088）→ 重建 + post @"ReloadProfileList"
//
// 通知面：监听 @"ReloadProfileList"（主页下载完成后 post，ZL2Home L671）
// 与 @"SelectedProfileChanged"（旧 VC viewDidLoad L860/865 双监听同款）；
// post @"SelectedProfileChanged" / @"ReloadProfileList" / @"ZL2ShellNavigate"
// （安装新游戏 → 壳 index=1 下载页，对标 ZL2 versions_manage_install_new）。
//
// 红线遵守：颜色/字体/圆角一律取 ZL2Theme 动态令牌（无 traitCollection
// 分支）；iOS 14.0+（无 configuration/UIMenu/iOS15+ API）；SF 符号全为
// SF1.0 级（gearshape 为 iOS14 起点，带旧名 fallback）；全部新建视图
// translatesAutoresizingMaskIntoConstraints = NO；视图身份直接属性
// 持有 + block 载荷（零 viewWithTag）；sender.tag 不使用。
// 文案口径：新页新增文案暂硬编码中文（7.0-UI-8 已立 i18n 入表待办，
// ZL2Home 同口径）；复用旧链既有键一律走 localize。
//

#import "ZL2VersionsViewController.h"
#import "ZL2Theme.h"
#import "PLProfiles.h"
#import "ModLoaderIconHelper.h"
#import "ModpackExportService.h"   // +parseVersionId:（lastVersionId 反解 MC 版本）
#import "ProfileSettingsViewController.h"
#import "ZL2VersionDetailViewController.h"   // 7.0-UI-13-V：设置钮新目标（ZL2 VersionSettings 容器）
#import "utils.h"   // localize()

// 内容列最大宽（与 ZL2HomeViewController 同款 999 等式宽度方案）
static const CGFloat ZL2VersionsContentMaxWidth = 520;

// 分类 chip 序号（载荷经 block 捕获，不经 tag）
static const NSInteger ZL2VersionsCategoryAll = 0;
static const NSInteger ZL2VersionsCategoryVanilla = 1;
static const NSInteger ZL2VersionsCategoryModloader = 2;

// SF Symbols 取图兜底（ZL2HomeViewController 同款判例：符号名异常时降级
// 旧名而不是空白；本页符号正常路径不会走 fallback）
static UIImage *ZL2VersionsSystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

#pragma mark - 私有点击控件（block 载荷，替代 tag/字典身份查找）

// 通用可点容器：页头图标钮 / 分类 chip / 版本卡整卡共用。
// init 时挂好 touchUpInside → ame_action block（实例自身为 target，
// 零 viewWithTag、零 delegate 数组）。
@interface ZL2VersionsTapControl : UIControl
@property (nonatomic, copy, nullable) void (^ame_action)(void);
@end

@implementation ZL2VersionsTapControl

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

#pragma mark - 私有扩展

@interface ZL2VersionsViewController ()

// 布局
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIStackView *headerRow;
@property (nonatomic, strong) UILabel *titleLabel;

// 分类 chips（构建一次，刷新只改计数文案与选中态）
@property (nonatomic, strong) UIStackView *chipsRow;
@property (nonatomic, strong) NSMutableArray<ZL2VersionsTapControl *> *categoryChips;
@property (nonatomic, strong) NSMutableArray<UILabel *> *categoryChipLabels;

// 卡片列表 / 空态
@property (nonatomic, strong) UIStackView *cardsStack;
@property (nonatomic, strong) UIView *emptyStateView;

// 数据
// 行模型字典：name / versionId / loader / mcVersion / summary / valid / isSelected
@property (nonatomic, copy) NSArray<NSDictionary *> *ame_allRows;
@property (nonatomic, assign) NSInteger ame_selectedCategory;

@end

@implementation ZL2VersionsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [ZL2Theme surface];
    [self buildViews];

    // 通知监听（旧 VC viewDidLoad 双监听同款）：列表重载 / 选中变化 → 全量重建
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileListDidChange)
                                                 name:@"ReloadProfileList"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileListDidChange)
                                                 name:@"SelectedProfileChanged"
                                               object:nil];

    [self reloadVersions];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 导航栏约定：根页隐藏系统栏（push 出去的 ProfileSettings 页自带返回栏）
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self reloadVersions];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // push 子页面（版本设置）时恢复导航栏，子页有返回按钮
    [self.navigationController setNavigationBarHidden:NO animated:NO];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)profileListDidChange {
    [self reloadVersions];
}

#pragma mark - State Refresh (public)

- (void)reloadVersions {
    // 旧 VC viewWillAppear 同款：先 updateCurrent 重拉注册表再重建
    [PLProfiles updateCurrent];
    [self ame_rebuildData];
    [self ame_rebuildList];
}

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
    _contentStack.spacing = 12;
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:_contentStack];

    [self buildHeaderRow];
    [self buildChipsRow];
    [self buildCardsStack];
    [self buildEmptyState];

    UILayoutGuide *contentLG = _scrollView.contentLayoutGuide;
    UILayoutGuide *frameLG = _scrollView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_contentStack.topAnchor constraintEqualToAnchor:contentLG.topAnchor constant:20],
        [contentLG.bottomAnchor constraintGreaterThanOrEqualToAnchor:_contentStack.bottomAnchor constant:24],
        // 两侧 inequality 边距 + centerX + <=520 上限 + 999 宽度等式
        //（ZL2Home 同款：窄屏占满 frame-40，iPad 横屏收敛到 520 居中）
        [_contentStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:contentLG.leadingAnchor constant:20],
        [contentLG.trailingAnchor constraintGreaterThanOrEqualToAnchor:_contentStack.trailingAnchor constant:20],
        [_contentStack.centerXAnchor constraintEqualToAnchor:frameLG.centerXAnchor],
        [_contentStack.widthAnchor constraintLessThanOrEqualToConstant:ZL2VersionsContentMaxWidth],
    ]];
    NSLayoutConstraint *fillWidth = [_contentStack.widthAnchor constraintEqualToAnchor:frameLG.widthAnchor
                                                                              constant:-40];
    fillWidth.priority = 999;
    fillWidth.active = YES;
}

/// ①页头行：大标题「版本」+ 右侧刷新 / 安装新游戏两枚 40×40 图标钮
- (void)buildHeaderRow {
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"版本";
    _titleLabel.font = [ZL2Theme fontTitleLarge];
    _titleLabel.textColor = [ZL2Theme onSurface];
    _titleLabel.numberOfLines = 1;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.isAccessibilityElement = YES;
    _titleLabel.accessibilityLabel = @"版本";

    // 弹性占位：把右侧两枚按钮推到行尾（hugging 显式低于标题，布局确定无歧义）
    UIView *spacer = [[UIView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:249 forAxis:UILayoutConstraintAxisHorizontal];
    [spacer setContentCompressionResistancePriority:249 forAxis:UILayoutConstraintAxisHorizontal];

    // 长生命周期按钮（self → headerRow → 按钮 → block）：block 统一 weak self
    // 防持有环（chips/卡片 block 同口径）
    __weak ZL2VersionsViewController *weakSelf = self;

    // 刷新（arrow.clockwise，SF1.0）：重拉 PLProfiles 并重建列表；
    // 页头钮规格 = 40×40 surfaceContainer 底 radiusS（spec ①）
    ZL2VersionsTapControl *refreshButton = [self iconButtonWithImageName:@"arrow.clockwise"
                                                                fallback:@"sync"
                                                                    size:40
                                                              accessibility:@"刷新"];
    refreshButton.backgroundColor = [ZL2Theme surfaceContainer];
    refreshButton.ame_action = ^{
        [weakSelf reloadVersions];
    };

    // 安装新游戏（arrow.down.circle.fill，SF1.0）：壳契约切下载页
    //（对标 ZL2 versions_manage_install_new）
    ZL2VersionsTapControl *installButton = [self iconButtonWithImageName:@"arrow.down.circle.fill"
                                                                fallback:@"arrow.down.circle"
                                                                    size:40
                                                              accessibility:@"安装新游戏"];
    installButton.backgroundColor = [ZL2Theme surfaceContainer];
    installButton.ame_action = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2ShellNavigate"
                                                            object:nil
                                                          userInfo:@{@"index": @(1)}];
    };

    _headerRow = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, spacer, refreshButton, installButton]];
    _headerRow.axis = UILayoutConstraintAxisHorizontal;
    _headerRow.alignment = UIStackViewAlignmentCenter;
    _headerRow.spacing = 12;
    _headerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentStack addArrangedSubview:_headerRow];
}

/// ②分类 chips 行：全部 / 原版 (n) / 可安装模组 (n)
/// 计数来源：旧 VC 同款加载器识别契约（detectLoaderFromVersionId）——
/// 注册表元数据无 loader 字段，从 lastVersionId 推导（非猜测字段）。
- (void)buildChipsRow {
    _categoryChips = [NSMutableArray array];
    _categoryChipLabels = [NSMutableArray array];

    _chipsRow = [[UIStackView alloc] init];
    _chipsRow.axis = UILayoutConstraintAxisHorizontal;
    _chipsRow.alignment = UIStackViewAlignmentCenter;
    _chipsRow.spacing = 10;
    _chipsRow.translatesAutoresizingMaskIntoConstraints = NO;

    [self addChipWithTitle:@"全部"];
    [self addChipWithTitle:@"原版"];
    [self addChipWithTitle:@"可安装模组"];

    [_contentStack addArrangedSubview:_chipsRow];
}

- (void)addChipWithTitle:(NSString *)title {
    ZL2VersionsTapControl *chip = [[ZL2VersionsTapControl alloc] init];
    chip.layer.cornerRadius = [ZL2Theme radiusS];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    chip.isAccessibilityElement = YES;
    chip.accessibilityTraits = UIAccessibilityTraitButton;
    chip.accessibilityLabel = title;

    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [ZL2Theme fontLabelMedium];
    label.textColor = [ZL2Theme onSurface];
    label.numberOfLines = 1;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [chip addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:16],
        [label.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-16],
        [label.topAnchor constraintEqualToAnchor:chip.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:chip.bottomAnchor constant:-8],
    ]];

    // block 载荷捕获分类序号（数组序 = 分类序）
    NSInteger category = (NSInteger)_categoryChips.count;
    __weak ZL2VersionsViewController *weakSelf = self;
    chip.ame_action = ^{
        [weakSelf ame_setCategory:category];
    };

    [_categoryChips addObject:chip];
    [_categoryChipLabels addObject:label];
    [_chipsRow addArrangedSubview:chip];
}

/// ③版本卡列表容器（spacing 12 对标 ZL2 LazyColumn verticalArrangement）
- (void)buildCardsStack {
    _cardsStack = [[UIStackView alloc] init];
    _cardsStack.axis = UILayoutConstraintAxisVertical;
    _cardsStack.alignment = UIStackViewAlignmentFill;
    _cardsStack.spacing = 12;
    _cardsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentStack addArrangedSubview:_cardsStack];
}

/// 空态：archivebox 68pt + 「没有安装版本」（ZL2 versions_manage_no_versions
/// 同语义；占位于 cardsStack，按数据有无挂载/摘除）
- (void)buildEmptyState {
    _emptyStateView = [[UIView alloc] init];
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;

    UIImage *archiveImage = ZL2VersionsSystemImage(@"archivebox", nil);
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[archiveImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    iconView.tintColor = [ZL2Theme onSurfaceVariant];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *label = [[UILabel alloc] init];
    label.text = @"没有安装版本";
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
    [_emptyStateView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateView.heightAnchor constraintGreaterThanOrEqualToConstant:240],
        [stack.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:_emptyStateView.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:_emptyStateView.leadingAnchor constant:20],
        [_emptyStateView.trailingAnchor constraintGreaterThanOrEqualToAnchor:stack.trailingAnchor constant:20],
        [iconView.widthAnchor constraintEqualToConstant:68],
        [iconView.heightAnchor constraintEqualToConstant:68],
    ]];
}

#pragma mark - 通用构件

/// 图标钮工厂：40×40（页头）/ 32×32（卡内），底色由调用方按档位指定
/// （页头 surfaceContainer / 卡内透明），圆角统一 radiusS
- (ZL2VersionsTapControl *)iconButtonWithImageName:(NSString *)name
                                          fallback:(NSString *)fallback
                                              size:(CGFloat)size
                                     accessibility:(NSString *)a11y {
    ZL2VersionsTapControl *button = [[ZL2VersionsTapControl alloc] init];
    button.backgroundColor = [UIColor clearColor];
    button.layer.cornerRadius = [ZL2Theme radiusS];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.isAccessibilityElement = YES;
    button.accessibilityTraits = UIAccessibilityTraitButton;
    button.accessibilityLabel = a11y;

    UIImage *image = ZL2VersionsSystemImage(name, fallback);
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    iconView.tintColor = [ZL2Theme onSurfaceVariant];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [button addSubview:iconView];

    // 页头 40×40 配 20pt 图标，卡内 32×32 配 18pt 图标
    CGFloat iconSize = (size >= 40) ? 20 : 18;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:size],
        [button.heightAnchor constraintEqualToConstant:size],
        [iconView.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:iconSize],
        [iconView.heightAnchor constraintEqualToConstant:iconSize],
    ]];
    return button;
}

#pragma mark - Data Build

/// 全量重建行模型（loadProfiles 排序同款：键降序）
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

        // 加载器 / MC 版本：旧 VC 同款双契约（字符串识别 + parseVersionId 反解）
        NSString *loader = versionId ? [ModLoaderIconHelper detectLoaderFromVersionId:versionId] : nil;
        NSDictionary *parsed = versionId ? [ModpackExportService parseVersionId:versionId] : @{};
        NSString *mcVersion = parsed[@"minecraft"] ?: versionId;

        // 无效版本：versions/<id>/<id>.json 不存在（路径口径 = 旧 VC
        // ame256_scanVersionsForCleanup：GAME_DIR 优先、POJAV_HOME 兜底）
        BOOL valid = [self ame_isVersionIdValid:versionId];

        [rows addObject:@{
            @"name": name,
            @"versionId": versionId ?: @"",
            @"loader": loader ?: @"",
            @"mcVersion": mcVersion ?: @"",
            @"summary": [self ame_formatLastPlayed:profile[@"lastPlayed"]],
            @"valid": @(valid),
            @"isSelected": @([name isEqualToString:selected]),
        }];
    }
    self.ame_allRows = rows;
}

- (BOOL)ame_isVersionIdValid:(NSString *)versionId {
    if (versionId.length == 0) return NO;
    // 与旧 VC Task255/Task256 路径口径逐项一致：真机实体在
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

/// lastPlayed 时间戳 → 「最后游玩：xxx」（旧 VC formatLastPlayed 1:1）
- (NSString *)ame_formatLastPlayed:(id)lastPlayedRaw {
    if (!lastPlayedRaw) return @"";
    NSTimeInterval ts;
    if ([lastPlayedRaw isKindOfClass:[NSNumber class]]) {
        ts = [lastPlayedRaw doubleValue];
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

/// 按分类过滤并重建卡片列表 + chips 计数/选中态 + 空态挂载
- (void)ame_rebuildList {
    // —— 分类计数（加载器识别推导）——
    NSInteger vanillaCount = 0;
    NSInteger modloaderCount = 0;
    for (NSDictionary *row in self.ame_allRows) {
        if ([row[@"loader"] length] > 0) {
            modloaderCount++;
        } else {
            vanillaCount++;
        }
    }
    UILabel *vanillaLabel = self.categoryChipLabels.count > (NSUInteger)ZL2VersionsCategoryVanilla
        ? self.categoryChipLabels[ZL2VersionsCategoryVanilla] : nil;
    UILabel *modloaderLabel = self.categoryChipLabels.count > (NSUInteger)ZL2VersionsCategoryModloader
        ? self.categoryChipLabels[ZL2VersionsCategoryModloader] : nil;
    vanillaLabel.text = [NSString stringWithFormat:@"原版 (%ld)", (long)vanillaCount];
    modloaderLabel.text = [NSString stringWithFormat:@"可安装模组 (%ld)", (long)modloaderCount];
    [self ame_applyChipStyles];

    // —— 分类过滤（switch 全枚举：全部 / 原版 / 可安装模组）——
    NSArray<NSDictionary *> *visibleRows = self.ame_allRows;
    switch (self.ame_selectedCategory) {
        case ZL2VersionsCategoryVanilla:
        case ZL2VersionsCategoryModloader: {
            BOOL wantLoader = (self.ame_selectedCategory == ZL2VersionsCategoryModloader);
            NSMutableArray *filtered = [NSMutableArray array];
            for (NSDictionary *row in visibleRows) {
                BOOL hasLoader = ([row[@"loader"] length] > 0);
                if (hasLoader == wantLoader) [filtered addObject:row];
            }
            visibleRows = filtered;
            break;
        }
        case ZL2VersionsCategoryAll:
        default:
            break;
    }

    // —— 重建卡片列表 ——
    for (UIView *subview in [self.cardsStack.arrangedSubviews copy]) {
        [self.cardsStack removeArrangedSubview:subview];
        [subview removeFromSuperview];
    }

    if (visibleRows.count == 0) {
        [self.cardsStack addArrangedSubview:self.emptyStateView];
        return;
    }
    for (NSDictionary *row in visibleRows) {
        [self.cardsStack addArrangedSubview:[self ame_cardForRow:row]];
    }
}

- (void)ame_applyChipStyles {
    // M3 filter chip 语义：选中 primaryContainer 底 + onPrimaryContainer 字，
    // 未选 surfaceVariant 底 + onSurface 字（令牌全取 ZL2Theme）
    [self.categoryChips enumerateObjectsUsingBlock:^(ZL2VersionsTapControl *chip, NSUInteger idx, BOOL *stop) {
        UILabel *label = self.categoryChipLabels[idx];
        BOOL selected = ((NSInteger)idx == self.ame_selectedCategory);
        chip.backgroundColor = selected ? [ZL2Theme primaryContainer] : [ZL2Theme surfaceVariant];
        label.textColor = selected ? [ZL2Theme onPrimaryContainer] : [ZL2Theme onSurface];
        chip.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitSelected;
    }];
}

- (void)ame_setCategory:(NSInteger)category {
    if (self.ame_selectedCategory == category) return;
    self.ame_selectedCategory = category;
    [self ame_rebuildList];
}

#pragma mark - Version Card（对标 ZL2 VersionItemLayout）

/// 版本卡：UIControl（surfaceContainer 底 radiusL，内边距 14）横排
/// [单选圈 20 | 加载器图标 34 | 名称/描述/标签列 | 设置钮 / 更多钮 32×32]
- (UIControl *)ame_cardForRow:(NSDictionary *)row {
    NSString *profileName = row[@"name"];
    NSString *loader = row[@"loader"];
    NSString *mcVersion = row[@"mcVersion"];
    NSString *summary = row[@"summary"];
    BOOL valid = [row[@"valid"] boolValue];
    BOOL isSelected = [row[@"isSelected"] boolValue];

    ZL2VersionsTapControl *card = [[ZL2VersionsTapControl alloc] init];
    card.backgroundColor = [ZL2Theme surfaceContainer];
    card.layer.cornerRadius = [ZL2Theme radiusL];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.isAccessibilityElement = YES;
    card.accessibilityTraits = UIAccessibilityTraitButton;
    card.accessibilityLabel = [NSString stringWithFormat:@"实例 %@，%@", profileName,
                               valid ? @"有效" : @"该版本无效"];

    // —— 整卡点击 = 选用（ZL2 Surface onClick 同语义；无效版本沿用旧 VC
    //    口径不拦截——旧 selectProfileNamed 无有效性守卫）——
    __weak ZL2VersionsViewController *weakSelf = self;
    card.ame_action = ^{
        [weakSelf ame_selectProfileNamed:profileName];
    };

    UIStackView *innerRow = [[UIStackView alloc] init];
    innerRow.axis = UILayoutConstraintAxisHorizontal;
    innerRow.alignment = UIStackViewAlignmentCenter;
    innerRow.spacing = 12;
    innerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:innerRow];

    // —— 单选圈：SF1.0 circle / circle.fill，20pt，选中 primary 未选 outline。
    //    纯指示器（userInteractionEnabled=NO，命中整体落在整卡 UIControl）——
    UIButton *radioButton = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *radioImage = [ZL2VersionsSystemImage(isSelected ? @"circle.fill" : @"circle", nil)
                           imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [radioButton setImage:radioImage forState:UIControlStateNormal];
    radioButton.tintColor = isSelected ? [ZL2Theme primary] : [ZL2Theme outline];
    radioButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    radioButton.userInteractionEnabled = NO;
    radioButton.translatesAutoresizingMaskIntoConstraints = NO;
    radioButton.isAccessibilityElement = NO;

    // —— 加载器图标 34pt：ModLoaderIconHelper 检出（PNG 保持原色 / SF 品牌
    //    色，旧 VC configureImageView 同款）；取不到 → gamecontroller 兜底装进
    //    surfaceVariant radiusS 容器（spec 定稿）——
    UIView *iconBg = [[UIView alloc] init];
    iconBg.layer.cornerRadius = [ZL2Theme radiusS];
    iconBg.layer.masksToBounds = YES;
    iconBg.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [iconBg addSubview:iconView];

    if (loader.length > 0) {
        [ModLoaderIconHelper configureImageView:iconView
                                      forLoader:loader
                                 traitCollection:self.traitCollection];
        iconBg.backgroundColor = [UIColor clearColor];
    } else {
        UIImage *fallbackIcon = ZL2VersionsSystemImage(@"gamecontroller", @"cube.box.fill");
        iconView.image = [fallbackIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        iconView.tintColor = [ZL2Theme onSurfaceVariant];
        iconBg.backgroundColor = [ZL2Theme surfaceVariant];
    }

    // —— 中列：版本名 / 描述 / 标签行 ——
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = profileName;
    nameLabel.font = [ZL2Theme fontLabelLarge];
    nameLabel.textColor = [ZL2Theme onSurface];
    nameLabel.numberOfLines = 1;
    nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.text = summary;
    descLabel.font = [ZL2Theme fontBodyMedium];
    descLabel.textColor = [ZL2Theme onSurfaceVariant];
    descLabel.numberOfLines = 1;
    descLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    descLabel.hidden = (summary.length == 0);
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;

    // 标签行：有效 = 「MC <mcVersion> · <加载器名>」（alpha 0.7 对标 ZL2
    // FlowRow alpha）；无效 = errorContainer/error/radiusXS 小标签
    //「该版本无效」（ZL2 versions_manage_invalid 同语义）
    UIStackView *tagStack = [[UIStackView alloc] init];
    tagStack.axis = UILayoutConstraintAxisHorizontal;
    tagStack.alignment = UIStackViewAlignmentLeading;
    tagStack.spacing = 6;
    tagStack.translatesAutoresizingMaskIntoConstraints = NO;

    if (!valid) {
        UIView *badgeContainer = [[UIView alloc] init];
        badgeContainer.backgroundColor = [ZL2Theme errorContainer];
        badgeContainer.layer.cornerRadius = [ZL2Theme radiusXS];
        badgeContainer.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *badgeLabel = [[UILabel alloc] init];
        badgeLabel.text = @"该版本无效";
        badgeLabel.font = [ZL2Theme fontLabelMedium];
        badgeLabel.textColor = [ZL2Theme error];
        badgeLabel.numberOfLines = 1;
        badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [badgeContainer addSubview:badgeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [badgeLabel.leadingAnchor constraintEqualToAnchor:badgeContainer.leadingAnchor constant:6],
            [badgeLabel.trailingAnchor constraintEqualToAnchor:badgeContainer.trailingAnchor constant:-6],
            [badgeLabel.topAnchor constraintEqualToAnchor:badgeContainer.topAnchor constant:2],
            [badgeLabel.bottomAnchor constraintEqualToAnchor:badgeContainer.bottomAnchor constant:-2],
        ]];
        [tagStack addArrangedSubview:badgeContainer];
    } else {
        UILabel *tagLabel = [[UILabel alloc] init];
        tagLabel.font = [ZL2Theme fontLabelMedium];
        tagLabel.textColor = [ZL2Theme onSurfaceVariant];
        tagLabel.alpha = 0.7;
        tagLabel.numberOfLines = 1;
        tagLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        tagLabel.translatesAutoresizingMaskIntoConstraints = NO;
        if (mcVersion.length > 0 && loader.length > 0) {
            tagLabel.text = [NSString stringWithFormat:@"MC %@ · %@", mcVersion, [ModLoaderIconHelper displayNameForLoader:loader]];
        } else if (mcVersion.length > 0) {
            tagLabel.text = [NSString stringWithFormat:@"MC %@", mcVersion];
        } else if (loader.length > 0) {
            tagLabel.text = [ModLoaderIconHelper displayNameForLoader:loader];
        }
        tagLabel.hidden = (tagLabel.text.length == 0);
        [tagStack addArrangedSubview:tagLabel];
    }

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[nameLabel, descLabel, tagStack]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.alignment = UIStackViewAlignmentLeading;
    textStack.spacing = 2;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;

    // —— 右列：竖排两枚 32×32 图标钮 ——
    // 设置（gearshape，iOS14 符号带旧名 fallback）→ push 版本设置页
    //（旧 VC editProfile: 同款目标与 init）
    ZL2VersionsTapControl *settingsButton = [self iconButtonWithImageName:@"gearshape"
                                                                 fallback:@"gear"
                                                                     size:32
                                                           accessibility:@"版本设置"];
    settingsButton.ame_action = ^{
        [weakSelf ame_openSettingsForProfile:profileName];
    };

    // 更多（ellipsis）→ actionSheet：删除（旧 VC deleteProfile: 全链 1:1；
    // 重命名/复制/导出/置顶旧 VC 不存在，铁律不移植）
    ZL2VersionsTapControl *moreButton = [self iconButtonWithImageName:@"ellipsis"
                                                             fallback:nil
                                                                 size:32
                                                       accessibility:@"更多操作"];
    // 按钮自身被 block 捕获（作 iPad popover 锚点）→ weak 防自持环；
    // actionSheet 同步弹出窗口期内按钮必然存活
    __weak ZL2VersionsTapControl *weakMoreButton = moreButton;
    moreButton.ame_action = ^{
        [weakSelf ame_showMoreSheetForProfile:profileName fromView:weakMoreButton];
    };

    UIStackView *rightStack = [[UIStackView alloc] initWithArrangedSubviews:@[settingsButton, moreButton]];
    rightStack.axis = UILayoutConstraintAxisVertical;
    rightStack.alignment = UIStackViewAlignmentCenter;
    rightStack.spacing = 8;
    rightStack.translatesAutoresizingMaskIntoConstraints = NO;

    [innerRow addArrangedSubview:radioButton];
    [innerRow addArrangedSubview:iconBg];
    [innerRow addArrangedSubview:textStack];
    [innerRow addArrangedSubview:rightStack];

    // 中列吃满剩余宽度（其余列均有显式尺寸约束，Fill 分布下中列为弹性项）
    [textStack setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    [NSLayoutConstraint activateConstraints:@[
        [innerRow.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [innerRow.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [innerRow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [innerRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],

        [radioButton.widthAnchor constraintEqualToConstant:20],
        [radioButton.heightAnchor constraintEqualToConstant:20],

        [iconBg.widthAnchor constraintEqualToConstant:34],
        [iconBg.heightAnchor constraintEqualToConstant:34],
        [iconView.topAnchor constraintEqualToAnchor:iconBg.topAnchor],
        [iconView.bottomAnchor constraintEqualToAnchor:iconBg.bottomAnchor],
        [iconView.leadingAnchor constraintEqualToAnchor:iconBg.leadingAnchor],
        [iconView.trailingAnchor constraintEqualToAnchor:iconBg.trailingAnchor],
    ]];
    return card;
}

#pragma mark - Profile Actions（1:1 旧 VC）

/// 选用实例：旧 VC selectProfileNamed: 同款——同名静默防抖，写 selected
/// + save + post @"SelectedProfileChanged" + 重建
- (void)ame_selectProfileNamed:(NSString *)profileName {
    NSString *selected = PLProfiles.current.selectedProfileName;
    if ([profileName isEqualToString:selected]) return;
    PLProfiles.current.selectedProfileName = profileName;
    [PLProfiles.current save];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectedProfileChanged" object:nil];
    [self ame_rebuildData];
    [self ame_rebuildList];
}

/// 版本设置：7.0-UI-13-V 起进 ZL2 版本详情容器（NestedNavKey.VersionSettings
/// 对标：概览/模组/存档/资源包/光影/截图/服务器/配置 八子页；实例级长尾
/// 设置由容器配置页「完整实例设置」兜底 push ProfileSettingsViewController）。
/// push 后由本页 viewWillDisappear 恢复导航栏。
- (void)ame_openSettingsForProfile:(NSString *)profileName {
    ZL2VersionDetailViewController *vc =
        [[ZL2VersionDetailViewController alloc] initWithProfileName:profileName];
    // 旧 VC 同款：依赖宿主 UINavigationController（壳 index=2 包 nav）
    [self.navigationController pushViewController:vc animated:YES];
}

/// 更多菜单（actionSheet）：删除 1:1 旧 VC deleteProfile:。重命名 / 复制 /
/// 导出整合包 / 置顶在本仓旧 VC 中不存在（ZL2 安卓端特性），按铁律不移植。
- (void)ame_showMoreSheetForProfile:(NSString *)profileName fromView:(UIView *)sourceView {
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:profileName
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_306", nil)
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *a) {
        [self ame_deleteProfile:profileName];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel handler:nil]];
    // iPad 锚点（iPhone 上 popoverPresentationController 为 nil，同旧 VC 口径）
    sheet.popoverPresentationController.sourceView = sourceView;
    sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

/// 删除实例：旧 VC deleteProfile:（L1893-1971）1:1 移植——至少保留一个
/// 实例守卫 + 二次确认 + 注册表删除 + 选中回退 + Task255 实体目录连带删除
/// （引用计数守卫）+ 重建 + ReloadProfileList。
- (void)ame_deleteProfile:(NSString *)profileName {
    if (self.ame_allRows.count <= 1) {
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
                        NSLog(@"[ZL2Versions] Task255: removed version folder for deleted profile '%@' -> %@", profileName, vdir);
                    } else {
                        NSLog(@"[ZL2Versions] Task255: failed to remove version folder %@: %@", vdir, err.localizedDescription);
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self showAlert:[NSString stringWithFormat:localize(@"i18n_str_1088", nil), err.localizedDescription]];
                        });
                    }
                }
            } else {
                NSLog(@"[ZL2Versions] Task255: version %@ still referenced by other profile(s), folder kept", versionId);
            }
        }

        [self ame_rebuildData];
        [self ame_rebuildList];
        // 旧 VC 同款：通知全局快照刷新（主页/下载页不再残留已删版本）
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - Alerts

- (void)showAlert:(NSString *)message {
    // 旧 VC showAlert 同款：i18n_str_388 标题 + i18n_str_44 确定钮
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_388", nil)
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
