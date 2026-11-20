//
// ZL2DownloadViewController.m — ZL2 下载页（7.0-UI-14 左轨真机对齐 + Task432 八轨收敛）
//
// 移植对象：ZalithLauncher2 DownloadScreen.kt TabMenu（GNU GPL 参考副本，只读；
//   真机截图 4-12 交叉验证）。
//
// 【7.0-UI-14 结构纠偏】旧"大标题 + 横向 chips + 内容容器"废弃——真机截图
//   实证 ZL2 下载页为「左竖轨 + 右内容区」双栏。
// 【Task432 八轨收敛】摘除 Task323 自造超集（第 8 期报告 §4.4），左轨回归
//   ZL2 DownloadScreen.kt TabMenu downloadsList 八轨原版（divider 位 1:1）：
//     0 游戏       gamecontroller
//     1 整合包     archivebox
//     ── 分隔线（onSurface 0.4 alpha，宽 40%）
//     2 模组       puzzlepiece
//     3 资源包     paintbrush
//     4 存档       globe
//     5 光影包     lightbulb
//     ── 分隔线
//     6 按ID搜索   number（ZL2 ic_card）
//     7 收藏       heart（ZL2 ic_favorite）
//   摘除去向注记（Task432）：
//     · 数据包（原 6 轨）→ 版本子页第九子页（SB 工位）
//     · 三仓库（原 9-11：控件/手柄/插件仓库）→ 设置·控制管理域（SD 工位；
//       ZL2SettingPages 控制管理/插件分区同源入口保留零回归）
//   仓库三件 VC 类本体不动（共享基础设施，SD 会另行接行）。
// 【★Task458 仓库三轨回归】用户指令「下载中心的插件和控件给我恢复」——SD
//   工位收敛与用户心智位相左，Task323 原版三件 1:1 复位（轨序紧跟收藏：
//     8 控件仓库   square.grid.2x2（nav 宿主；控件仓库 navigationItem 链）
//     9 手柄仓库   dial（nav 宿主；initialCategoryIndex=2 手柄分类直达）
//    10 插件仓库   shippingbox（nav 宿主；Task318 内置插件仓库）
//   ── 分隔线（三仓库组前置）
//   标题走 localize 复用既有键零新增；设置域仓库三行组入口保留 = 双面共存）。
//   轨项几何（M3 NavigationRailItem 语义 + 截图）：图标 22 + label 11 下方，
//   选中 = primaryContainer 圆角胶囊（radiusM）+ onPrimaryContainer；未选 =
//   透明底 + onSurfaceVariant。分隔线 = onSurface 40% alpha 水平线（宽 40%）。
//
// 内容区：懒建缓存 + addChild + 四边钉入 + 0.18s crossDissolve（7.0-UI-9
//   机制平移）。子页（Task432 八轨口径）：
//     0 ZL2GameDownloadViewController（7.0-UI-14 截图对齐重写）
//     1-5 ZL2AssetSearchViewController（五类远程搜索；存档轨 Task432 起
//         Modrinth+CurseForge 双源，实现形态同模组/整合包轨）
//     6 ZL2SearchIdViewController（项目 ID 直查）
//     7 ZL2AssetSearchViewController 收藏模式（收藏仓库直出）
//
// 任务胶囊：删除（壳顶栏已有同款 taskPill，页内重复）。
// 通知面：任务胶囊两通知监听随胶囊删除。
// 导航栏约定/红线遵守：同 7.0-UI-9 契约不变（颜色/字体/圆角一律 ZL2Theme、
//   iOS 14 API 上限、SF 符号 SF1.0 级、translates = NO、零 viewWithTag 存状态）。
//

#import "ZL2DownloadViewController.h"
#import "ZL2Theme.h"
#import "ZL2GameDownloadViewController.h"
#import "ZL2AssetSearchViewController.h"
#import "ZL2SearchIdViewController.h"
#import "ZL2ControlRepoViewController.h"   // ★Task458：仓库三轨回归（Task432 摘除后用户钦定恢复）
#import "ZL2PluginRepoViewController.h"    // ★Task458：同上（Task318 内置插件仓库）
#import "utils.h"                           // localize()（轨项标题）
// ★Task432 曾随仓库三轨摘除退役的两 import（★Task436 类名迁移后形态）随
// ★Task458 用户指令「下载中心的插件和控件给我恢复」同步复位；设置域入口
// （ZL2SettingPages 仓库三行组）保留不动 = 双面共存零回归。

