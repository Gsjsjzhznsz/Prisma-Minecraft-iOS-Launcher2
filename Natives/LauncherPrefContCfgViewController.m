//
//  LauncherPrefContCfgViewController.m
//  ★Task428（428-G，报告 7.3 第一/二层）：手柄映射编辑页原地重做。
//
//   旧病历（报告 7.1）：纯一代样式——裸 InsetGrouped 表 + Value1 cell +
//   UIPickerView 长列表选 GLFW 键名（约 :48、:133-185），文件零主题令牌。
//   本轮按 7.3 分两层落地：
//   第一层（P0 止血）：弃用 UIPickerView 长列表；主界面 = 连体组卡行列表
//     （每行：控件名 + 当前映射的 GLFW 键名 + 触发键摘要），点行进入
//     「按下采集」全屏向导（大示意图 + 700ms 防抖 + 成功高亮回列表刷新）；
//     未连接手柄时回退为行内联三组选择器（方向键/动作键/摇杆）。
//   第二层（P1 可视化）：页首 Xbox 布局手柄示意图（CoreGraphics 纯形状
//     自绘，零 SF Symbols），已映射控件显示键名缩写角标；连接手柄时
//     GCController 事件驱动实时高亮（演示即映射）；映射行列表用
//     ZL2M3FilterChip 过滤（全部/动作键/方向键/摇杆）。
//
//   兼容红线（铁律）：映射的存储格式完全不变——JSON 文件结构
//     {version, mGameMappingList:[{name, gamepad_button, keycode}],
//      mMenuMappingList:[…]}，gamepad_button 仍为 GLFW 手柄键 id
//     （0-14 + 349/350），keycode 仍为 GLFW 键码/SPECIALBTN_*；偏好键
//     control.default_gamepad_ctrl / control.controller_type /
//     control.nintendo_layout 读写语义与旧页逐位一致；游戏内消费方
//     （ControllerInput.sendKeyEvent 的 int 匹配）零改动。
//     「按下采集」只改写条目的 gamepad_button（把某物理键换绑到该控件
//     行；若该物理键已被同列表其他行占用则两者交换）；keycode 侧经
//     行尾键位 chip 的分组选择底部弹层编辑（长列表的分组化替代）。
//
//   UI 语言（ZL2 域同一红线）：颜色/字体/圆角一律 ZL2Theme 类方法；
//   卡片 = ZL2SettingCardGroup 连体组卡；chip = ZL2M3FilterChip；
//   底部弹层 = ZL2M3BottomSheet；iOS 14.0 API 上限；新建视图一律
//   translatesAutoresizingMaskIntoConstraints = NO；类扩展成员用裸 ivar（不用
//   @property/self. 属性语法）。
//

#import <GameController/GameController.h>

#import "LauncherPrefContCfgViewController.h"

#import "customcontrols/CustomControlsUtils.h"
#import "FileListViewController.h"
#import "LauncherPreferences.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

#import "ZL2M3Kit.h"
#import "ZL2SettingCards.h"
#import "ZL2Theme.h"

#include "glfw_keycodes.h"

#pragma mark - ★Task428：静态数据表（控件角色名 / 物理键 / 出厂默认 / 键码）

// ★Task428：键码表（initKeycodeTable 同源；进程内一次构建）。
//   ame428G_keyNames/ame428G_keyCodes 与旧页 pickerView 数据完全同源，
//   ame428G_codeToName 为键值 → 键名反查（旧页 indexOfObject 的替代）。
static NSMutableArray<NSString *> *ame428G_keyNames = nil;
static NSMutableArray<NSNumber *> *ame428G_keyCodes = nil;
static NSDictionary<NSNumber *, NSString *> *ame428G_codeToName = nil;

static void ame428G_ensureKeyTables(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ame428G_keyNames = [[NSMutableArray alloc] init];
        ame428G_keyCodes = [[NSMutableArray alloc] init];
        initKeycodeTable(ame428G_keyNames, ame428G_keyCodes);
        NSMutableDictionary *rev = [[NSMutableDictionary alloc] init];
        for (NSUInteger i = 0; i < ame428G_keyNames.count; i++) {
            rev[ame428G_keyCodes[i]] = ame428G_keyNames[i];
        }
        ame428G_codeToName = rev;
    });
}

// ★Task428：控件角色名键表（旧页动态拼键 controller_configurator.%@.title.%@
//   的静态化替代——表内一律完整字面量，零运行时拼键）。
//   键空间即 Localizable.strings 既有键（零新增）；nintendo 按 Task311
//   语义回落 xbox 表（读取侧 ame428G_currentTypeString 统一折叠）。
static NSDictionary *ame428G_roleKeyTable(void) {
    static NSDictionary *table = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @"bumper_left":   @{@"xbox": @"controller_configurator.xbox.title.bumper_left",
                                @"playstation": @"controller_configurator.playstation.title.bumper_left"},
            @"bumper_right":  @{@"xbox": @"controller_configurator.xbox.title.bumper_right",
                                @"playstation": @"controller_configurator.playstation.title.bumper_right"},
            @"trigger_left":  @{@"xbox": @"controller_configurator.xbox.title.trigger_left",
                                @"playstation": @"controller_configurator.playstation.title.trigger_left"},
            @"trigger_right": @{@"xbox": @"controller_configurator.xbox.title.trigger_right",
                                @"playstation": @"controller_configurator.playstation.title.trigger_right"},
            @"named_back":    @{@"xbox": @"controller_configurator.xbox.title.named_back",
                                @"playstation": @"controller_configurator.playstation.title.named_back"},
            @"named_start":   @{@"xbox": @"controller_configurator.xbox.title.named_start",
                                @"playstation": @"controller_configurator.playstation.title.named_start"},
            @"named_a":       @{@"xbox": @"controller_configurator.xbox.title.named_a",
                                @"playstation": @"controller_configurator.playstation.title.named_a"},
            @"named_b":       @{@"xbox": @"controller_configurator.xbox.title.named_b",
                                @"playstation": @"controller_configurator.playstation.title.named_b"},
            @"named_x":       @{@"xbox": @"controller_configurator.xbox.title.named_x",
                                @"playstation": @"controller_configurator.playstation.title.named_x"},
            @"named_y":       @{@"xbox": @"controller_configurator.xbox.title.named_y",
                                @"playstation": @"controller_configurator.playstation.title.named_y"},
            @"dpad_up":       @{@"xbox": @"controller_configurator.xbox.title.dpad_up",
                                @"playstation": @"controller_configurator.playstation.title.dpad_up"},
            @"dpad_down":     @{@"xbox": @"controller_configurator.xbox.title.dpad_down",
                                @"playstation": @"controller_configurator.playstation.title.dpad_down"},
            @"dpad_left":     @{@"xbox": @"controller_configurator.xbox.title.dpad_left",
                                @"playstation": @"controller_configurator.playstation.title.dpad_left"},
            @"dpad_right":    @{@"xbox": @"controller_configurator.xbox.title.dpad_right",
                                @"playstation": @"controller_configurator.playstation.title.dpad_right"},
            @"thumb_left":    @{@"xbox": @"controller_configurator.xbox.title.thumb_left",
                                @"playstation": @"controller_configurator.playstation.title.thumb_left"},
            @"thumb_right":   @{@"xbox": @"controller_configurator.xbox.title.thumb_right",
                                @"playstation": @"controller_configurator.playstation.title.thumb_right"},
        };
    });
    return table;
}

// ★Task428：物理手柄键信息表（id → 显示键 + 分组）。
//   分组 cat：0=动作键 1=方向键 2=摇杆 3=仅装饰（指南键——不可绑定，
//   采集/回退选择器不出现，仅实时高亮）。
//   id 空间与消费方（ControllerInput 的 gamepad_button int 匹配）完全一致。
static NSDictionary *ame428G_buttonInfoTable(void) {
    static NSDictionary *table = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @(GLFW_GAMEPAD_BUTTON_A):             @{@"key": @"ame428.gp.btn.a", @"cat": @(0)},
            @(GLFW_GAMEPAD_BUTTON_B):             @{@"key": @"ame428.gp.btn.b", @"cat": @(0)},
            @(GLFW_GAMEPAD_BUTTON_X):             @{@"key": @"ame428.gp.btn.x", @"cat": @(0)},
            @(GLFW_GAMEPAD_BUTTON_Y):             @{@"key": @"ame428.gp.btn.y", @"cat": @(0)},
            @(GLFW_GAMEPAD_BUTTON_LEFT_BUMPER):   @{@"key": @"ame428.gp.btn.lb", @"cat": @(0)},
            @(GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER):  @{@"key": @"ame428.gp.btn.rb", @"cat": @(0)},
            @(GLFW_GAMEPAD_BUTTON_LEFT_TRIGGER):  @{@"key": @"ame428.gp.btn.lt", @"cat": @(0)},
            @(GLFW_GAMEPAD_BUTTON_RIGHT_TRIGGER): @{@"key": @"ame428.gp.btn.rt", @"cat": @(0)},
            @(GLFW_GAMEPAD_BUTTON_BACK):          @{@"key": @"ame428.gp.btn.back", @"cat": @(0)},
            @(GLFW_GAMEPAD_BUTTON_START):         @{@"key": @"ame428.gp.btn.start", @"cat": @(0)},
            @(GLFW_GAMEPAD_BUTTON_LEFT_THUMB):    @{@"key": @"ame428.gp.btn.l3", @"cat": @(2)},
            @(GLFW_GAMEPAD_BUTTON_RIGHT_THUMB):   @{@"key": @"ame428.gp.btn.r3", @"cat": @(2)},
            @(GLFW_GAMEPAD_BUTTON_DPAD_UP):       @{@"key": @"ame428.gp.btn.dpad_up", @"cat": @(1)},
            @(GLFW_GAMEPAD_BUTTON_DPAD_RIGHT):    @{@"key": @"ame428.gp.btn.dpad_right", @"cat": @(1)},
            @(GLFW_GAMEPAD_BUTTON_DPAD_DOWN):     @{@"key": @"ame428.gp.btn.dpad_down", @"cat": @(1)},
            @(GLFW_GAMEPAD_BUTTON_DPAD_LEFT):     @{@"key": @"ame428.gp.btn.dpad_left", @"cat": @(1)},
            @(GLFW_GAMEPAD_BUTTON_GUIDE):         @{@"key": @"ame428.gp.btn.guide", @"cat": @(3)},
        };
    });
    return table;
}

// ★Task428：物理键显示名（位置语义，Xbox 命名口径——与示意图布局同源）。
static NSString *ame428G_buttonName(int buttonId) {
    NSDictionary *info = ame428G_buttonInfoTable()[@(buttonId)];
    if (info == nil) return [NSString stringWithFormat:@"#%d", buttonId];
    return localize(info[@"key"], nil);
}

// ★Task428：当前手柄类型显示表（control.controller_type；nintendo 折叠
//   xbox——Task311 语义：任天堂无专属键名表，仅布局交换）。
static NSString *ame428G_currentTypeString(void) {
    NSString *t = getPrefObject(@"control.controller_type");
    if (![t isKindOfClass:[NSString class]]) t = @"xbox";
    if ([t isEqualToString:@"playstation"]) return @"playstation";
    return @"xbox";
}

// ★Task428：控件角色（按 name）所属分组——Chip 过滤与行内联回退
//   选择器共用同一分组口径（方向键/动作键/摇杆）。
static int ame428G_categoryOfRole(NSString *roleName) {
    if ([roleName hasPrefix:@"dpad_"]) return 1;
    if ([roleName hasPrefix:@"thumb_"]) return 2;
    return 0;
}

