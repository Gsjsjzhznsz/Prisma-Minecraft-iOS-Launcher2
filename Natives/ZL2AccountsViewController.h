//
// ZL2AccountsViewController.h — ZL2 风格账户页（7.0-UI-9-c：对标 ZL2 AccountManageScreen）
//
// 信息架构对标 ZL2 账户管理页（AccountManageScreen.kt：左 3D 皮肤预览 + 添加
// 账号按钮，右账号卡列表；本仓无 3D 皮肤预览，改为顶部账户视觉卡 + 添加账号
// 大按钮 + 账号卡列表，全宽单列，内容列宽度方案与 ZL2HomeViewController 同款
// 999 等式：520 上限居中 / iPhone 占满 / 两侧 >= 20）。
//
// 既有操作 1:1 移植旧 AccountListViewController：
//   账号列表数据源（POJAV_HOME/accounts/*.json 扫描 + Task180 去重/坏文件
//   过滤）、账号类型文案与判定（ame190_accountTypeTextForAccount 同源）、
//   选中链（第三方 refreshToken 会话校验 + 失败优雅降级 Task128）、刷新
//   （refreshTokenWithCallback）、删除链（MSA token 清理 + 文件删除 + 选中
//   态清空）。
//
// 通知契约：本页监听 @"UpdateAccountInfo" 自动重建列表；登录/选中/刷新/
//   删除成功后发出 @"UpdateAccountInfo"（旧容器 whenItemSelected/whenDelete
//   的等价契约，主页 pendingLaunchAfterLogin 据此自动续启动）。
//
// 登录入口（与旧 AccountListViewController 实际支持 1:1，四种全保留）：
//   微软账户 → ASWebAuthenticationSession MSA 流程（旧 actionLoginMicrosoft
//     原样移植，本页内完成，无独立登录 VC）；
//   LittleSkin / 自定义第三方认证服务器 → push ThirdPartyLoginViewController
//     （mode=LittleSkin/Custom）；
//   本地账户 → 本页输入框 + LocalAuthenticator（旧 actionLoginLocal 原样
//     移植）。
//   注：AccountLoginViewController 为登录方式四选一卡片页（选择结果仍回抛
//   容器执行流程），本页已有 actionSheet 选择层，再 push 一层选择页属重复
//   选择器，故不消费（Microsoft/本地两种方式其本身也没有独立登录 VC）。
//
// 导航约定：根页隐藏系统导航栏（viewWillAppear），push 登录页返回后由
//   viewWillDisappear 约定恢复；列表在 viewWillAppear + @"UpdateAccountInfo"
//   自动重建（登录流程返回本页后新账号立即可见）。
//
// 红线遵守：颜色/字体/圆角一律取 ZL2Theme 动态令牌（无 traitCollection
//   分支）；iOS 14.0+ API（无 button.configuration/UIMenu 等）；SF1.0 级
//   符号 + 旧名 fallback；新建视图全部 translatesAutoresizingMaskIntoConstraints
//   = NO；账号行不做 viewWithTag 状态存取（行对象数组下标索引）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZL2AccountsViewController : UIViewController

/// 重建账号列表 + 顶部视觉卡（viewWillAppear 与 @"UpdateAccountInfo" 自动
/// 触发；壳侧亦可手动调用）
- (void)reloadAccounts;

@end

NS_ASSUME_NONNULL_END
