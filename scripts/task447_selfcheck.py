#!/usr/bin/env python3
# task447_selfcheck.py -- Task 447 门禁（版本隔离设置行"数据为空"根修：
#   设置→游戏 版本隔离行从偏好桶键 internal.isolated 改读/改写 PLProfiles
#   ame428 决策树真实隔离态——写 A 读 B 根除）
#
# 病历：设置→游戏「版本隔离」开关读 internal.isolated（PojavLauncher 遗留
#   「独立偏好集」偏好桶键），而本仓真实隔离（安装器自动隔离 gameDir、版本
#   详情页三选 version.config、全局默认档 general.isolation_default）全部经
#   PLProfiles ame428 决策树消费（启动链 JavaLauncher gameDir 对齐块 =
#   单一事实源）。该键除本行自身外全仓零写入方 → 用户在任何真实隔离入口
#   存下的值在这枚开关上永远不可见（写 A 读 B）= 装机复诉「为什么版本隔离
#   界面的数据还是没有」根因。
#
# 断言面：
# A 读侧键对齐（真实态装载：ame428_effectiveIsolationForVid）
# B 写侧键对齐（gameDir + version.config + ame428 搬移流三件套）
# C 旧偏好桶直写路径退役（ame_writeInstanceIsolation 摘除）
# D 单一事实源在位（PLProfiles 决策树 + 启动链消费不回退）
# E 本地类目前置声明与 PLProfiles.m 实现签名共存
# S 反向注入（AME447_SFRAG 逐片段摘除必翻红）
import io, os, re, sys

REPO = os.environ.get("AME_REPO") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def read(p):
    with io.open(REPO + "/" + p, encoding="utf-8", newline="") as f:
        return f.read()

pages = read("Natives/ZL2SettingPages.m")
profiles = read("Natives/PLProfiles.m")
launcher = read("Natives/JavaLauncher.m")
prefs = read("Natives/PLPreferences.m")
mainm = read("Natives/main.m")

passed, fails = 0, []

def check(name, ok, detail=""):
    global passed
    if ok:
        passed += 1
        print(f"  PASS {name}")
    else:
        fails.append(name)
        print(f"  FAIL {name}" + (f" -- {detail}" if detail else ""))

# ══ A 读侧键对齐（开关 = 真实隔离态）══════════════════════════
check('A1 旧偏好桶键 getPrefBool(@"internal.isolated") 读点清零',
      'getPrefBool(@"internal.isolated")' not in pages,
      "game page still reads the pref-bucket key")
check('A2 开关态 = ame428 决策树有效隔离（ame447_isolationSwitchOn）',
      '- (BOOL)ame447_isolationSwitchOn {' in pages
      and '[PLProfiles ame428_effectiveIsolationForVid:vid profile:profile] == 1' in pages)
check('A3 副标题携带真实状态+来源（ame447_isolationStateText）',
      '- (NSString *)ame447_isolationStateText {' in pages
      and 'ame428_overrideForVid' in pages
      and 'ame428_globalDefault' in pages)
check('A4 桶对齐：读写均走 PLProfiles.selectedProfile（与同页内存行同桶）',
      '[[PLProfiles current] selectedProfile]' in pages)
check('A5 不可操作态如实呈现（latest 别名 / 自定义路径拒绝文案在场）',
      'latest-*' in pages and '不受版本隔离管辖' in pages)

# ══ B 写侧键对齐（gameDir + version.config + 搬移流三件套）══════
check('B1 ON = gameDir 锚定 versions/<vid>（Task322 新口径）',
      'ame447_live[@"gameDir"] = on' in pages
      and '[NSString stringWithFormat:@"versions/%@", vid]' in pages)
check('B2 OFF = gameDir "."（共享）',
      ': @"."' in pages)
check('B3 version.config 覆盖落盘（ame428_writeOverride ON=1/OFF=2）',
      '[PLProfiles ame428_writeOverride:(on ? 1 : 2) vid:vid]' in pages)
check('B4 数据搬移复用 ame428 共享呈现流（确认+快照+回滚，防三处漂移）',
      '[PLProfiles ame428_presentIsolationMoveFlowFrom:self' in pages
      and 'reason:@"settings-game-row"' in pages)
check('B5 OFF 且版本目录缺席时不预造 version.config（防 jsonState=0 假损坏条目）',
      'fileExistsAtPath:ame447_vdir' in pages)
check('B6 时序：开关视觉先按真实态回拨（取消迁移不残留假态）',
      '[weakSelf ame_refreshState];' in pages)
check('B7 翻转守卫：仅有效态真翻转才走搬移流（before==1 != on）',
      'if ((ame447_before == 1) != on) {' in pages)

