//
//  AiInstanceCreator.m
//  Prisma
//

#import "AiInstanceCreator.h"
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "../utils.h"   // Task271-e：结果/错误文案 i18n 接线需要 localize()

@implementation AiInstanceCreator

- (NSString *)name {
    return @"create_instance";
}

- (AiToolPermission)permission {
    return AiToolPermissionControlledWrite;
}

- (NSString *)summary {
    // ★ Task483：单根终局——本工具恒拒绝（instances 布局退役）
    return @"新建游戏目录（已停用）。"
           "\n单一真实根已生效：instances 多目录布局已退役，新建/切换游戏目录不再受支持，"
           "现有数据已统一收编到 Library/Application Support/minecraft。"
           "\n行为：调用本工具恒返回错误，不产生任何目录。";
}

- (void)execute:(NSDictionary<NSString *, id> *)params
     completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error))completion {
    if (!completion) return;

    NSString *name = [params[@"name"] isKindOfClass:[NSString class]] ? params[@"name"] : @"";
    if (name.length == 0) {
        completion(nil, [NSError errorWithDomain:@"AiTool" code:400
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"ai.instance.param_name_required", nil)}]);
        return;
    }
    // 目录名安全化：去掉路径分隔符（与 VersionManagerViewController 创建目录一致直接拼接，
    // 这里额外剥离分隔符防止「../」逃逸出 instances/）
    NSArray *parts = [name componentsSeparatedByCharactersInSet:
                      [NSCharacterSet characterSetWithCharactersInString:@"/\\:"]];
    name = [parts componentsJoinedByString:@"_"];
    if (name.length == 0) {
        completion(nil, [NSError errorWithDomain:@"AiTool" code:400
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"ai.instance.name_invalid", nil)}]);
        return;
    }

    // ★ Task483（单根终局，用户指令：命中 instances 的代码全部删除）：
    //   instances/<name> 目录创建 + lasm 链接重指整段退役——单一真实数据根
    //   政策下「新建游戏目录」不再是合法操作（历史数据由 main.m Task483
    //   单根迁移收编）。工具如实拒绝并指引单根语义。
    NSLog(@"[AiInstanceCreator] Task483: single real root policy -- create_instance rejected (instances layout retired, no directory created)");
    completion(nil, [NSError errorWithDomain:@"AiTool" code:409
                                 userInfo:@{NSLocalizedDescriptionKey:
                                         localize(@"ai.instance.single_root_rejected", @"单一真实根已生效（Task483）：instances 多目录布局已退役，新建/切换游戏目录不再受支持；现有数据已统一收编到 Library/Application Support/minecraft。")}]);
    return;
}

@end