// ★Task428：控件角色显示名（静态键表查表，零动态拼键）。
static NSString *ame428G_roleTitle(NSString *roleName, NSString *typeTable) {
    NSDictionary *perName = ame428G_roleKeyTable()[roleName];
    if (perName == nil) return roleName ?: @"?";
    NSString *key = perName[typeTable] ?: perName[@"xbox"];
    if (key == nil) return roleName ?: @"?";
    return localize(key, nil);
}

// ★Task428：出厂默认绑定表（generateAndSaveDefaultControlForGamepad
//   同源字面量；「清除映射」= 该行恢复对应列表的出厂绑定）。
static NSDictionary *ame428G_stockTable(BOOL menu) {
    if (!menu) {
        static NSDictionary *game = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            game = @{
                @"bumper_left":   @{@"button": @(GLFW_GAMEPAD_BUTTON_LEFT_BUMPER),   @"keycode": @(SPECIALBTN_SCROLLUP)},
                @"bumper_right":  @{@"button": @(GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER),  @"keycode": @(SPECIALBTN_SCROLLDOWN)},
                @"trigger_left":  @{@"button": @(GLFW_GAMEPAD_BUTTON_LEFT_TRIGGER),  @"keycode": @(SPECIALBTN_MOUSESEC)},
                @"trigger_right": @{@"button": @(GLFW_GAMEPAD_BUTTON_RIGHT_TRIGGER), @"keycode": @(SPECIALBTN_MOUSEPRI)},
                @"named_back":    @{@"button": @(GLFW_GAMEPAD_BUTTON_BACK),          @"keycode": @(GLFW_KEY_TAB)},
                @"named_start":   @{@"button": @(GLFW_GAMEPAD_BUTTON_START),         @"keycode": @(GLFW_KEY_ESCAPE)},
                @"named_a":       @{@"button": @(GLFW_GAMEPAD_BUTTON_A),             @"keycode": @(GLFW_KEY_SPACE)},
                @"named_b":       @{@"button": @(GLFW_GAMEPAD_BUTTON_B),             @"keycode": @(GLFW_KEY_Q)},
                @"named_x":       @{@"button": @(GLFW_GAMEPAD_BUTTON_X),             @"keycode": @(GLFW_KEY_E)},
                @"named_y":       @{@"button": @(GLFW_GAMEPAD_BUTTON_Y),             @"keycode": @(GLFW_KEY_F)},
                @"dpad_up":       @{@"button": @(GLFW_GAMEPAD_BUTTON_DPAD_UP),       @"keycode": @(GLFW_KEY_LEFT_SHIFT)},
                @"dpad_down":     @{@"button": @(GLFW_GAMEPAD_BUTTON_DPAD_DOWN),     @"keycode": @(GLFW_KEY_O)},
                @"dpad_left":     @{@"button": @(GLFW_GAMEPAD_BUTTON_DPAD_LEFT),     @"keycode": @(GLFW_KEY_J)},
                @"dpad_right":    @{@"button": @(GLFW_GAMEPAD_BUTTON_DPAD_RIGHT),    @"keycode": @(GLFW_KEY_K)},
                @"thumb_left":    @{@"button": @(GLFW_GAMEPAD_BUTTON_LEFT_THUMB),    @"keycode": @(GLFW_KEY_LEFT_CONTROL)},
                @"thumb_right":   @{@"button": @(GLFW_GAMEPAD_BUTTON_RIGHT_THUMB),   @"keycode": @(GLFW_KEY_LEFT_SHIFT)},
            };
        });
        return game;
    } else {
        static NSDictionary *menuTable = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            menuTable = @{
                @"bumper_left":   @{@"button": @(GLFW_GAMEPAD_BUTTON_LEFT_BUMPER),   @"keycode": @(SPECIALBTN_SCROLLUP)},
                @"bumper_right":  @{@"button": @(GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER),  @"keycode": @(SPECIALBTN_SCROLLDOWN)},
                @"trigger_left":  @{@"button": @(GLFW_GAMEPAD_BUTTON_LEFT_TRIGGER),  @"keycode": @(GLFW_KEY_UNKNOWN)},
                @"trigger_right": @{@"button": @(GLFW_GAMEPAD_BUTTON_RIGHT_TRIGGER), @"keycode": @(GLFW_KEY_UNKNOWN)},
                @"named_back":    @{@"button": @(GLFW_GAMEPAD_BUTTON_BACK),          @"keycode": @(GLFW_KEY_UNKNOWN)},
                @"named_start":   @{@"button": @(GLFW_GAMEPAD_BUTTON_START),         @"keycode": @(GLFW_KEY_UNKNOWN)},
                @"named_a":       @{@"button": @(GLFW_GAMEPAD_BUTTON_A),             @"keycode": @(SPECIALBTN_MOUSEPRI)},
                @"named_b":       @{@"button": @(GLFW_GAMEPAD_BUTTON_B),             @"keycode": @(GLFW_KEY_ESCAPE)},
                @"named_x":       @{@"button": @(GLFW_GAMEPAD_BUTTON_X),             @"keycode": @(SPECIALBTN_MOUSESEC)},
                @"named_y":       @{@"button": @(GLFW_GAMEPAD_BUTTON_Y),             @"keycode": @(GLFW_KEY_LEFT_SHIFT)},
                @"dpad_up":       @{@"button": @(GLFW_GAMEPAD_BUTTON_DPAD_UP),       @"keycode": @(GLFW_KEY_UNKNOWN)},
                @"dpad_down":     @{@"button": @(GLFW_GAMEPAD_BUTTON_DPAD_DOWN),     @"keycode": @(GLFW_KEY_O)},
                @"dpad_left":     @{@"button": @(GLFW_GAMEPAD_BUTTON_DPAD_LEFT),     @"keycode": @(GLFW_KEY_J)},
                @"dpad_right":    @{@"button": @(GLFW_GAMEPAD_BUTTON_DPAD_RIGHT),    @"keycode": @(GLFW_KEY_K)},
                @"thumb_left":    @{@"button": @(GLFW_GAMEPAD_BUTTON_LEFT_THUMB),    @"keycode": @(GLFW_KEY_UNKNOWN)},
                @"thumb_right":   @{@"button": @(GLFW_GAMEPAD_BUTTON_RIGHT_THUMB),   @"keycode": @(GLFW_KEY_UNKNOWN)},
            };
        });
        return menuTable;
    }
}

// ★Task428：SPECIALBTN_* 显示键表（完整字面量，零动态拼键）。
static NSDictionary *ame428G_specialDisplayKeys(void) {
    static NSDictionary *table = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @"SPECIALBTN_MENU":         @"ame428.gp.spec.menu",
            @"SPECIALBTN_SCROLLDOWN":   @"ame428.gp.spec.scrolldown",
            @"SPECIALBTN_SCROLLUP":     @"ame428.gp.spec.scrollup",
            @"SPECIALBTN_VIRTUALMOUSE": @"ame428.gp.spec.virtualmouse",
            @"SPECIALBTN_MOUSEMID":     @"ame428.gp.spec.mousemid",
            @"SPECIALBTN_MOUSESEC":     @"ame428.gp.spec.mousesec",
            @"SPECIALBTN_MOUSEPRI":     @"ame428.gp.spec.mousepri",
            @"SPECIALBTN_TOGGLECTRL":   @"ame428.gp.spec.togglectrl",
            @"SPECIALBTN_KEYBOARD":     @"ame428.gp.spec.keyboard",
        };
    });
    return table;
}

// ★Task428：键码 → 行尾显示名（SPECIALBTN_* 走本地化短名；0=未映射）。
static NSString *ame428G_keyDisplay(int code) {
    if (code == 0) return localize(@"ame428.gp.key.none", nil);
    ame428G_ensureKeyTables();
    NSString *name = ame428G_codeToName[@(code)];
    if (name == nil) return [NSString stringWithFormat:@"%d", code];
    NSString *specKey = ame428G_specialDisplayKeys()[name];
    if (specKey != nil) return localize(specKey, nil);
    return name;
}

// ★Task428：显示名 → 示意图角标缩写（压缩 + 截断；LEFT_/RIGHT_ 折叠为 L/R）。
static NSString *ame428G_keyShort(NSString *display) {
    if (display.length > 6) {
        if ([display hasPrefix:@"LEFT_"]) {
            display = [@"L" stringByAppendingString:[display substringFromIndex:5]];
        } else if ([display hasPrefix:@"RIGHT_"]) {
            display = [@"R" stringByAppendingString:[display substringFromIndex:6]];
        }
        display = [display stringByReplacingOccurrencesOfString:@"_" withString:@""];
    }
    if (display.length > 5) display = [display substringToIndex:4];  // 角标宽度约 30pt：4 字 + 视觉余量
    return display;
}

#pragma mark - ★Task428：示意图几何表（设计空间 280×148，Xbox 布局口径）

// ★Task428：shape：0=肩键页签 1=摇杆圆（含内芯）2=面键圆 3=十字臂
//   4=胶囊（BACK/START）5=指南圆点（仅装饰/高亮）。
//   badge 为该控件角标（CGRectNull = 无角标）。
static NSArray *ame428G_schematicTable(void) {
    static NSArray *table = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // ★Task428-r1：block 指针而非 C 函数指针（^ 字面量初始化函数指针 = CI 判例
        //   家族——本地括号门禁不查类型，新代码面首上 CI 才暴露）
        NSDictionary * (^E)(int, int, CGRect, CGRect) = ^NSDictionary *(int pid, int shape, CGRect f, CGRect badge) {
            return @{
                @"id": @(pid),
                @"shape": @(shape),
                @"frame": [NSValue valueWithCGRect:f],
                @"badge": [NSValue valueWithCGRect:badge],
            };
        };
        table = @[
            E(GLFW_GAMEPAD_BUTTON_LEFT_TRIGGER,  0, CGRectMake(36, 4, 22, 18),  CGRectMake(34, 26, 26, 12)),
            E(GLFW_GAMEPAD_BUTTON_RIGHT_TRIGGER, 0, CGRectMake(222, 4, 22, 18), CGRectMake(210, 26, 26, 12)),
            E(GLFW_GAMEPAD_BUTTON_LEFT_BUMPER,   0, CGRectMake(76, 8, 30, 18),  CGRectMake(78, 30, 26, 12)),
            E(GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER,  0, CGRectMake(174, 8, 30, 18), CGRectMake(176, 30, 26, 12)),
            E(GLFW_GAMEPAD_BUTTON_BACK,          4, CGRectMake(108, 55, 10, 14), CGRectMake(100, 78, 28, 12)),
            E(GLFW_GAMEPAD_BUTTON_START,         4, CGRectMake(152, 55, 10, 14), CGRectMake(144, 84, 26, 12)),
            E(GLFW_GAMEPAD_BUTTON_GUIDE,         5, CGRectMake(130, 52, 20, 20), CGRectNull),
            E(GLFW_GAMEPAD_BUTTON_LEFT_THUMB,    1, CGRectMake(67, 41, 34, 34),  CGRectMake(69, 52, 30, 12)),
            E(GLFW_GAMEPAD_BUTTON_RIGHT_THUMB,   1, CGRectMake(180, 100, 32, 32), CGRectMake(181, 110, 30, 12)),
            E(GLFW_GAMEPAD_BUTTON_DPAD_UP,       3, CGRectMake(79, 91, 10, 19),  CGRectMake(69, 76, 30, 12)),
            E(GLFW_GAMEPAD_BUTTON_DPAD_RIGHT,    3, CGRectMake(84, 105, 19, 10), CGRectMake(107, 106, 30, 12)),
            E(GLFW_GAMEPAD_BUTTON_DPAD_DOWN,     3, CGRectMake(79, 110, 10, 19), CGRectMake(69, 133, 30, 12)),
            E(GLFW_GAMEPAD_BUTTON_DPAD_LEFT,     3, CGRectMake(65, 105, 19, 10), CGRectMake(31, 106, 30, 12)),
            E(GLFW_GAMEPAD_BUTTON_Y,             2, CGRectMake(187, 32, 18, 18),  CGRectMake(181, 18, 30, 12)),
            E(GLFW_GAMEPAD_BUTTON_B,             2, CGRectMake(204, 49, 18, 18),  CGRectMake(218, 53, 26, 12)),
            E(GLFW_GAMEPAD_BUTTON_A,             2, CGRectMake(187, 66, 18, 18),  CGRectMake(181, 88, 30, 12)),
            E(GLFW_GAMEPAD_BUTTON_X,             2, CGRectMake(170, 49, 18, 18),  CGRectMake(158, 70, 28, 12)),
        ];
    });
    return table;
}

