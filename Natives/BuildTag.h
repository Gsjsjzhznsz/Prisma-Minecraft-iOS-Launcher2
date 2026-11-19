//
//  BuildTag.h
//  Amethyst
//
//  ★Task421 构建代际单一事实源（header 化）：Task407 立常量于 AboutViewController.m
//  私有 static，Task420 装机验锚 = 设置→关于版本行——但用户从不导航，四轮
//  「还是旧观感」复诉（IMG_0655/0661 = 416+ 共享角点几何数学不可能的手臂离位
//  缝 30~40px，Task415 代引擎签名）实锚失效。本轮：常量 header 化，关于页版本
//  行与预览卡代际角标（ZL2SkinPreviewView ame421_buildChip）同源同一字面量 =
//  双面恒等零漂移；用户任何一张预览截图即可判代际（无角标 = 旧构建）。
//
//  static NSString *const 于头文件 = 各 TU 自持指针指向同一常量字符串节，
//  零重复符号链接风险（冒烟固定清单无需加编任何 TU——Task416-r1/418-r1/
//  420-r1「新代码面首上 CI 才暴露」判例的预防式规避）。纯构建标识非用户文案，
//  零 i18n 键（同 [Ame406] 日志锚纪律）。
//

#ifndef BUILD_TAG_H
#define BUILD_TAG_H

#import <Foundation/Foundation.h>

<<<<<<< HEAD
static NSString *const ame415_buildTag = @"Task448 · 2026-11-18";   // 常量名留档 415 判例，值随轮次推进；★Task439 起由 scripts/task439_buildtag_anchor.py 每轮门禁强制重锚（第 10 期报告 6.3 节代际锚落后 2 轮整改）
=======
static NSString *const ame415_buildTag = @"Task451 · 2026-11-19";   // 常量名留档 415 判例，值随轮次推进；★Task439 起由 scripts/task439_buildtag_anchor.py 每轮门禁强制重锚（第 10 期报告 6.3 节代际锚落后 2 轮整改）
>>>>>>> be9a2da60 (fix(cycle16): Task451 —— 议题#3 第七轮：JIT26ExecPreflight 授予前 64MB 级通道预检（与 libjvm 64m 镜像请求同形分配 + 零取指执行探测：SIGILL=映射真实且可执行/SIGBUS·SEGV=空壳定罪，3 试重试后拒绝发射 = SIGBUS 黑屏根除，弹窗内联第七轮实录处置阶梯：彻底重启 StikDebug→重指派→重装 Prisma→换 enabler）+ 逃生阀 debug.jit26_preflight_disable 注册 + ame451 定罪 marker + i18n_str_ame451_preflight 54 表（zh 家族原生）+ verify219 唯一键重锚 4349 + 新门 task451_selfcheck 26 断言 + 电池 33/33)

#endif /* BUILD_TAG_H */
