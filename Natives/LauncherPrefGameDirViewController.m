#import "LauncherPreferences.h"
#import "LauncherPrefGameDirViewController.h"
#import "BackgroundManager.h"
#import "NSFileManager+NRFileManager.h"
#import "PLProfiles.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "AmeNativeMenu.h"       // Task247（T9）：伪玻璃档长按菜单 ame240 路由
#import "LiquidGlassCompat.h"   // Task247（T9）：伪玻璃档分档判定

// ★ Task483（单根终局）：instances 多实例管理页整体退役重写——单一真实数据根
//   = lasm（Library/Application Support/minecraft），本页降级为「游戏目录」
//   只读信息页：单条目展示真实根（体量统计 + 外部打开），不再列出/新建/改名/
//   删除/切换 instances 目录（旧实现的 removeItemAtPath + 重建符号链接 =
//   「删 instances 丢数据」直接病灶面，随 instances 布局一并退役）。

@interface LauncherPrefGameDirViewController ()<UITextFieldDelegate>
@property(nonatomic) NSMutableArray *array;
@end

@implementation LauncherPrefGameDirViewController

// 单一真实数据根（与 main.m init_setupMultiDir 同源：POJAV_GAME_DIR 已由
// pre-init 指向 lasm 真实目录；env 缺席时按 lasm 字面量兜底）。
+ (NSString *)ame483_singleRoot {
    const char *gd = getenv("POJAV_GAME_DIR");
    if (gd && strlen(gd) > 0) return [NSString stringWithUTF8String:gd];
    const char *home = getenv("POJAV_HOME");
    if (home && strlen(home) > 0) {
        return [NSString stringWithFormat:@"%s/Library/Application Support/minecraft", home];
    }
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // ★ Task247（T9）：伪玻璃档——系统 UIContextMenu 长按菜单改由长按手势
    //   + ame240 统一路由（磨砂面板）；真液态玻璃/原生档保留系统菜单。
    if (LGCIsPseudoGlassStyleActive()) {
        UILongPressGestureRecognizer *ame247_lp =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(ame247_longPressDirMenu:)];
        ame247_lp.minimumPressDuration = 0.45;
        [self.tableView addGestureRecognizer:ame247_lp];
    }
    [self setTitle:localize(@"preference.title.game_directory", nil)];

    self.array = [[NSMutableArray alloc] init];
    // ★ Task483：仅单一真实根一个条目（instances/<name> 列表扫描退役）
    [self.array addObject:[[self class] ame483_singleRoot].lastPathComponent ?: @"minecraft"];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.sectionFooterHeight = 50;

    // 适配自定义启动器背景：将当前视图控制器透明化，让全局背景（图片/视频）能够透出显示。
    // 放在 tableView 重新创建之后调用，确保 makeViewControllerTransparent 处理的是最终的 tableView。
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // 监听背景 UI 效果变化通知：当用户在背景设置中切换毛玻璃/半透明或调整透明度时，
    // 重新调用 makeViewControllerTransparent 以应用最终的视觉效果，保证背景始终正确透出。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

// ★ Task483：instances 切换（remove + 重建符号链接）整段退役。单根下唯一
//   合法目标 = 真实根自身：仅刷新 profile 缓存与列表通知（保持调用方兼容），
//   不做任何文件系统手术、绝不触碰 lasm。
- (void)changeSelectionTo:(NSString *)name {
    if (getenv("DEMO_LOCK")) return;
    NSLog(@"[GameDir] Task483: single real root policy -- switch request to '%@' is a no-op (no link surgery, lasm untouched)", name);
    toggleIsolatedPref(NO);

    // 刷新 PLProfiles 缓存，确保后续读取的是单一真实根的 launcher_profiles.json
    [PLProfiles updateCurrent];

    // 尝试直接调用 reloadProfileList，如果 navigationController 响应该选择器
    if ([self.navigationController respondsToSelector:@selector(reloadProfileList)]) {
        [self.navigationController performSelector:@selector(reloadProfileList)];
    } else {
        // 否则发送通知
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadProfileList" object:nil];
    }

    // 发送通知刷新版本配置和编辑 profile 界面
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectedProfileChanged" object:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.array.count;
}

- (UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITextField *view;
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
        view = [[UITextField alloc] initWithFrame:CGRectMake(20, 10, (cell.bounds.size.width-40)/2, cell.bounds.size.height-20)];
        [view addTarget:view action:@selector(resignFirstResponder) forControlEvents:UIControlEventEditingDidEndOnExit];
        view.autocorrectionType = UITextAutocorrectionTypeNo;
        view.autocapitalizationType = UITextAutocapitalizationTypeNone;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        view.delegate = self;
        view.returnKeyType = UIReturnKeyDone;
        // ★ Task483：单根条目只读（旧实现 row!=0 可编辑改名 = instances 改名入口）
        view.userInteractionEnabled = NO;
        [cell.contentView addSubview:view];
        cell.detailTextLabel.text = @"...";
    }
    view = cell.contentView.subviews.firstObject;
    view.placeholder = self.array[indexPath.row];
    view.text = self.array[indexPath.row];
    cell.textLabel.hidden = YES;
    cell.textLabel.text = view.text;

    // Calculate the instance size
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        unsigned long long folderSize = 0;
        NSString *directory = [[self class] ame483_singleRoot];
        [NSFileManager.defaultManager nr_getAllocatedSize:&folderSize ofDirectoryAtURL:[NSURL fileURLWithPath:directory] error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            cell.detailTextLabel.text = [NSByteCountFormatter stringFromByteCount:folderSize countStyle:NSByteCountFormatterCountStyleMemory];
        });
    });

    if ([getPrefObject(@"general.game_directory") isEqualToString:self.array[indexPath.row]]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

- (UIView *)tableView:(UITableView *)tableView
viewForFooterInSection:(NSInteger)section
{
    // ★ Task483：新建目录入口退役——页脚改为单一真实根说明文案
    UILabel *footer = [[UILabel alloc] init];
    footer.text = localize(@"ame483.gamedir.single_root_hint", @"单一游戏目录已启用（instances 多目录布局已退役），游戏数据统一存放在 Library/Application Support/minecraft");
    footer.font = [UIFont systemFontOfSize:13];
    footer.textColor = [UIColor secondaryLabelColor];
    footer.numberOfLines = 0;
    return footer;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self changeSelectionTo:self.array[indexPath.row]];
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    for (int i = 0; i < self.array.count; i++) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]];
        if (i == indexPath.row) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        } else {
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
    }
}