// SF Symbols 取图兜底（符号名异常时降级旧名）
static UIImage *ZL2DownloadSystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    return image;
}

#pragma mark - 左轨项（M3 NavigationRailItem 语义）

@interface ZL2DownloadRailItem : UIControl
- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol;
@end

@implementation ZL2DownloadRailItem {
    UIImageView *_iconView;
    UILabel *_label;
}
- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = title;
        self.accessibilityTraits = UIAccessibilityTraitButton;

        UIImage *icon = ZL2DownloadSystemImage(symbol, [symbol stringByAppendingString:@".fill"]);
        _iconView = [[UIImageView alloc] initWithImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_iconView];

        _label = [[UILabel alloc] init];
        _label.text = title;
        _label.font = [ZL2Theme fontLabelMedium];
        _label.numberOfLines = 1;
        _label.textAlignment = NSTextAlignmentCenter;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_iconView.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [_iconView.widthAnchor constraintEqualToConstant:22],
            [_iconView.heightAnchor constraintEqualToConstant:22],

            [_label.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:3],
            [_label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_label.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:2],
            [_label.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-2],
            [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6],
        ]];
        [self ame_applySelected:NO];
    }
    return self;
}
- (void)ame_applySelected:(BOOL)selected {
    self.backgroundColor = selected ? [ZL2Theme primaryContainer] : [UIColor clearColor];
    self.layer.cornerRadius = [ZL2Theme radiusM];
    _iconView.tintColor = selected ? [ZL2Theme onPrimaryContainer] : [ZL2Theme onSurfaceVariant];
    _label.textColor = selected ? [ZL2Theme onPrimaryContainer] : [ZL2Theme onSurfaceVariant];
    self.accessibilityTraits = UIAccessibilityTraitButton |
                               (selected ? UIAccessibilityTraitSelected : 0);
}
@end

#pragma mark - 页面本体

@interface ZL2DownloadViewController ()
// 左轨
@property (nonatomic, strong) UIScrollView *railScroll;
@property (nonatomic, strong) UIStackView *railStack;
@property (nonatomic, strong) NSMutableArray<ZL2DownloadRailItem *> *railItems;
@property (nonatomic, strong) NSMutableArray<UIView *> *railDividers;

// 内容容器与子页
@property (nonatomic, strong) UIView *contentContainer;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIViewController *> *childCache;
// selectedIndex 已上移 .h 公开契约（Task324 管理器预选透传；-1 = 尚未选中，
// init 置 -1，viewDidLoad 以 >=0 ? 预选 : 0 首选）

@end

@implementation ZL2DownloadViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _railItems = [NSMutableArray array];
        _railDividers = [NSMutableArray array];
        _childCache = [NSMutableDictionary dictionary];
        _selectedIndex = -1;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];

    [self buildViews];
    // ★ Task324：管理器改道预选（selectedIndex 在 view 加载前置定 → 首选即用；
    //   未预选保持 0 游戏页；ame_showCategory 内部会重写 selectedIndex 并刷左轨选中态）
    [self ame_showCategory:(self.selectedIndex >= 0 ? self.selectedIndex : 0)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 根页隐藏系统栏：pop 回来自动隐藏（子页 push 出去时 viewWillDisappear
    // 已恢复系统栏，旧子页可见返回栏）
    // ★ Task324：管理器改道 push 场景（本页非 nav 根）保留系统栏——返回钮
    //   可回管理页（旧 DVC 同语义）；壳内 nav 根用法照旧隐藏（壳顶栏接管）
    BOOL ame324_isNavRoot =
        (self.navigationController.viewControllers.firstObject == self);
    [self.navigationController setNavigationBarHidden:ame324_isNavRoot animated:NO];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:NO];
}