#pragma mark - ★Task428：私有视图一：Xbox 布局手柄示意图（CoreGraphics 自绘）

// ★Task428：第二层可视化核心件。纯形状绘制（零 SF Symbols、零图片资产）：
//   机身轮廓 + 肩键/扳机页签 + 十字键 + ABXY + 双摇杆 + BACK/START 胶囊 +
//   指南圆点；已映射控件（badges 命中）绘制键名缩写角标（primaryContainer
//   圆角小块）；实时按下 / 采集目标（呼吸脉冲）/ 采集成功（primary 填充）。
@interface AME428SchematicView : UIView
- (void)ame428_applyBadges:(NSDictionary<NSNumber *, NSString *> *)badges;
- (void)ame428_setPressed:(BOOL)pressed forButton:(int)buttonId;
- (void)ame428_setTarget:(int)buttonId;
- (void)ame428_setSuccess:(int)buttonId;
@end

@implementation AME428SchematicView {
    NSMutableDictionary<NSNumber *, NSString *> *_badges;
    NSMutableSet<NSNumber *> *_pressed;
    int _targetId;
    int _successId;
    CADisplayLink *_pulseLink;
    double _pulsePhase;
    CGFloat _targetAlpha;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return self;
    self.backgroundColor = [UIColor clearColor];
    self.contentMode = UIViewContentModeRedraw;
    _badges = [[NSMutableDictionary alloc] init];
    _pressed = [[NSMutableSet alloc] init];
    _targetId = -1;
    _successId = -1;
    _targetAlpha = 1.0;
    return self;
}

- (void)ame428_applyBadges:(NSDictionary<NSNumber *, NSString *> *)badges {
    [_badges removeAllObjects];
    if (badges != nil) [_badges addEntriesFromDictionary:badges];
    [self setNeedsDisplay];
}

- (void)ame428_setPressed:(BOOL)pressed forButton:(int)buttonId {
    if (pressed) {
        [_pressed addObject:@(buttonId)];
    } else {
        [_pressed removeObject:@(buttonId)];
    }
    [self setNeedsDisplay];
}

- (void)ame428_setTarget:(int)buttonId {
    if (_targetId == buttonId) return;
    _targetId = buttonId;
    _targetAlpha = 1.0;
    [self ame428_updatePulseLink];
    [self setNeedsDisplay];
}

- (void)ame428_setSuccess:(int)buttonId {
    _successId = buttonId;
    [self setNeedsDisplay];
}

// ★Task428：采集目标呼吸脉冲（CADisplayLink 驱动相位，仅目标态启用）。
- (void)ame428_updatePulseLink {
    BOOL need = (_targetId >= 0 && self.window != nil);
    if (need && _pulseLink == nil) {
        _pulseLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(ame428_pulseTick:)];
        [_pulseLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    } else if (!need && _pulseLink != nil) {
        [_pulseLink invalidate];
        _pulseLink = nil;
    }
}

- (void)ame428_pulseTick:(CADisplayLink *)link {
    _pulsePhase += 0.07;
    double s = sin(_pulsePhase);
    _targetAlpha = (CGFloat)(0.55 + 0.45 * (0.5 + 0.5 * s));
    [self setNeedsDisplay];
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];
    if (newWindow == nil) {
        if (_pulseLink != nil) {
            [_pulseLink invalidate];
            _pulseLink = nil;
        }
    } else {
        [self ame428_updatePulseLink];
    }
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx == nil) return;
    CGFloat s = self.bounds.size.width / 280.0;
    if (s <= 0.0) return;

    // ★Task428：机身轮廓（圆角矩形，Xbox 布局；表面凹陷底 + 弱描边）。
    UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(14.0 * s, 18.0 * s, 252.0 * s, 120.0 * s)
                                                     cornerRadius:26.0 * s];
    [[ZL2Theme surfaceContainerLow] setFill];
    [body fill];
    [[ZL2Theme outlineVariant] setStroke];
    body.lineWidth = 1.5;
    [body stroke];

    NSMutableParagraphStyle *centerStyle = [[NSMutableParagraphStyle alloc] init];
    centerStyle.alignment = NSTextAlignmentCenter;
    NSDictionary *badgeTextAttrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium],
        NSForegroundColorAttributeName: [ZL2Theme onPrimaryContainer],
        NSParagraphStyleAttributeName: centerStyle,
    };

    for (NSDictionary *info in ame428G_schematicTable()) {
        int pid = [info[@"id"] intValue];
        CGRect f = [info[@"frame"] CGRectValue];
        f = CGRectMake(f.origin.x * s, f.origin.y * s, f.size.width * s, f.size.height * s);
        int shape = [info[@"shape"] intValue];
        BOOL isPressed = [_pressed containsObject:@(pid)];
        BOOL isTarget = (_targetId == pid);
        BOOL isSuccess = (_successId == pid);

        UIBezierPath *path = nil;
        switch (shape) {
            case 0:  path = [UIBezierPath bezierPathWithRoundedRect:f cornerRadius:8.0 * s]; break;
            case 3:  path = [UIBezierPath bezierPathWithRect:f]; break;
            case 4:  path = [UIBezierPath bezierPathWithRoundedRect:f cornerRadius:4.0 * s]; break;
            default: path = [UIBezierPath bezierPathWithOvalInRect:f]; break;
        }

        UIColor *fill;
        UIColor *strokeC;
        if (isSuccess || isPressed) {
            fill = [ZL2Theme primary];
            strokeC = nil;
        } else if (isTarget) {
            fill = [[ZL2Theme primaryContainer] colorWithAlphaComponent:_targetAlpha];
            strokeC = [[ZL2Theme primary] colorWithAlphaComponent:_targetAlpha];
        } else {
            fill = [ZL2Theme surface];
            strokeC = [ZL2Theme outlineVariant];
        }
        if (path != nil) {
            [fill setFill];
            [path fill];
            if (strokeC != nil) {
                [strokeC setStroke];
                path.lineWidth = (shape == 1 || shape == 2) ? 1.5 : 1.0;
                [path stroke];
            }
            if (isSuccess) {
                // ★Task428：采集成功高亮（primary 填充 + onPrimary 外圈）。
                [[ZL2Theme onPrimary] setStroke];
                path.lineWidth = 3.0 * s;
                [path stroke];
            }
            // ★Task428：摇杆内芯（装饰小圆）。
            if (shape == 1) {
                CGRect core = CGRectInset(f, 11.0 * s, 11.0 * s);
                UIBezierPath *corePath = [UIBezierPath bezierPathWithOvalInRect:core];
                [(isSuccess || isPressed) ? [ZL2Theme onPrimary] : [ZL2Theme outlineVariant] setFill];
                [corePath fill];
            }
        }

        // ★Task428：键名缩写角标（已映射控件；primaryContainer 底 + onPrimaryContainer 字）。
        NSValue *badgeVal = info[@"badge"];
        if (badgeVal != nil && !CGRectIsNull(badgeVal.CGRectValue)) {
            NSString *text = _badges[@(pid)];
            if (text.length > 0) {
                CGRect b = badgeVal.CGRectValue;
                b = CGRectMake(b.origin.x * s, b.origin.y * s, b.size.width * s, b.size.height * s);
                UIBezierPath *badgePath = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, 0, 1.0 * s)
                                                                      cornerRadius:4.0 * s];
                [[ZL2Theme primaryContainer] setFill];
                [badgePath fill];
                [text drawInRect:CGRectInset(b, 2.0 * s, 1.5 * s) withAttributes:badgeTextAttrs];
            }
        }
    }
}

@end

#pragma mark - ★Task428：手柄事件桥（GCController 订阅/拆除共用件）

// ★Task428：主页面实时高亮与采集页按下采集共用的事件层。
//   订阅 GCController.controllers 全部 extendedGamepad：离散按键走
//   pressedChangedHandler；摇杆轴走 valueChangedHandler（|x|≥0.75 或
//   |y|≥0.75 记为按下、|x|<0.6 且 |y|<0.6 记为释放——带回滞，避免阈值
//   边缘抖动）。controllerPausedPauseHandler 等系统行为不触碰、不干预。
//   元素 handler 为整体覆盖式：本桥 install 时覆盖既有 handler，teardown
//   置 nil；下一局游戏创建 SurfaceViewController 时会重新注册
//   ControllerInput 回调（既有链路，见 SurfaceViewController.m:1657）。
@interface AME428PadBridge : NSObject
- (void)installWithEventBlock:(void (^)(int buttonId, BOOL pressed))block;
- (void)teardown;
@end

@implementation AME428PadBridge {
    void (^_eventBlock)(int buttonId, BOOL pressed);
    BOOL _leftTilt;
    BOOL _rightTilt;
}

- (void)installWithEventBlock:(void (^)(int, BOOL))block {
    _eventBlock = [block copy];
    for (GCController *controller in GCController.controllers) {
        GCExtendedGamepad *gp = controller.extendedGamepad;
        if (gp != nil) [self ame428_installOnGamepad:gp];
    }
}

- (void)teardown {
    _eventBlock = nil;
    _leftTilt = NO;
    _rightTilt = NO;
    for (GCController *controller in GCController.controllers) {
        GCExtendedGamepad *gp = controller.extendedGamepad;
        if (gp == nil) continue;
        gp.buttonA.pressedChangedHandler = nil;
        gp.buttonB.pressedChangedHandler = nil;
        gp.buttonX.pressedChangedHandler = nil;
        gp.buttonY.pressedChangedHandler = nil;
        gp.leftShoulder.pressedChangedHandler = nil;
        gp.rightShoulder.pressedChangedHandler = nil;
        gp.leftTrigger.pressedChangedHandler = nil;
        gp.rightTrigger.pressedChangedHandler = nil;
        gp.buttonOptions.pressedChangedHandler = nil;
        gp.buttonMenu.pressedChangedHandler = nil;
        gp.buttonHome.pressedChangedHandler = nil;
        gp.leftThumbstickButton.pressedChangedHandler = nil;
        gp.rightThumbstickButton.pressedChangedHandler = nil;
        gp.dpad.up.pressedChangedHandler = nil;
        gp.dpad.down.pressedChangedHandler = nil;
        gp.dpad.left.pressedChangedHandler = nil;
        gp.dpad.right.pressedChangedHandler = nil;
        gp.leftThumbstick.valueChangedHandler = nil;
        gp.rightThumbstick.valueChangedHandler = nil;
    }
}

