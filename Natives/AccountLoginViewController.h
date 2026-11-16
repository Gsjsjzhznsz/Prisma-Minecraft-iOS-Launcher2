//
//  AccountLoginViewController.h
//  Amethyst
//
//  参照 FCL (Fold Craft Launcher) 安卓版的账户登录界面：
//  用卡片式列表展示微软 / LittleSkin / 自定义第三方 / 本地 四种登录方式，
//  替代原来的 ActionSheet + UIAlertController 简陋交互。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AccountLoginViewController : UIViewController

/// 登录方式枚举
typedef NS_ENUM(NSInteger, AccountLoginType) {
    AccountLoginTypeMicrosoft = 0,
    AccountLoginTypeLittleSkin,
    AccountLoginTypeThirdParty,
    AccountLoginTypeLocal,
};

/// 用户选中某种登录方式后的回调（由账号列表页处理具体登录流程；原 AccountList 类 Task432 已退役）
@property (nonatomic, copy) void (^onSelectLoginType)(AccountLoginType type);

@end

NS_ASSUME_NONNULL_END
