#!/usr/bin/env python3
# Task317-r2 CI 热修：development 全量编译暴露 5 组真雷
# ① Permissions.m @implementation 内游离方法声明不合法（expected method body + duplicate）
# ② Permissions.h 缺 ame317_pluginsRootDir C 函数声明（Manager 隐式声明=ARC 报错）
# ③ Manager.m validateManifestDictionary goto 跳入后置 __strong 顶层变量作用域（ARC 禁止）
# ④ Manager.m singleDir block 内赋值缺 __block
# ⑤ Manager.m performOnFilesInArchive: 缺 error: 参数（头文件唯一签名=双参；
#    ModService 的"} error:nil];"是跨行双参，非单参反例）
p1 = 'Natives/AmePluginPermissions.m'
s = open(p1, encoding='utf-8').read()
old = '''@implementation AmePluginPermissions

// 私有方法前向声明（ObjC 方法需先声明后使用）
+ (AmePluginPermissionItem *)itemForId:(NSString *)permissionId;

+ (NSArray<AmePluginPermissionItem *> *)allPermissions {'''
new = '''@implementation AmePluginPermissions

// ObjC @implementation 内方法定义顺序无关（clang 全 implementation 查找），
// itemForId: 定义于下方，无需前向声明。
+ (NSArray<AmePluginPermissionItem *> *)allPermissions {'''
assert s.count(old) == 1, 'p1 anchor %d' % s.count(old)
s = s.replace(old, new)
open(p1, 'w', encoding='utf-8').write(s)
print('① Permissions.m 游离声明删除')

p2 = 'Natives/AmePluginPermissions.h'
s = open(p2, encoding='utf-8').read()
old2 = '''@interface AmePluginPermissionItem : NSObject'''
new2 = '''/// 插件根目录（POJAV_HOME/plugins；C 函数，Manager/Runtime 共用）
NSString *ame317_pluginsRootDir(void);

@interface AmePluginPermissionItem : NSObject'''
assert s.count(old2) == 1, 'p2 anchor %d' % s.count(old2)
s = s.replace(old2, new2)
open(p2, 'w', encoding='utf-8').write(s)
print('② Permissions.h C 函数声明补齐')

p3 = 'Natives/AmePluginManager.m'
s = open(p3, encoding='utf-8').read()
# ③ ok 声明移到 goto 之前（函数开头）
old3 = '''    AmePluginInstallResult fail = AmePluginInstallErrBadSchema;
    AmePluginManifest *m = nil;
'''
new3 = '''    AmePluginInstallResult fail = AmePluginInstallErrBadSchema;
    AmePluginManifest *m = nil;
    // ARC：goto 不得跳入后置 __strong 顶层变量作用域——id 白名单字符集
    // 预声明于此（goto 前），供两处校验循环共用
    NSCharacterSet *ame317_idChars = [NSCharacterSet characterSetWithCharactersInString:
                          @"abcdefghijklmnopqrstuvwxyz0123456789._-"];
'''
assert s.count(old3) == 1, 'p3 anchor %d' % s.count(old3)
s = s.replace(old3, new3)
old3b = '''    // id 白名单：首字符字母数字，整体 [a-z0-9._-]
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:
                          @"abcdefghijklmnopqrstuvwxyz0123456789._-"];
    {'''
new3b = '''    // id 白名单：首字符字母数字，整体 [a-z0-9._-]（字符集已在 goto 前预声明）
    {'''
assert s.count(old3b) == 1, 'p3b anchor %d' % s.count(old3b)
s = s.replace(old3b, new3b)
s = s.replace('''        if (![ok characterIsMember:c]) goto out;''',
              '''        if (![ame317_idChars characterIsMember:c]) goto out;''')
# ④ __block
old4 = '''        NSString *singleDir = nil;'''
new4 = '''        __block NSString *singleDir = nil;'''
assert s.count(old4) == 1, 'p4 anchor %d' % s.count(old4)
s = s.replace(old4, new4)
# ⑤ performOnFilesInArchive 补 error:
old5 = '''            else if (![singleDir isEqualToString:top]) { ambiguous = YES; *stop = YES; }
        }];'''
new5 = '''            else if (![singleDir isEqualToString:top]) { ambiguous = YES; *stop = YES; }
        } error:nil];'''
assert s.count(old5) == 1, 'p5 anchor %d' % s.count(old5)
s = s.replace(old5, new5)
open(p3, 'w', encoding='utf-8').write(s)
print('③④⑤ Manager.m goto/__block/error: 修复')