- (void)ame428_installOnGamepad:(GCExtendedGamepad *)gp {
    __weak typeof(self) weakSelf = self;
    gp.buttonA.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_A pressed:p];
    };
    gp.buttonB.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_B pressed:p];
    };
    gp.buttonX.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_X pressed:p];
    };
    gp.buttonY.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_Y pressed:p];
    };
    gp.leftShoulder.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_LEFT_BUMPER pressed:p];
    };
    gp.rightShoulder.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER pressed:p];
    };
    gp.leftTrigger.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_LEFT_TRIGGER pressed:p];
    };
    gp.rightTrigger.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_RIGHT_TRIGGER pressed:p];
    };
    gp.buttonOptions.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_BACK pressed:p];
    };
    gp.buttonMenu.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_START pressed:p];
    };
    gp.buttonHome.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_GUIDE pressed:p];
    };
    gp.leftThumbstickButton.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_LEFT_THUMB pressed:p];
    };
    gp.rightThumbstickButton.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_RIGHT_THUMB pressed:p];
    };
    gp.dpad.up.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_DPAD_UP pressed:p];
    };
    gp.dpad.down.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_DPAD_DOWN pressed:p];
    };
    gp.dpad.left.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_DPAD_LEFT pressed:p];
    };
    gp.dpad.right.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) {
        [weakSelf ame428_emit:GLFW_GAMEPAD_BUTTON_DPAD_RIGHT pressed:p];
    };
    // ★Task428：摇杆轴采集（leftThumbstick/rightThumbstick X/Y 超阈值；
    //   回滞双阈值防抖）——轴倾倒等效于对应摇杆键（L3/R3）的按下。
    gp.leftThumbstick.valueChangedHandler = ^(GCControllerDirectionPad *d, float x, float y) {
        [weakSelf ame428_tilt:GLFW_GAMEPAD_BUTTON_LEFT_THUMB x:x y:y];
    };
    gp.rightThumbstick.valueChangedHandler = ^(GCControllerDirectionPad *d, float x, float y) {
        [weakSelf ame428_tilt:GLFW_GAMEPAD_BUTTON_RIGHT_THUMB x:x y:y];
    };
}

- (void)ame428_emit:(int)buttonId pressed:(BOOL)pressed {
    if (self->_eventBlock == nil) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^b)(int, BOOL) = self->_eventBlock;
        if (b != nil) b(buttonId, pressed);
    });
}

- (void)ame428_tilt:(int)stickId x:(float)x y:(float)y {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL on = (fabsf(x) >= 0.75f || fabsf(y) >= 0.75f);
        BOOL off = (fabsf(x) < 0.6f && fabsf(y) < 0.6f);
        BOOL *state = (stickId == GLFW_GAMEPAD_BUTTON_LEFT_THUMB) ? &self->_leftTilt : &self->_rightTilt;
        if (on && !*state) {
            *state = YES;
            [self ame428_emit:stickId pressed:YES];
        } else if (off && *state) {
            *state = NO;
            [self ame428_emit:stickId pressed:NO];
        }
    });
}

@end

#pragma mark - ★Task428：私有视图二：映射行卡（连体组卡行 + 键位 chip + 行内联回退选择器）

// ★Task428：每行 = 控件名（fontTitleMedium）+ 副文本（触发键 · 发送键）+
//   行尾「当前映射的 GLFW 键名」chip（点按打开分组键位选择底部弹层）+
//   行点击进入「按下采集」（未连接手柄时展开行内联三组选择器）。
@interface AME428MappingRow : ZL2SettingRowBase
- (instancetype)initWithEntry:(NSMutableDictionary *)entry menu:(BOOL)menu;
- (NSMutableDictionary *)ame428_entry;
- (BOOL)ame428_menu;
- (void)ame428_reload;
- (BOOL)ame428_isExpanded;
- (void)ame428_setExpanded:(BOOL)expanded;
- (void)ame428_configureOnEnterCapture:(void (^)(void))onEnterCapture
                              onPickKey:(void (^)(void))onPickKey
                            onPickButton:(void (^)(int buttonId))onPickButton
                                onClear:(void (^)(void))onClear;
@end

@implementation AME428MappingRow {
    NSMutableDictionary *_entry;
    BOOL _menu;
    UIButton *_keyChip;
    UILabel *_chevronLabel;
    UIView *_expandBox;
    NSLayoutConstraint *_expandHeightC;
    UIStackView *_expandStack;
    NSMutableArray<ZL2M3FilterChip *> *_bindChips;
    void (^_onEnterCapture)(void);
    void (^_onPickKey)(void);
    void (^_onPickButton)(int);
    void (^_onClear)(void);
}

- (instancetype)initWithEntry:(NSMutableDictionary *)entry menu:(BOOL)menu {
    self = [super initWithTitle:@"" subtitle:@""];
    if (!self) return nil;
    _entry = entry;
    _menu = menu;
    _bindChips = [[NSMutableArray alloc] init];

    [self addSubview:self.ame_textStack];

    // ★Task428：行尾键位 chip（进入键位选择器的独立点击区）。
    _keyChip = [UIButton buttonWithType:UIButtonTypeCustom];
    _keyChip.translatesAutoresizingMaskIntoConstraints = NO;
    _keyChip.layer.cornerRadius = [ZL2Theme radiusS];
    _keyChip.backgroundColor = [ZL2Theme surfaceVariant];
    _keyChip.titleLabel.font = [ZL2Theme fontLabelMedium];
    _keyChip.titleLabel.adjustsFontSizeToFitWidth = YES;
    _keyChip.titleLabel.minimumScaleFactor = 0.7;
    [_keyChip setTitleColor:[ZL2Theme onSurface] forState:UIControlStateNormal];
    _keyChip.contentEdgeInsets = UIEdgeInsetsMake(7, 12, 7, 12);
    [_keyChip addTarget:self action:@selector(ame428_keyChipTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_keyChip];

    // ★Task428：行尾箭头（Unicode 字形，非 SF Symbol）——提示整行可点进采集。
    _chevronLabel = [[UILabel alloc] init];
    _chevronLabel.text = @"\u203A";
    _chevronLabel.font = [ZL2Theme fontTitleLarge];
    _chevronLabel.textColor = [ZL2Theme onSurfaceVariant];
    _chevronLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_chevronLabel];

    // ★Task428：行内联回退选择器容器（未连接手柄时展开；高度约束 0=收起）。
    _expandBox = [[UIView alloc] init];
    _expandBox.translatesAutoresizingMaskIntoConstraints = NO;
    _expandBox.hidden = YES;
    [self addSubview:_expandBox];

    _expandHeightC = [_expandBox.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [self.ame_textStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [self.ame_textStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
        [self.ame_textStack.trailingAnchor constraintLessThanOrEqualToAnchor:_keyChip.leadingAnchor constant:-8],

        [_keyChip.centerYAnchor constraintEqualToAnchor:self.ame_textStack.centerYAnchor],
        [_keyChip.trailingAnchor constraintEqualToAnchor:_chevronLabel.leadingAnchor constant:-6],
        [_keyChip.widthAnchor constraintLessThanOrEqualToConstant:150],

        [_chevronLabel.centerYAnchor constraintEqualToAnchor:self.ame_textStack.centerYAnchor],
        [_chevronLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],

        [_expandBox.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_expandBox.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_expandBox.topAnchor constraintEqualToAnchor:self.ame_textStack.bottomAnchor constant:8],
        [_expandBox.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
        _expandHeightC,

        [self.heightAnchor constraintGreaterThanOrEqualToConstant:[ZL2SettingRowBase minRowHeight]],
    ]];

    [self addTarget:self action:@selector(ame428_rowTapped) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (NSMutableDictionary *)ame428_entry { return _entry; }
- (BOOL)ame428_menu { return _menu; }

- (void)ame428_configureOnEnterCapture:(void (^)(void))onEnterCapture
                              onPickKey:(void (^)(void))onPickKey
                            onPickButton:(void (^)(int))onPickButton
                                onClear:(void (^)(void))onClear {
    _onEnterCapture = [onEnterCapture copy];
    _onPickKey = [onPickKey copy];
    _onPickButton = [onPickButton copy];
    _onClear = [onClear copy];
}

- (void)ame428_reload {
    int buttonId = [_entry[@"gamepad_button"] intValue];
    int keycode = [_entry[@"keycode"] intValue];
    self.title = ame428G_roleTitle(_entry[@"name"], ame428G_currentTypeString());
    NSString *keyName = ame428G_keyDisplay(keycode);
    self.subtitle = [NSString stringWithFormat:localize(@"ame428.gp.row.subtitle", nil),
                      ame428G_buttonName(buttonId), keyName];
    [_keyChip setTitle:keyName forState:UIControlStateNormal];
    // ★Task428：行内联选择器的当前绑定 chip 选中态同步。
    for (ZL2M3FilterChip *chip in _bindChips) {
        chip.selected = (chip.tag != 999 && chip.tag == buttonId);
    }
}

- (BOOL)ame428_isExpanded {
    return !_expandBox.hidden;
}

- (void)ame428_setExpanded:(BOOL)expanded {
    if (expanded == [self ame428_isExpanded]) return;
    if (expanded) {
        [self ame428_buildExpandContentOnce];
        _expandBox.hidden = NO;
        CGFloat width = self.bounds.size.width - 32;
        CGSize fit = [_expandStack systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                        withHorizontalFittingPriority:UILayoutPriorityRequired
                              verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
        _expandHeightC.constant = fit.height;
    } else {
        _expandHeightC.constant = 0;
        _expandBox.hidden = YES;
    }
    [UIView animateWithDuration:0.25 animations:^{
        [[self window] layoutIfNeeded];
    }];
}

// ★Task428：行内联回退选择器（三组：方向键 / 动作键 / 摇杆 + 恢复默认）。
- (void)ame428_buildExpandContentOnce {
    if (_expandStack != nil) return;
    _expandStack = [[UIStackView alloc] init];
    _expandStack.axis = UILayoutConstraintAxisVertical;
    _expandStack.alignment = UIStackViewAlignmentFill;
    _expandStack.spacing = 6;
    _expandStack.translatesAutoresizingMaskIntoConstraints = NO;

    // 组 1：方向键
    [_expandStack addArrangedSubview:[self ame428_groupLabel:localize(@"ame428.gp.chip.dpad", nil)]];
    [_expandStack addArrangedSubview:[self ame428_chipLine:@[
        @(GLFW_GAMEPAD_BUTTON_DPAD_UP), @(GLFW_GAMEPAD_BUTTON_DPAD_DOWN),
        @(GLFW_GAMEPAD_BUTTON_DPAD_LEFT), @(GLFW_GAMEPAD_BUTTON_DPAD_RIGHT)]]];
    // 组 2：动作键
    [_expandStack addArrangedSubview:[self ame428_groupLabel:localize(@"ame428.gp.chip.action", nil)]];
    [_expandStack addArrangedSubview:[self ame428_chipLine:@[
        @(GLFW_GAMEPAD_BUTTON_A), @(GLFW_GAMEPAD_BUTTON_B),
        @(GLFW_GAMEPAD_BUTTON_X), @(GLFW_GAMEPAD_BUTTON_Y)]]];
    [_expandStack addArrangedSubview:[self ame428_chipLine:@[
        @(GLFW_GAMEPAD_BUTTON_LEFT_BUMPER), @(GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER),
        @(GLFW_GAMEPAD_BUTTON_LEFT_TRIGGER), @(GLFW_GAMEPAD_BUTTON_RIGHT_TRIGGER)]]];
    [_expandStack addArrangedSubview:[self ame428_chipLine:@[
        @(GLFW_GAMEPAD_BUTTON_BACK), @(GLFW_GAMEPAD_BUTTON_START), @(999)]]];
    // 组 3：摇杆
    [_expandStack addArrangedSubview:[self ame428_groupLabel:localize(@"ame428.gp.chip.stick", nil)]];
    [_expandStack addArrangedSubview:[self ame428_chipLine:@[
        @(GLFW_GAMEPAD_BUTTON_LEFT_THUMB), @(GLFW_GAMEPAD_BUTTON_RIGHT_THUMB)]]];

    [_expandBox addSubview:_expandStack];
    [NSLayoutConstraint activateConstraints:@[
        [_expandStack.topAnchor constraintEqualToAnchor:_expandBox.topAnchor],
        [_expandStack.bottomAnchor constraintEqualToAnchor:_expandBox.bottomAnchor],
        [_expandStack.leadingAnchor constraintEqualToAnchor:_expandBox.leadingAnchor],
        [_expandStack.trailingAnchor constraintEqualToAnchor:_expandBox.trailingAnchor],
    ]];
}

- (UILabel *)ame428_groupLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [ZL2Theme fontLabelMedium];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (UIStackView *)ame428_chipLine:(NSArray<NSNumber *> *)ids {
    UIStackView *line = [[UIStackView alloc] init];
    line.axis = UILayoutConstraintAxisHorizontal;
    line.alignment = UIStackViewAlignmentCenter;
    line.spacing = 8;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSNumber *pid in ids) {
        int v = pid.intValue;
        NSString *title = (v == 999) ? localize(@"ame428.gp.restore", nil) : ame428G_buttonName(v);
        ZL2M3FilterChip *chip = [[ZL2M3FilterChip alloc] initWithText:title];
        chip.tag = v;
        [chip addTarget:self action:@selector(ame428_expandChipTapped:)
               forControlEvents:UIControlEventTouchUpInside];
        [_bindChips addObject:chip];
        [line addArrangedSubview:chip];
    }
    return line;
}

- (void)ame428_expandChipTapped:(ZL2M3FilterChip *)chip {
    [self ame428_setExpanded:NO];
    if (chip.tag == 999) {
        if (_onClear != nil) _onClear();
    } else if (_onPickButton != nil) {
        _onPickButton(chip.tag);
    }
}

- (void)ame428_rowTapped {
    if (_onEnterCapture != nil) _onEnterCapture();
}

- (void)ame428_keyChipTapped {
    if (_onPickKey != nil) _onPickKey();
}

@end

#pragma mark - ★Task428：私有视图三：全屏「按下采集」向导

// ★Task428：ZL2 GamepadRemapperUI 口径的单控件采集页。时序：
//   按下 → 记候选 + 重置 700ms 防抖计时（窗内重复事件忽略）→ 候选提前
//   释放则取消 → 计时到期且候选仍按住 = 持续过防抖窗 → 采集成立（成功
//   高亮 + 0.45s 后自动dismiss，回调宿主页换绑刷新该行）。
//   指南键（系统保留）仅参与实时高亮，不参与采集。
@interface AME428CaptureViewController : UIViewController
- (void)ame428_configureWithRole:(NSString *)role
                    currentTrigger:(NSString *)trigger
                      targetButton:(int)targetId
                           badges:(NSDictionary<NSNumber *, NSString *> *)badges
                       onCaptured:(void (^)(int buttonId))onCaptured
                        onCleared:(void (^)(void))onCleared;
@end

@implementation AME428CaptureViewController {
    NSString *_roleName;
    NSString *_triggerName;
    int _targetButtonId;
    NSDictionary<NSNumber *, NSString *> *_badges;
    void (^_onCaptured)(int);
    void (^_onCleared)(void);
    AME428PadBridge *_bridge;
    NSMutableSet<NSNumber *> *_activeIds;
    int _candidateId;
    NSTimer *_debounceTimer;
    BOOL _finished;
    AME428SchematicView *_schematic;
    UILabel *_titleLabel;
    UILabel *_promptLabel;
    UILabel *_currentLabel;
    UILabel *_holdHintLabel;
    UILabel *_stickHintLabel;
    UILabel *_successLabel;
    UILabel *_waitLabel;
    UIButton *_cancelButton;
    UIButton *_clearButton;
    id _connectObs;
    id _disconnectObs;
}

- (void)ame428_configureWithRole:(NSString *)role
                    currentTrigger:(NSString *)trigger
                      targetButton:(int)targetId
                           badges:(NSDictionary<NSNumber *, NSString *> *)badges
                       onCaptured:(void (^)(int))onCaptured
                        onCleared:(void (^)(void))onCleared {
    _roleName = [role copy];
    _triggerName = [trigger copy];
    _targetButtonId = targetId;
    _badges = [badges copy];
    _onCaptured = [onCaptured copy];
    _onCleared = [onCleared copy];
    self.modalPresentationStyle = UIModalPresentationFullScreen;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];
    _activeIds = [[NSMutableSet alloc] init];
    _candidateId = -1;
    [self ame428_buildUI];

    __weak typeof(self) weakSelf = self;
    _connectObs = [[NSNotificationCenter defaultCenter]
        addObserverForName:GCControllerDidConnectNotification object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *n) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf ame428_reinstallBridge];
        }];
    _disconnectObs = [[NSNotificationCenter defaultCenter]
        addObserverForName:GCControllerDidDisconnectNotification object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *n) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (strongSelf->_waitLabel != nil) {
                strongSelf->_waitLabel.text = localize(@"ame428.gp.capture.waiting", nil);
            }
        }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_bridge == nil) _bridge = [[AME428PadBridge alloc] init];
    [self ame428_reinstallBridge];
    [_schematic ame428_setTarget:_targetButtonId];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_bridge teardown];
    [_schematic ame428_setTarget:-1];
    if (_debounceTimer != nil) {
        [_debounceTimer invalidate];
        _debounceTimer = nil;
    }
    _candidateId = -1;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:_connectObs];
    [[NSNotificationCenter defaultCenter] removeObserver:_disconnectObs];
    if (_bridge != nil) [_bridge teardown];
}

