//
// ZL2DownloadViewController.m — ZL2 下载页（7.0-UI-14：左轨 8 项真机对齐版）
//
// 移植对象：ZalithLauncher2 DownloadScreen.kt TabMenu（GNU GPL 参考副本，只读；
//   真机截图 4-12 交叉验证）。
//
// 【7.0-UI-14 结构纠偏】旧"大标题 + 横向 chips + 内容容器"废弃——真机截图
//   实证 ZL2 下载页为「左竖轨 + 右内容区」双栏。左轨 8 项 2 分隔线
//   （ZL2 TabMenu downloadsList 顺序 1:1）：
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
//   轨项几何（M3 NavigationRailItem 语义 + 截图）：图标 22 + label 11 下方，
//   选中 = primaryContainer 圆角胶囊（radiusM）+ onPrimaryContainer；未选 =
//   透明底 + onSurfaceVariant。分隔线 = onSurface 40% alpha 水平线（宽 40%）。
//
// 内容区：懒建缓存 + addChild + 四边钉入 + 0.18s crossDissolve（7.0-UI-9
//   机制平移）。子页：
//     0 ZL2GameDownloadViewController（7.0-UI-14 截图对齐重写）
//     1-5 ZL2AssetSearchViewController（五类远程搜索）
//     6 ZL2SearchIdViewController（新：项目 ID 直查）
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
@property (nonatomic, assign) NSInteger selectedIndex;   // -1 = 尚未选中

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
    [self ame_showCategory:0];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 根页隐藏系统栏：pop 回来自动隐藏（子页 push 出去时 viewWillDisappear
    // 已恢复系统栏，旧子页可见返回栏）
    [self.navigationController setNavigationBarHidden:YES animated:NO];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:NO];
}

#pragma mark - 布局（左轨 + 右内容）

- (void)buildViews {
    // ① 左轨滚动容器（纵向；8 项 + 2 分隔线）
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
    NSArray<NSString *> *titles = @[@"游戏", @"整合包", @"模组", @"资源包",
                                    @"存档", @"光影包", @"按ID搜索", @"收藏"];
    NSArray<NSString *> *symbols = @[@"gamecontroller", @"archivebox", @"puzzlepiece",
                                     @"paintbrush", @"globe", @"lightbulb",
                                     @"number", @"heart"];
    NSArray<NSNumber *> *dividerBefore = @[@NO, @NO, @YES, @NO, @NO, @NO, @YES, @NO];
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
                                                              title:@"整合包"];
            break;
        }
        case 2: {
            vc = [[ZL2AssetSearchViewController alloc] initWithType:ZL2AssetSearchTypeMod
                                                              title:@"模组"];
            break;
        }
        case 3: {
            vc = [[ZL2AssetSearchViewController alloc] initWithType:ZL2AssetSearchTypeResourcePack
                                                              title:@"资源包"];
            break;
        }
        case 4: {
            vc = [[ZL2AssetSearchViewController alloc] initWithType:ZL2AssetSearchTypeWorld
                                                              title:@"存档"];
            break;
        }
        case 5: {
            vc = [[ZL2AssetSearchViewController alloc] initWithType:ZL2AssetSearchTypeShader
                                                              title:@"光影包"];
            break;
        }
        case 6: {
            vc = [[ZL2SearchIdViewController alloc] init];
            break;
        }
        case 7: {
            // 收藏模式：搜索页复用（安装/依赖解析全链零重复），数据源切收藏仓库
            vc = [[ZL2AssetSearchViewController alloc] initWithFavorites];
            break;
        }
        default:
            return nil;
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