#pragma mark - 布局（左轨 + 右内容）

- (void)buildViews {
    // ① 左轨滚动容器（纵向；Task432 八轨收敛 + ★Task458 仓库三轨回归 =
    //    11 项 + 3 分隔线，ZL2 原版八轨口径 + Prisma 仓库三件原版形态）
    _railScroll = [[UIScrollView alloc] init];
    _railScroll.showsVerticalScrollIndicator = NO;
    _railScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_railScroll];

    _railStack = [[UIStackView alloc] init];
    _railStack.axis = UILayoutConstraintAxisVertical;
    _railStack.alignment = UIStackViewAlignmentCenter;
    _railStack.spacing = 8;   // ZL2 items 间 Spacer(8.dp)
    _railStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_railScroll addSubview:_railStack];

    // ZL2 TabMenu downloadsList 顺序（divider 前置语义 = 项自带 division 标记）
    // ★ Task432 八轨收敛：摘「数据包」轨与末尾「控件/手柄/插件仓库」三轨，轨
    //   序与 divider 位 1:1 回归 ZL2 DownloadScreen.kt（模组/按ID搜索前分隔）。
    //   去向：数据包→版本子页第九子页（SB 工位）/ 三仓库→设置·控制管理域
    //   （SD 工位）；i18n 键主控管表保留不动。
    // ★ Task458 仓库三轨回归（用户指令「下载中心的插件和控件给我恢复」——
    //   Task432 SD 工位收敛判读与用户实际使用习惯相左：用户以「下载」为仓库
    //   的心智位）。恢复形态 = Task323 原版三件 1:1（轨序紧跟收藏 + divider
    //   前置 + nav 宿主嵌入 + 符号 square.grid.2x2/dial/shippingbox 同源），
    //   仅两处当代化：类名 ZL2 前缀（★Task436 迁移后形态）+ 标题走 localize
    //   复用既有键（ame369.common.control_repo / ame369.common.gamepad_repo /
    //   ame318.repo.title，54 表齐备零新增键 = task191/248/250 面不变）；设置
    //   域仓库三行组入口保留 = 双面共存。
    NSArray<NSString *> *titles = @[localize(@"ame369.dl.tab.games", @"游戏"), localize(@"ame369.dl.tab.modpacks", @"整合包"), localize(@"ame369.common.mods", @"模组"), localize(@"ame369.common.resource_packs", @"资源包"),
                                    localize(@"ame369.common.worlds", @"存档"), localize(@"ame369.common.shaders", @"光影包"),
                                    localize(@"ame369.dl.tab.search_by_id", @"按ID搜索"), localize(@"ame369.common.favorites", @"收藏"),
                                    localize(@"ame369.common.control_repo", @"控件仓库"), localize(@"ame369.common.gamepad_repo", @"手柄仓库"), localize(@"ame318.repo.title", @"插件仓库")];
    NSArray<NSString *> *symbols = @[@"gamecontroller", @"archivebox", @"puzzlepiece",
                                     @"paintbrush", @"globe", @"lightbulb",
                                     @"number", @"heart",
                                     @"square.grid.2x2", @"dial", @"shippingbox"];
    NSArray<NSNumber *> *dividerBefore = @[@NO, @NO, @YES, @NO, @NO, @NO,
                                           @YES, @NO,
                                           @YES, @NO, @NO];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger idx, BOOL *stop) {
        if (dividerBefore[idx].boolValue) {
            [_railStack addArrangedSubview:[self ame_dividerView]];
        }
        ZL2DownloadRailItem *item = [[ZL2DownloadRailItem alloc] initWithTitle:title
                                                                        symbol:symbols[idx]];
        item.tag = (NSInteger)idx;   // 仅作 ame_railTapped: 下标载荷（域内判例）
        [item addTarget:self
                 action:@selector(ame_railTapped:)
       forControlEvents:UIControlEventTouchUpInside];
        [_railStack addArrangedSubview:item];
        [item.widthAnchor constraintEqualToConstant:64].active = YES;
        [item.heightAnchor constraintEqualToConstant:52].active = YES;
        [_railItems addObject:item];
    }];

    // ② 内容容器
    _contentContainer = [[UIView alloc] init];
    _contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _contentContainer.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_contentContainer];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    UILayoutGuide *railLG = _railScroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_railScroll.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_railScroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_railScroll.widthAnchor constraintEqualToConstant:76],
        [_railScroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_railStack.topAnchor constraintEqualToAnchor:railLG.topAnchor constant:8],
        [_railStack.bottomAnchor constraintEqualToAnchor:railLG.bottomAnchor constant:16],
        [_railStack.leadingAnchor constraintEqualToAnchor:railLG.leadingAnchor],
        [_railStack.trailingAnchor constraintEqualToAnchor:railLG.trailingAnchor],
        [_railStack.widthAnchor constraintEqualToAnchor:_railScroll.widthAnchor],

        [_contentContainer.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [_contentContainer.leadingAnchor constraintEqualToAnchor:_railScroll.trailingAnchor],
        [_contentContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_contentContainer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

// 分隔线（ZL2 HorizontalDivider：宽 40%、onSurface 0.4 alpha、纵向 12 间距）
- (UIView *)ame_dividerView {
    UIView *line = [[UIView alloc] init];
    line.backgroundColor = [ZL2Theme onSurface];
    line.alpha = 0.4;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [line.heightAnchor constraintEqualToConstant:0.5].active = YES;
    [line.widthAnchor constraintEqualToConstant:26].active = YES;
    [_railDividers addObject:line];
    return line;
}

#pragma mark - 类别切换（懒建缓存 + 首显 attach + hidden 切换）

- (void)ame_railTapped:(UIControl *)sender {
    [self ame_showCategory:sender.tag];
}

- (void)ame_showCategory:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_railItems.count) return;
    UIViewController *next = [self ame_childForIndex:index];
    if (!next) return;

    // 重复点击当前类别：仅归位外观，不重播过渡
    if (index == self.selectedIndex && next.view.superview) {
        [self ame_applyRailAppearance];
        return;
    }

    UIViewController *prev = nil;
    if (self.selectedIndex >= 0) {
        prev = self.childCache[@(self.selectedIndex)];
    }

    [self ame_attachChildIfNeeded:next];

    void (^apply)(void) = ^{
        prev.view.hidden = YES;
        next.view.hidden = NO;
    };
    if (prev && prev.view.superview) {
        [UIView transitionWithView:self.contentContainer
                          duration:0.18
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:apply
                        completion:nil];
    } else {
        apply();
    }

    self.selectedIndex = index;
    [self ame_applyRailAppearance];
}