- (void)ame428_reinstallBridge {
    if (_bridge == nil) return;
    __weak typeof(self) weakSelf = self;
    [_bridge installWithEventBlock:^(int buttonId, BOOL pressed) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf ame428_captureEvent:buttonId pressed:pressed];
    }];
}

- (void)ame428_buildUI {
    UIView *v = self.view;

    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    _cancelButton.titleLabel.font = [ZL2Theme fontLabelLarge];
    [_cancelButton setTitle:localize(@"Cancel", nil) forState:UIControlStateNormal];
    [_cancelButton addTarget:self action:@selector(ame428_cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:_cancelButton];

    _clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    _clearButton.titleLabel.font = [ZL2Theme fontLabelLarge];
    [_clearButton setTitle:localize(@"ame428.gp.clear", nil) forState:UIControlStateNormal];
    [_clearButton setTitleColor:[ZL2Theme error] forState:UIControlStateNormal];
    [_clearButton addTarget:self action:@selector(ame428_clearTapped) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:_clearButton];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = localize(@"ame428.gp.capture.title", nil);
    _titleLabel.font = [ZL2Theme fontTitleMedium];
    _titleLabel.textColor = [ZL2Theme onSurface];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:_titleLabel];

    _schematic = [[AME428SchematicView alloc] init];
    _schematic.translatesAutoresizingMaskIntoConstraints = NO;
    [_schematic ame428_applyBadges:_badges];
    [v addSubview:_schematic];

    _promptLabel = [[UILabel alloc] init];
    _promptLabel.text = [NSString stringWithFormat:localize(@"ame428.gp.capture.prompt", nil), _roleName ?: @""];
    _promptLabel.font = [ZL2Theme fontTitleMedium];
    _promptLabel.textColor = [ZL2Theme onSurface];
    _promptLabel.textAlignment = NSTextAlignmentCenter;
    _promptLabel.numberOfLines = 2;
    _promptLabel.adjustsFontSizeToFitWidth = YES;
    _promptLabel.minimumScaleFactor = 0.8;
    _promptLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:_promptLabel];

    _currentLabel = [[UILabel alloc] init];
    _currentLabel.text = [NSString stringWithFormat:localize(@"ame428.gp.key.current", nil), _triggerName ?: @""];
    _currentLabel.font = [ZL2Theme fontLabelMedium];
    _currentLabel.textColor = [ZL2Theme onSurfaceVariant];
    _currentLabel.textAlignment = NSTextAlignmentCenter;
    _currentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:_currentLabel];

    _holdHintLabel = [[UILabel alloc] init];
    _holdHintLabel.text = localize(@"ame428.gp.capture.hold", nil);
    _holdHintLabel.font = [ZL2Theme fontBodyMedium];
    _holdHintLabel.textColor = [ZL2Theme onSurfaceVariant];
    _holdHintLabel.textAlignment = NSTextAlignmentCenter;
    _holdHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:_holdHintLabel];

    _stickHintLabel = [[UILabel alloc] init];
    _stickHintLabel.text = localize(@"ame428.gp.capture.stick", nil);
    _stickHintLabel.font = [ZL2Theme fontBodyMedium];
    _stickHintLabel.textColor = [ZL2Theme onSurfaceVariant];
    _stickHintLabel.textAlignment = NSTextAlignmentCenter;
    _stickHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:_stickHintLabel];

    _successLabel = [[UILabel alloc] init];
    _successLabel.font = [ZL2Theme fontTitleMedium];
    _successLabel.textColor = [ZL2Theme primary];
    _successLabel.textAlignment = NSTextAlignmentCenter;
    _successLabel.hidden = YES;
    _successLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:_successLabel];

    _waitLabel = [[UILabel alloc] init];
    _waitLabel.text = localize(@"ame428.gp.capture.waiting", nil);
    _waitLabel.font = [ZL2Theme fontLabelMedium];
    _waitLabel.textColor = [ZL2Theme onSurfaceVariant];
    _waitLabel.textAlignment = NSTextAlignmentCenter;
    _waitLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:_waitLabel];

    UILayoutGuide *safe = v.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_cancelButton.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_cancelButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [_cancelButton.heightAnchor constraintEqualToConstant:36],

        [_clearButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [_clearButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [_clearButton.heightAnchor constraintEqualToConstant:36],

        [_titleLabel.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_cancelButton.centerYAnchor],
        [_titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_cancelButton.trailingAnchor constant:8],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_clearButton.leadingAnchor constant:-8],

        [_schematic.topAnchor constraintEqualToAnchor:_cancelButton.bottomAnchor constant:28],
        [_schematic.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [_schematic.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [NSLayoutConstraint constraintWithItem:_schematic attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual
            toItem:_schematic attribute:NSLayoutAttributeHeight multiplier:280.0 / 148.0 constant:0],
        [_schematic.widthAnchor constraintLessThanOrEqualToConstant:420],

        [_promptLabel.topAnchor constraintEqualToAnchor:_schematic.bottomAnchor constant:24],
        [_promptLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [_promptLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],

        [_currentLabel.topAnchor constraintEqualToAnchor:_promptLabel.bottomAnchor constant:8],
        [_currentLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [_currentLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],

        [_holdHintLabel.topAnchor constraintEqualToAnchor:_currentLabel.bottomAnchor constant:16],
        [_holdHintLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [_holdHintLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],

        [_stickHintLabel.topAnchor constraintEqualToAnchor:_holdHintLabel.bottomAnchor constant:6],
        [_stickHintLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [_stickHintLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],

        [_successLabel.topAnchor constraintEqualToAnchor:_stickHintLabel.bottomAnchor constant:18],
        [_successLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [_successLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],

        [_waitLabel.topAnchor constraintEqualToAnchor:_successLabel.bottomAnchor constant:6],
        [_waitLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [_waitLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [_waitLabel.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-24],
    ]];
}

- (void)ame428_captureEvent:(int)buttonId pressed:(BOOL)pressed {
    // ★Task428：指南键为系统保留（GC 悬浮层），仅实时高亮、不参与采集。
    if (buttonId == GLFW_GAMEPAD_BUTTON_GUIDE) {
        [_schematic ame428_setPressed:pressed forButton:buttonId];
        return;
    }
    [_schematic ame428_setPressed:pressed forButton:buttonId];
    if (_finished) return;
    if (pressed) {
        [_activeIds addObject:@(buttonId)];
        if (_candidateId == buttonId) return;  // ★防抖：700ms 窗内重复事件忽略
        _candidateId = buttonId;
        if (_debounceTimer != nil) {
            [_debounceTimer invalidate];
            _debounceTimer = nil;
        }
        _debounceTimer = [NSTimer scheduledTimerWithTimeInterval:0.7
                                                         target:self
                                                       selector:@selector(ame428_debounceFire:)
                                                       userInfo:nil repeats:NO];
    } else {
        [_activeIds removeObject:@(buttonId)];
        if (_candidateId == buttonId) {  // ★未持续过防抖窗：候选作废
            [_debounceTimer invalidate];
            _debounceTimer = nil;
            _candidateId = -1;
        }
    }
}

- (void)ame428_debounceFire:(NSTimer *)timer {
    _debounceTimer = nil;
    int pid = _candidateId;
    _candidateId = -1;
    if (pid < 0) return;
    if (![_activeIds containsObject:@(pid)]) return;  // ★松开早于防抖窗：不作数
    [self ame428_confirm:pid];
}

- (void)ame428_confirm:(int)buttonId {
    _finished = YES;
    if (_debounceTimer != nil) {
        [_debounceTimer invalidate];
        _debounceTimer = nil;
    }
    // ★Task428：采集成功高亮反馈（示意图 primary 填充 + 成功文案，0.45s 自动返回）。
    [_schematic ame428_setSuccess:buttonId];
    _successLabel.text = [NSString stringWithFormat:localize(@"ame428.gp.capture.success", nil),
                           ame428G_buttonName(buttonId)];
    _successLabel.hidden = NO;
    _waitLabel.hidden = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self dismissViewControllerAnimated:YES completion:^{
            if (self->_onCaptured != nil) self->_onCaptured(buttonId);
        }];
    });
}

- (void)ame428_cancelTapped {
    _finished = YES;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)ame428_clearTapped {
    _finished = YES;
    [self dismissViewControllerAnimated:YES completion:^{
        if (self->_onCleared != nil) self->_onCleared();
    }];
}

@end

#pragma mark - ★Task428：页面本体（ZL2SettingPage 子类）

@interface LauncherPrefContCfgViewController () <UIPopoverPresentationControllerDelegate>
{
    NSMutableDictionary *_currentMappings;
    NSString *_currentFileName;
    BOOL _dirty;
    NSInteger _filterCategory;
    AME428SchematicView *_schematic;
    UILabel *_statusLabel;
    UILabel *_liveHintLabel;
    ZL2SettingCardGroup *_gameGroup;
    ZL2SettingCardGroup *_menuGroup;
    NSMutableArray<AME428MappingRow *> *_gameRows;
    NSMutableArray<AME428MappingRow *> *_menuRows;
    NSMutableArray<ZL2M3FilterChip *> *_filterChips;
    AME428PadBridge *_bridge;
    id _connectObs;
    id _disconnectObs;
    ZL2SettingRowAction *_fileRow;
    ZL2SettingRowEnum *_typeRow;
    NSMutableDictionary *_sheetEntry;
    UIView *_sheetContentView;
}
@end

@implementation LauncherPrefContCfgViewController

#pragma mark 生命周期

- (void)viewDidLoad {
    // ★Task428：标题与数据先就绪，再走基类（基类末尾回调 ame_buildGroups，
    //   组卡构建依赖 _currentMappings；页首大标题读取 self.title）。
    if (self.title.length == 0) self.title = localize(@"preference.title.default_gamepad_ctrl", nil);
    ame428G_ensureKeyTables();
    [self loadGamepadConfigurationFile];
    _dirty = NO;
    _filterCategory = 0;
    _filterChips = [[NSMutableArray alloc] init];
    [super viewDidLoad];
    // ★Task428：初次构建后填充两列表行（此后由 Chip 过滤重建）。
    [self ame428_rebuildMappingGroups];

    // ★Task428：导航项——左「保存」右「关闭」（与旧页同语义；旧页 close
    //   即本页 exitButtonSelector，dirty 时走保存告警弹窗）。
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:localize(@"custom_controls.control_menu.save", nil)
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(actionMenuSave)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:localize(@"ame428.gp.close", nil)
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(exitButtonSelector)];

    __weak typeof(self) weakSelf = self;
    _connectObs = [[NSNotificationCenter defaultCenter]
        addObserverForName:GCControllerDidConnectNotification object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *n) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            // ★Task428：页面在屏期间新连手柄——实时高亮桥即时挂载（无需离开重进）。
            [strongSelf ame428_startLiveHighlight];
            [strongSelf ame428_refreshStatus];
        }];
    _disconnectObs = [[NSNotificationCenter defaultCenter]
        addObserverForName:GCControllerDidDisconnectNotification object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *n) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf ame428_refreshStatus];
        }];
    [self ame428_refreshStatus];
    [self ame428_refreshFileRow];
    [self ame428_refreshSchematic];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self ame428_startLiveHighlight];
    [self ame428_refreshStatus];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (_bridge != nil) [_bridge teardown];
    // ★Task428：清掉实时高亮残留（避免离开页面后示意图定格在按下态）。
    for (NSNumber *pid in ame428G_buttonInfoTable()) {
        if (_schematic != nil) [_schematic ame428_setPressed:NO forButton:pid.intValue];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:_connectObs];
    [[NSNotificationCenter defaultCenter] removeObserver:_disconnectObs];
    if (_bridge != nil) [_bridge teardown];
}