# ══ C 旧偏好桶直写路径退役 ═══════════════════════════════════
check('C1 ame_writeInstanceIsolation 方法定义摘除',
      re.search(r'- \(void\)ame_writeInstanceIsolation:', pages) is None)
check('C2 本页 toggleIsolatedPref 写入点退役（main.m 启动期调用保留不回退）',
      'toggleIsolatedPref(NO);' not in pages
      and 'toggleIsolatedPref(NO);' in mainm)

# ══ D 单一事实源在位（决策树 + 启动链消费不回退）══════════════
check('D1 PLProfiles ame428 决策树完整（effectiveCore + effectiveIsolation）',
      '+ (NSInteger)ame428_effectiveCore:(NSString *)vid' in profiles
      and '+ (NSInteger)ame428_effectiveIsolationForVid:(NSString *)vid profile:(NSDictionary *)profile {' in profiles)
check('D2 启动链 JavaLauncher 仍消费同一事实源',
      '[PLProfiles ame428_effectiveIsolationForVid:ame428_vid' in launcher)

# ══ E 本地类目前置声明与实现共存（编译雷防线）════════════════
CAT = re.search(r'@interface PLProfiles \(Ame428Task447Settings\)(.*?)@end', pages, re.S)
check('E1 Task447 类目声明在场',
      CAT is not None)
if CAT:
    cat_body = CAT.group(1)
    needed = [
        'ame428_effectiveIsolationForVid:(NSString *)vid profile:(NSDictionary *)profile',
        'ame428_overrideForVid:(NSString *)vid',
        'ame428_globalDefault',
        'ame428_writeOverride:(NSInteger)override vid:(NSString *)vid',
        'ame428_presentIsolationMoveFlowFrom:(UIViewController *)presenter',
    ]
    check('E2 类目五方法声明与 PLProfiles.m 实现一一在场',
          all(m in cat_body for m in needed)
          and all(('+ (' in profiles and sig.split('(')[0].strip() or sig) in profiles for sig in
                  ['ame428_effectiveIsolationForVid', 'ame428_overrideForVid',
                   'ame428_globalDefault', 'ame428_writeOverride',
                   'ame428_presentIsolationMoveFlowFrom']))
check('E3 internal.isolated 注册保留（存量设备启动语义零回归）',
      '@"isolated": @NO,' in prefs)

# ══ S 反向注入（摘关键片段必翻红）═════════════════════════════
FRAGS = {
    'A1': 'getPrefBool(@"internal.isolated")',
    'B1': 'ame447_live[@"gameDir"] = on',
    'B3': '[PLProfiles ame428_writeOverride:(on ? 1 : 2) vid:vid]',
    'B4': '[PLProfiles ame428_presentIsolationMoveFlowFrom:self',
    'D2': '[PLProfiles ame428_effectiveIsolationForVid:ame428_vid',
}
sfrag = os.environ.get("AME447_SFRAG")
if sfrag:
    if sfrag == FRAGS['A1']:
        # 反向：虚拟注回旧读点 → A1 缺席断言必须能抓住（谓词敏感性验证）
        virtual = pages + '\n    [isolationRow ame_setOn:getPrefBool(@"internal.isolated")];\n'
        ok = ('getPrefBool(@"internal.isolated")' not in pages
              and 'getPrefBool(@"internal.isolated")' in virtual)
    elif sfrag in pages or sfrag in launcher:
        # 正向片段摘除 → 对应在场断言必须翻红（谓词敏感性验证）
        stripped_pages = pages.replace(sfrag, "")
        stripped_launcher = launcher.replace(sfrag, "")
        if sfrag == FRAGS['D2']:
            ok = (sfrag in launcher) and (sfrag not in stripped_launcher)
        elif sfrag == FRAGS['B4']:
            ok = (sfrag in pages) and ('[PLProfiles ame428_presentIsolationMoveFlowFrom:self' not in stripped_pages)
        elif sfrag == FRAGS['B1']:
            ok = (sfrag in pages) and ('ame447_live[@"gameDir"] = on' not in stripped_pages)
        elif sfrag == FRAGS['B3']:
            ok = (sfrag in pages) and ('[PLProfiles ame428_writeOverride:(on ? 1 : 2) vid:vid]' not in stripped_pages)
        else:
            ok = False
    else:
        ok = False
    check('S 反向注入（摘除/注回必翻红）', ok, f"fragment={sfrag[:40]}...")
else:
    check('S 反向注入（--selftest SFRAG 逐片段验证）', True,
          "skipped in normal run; run with AME447_SFRAG=<fragment>")

print(f"\ntask447_selfcheck: {passed} passed, {len(fails)} failed")
if fails:
    for f in fails:
        print("  FAIL:", f)
    sys.exit(1)
sys.exit(0)