// ★ Task247（T9）：伪玻璃档长按手势 → ame240 统一路由（磨砂面板）。
//   ★Task483：菜单仅保留「外部打开」（单一真实根）；重命名/删除退役。
- (void)ame247_longPressDirMenu:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint ame247_pt = [gesture locationInView:self.tableView];
    NSIndexPath *ame247_ip = [self.tableView indexPathForRowAtPoint:ame247_pt];
    if (ame247_ip == nil || ame247_ip.row >= self.array.count) return;

    NSString *ame247_name = self.array[ame247_ip.row];
    NSString *ame247_dir = [[self class] ame483_singleRoot];
    NSMutableArray<NSDictionary *> *ame247_items = [NSMutableArray array];
    NSDictionary *ame247_apps = @{
        @"shareddocuments": @"Files",
        @"filza": @"Filza",
        @"santander": @"Santander",
    };
    for (NSString *ame247_key in ame247_apps.allKeys) {
        NSString *ame247_url = [NSString stringWithFormat:@"%@://", ame247_key];
        if ([UIApplication.sharedApplication canOpenURL:[NSURL URLWithString:ame247_url]]) {
            NSString *ame247_scheme = ame247_key;
            [ame247_items addObject:@{
                @"title": ame247_apps[ame247_key],
                @"handler": ^{
                    [UIApplication.sharedApplication
                        openURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", ame247_scheme, ame247_dir]]
                        options:@{} completionHandler:nil];
                },
            }];
        }
    }
    if (ame247_items.count == 0) return;
    UITableViewCell *ame247_anchor = [self.tableView cellForRowAtIndexPath:ame247_ip];
    [AmeNativeMenu ame240_presentMenuWithTitle:ame247_name
                                     dictItems:ame247_items
                                    sourceView:ame247_anchor ?: self.view];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point
{
    // ★ Task247（T9）：伪玻璃档返回 nil（系统上下文菜单不上场），长按由
    //   viewDidLoad 挂的手势经 ame240 路由呈磨砂面板。
    if (LGCIsPseudoGlassStyleActive()) return nil;
    // ★ Task483：仅「外部打开」（单一真实根）；重命名/删除退役。
    NSMutableArray *openItems = [[NSMutableArray alloc] init];

    NSString *directory = [[self class] ame483_singleRoot];
    NSDictionary *apps = @{
        @"shareddocuments": @"Files",
        @"filza": @"Filza",
        @"santander": @"Santander",
    };
    for (NSString *key in apps.allKeys) {
        NSString *url = [NSString stringWithFormat:@"%@://", key];
        if ([UIApplication.sharedApplication canOpenURL:[NSURL URLWithString:url]]) {
            [openItems addObject:[UIAction
                actionWithTitle:apps[key]
                image:nil
                identifier:nil
                handler:[self createOpenScheme:key at:directory]]];
        }
    }
    UIMenu *open = [UIMenu
        menuWithTitle:@""
        image:nil
        identifier:nil
        options:UIMenuOptionsDisplayInline
        children:openItems];

    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
        previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
            return [UIMenu menuWithTitle:self.array[indexPath.row] children:@[open]];
        }
    ];
}

- (id)createOpenScheme:(NSString *)scheme at:(NSString *)directory {
    return ^(UIAction *action) {
        [UIApplication.sharedApplication
            openURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", scheme, directory]]
            options:@{} completionHandler:nil];
    };
}

- (void) dismissModalViewController {
    dismissModalViewController(self);
}

#pragma mark UITextField

- (void)textFieldDidEndEditing:(UITextField *)sender {
    // ★ Task483：单根条目只读、页脚改说明文案——编辑路径只剩文本还原。
    if (!sender.hasText || [sender.text isEqualToString:sender.placeholder]) {
        return;
    }
    sender.text = sender.placeholder;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    [textField invalidateIntrinsicContentSize];
    CGRect frame = textField.frame;
    frame.size.width = MAX(50, textField.intrinsicContentSize.width + 10);
    textField.frame = frame;
    return YES;
}

/// 重新应用背景效果：当 BackgroundUIEffectChanged 通知到达时调用，
/// 通过 BackgroundManager 重新设置当前视图控制器的透明度/毛玻璃效果，
/// 确保 tableView 背景透明、全局背景能够正常透出。
- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