#pragma mark 数据加载（既有语义：文件、mouse_ 过滤、保存名默认值）

- (void)loadGamepadConfigurationFile {
    NSString *gamepadPath = [NSString stringWithFormat:@"%s/controlmap/gamepads/%@",
                              getenv("POJAV_HOME"), getPrefObject(@"control.default_gamepad_ctrl")];
    _currentMappings = parseJSONFromFile(gamepadPath);
    if (_currentMappings == nil) _currentMappings = [NSMutableDictionary dictionary];
    _currentFileName = [getPrefObject(@"control.default_ctrl") stringByDeletingPathExtension];
    // ★Task428：沿用旧页行为——mouse_ 前缀条目不进编辑列表（保存时随之
    //   落盘消失，与旧页 filterUsingPredicate 语义一致）。
    NSPredicate *filterPredicate = [NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *dict) {
        return ![obj[@"name"] hasPrefix:@"mouse_"];
    }];
    [_currentMappings[@"mGameMappingList"] filterUsingPredicate:filterPredicate];
    [_currentMappings[@"mMenuMappingList"] filterUsingPredicate:filterPredicate];
    if (_currentMappings[@"mGameMappingList"] == nil) {
        _currentMappings[@"mGameMappingList"] = [NSMutableArray array];
    }
    if (_currentMappings[@"mMenuMappingList"] == nil) {
        _currentMappings[@"mMenuMappingList"] = [NSMutableArray array];
    }
}

#pragma mark 组卡装配（ame_buildGroups 覆写）

- (void)ame_buildGroups {
    [self ame428_buildSchematicGroup];
    [self ame428_buildFileGroup];
    [self ame428_buildFilterChips];
    [self ame428_buildMappingSection:NO
                          headerKey:@"controller_configurator.section.game_mappings"
                          footerKey:@"controller_configurator.section.footer.game_mappings"];
    [self ame428_buildMappingSection:YES
                          headerKey:@"controller_configurator.section.menu_mappings"
                          footerKey:@"controller_configurator.section.footer.menu_mappings"];
}

// ★Task428：区头标签（ZL2 关于屏同款：fontLabelLarge + onSurfaceVariant）。
- (void)ame428_addSectionHeader:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [ZL2Theme fontLabelLarge];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *prev = self.groupsStack.arrangedSubviews.lastObject;
    [self.groupsStack addArrangedSubview:label];
    if (prev != nil) [self.groupsStack setCustomSpacing:12 afterView:prev];
    [self.groupsStack setCustomSpacing:4 afterView:label];
}

// ★Task428：组脚注（既有 game/menu footer 键；13pt onSurfaceVariant 多行）。
- (void)ame428_addFooterLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont systemFontOfSize:13];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.numberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *prev = self.groupsStack.arrangedSubviews.lastObject;
    [self.groupsStack addArrangedSubview:label];
    if (prev != nil) [self.groupsStack setCustomSpacing:4 afterView:prev];
    [self.groupsStack setCustomSpacing:12 afterView:label];
}