- (void)ame_applyRailAppearance {
    for (NSUInteger i = 0; i < self.railItems.count; i++) {
        [self.railItems[i] ame_applySelected:((NSInteger)i == self.selectedIndex)];
    }
}

- (UIViewController *)ame_childForIndex:(NSInteger)index {
    UIViewController *cached = self.childCache[@(index)];
    if (cached) return cached;

    UIViewController *vc = nil;
    switch (index) {
        case 0: {
            vc = [[ZL2GameDownloadViewController alloc] init];
            break;
        }
        case 1: {
            vc = [[ZL2AssetSearchViewController alloc] initWithType:ZL2AssetSearchTypeModpack
                                                              title:localize(@"ame369.dl.tab.modpacks", @"整合包")];
            break;
        }
        case 2: {
            vc = [[ZL2AssetSearchViewController alloc] initWithType:ZL2AssetSearchTypeMod
                                                              title:localize(@"ame369.common.mods", @"模组")];
            break;
        }
        case 3: {
            vc = [[ZL2AssetSearchViewController alloc] initWithType:ZL2AssetSearchTypeResourcePack
                                                              title:localize(@"ame369.common.resource_packs", @"资源包")];
            break;
        }
        case 4: {
            vc = [[ZL2AssetSearchViewController alloc] initWithType:ZL2AssetSearchTypeWorld
                                                              title:localize(@"ame369.common.worlds", @"存档")];
            break;
        }
        case 5: {
            vc = [[ZL2AssetSearchViewController alloc] initWithType:ZL2AssetSearchTypeShader
                                                              title:localize(@"ame369.common.shaders", @"光影包")];
            break;
        }
        // ★Task432 去向注记：原 case 6「数据包」轨摘除 → 版本子页第九子页
        //   （SB 工位接管）；ZL2AssetSearchTypeDataPack 枚举与 ZL2AssetSearch
        //   页内 DataPack 通路本体保留（共享基础设施，非本 TU 摘除面）。
        case 6: {
            vc = [[ZL2SearchIdViewController alloc] init];
            break;
        }
        case 7: {
            // 收藏模式：搜索页复用（安装/依赖解析全链零重复），数据源切收藏仓库
            vc = [[ZL2AssetSearchViewController alloc] initWithFavorites];
            break;
        }
        // ★Task458 仓库三轨回归（Task323 原版形态 1:1：nav 宿主嵌入，仓库页
        //   自用 navigationItem 按钮链/插件仓库 push 详情页均需 nav 宿主；
        //   ★Task432 去向注记原 case 9/10/11 摘除面在此复位为当代下标 8/9/10）
        case 8: {
            // 控件仓库（启动器特有仓库；设置页同源入口保留零回归）
            ZL2ControlRepoViewController *ame458_repo = [[ZL2ControlRepoViewController alloc] init];
            ame458_repo.title = localize(@"ame369.common.control_repo", @"控件仓库");
            UINavigationController *ame458_nav =
                [[UINavigationController alloc] initWithRootViewController:ame458_repo];
            ame458_nav.edgesForExtendedLayout = UIRectEdgeNone;
            vc = ame458_nav;
            break;
        }
        case 9: {
            // 手柄仓库（= 控件仓库手柄分类直达，设置页同口径 initialCategoryIndex=2）
            ZL2ControlRepoViewController *ame458_repo = [[ZL2ControlRepoViewController alloc] init];
            ame458_repo.initialCategoryIndex = 2;
            ame458_repo.title = localize(@"ame369.common.gamepad_repo", @"手柄仓库");
            UINavigationController *ame458_nav =
                [[UINavigationController alloc] initWithRootViewController:ame458_repo];
            ame458_nav.edgesForExtendedLayout = UIRectEdgeNone;
            vc = ame458_nav;
            break;
        }
        case 10: {
            // 插件仓库（Task318 内置插件仓库；push 插件详情页需 nav 宿主）
            ZL2PluginRepoViewController *ame458_repo = [[ZL2PluginRepoViewController alloc] init];
            ame458_repo.title = localize(@"ame318.repo.title", nil);
            UINavigationController *ame458_nav =
                [[UINavigationController alloc] initWithRootViewController:ame458_repo];
            ame458_nav.edgesForExtendedLayout = UIRectEdgeNone;
            vc = ame458_nav;
            break;
        }
        // ★Task432 去向注记：原 case 6「数据包」轨摘除 → 版本子页第九子页
        //   （SB 工位接管）；ZL2AssetSearchTypeDataPack 枚举与 ZL2AssetSearch
        //   页内 DataPack 通路本体保留（共享基础设施，非本 TU 摘除面）。
        //   ★Task458 注记：原 case 9/10/11「控件/手柄/插件仓库」三轨经用户钦定
        //   在上方 case 8/9/10 复位（设置域入口双面共存）；本 switch 其余摘除
        //   面维持 Task432 判例不变。
        default:
            return nil;
    }
    // ★ Task324：管理器改道透传——ZL2AssetSearch 子页（1-5/7）接收目标实例
    //   （viewDidLoad 快照优先取透传值，Task265 语义保留：下载写入随调用方
    //   绑定实例，非当前选中实例）
    if (self.targetProfileName.length > 0 && [vc isKindOfClass:[ZL2AssetSearchViewController class]]) {
        ((ZL2AssetSearchViewController *)vc).targetProfileName = self.targetProfileName;
    }
    self.childCache[@(index)] = vc;
    return vc;
}

- (void)ame_attachChildIfNeeded:(UIViewController *)child {
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

@end