// ★Task428：示意图组卡（第二层可视化：Xbox 布局 + 连接状态 + 演示提示）。
- (void)ame428_buildSchematicGroup {
    [self ame428_addSectionHeader:localize(@"ame428.gp.schematic.header", nil)];

    ZL2SettingCardGroup *group = [[ZL2SettingCardGroup alloc] init];
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    _schematic = [[AME428SchematicView alloc] init];
    _schematic.translatesAutoresizingMaskIntoConstraints = NO;

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.font = [ZL2Theme fontLabelMedium];
    _statusLabel.textColor = [ZL2Theme onSurfaceVariant];
    _statusLabel.numberOfLines = 2;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _liveHintLabel = [[UILabel alloc] init];
    _liveHintLabel.text = localize(@"ame428.gp.livehint", nil);
    _liveHintLabel.font = [UIFont systemFontOfSize:13];
    _liveHintLabel.textColor = [ZL2Theme onSurfaceVariant];
    _liveHintLabel.numberOfLines = 0;
    _liveHintLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [card addSubview:_schematic];
    [card addSubview:_statusLabel];
    [card addSubview:_liveHintLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_schematic.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [_schematic.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [_schematic.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [NSLayoutConstraint constraintWithItem:_schematic attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual
            toItem:_schematic attribute:NSLayoutAttributeHeight multiplier:280.0 / 148.0 constant:0],

        [_statusLabel.topAnchor constraintEqualToAnchor:_schematic.bottomAnchor constant:12],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [_liveHintLabel.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:4],
        [_liveHintLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [_liveHintLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [_liveHintLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
    ]];
    [group ame_addRow:card];
    [self ame_addGroup:group];
}

// ★Task428：映射文件 + 手柄类型组卡（偏好键与旧页逐位一致）。
- (void)ame428_buildFileGroup {
    [self ame428_addSectionHeader:localize(@"ame428.gp.file.section", nil)];
    __weak typeof(self) weakSelf = self;

    ZL2SettingCardGroup *group = [[ZL2SettingCardGroup alloc] init];

    _fileRow = [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
    _fileRow.title = localize(@"ame428.gp.file.title", nil);
    _fileRow.onTap = ^{
        [weakSelf actionMenuLoad];
    };

    NSArray<NSString *> *typeKeys = @[@"xbox", @"playstation", @"nintendo"];
    NSArray<NSString *> *typeNames = @[
        localize(@"controller_configurator.title.type.xbox", nil),
        localize(@"controller_configurator.title.type.playstation", nil),
        localize(@"controller_configurator.title.type.nintendo", nil),
    ];
    _typeRow = [[ZL2SettingRowEnum alloc] initWithTitle:@"" subtitle:nil options:typeNames];
    _typeRow.title = localize(@"ame369.setpg.gamepad_type", @"手柄类型");
    _typeRow.subtitle = localize(@"ame369.setpg.gamepad_type.subtitle",
                                  @"面键图标风格；选任天堂即交换 A/B、X/Y 键面（Switch 布局）");
    NSString *currentType = getPrefObject(@"control.controller_type");
    if (![currentType isKindOfClass:[NSString class]]) currentType = @"xbox";
    [_typeRow ame_reloadSelectedIndex:(NSInteger)[typeKeys indexOfObject:currentType]];
    _typeRow.onSelect = ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= typeKeys.count) return;
        // ★Task428：与旧页 didSelectRow 同一写法（Task311 语义）。
        NSString *key = typeKeys[index];
        setPrefObject(@"control.controller_type", key);
        setPrefObject(@"control.nintendo_layout", [key isEqualToString:@"nintendo"] ? @YES : @NO);
        [weakSelf ame428_refreshRows];
    };

    [group ame_addRows:@[_fileRow, _typeRow]];
    [self ame_addGroup:group];
}

// ★Task428：Chip 过滤行（全部/动作键/方向键/摇杆——ZL2M3Kit 既有组件）。
- (void)ame428_buildFilterChips {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    if (_filterChips == nil) _filterChips = [[NSMutableArray alloc] init];
    NSArray<NSString *> *chipKeys = @[
        @"ame428.gp.chip.all", @"ame428.gp.chip.action",
        @"ame428.gp.chip.dpad", @"ame428.gp.chip.stick",
    ];
    for (NSUInteger i = 0; i < chipKeys.count; i++) {
        ZL2M3FilterChip *chip = [[ZL2M3FilterChip alloc] initWithText:localize(chipKeys[i], nil)];
        chip.tag = (NSInteger)i;
        chip.selected = (_filterCategory == (NSInteger)i);
        [chip addTarget:self action:@selector(ame428_chipTapped:)
               forControlEvents:UIControlEventTouchUpInside];
        [_filterChips addObject:chip];
        [row addArrangedSubview:chip];
    }
    UIView *prev = self.groupsStack.arrangedSubviews.lastObject;
    [self.groupsStack addArrangedSubview:row];
    if (prev != nil) [self.groupsStack setCustomSpacing:12 afterView:prev];
    [self.groupsStack setCustomSpacing:12 afterView:row];
}

- (void)ame428_chipTapped:(ZL2M3FilterChip *)chip {
    if (_filterCategory == chip.tag) return;
    _filterCategory = chip.tag;
    for (ZL2M3FilterChip *c in _filterChips) {
        c.selected = (c.tag == _filterCategory);
    }
    [self ame428_rebuildMappingGroups];
}

// ★Task428：游戏/菜单映射连体组卡（行 = 控件角色，见 AME428MappingRow）。
- (void)ame428_buildMappingSection:(BOOL)menu headerKey:(NSString *)headerKey footerKey:(NSString *)footerKey {
    [self ame428_addSectionHeader:localize(headerKey, nil)];
    ZL2SettingCardGroup *group = [[ZL2SettingCardGroup alloc] init];
    if (menu) {
        _menuGroup = group;
        _menuRows = [[NSMutableArray alloc] init];
    } else {
        _gameGroup = group;
        _gameRows = [[NSMutableArray alloc] init];
    }
    [self ame_addGroup:group];
    [self ame428_addFooterLabel:localize(footerKey, nil)];
}

- (void)ame428_rebuildMappingGroups {
    if (_gameGroup == nil || _menuGroup == nil) return;
    [_gameGroup ame_removeAllRows];
    [_menuGroup ame_removeAllRows];
    [_gameRows removeAllObjects];
    [_menuRows removeAllObjects];
    [self ame428_fillGroup:_gameGroup rows:_gameRows list:_currentMappings[@"mGameMappingList"] menu:NO];
    [self ame428_fillGroup:_menuGroup rows:_menuRows list:_currentMappings[@"mMenuMappingList"] menu:YES];
}

- (void)ame428_fillGroup:(ZL2SettingCardGroup *)group
                    rows:(NSMutableArray<AME428MappingRow *> *)rows
                    list:(NSArray *)list
                    menu:(BOOL)menu {
    NSMutableArray<AME428MappingRow *> *built = [[NSMutableArray alloc] init];
    for (NSMutableDictionary *entry in list) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        if (_filterCategory != 0 && ame428G_categoryOfRole(entry[@"name"]) != _filterCategory) continue;
        [built addObject:[self ame428_rowForEntry:entry menu:menu]];
    }
    if (built.count == 0) {
        // ★Task428：空态行（只读展示行：onTap nil 无 chevron）。
        ZL2SettingRowAction *emptyRow = [[ZL2SettingRowAction alloc] initWithTitle:@"" subtitle:nil];
        emptyRow.title = localize(@"ame428.gp.filter.empty", nil);
        [group ame_addRow:emptyRow];
        return;
    }
    [rows addObjectsFromArray:built];
    [group ame_addRows:built];
}

- (AME428MappingRow *)ame428_rowForEntry:(NSMutableDictionary *)entry menu:(BOOL)menu {
    __weak typeof(self) weakSelf = self;
    AME428MappingRow *row = [[AME428MappingRow alloc] initWithEntry:entry menu:menu];
    __weak AME428MappingRow *wrow = row;
    [row ame428_configureOnEnterCapture:^{
        [weakSelf ame428_rowTapped:wrow];
    } onPickKey:^{
        [weakSelf ame428_showKeySheetForEntry:entry menu:menu];
    } onPickButton:^(int buttonId) {
        [wrow ame428_setExpanded:NO];
        [weakSelf ame428_bindEntry:entry menu:menu toButton:buttonId];
    } onClear:^{
        [weakSelf ame428_clearEntry:entry menu:menu];
    }];
    [row ame428_reload];
    return row;
}

#pragma mark 行点击：按下采集 / 行内联回退

- (void)ame428_rowTapped:(AME428MappingRow *)row {
    if (row == nil) return;
    NSMutableDictionary *entry = [row ame428_entry];
    BOOL menu = [row ame428_menu];
    if ([self ame428_controllerAvailable]) {
        [self ame428_presentCaptureForEntry:entry menu:menu];
    } else {
        // ★Task428：未连接手柄回退——展开行内联三组选择器（同时收起其他行）。
        BOOL expand = ![row ame428_isExpanded];
        for (AME428MappingRow *other in _gameRows) {
            if (other != row && [other ame428_isExpanded]) [other ame428_setExpanded:NO];
        }
        for (AME428MappingRow *other in _menuRows) {
            if (other != row && [other ame428_isExpanded]) [other ame428_setExpanded:NO];
        }
        [row ame428_setExpanded:expand];
    }
}

- (BOOL)ame428_controllerAvailable {
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad != nil) return YES;
    }
    return NO;
}

- (void)ame428_presentCaptureForEntry:(NSMutableDictionary *)entry menu:(BOOL)menu {
    int currentId = [entry[@"gamepad_button"] intValue];
    AME428CaptureViewController *cap = [[AME428CaptureViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    [cap ame428_configureWithRole:ame428G_roleTitle(entry[@"name"], ame428G_currentTypeString())
                      currentTrigger:ame428G_buttonName(currentId)
                        targetButton:currentId
                             badges:[self ame428_gameBadges]
                         onCaptured:^(int buttonId) {
                             [weakSelf ame428_bindEntry:entry menu:menu toButton:buttonId];
                         }
                          onCleared:^{
                             [weakSelf ame428_clearEntry:entry menu:menu];
                         }];
    [self presentViewController:cap animated:YES completion:nil];
}

#pragma mark 数据操作（换绑交换 / 清除回默认 / 换发送键）

// ★Task428：把某物理键换绑到该控件行——若该物理键已被同列表其他行占用，
//   两者交换（无重复 gamepad_button，消费方 int 匹配语义不变）。
- (void)ame428_bindEntry:(NSMutableDictionary *)entry menu:(BOOL)menu toButton:(int)buttonId {
    if (entry == nil) return;
    NSMutableArray *list = _currentMappings[menu ? @"mMenuMappingList" : @"mGameMappingList"];
    if (list == nil) return;
    int oldId = [entry[@"gamepad_button"] intValue];
    if (oldId != buttonId) {
        for (NSMutableDictionary *other in list) {
            if (other == entry) continue;
            if (![other isKindOfClass:[NSDictionary class]]) continue;
            if ([other[@"gamepad_button"] intValue] == buttonId) {
                other[@"gamepad_button"] = @(oldId);
            }
        }
        entry[@"gamepad_button"] = @(buttonId);
    }
    [self ame428_afterMutation];
}

// ★Task428：清除映射 = 该行恢复对应列表（游戏/菜单）的出厂默认绑定。
- (void)ame428_clearEntry:(NSMutableDictionary *)entry menu:(BOOL)menu {
    if (entry == nil) return;
    NSDictionary *stock = ame428G_stockTable(menu)[entry[@"name"]];
    if (stock != nil) {
        entry[@"gamepad_button"] = stock[@"button"];
        entry[@"keycode"] = stock[@"keycode"];
    }
    [self ame428_afterMutation];
}

- (void)ame428_setKeycode:(int)code onEntry:(NSMutableDictionary *)entry {
    if (entry == nil) return;
    entry[@"keycode"] = @(code);
    [self ame428_afterMutation];
}

- (void)ame428_afterMutation {
    _dirty = YES;
    [self ame428_refreshRows];
    [self ame428_refreshSchematic];
    [self ame428_refreshFileRow];
}

- (void)ame428_refreshRows {
    for (AME428MappingRow *row in _gameRows) [row ame428_reload];
    for (AME428MappingRow *row in _menuRows) [row ame428_reload];
}

// ★Task428：示意图角标取自游戏映射列表（消费口径与 isGrabbing 主表一致）。
- (NSDictionary<NSNumber *, NSString *> *)ame428_gameBadges {
    NSMutableDictionary<NSNumber *, NSString *> *badges = [[NSMutableDictionary alloc] init];
    for (NSMutableDictionary *entry in _currentMappings[@"mGameMappingList"]) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        int buttonId = [entry[@"gamepad_button"] intValue];
        int keycode = [entry[@"keycode"] intValue];
        if (keycode == 0) continue;  // 未映射（GLFW_KEY_UNKNOWN）不亮角标
        badges[@(buttonId)] = ame428G_keyShort(ame428G_keyDisplay(keycode));
    }
    return badges;
}

- (void)ame428_refreshSchematic {
    if (_schematic == nil) return;
    [_schematic ame428_applyBadges:[self ame428_gameBadges]];
}

- (void)ame428_refreshStatus {
    if (_statusLabel == nil) return;
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad != nil) {
            NSString *name = controller.vendorName ?: @"controller";
            _statusLabel.text = [NSString stringWithFormat:localize(@"ame428.gp.status.connected", nil), name];
            return;
        }
    }
    _statusLabel.text = localize(@"ame428.gp.status.none", nil);
}

- (void)ame428_refreshFileRow {
    if (_fileRow == nil) return;
    NSString *fileName = getPrefObject(@"control.default_gamepad_ctrl");
    if (![fileName isKindOfClass:[NSString class]]) fileName = @"default.json";
    _fileRow.detailText = fileName;
    _fileRow.subtitle = _dirty ? localize(@"ame428.gp.file.dirty", nil)
                               : localize(@"ame428.gp.file.hint", nil);
}

#pragma mark 实时高亮（第二层：演示即映射）

- (void)ame428_startLiveHighlight {
    if (_bridge == nil) _bridge = [[AME428PadBridge alloc] init];
    __weak typeof(self) weakSelf = self;
    [_bridge installWithEventBlock:^(int buttonId, BOOL pressed) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf->_schematic != nil) {
            [strongSelf->_schematic ame428_setPressed:pressed forButton:buttonId];
        }
    }];
}

#pragma mark 键位选择底部弹层（keycode 侧编辑；长列表的分组化替代）

- (void)ame428_showKeySheetForEntry:(NSMutableDictionary *)entry menu:(BOOL)menu {
    ame428G_ensureKeyTables();
    _sheetEntry = entry;
    int currentCode = [entry[@"keycode"] intValue];

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    _sheetContentView = content;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = localize(@"ame428.gp.key.sheet", nil);
    titleLabel.font = [ZL2Theme fontTitleMedium];
    titleLabel.textColor = [ZL2Theme onSurface];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:titleLabel];

    UILabel *currentLabel = [[UILabel alloc] init];
    currentLabel.text = [NSString stringWithFormat:localize(@"ame428.gp.key.current", nil),
                          ame428G_keyDisplay(currentCode)];
    currentLabel.font = [ZL2Theme fontLabelMedium];
    currentLabel.textColor = [ZL2Theme onSurfaceVariant];
    currentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:currentLabel];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.showsVerticalScrollIndicator = YES;
    [content addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    // ★Task428：候选键分组——无映射（空映射）置顶，其后常用/字母/数字/
    //   功能/特殊（特殊=SPECIALBTN_* 的本地化短名；NONE 走「无映射」选项）。
    NSMutableArray<NSNumber *> *optionCodes = [[NSMutableArray alloc] init];
    {
        UIButton *btn = [self ame428_sheetOptionWithTitle:localize(@"ame428.gp.key.none", nil)
                                                     code:0 current:currentCode];
        [stack addArrangedSubview:btn];
    }
    // 常用键
    NSArray<NSString *> *commonNames = @[
        @"W", @"A", @"S", @"D", @"SPACE", @"E", @"Q", @"F",
        @"LEFT_SHIFT", @"LEFT_CONTROL", @"TAB", @"ESCAPE", @"ENTER",
    ];
    [stack addArrangedSubview:[self ame428_sheetHeader:localize(@"ame428.gp.key.group.common", nil)]];
    [optionCodes removeAllObjects];
    [optionCodes addObjectsFromArray:[self ame428_codesForNames:commonNames]];
    [self ame428_appendOptions:optionCodes current:currentCode toStack:stack];

    // 字母
    NSMutableArray<NSString *> *letters = [[NSMutableArray alloc] init];
    for (char c = 'A'; c <= 'Z'; c++) {
        [letters addObject:[NSString stringWithFormat:@"%c", c]];
    }
    [stack addArrangedSubview:[self ame428_sheetHeader:localize(@"ame428.gp.key.group.letters", nil)]];
    [optionCodes removeAllObjects];
    [optionCodes addObjectsFromArray:[self ame428_codesForNames:letters]];
    [self ame428_appendOptions:optionCodes current:currentCode toStack:stack];

    // 数字
    NSMutableArray<NSString *> *digits = [[NSMutableArray alloc] init];
    for (NSInteger i = 0; i <= 9; i++) {
        [digits addObject:[NSString stringWithFormat:@"%ld", (long)i]];
    }
    [stack addArrangedSubview:[self ame428_sheetHeader:localize(@"ame428.gp.key.group.digits", nil)]];
    [optionCodes removeAllObjects];
    [optionCodes addObjectsFromArray:[self ame428_codesForNames:digits]];
    [self ame428_appendOptions:optionCodes current:currentCode toStack:stack];

    // 功能键（表内其余键）
    NSMutableSet<NSString *> *skip = [[NSMutableSet alloc] init];
    [skip addObjectsFromArray:commonNames];
    [skip addObjectsFromArray:letters];
    [skip addObjectsFromArray:digits];
    NSMutableArray<NSString *> *fnNames = [[NSMutableArray alloc] init];
    for (NSString *name in ame428G_keyNames) {
        if ([name hasPrefix:@"SPECIALBTN_"]) continue;
        if ([name isEqualToString:@"NONE"]) continue;
        if ([skip containsObject:name]) continue;
        [fnNames addObject:name];
    }
    [stack addArrangedSubview:[self ame428_sheetHeader:localize(@"ame428.gp.key.group.fn", nil)]];
    [optionCodes removeAllObjects];
    [optionCodes addObjectsFromArray:[self ame428_codesForNames:fnNames]];
    [self ame428_appendOptions:optionCodes current:currentCode toStack:stack];

    // 特殊操作（SPECIALBTN_*）
    [stack addArrangedSubview:[self ame428_sheetHeader:localize(@"ame428.gp.key.group.special", nil)]];
    NSMutableArray<NSString *> *specialNames = [[NSMutableArray alloc] init];
    for (NSString *name in ame428G_keyNames) {
        if ([name hasPrefix:@"SPECIALBTN_"]) [specialNames addObject:name];
    }
    [optionCodes removeAllObjects];
    [optionCodes addObjectsFromArray:[self ame428_codesForNames:specialNames]];
    [self ame428_appendOptions:optionCodes current:currentCode toStack:stack];

    CGFloat sheetHeight = MIN(430.0, [UIScreen mainScreen].bounds.size.height * 0.6);
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:content.topAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [currentLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4],
        [currentLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [currentLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [scroll.topAnchor constraintEqualToAnchor:currentLabel.bottomAnchor constant:10],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],

        [content.heightAnchor constraintEqualToConstant:sheetHeight],
    ]];

    __weak typeof(self) weakSelf = self;
    [ZL2M3BottomSheet presentWithContentView:content onDismiss:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_sheetEntry = nil;
        strongSelf->_sheetContentView = nil;
    }];
}

- (NSArray<NSNumber *> *)ame428_codesForNames:(NSArray<NSString *> *)names {
    NSMutableArray<NSNumber *> *codes = [[NSMutableArray alloc] init];
    for (NSString *name in names) {
        NSUInteger idx = [ame428G_keyNames indexOfObject:name];
        if (idx != NSNotFound && idx < ame428G_keyCodes.count) {
            [codes addObject:ame428G_keyCodes[idx]];
        }
    }
    return codes;
}

- (UILabel *)ame428_sheetHeader:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [ZL2Theme fontLabelMedium];
    label.textColor = [ZL2Theme onSurfaceVariant];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (void)ame428_appendOptions:(NSArray<NSNumber *> *)codes current:(int)current toStack:(UIStackView *)stack {
    NSMutableArray<UIButton *> *buttons = [[NSMutableArray alloc] init];
    for (NSNumber *code in codes) {
        int c = code.intValue;
        if (c == 0) continue;  // NONE 已由「无映射」选项覆盖
        [buttons addObject:[self ame428_sheetOptionWithTitle:ame428G_keyDisplay(c) code:c current:current]];
    }
    if (buttons.count == 0) return;
    // ★Task428：每行最多 4 个选项键（栅格折行——ZL2 RowEnum 同款判例）。
    NSInteger perRow = 4;
    for (NSInteger start = 0; start < (NSInteger)buttons.count; start += perRow) {
        NSInteger end = MIN(start + perRow, (NSInteger)buttons.count);
        UIStackView *line = [[UIStackView alloc] init];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.alignment = UIStackViewAlignmentFill;
        line.distribution = UIStackViewDistributionFillEqually;
        line.spacing = 8;
        line.translatesAutoresizingMaskIntoConstraints = NO;
        for (NSInteger i = start; i < end; i++) {
            [line addArrangedSubview:buttons[i]];
        }
        [stack addArrangedSubview:line];
    }
}

- (UIButton *)ame428_sheetOptionWithTitle:(NSString *)title code:(int)code current:(int)current {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.layer.cornerRadius = [ZL2Theme radiusS];
    btn.titleLabel.font = [ZL2Theme fontLabelMedium];
    btn.titleLabel.adjustsFontSizeToFitWidth = YES;
    btn.titleLabel.minimumScaleFactor = 0.6;
    [btn setTitle:title forState:UIControlStateNormal];
    btn.tag = code;
    [btn addTarget:self action:@selector(ame428_sheetOptionTapped:) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [btn.heightAnchor constraintEqualToConstant:40],
    ]];
    if (code == current) {
        btn.backgroundColor = [ZL2Theme primaryContainer];
        [btn setTitleColor:[ZL2Theme onPrimaryContainer] forState:UIControlStateNormal];
    } else {
        btn.backgroundColor = [ZL2Theme surfaceContainer];
        [btn setTitleColor:[ZL2Theme onSurface] forState:UIControlStateNormal];
    }
    return btn;
}

- (void)ame428_sheetOptionTapped:(UIButton *)sender {
    UIView *content = _sheetContentView;
    NSMutableDictionary *entry = _sheetEntry;
    _sheetEntry = nil;
    _sheetContentView = nil;
    if (entry != nil) {
        [self ame428_setKeycode:sender.tag onEntry:entry];
    }
    if (content != nil) {
        [ZL2M3BottomSheet dismissWithContentView:content];
    }
}

#pragma mark 映射文件装载/保存（既有流程，入口换 ZL2 卡片行）

- (void)actionOpenFilePicker:(void (^)(NSString *name))handler {
    FileListViewController *vc = [[FileListViewController alloc] init];
    vc.listPath = [NSString stringWithFormat:@"%s/controlmap/gamepads", getenv("POJAV_HOME")];
    vc.whenItemSelected = handler;
    vc.modalPresentationStyle = UIModalPresentationPopover;
    vc.preferredContentSize = CGSizeMake(350, 250);

    UIPopoverPresentationController *popoverController = [vc popoverPresentationController];
    popoverController.sourceView = self.view;
    if (_fileRow != nil) {
        popoverController.sourceRect = [_fileRow convertRect:_fileRow.bounds toView:self.view];
    } else {
        popoverController.sourceRect = CGRectMake(0, 0, 220, 48);
    }
    popoverController.delegate = self;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)actionMenuLoad {
    __weak typeof(self) weakSelf = self;
    [self actionOpenFilePicker:^void(NSString *name) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *currentFile = [NSString stringWithFormat:@"%@.json",
                                 getPrefObject(@"control.default_gamepad_ctrl")];
        if ([currentFile isEqualToString:name]) return;
        setPrefObject(@"control.default_gamepad_ctrl", [NSString stringWithFormat:@"%@.json", name]);
        [strongSelf loadGamepadConfigurationFile];
        strongSelf->_dirty = NO;
        [strongSelf ame428_rebuildMappingGroups];
        [strongSelf ame428_afterFileSwap];
    }];
}

- (void)ame428_afterFileSwap {
    [self ame428_refreshRows];
    [self ame428_refreshSchematic];
    [self ame428_refreshFileRow];
}

- (void)actionMenuSaveWithExit:(BOOL)exitFlag {
    UIAlertController *controller = [UIAlertController
        alertControllerWithTitle:localize(@"custom_controls.control_menu.save", nil)
                         message:exitFlag ? localize(@"custom_controls.control_menu.exit.warn", nil) : @""
                  preferredStyle:UIAlertControllerStyleAlert];
    [controller addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Name";
        textField.text = _currentFileName;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.borderStyle = UITextBorderStyleRoundedRect;
    }];
    [controller addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
        UITextField *field = controller.textFields.firstObject;
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_currentMappings
                                                           options:NSJSONWritingPrettyPrinted
                                                             error:&error];
        if (jsonData == nil) {
            showDialog(localize(@"custom_controls.control_menu.save.error.json", nil),
                       error.localizedDescription);
            return;
        }
        NSString *target = [NSString stringWithFormat:@"%s/controlmap/gamepads/%@.json",
                            getenv("POJAV_HOME"), field.text];
        BOOL success = [jsonData writeToFile:target options:NSDataWritingAtomic error:&error];
        if (!success) {
            showDialog(localize(@"custom_controls.control_menu.save.error.write", nil),
                       error.localizedDescription);
            return;
        }
        _dirty = NO;
        setPrefObject(@"control.default_gamepad_ctrl", [NSString stringWithFormat:@"%@.json", field.text]);
        [self ame428_refreshFileRow];
        if (exitFlag) [self ame428_closePage];
    }]];
    if (exitFlag) {
        [controller addAction:[UIAlertAction
            actionWithTitle:localize(@"custom_controls.control_menu.discard_changes", nil)
                      style:UIAlertActionStyleDestructive
                    handler:^(UIAlertAction *action) {
                        [self ame428_closePage];
                    }]];
    }
    [controller addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)actionMenuSave {
    [self actionMenuSaveWithExit:NO];
}

- (void)exitButtonSelector {
    NSString *gamepadPath = [NSString stringWithFormat:@"%s/controlmap/gamepads/%@",
                              getenv("POJAV_HOME"), getPrefObject(@"control.default_gamepad_ctrl")];
    if ([_currentMappings isEqualToDictionary:parseJSONFromFile(gamepadPath)]) {
        [self ame428_closePage];
    } else {
        [self actionMenuSaveWithExit:YES];
    }
}

// ★Task428：退出 = 导航栈 pop（兼容万一被模态呈现的兜底 dismiss）。
- (void)ame428_closePage {
    if (self.navigationController != nil) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

@end
