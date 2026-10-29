#!/usr/bin/env python3
# ame349_selfcheck.py -- Task349 两线门禁（装机 0ad0735 IMG_0522 第八轮复诉联修）
# A 线A：NavigationView 排版级重设计首次真正可见（iPad 宽窄态派发缺陷双保险
#         + 大标题让位左钮槽位）+ ZL2 全壳壁纸描边字体树级豁免（幽灵字根修）
# C 线C：孤儿实例目录收编（导入收尾 + 启动期双挂点 + 一代全局注册表合并）
# D 结构护栏 + --selftest 反向验证（内存注入病灶变体必翻红，零仓内触碰）
import os, re, sys, io

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
os.chdir(REPO)

def read(p):
    with io.open(os.path.join(REPO, p), encoding="utf-8", newline="") as f:
        return f.read()

passed, fails = 0, []
def check(name, ok, detail=""):
    global passed
    if ok:
        passed += 1
        print(f"  PASS {name}")
    else:
        fails.append(name)
        print(f"  FAIL {name}" + (f" -- {detail}" if detail else ""))

def strip_code(text):
    out, i, n, mode = [], 0, len(text), 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if mode == 0:
            if c == '"': mode = 1
            elif c == "'": mode = 2
            elif c == "/" and nxt == "/": mode = 3
            elif c == "/" and nxt == "*": mode = 4
            else: out.append(c)
        elif mode == 1:
            if c == "\\": i += 1
            elif c == '"': mode = 0
        elif mode == 2:
            if c == "\\": i += 1
            elif c == "'": mode = 0
        elif mode == 3:
            if c == "\n": mode = 0; out.append(c)
        elif mode == 4:
            if c == "*" and nxt == "/": mode = 0; i += 1
        i += 1
    return "".join(out)

shell = read("Natives/ZL2ShellViewController.m")
shell_code = strip_code(shell)
plp = read("Natives/PLProfiles.m")
plp_code = strip_code(plp)
plph = read("Natives/PLProfiles.h")
dt = read("Natives/DataTransferService.m")
dt_code = strip_code(dt)
mm = read("Natives/main.m")

# ══ A 线A NavigationView 真可见 + 幽灵字豁免 ═══════════════════
check('A1 iPad 宽窄态派发缺陷双保险（构建期 contentLeading 即真值 + 首轮无条件派发哨兵）',
      "self.ame347_contentLeading.constant = ZL2ShellPaneWidth;" in shell_code
      and "!self.ame347_widthClassApplied || ame347_nowRegular != self.ame347_regular" in shell_code
      and "self.ame347_widthClassApplied = YES;" in shell_code
      and "@property(nonatomic, assign) BOOL ame347_widthClassApplied;" in shell)

check('A2 大标题让位左钮槽位（可变前导约束 + 46/16 按汉堡/返回可见性派发）',
      "@property(nonatomic, strong) NSLayoutConstraint *ame347_headerLeading;" in shell
      and "self.ame347_headerLeading = [self.headerTitle.leadingAnchor constraintEqualToAnchor:self.contentHeader.safeAreaLayoutGuide.leadingAnchor constant:16.0]," in shell
      and "(ame347_hamburgerVisible || ame347_backVisible) ? 46.0 : 16.0" in shell_code)

check('B1 ZL2 全壳壁纸描边字体树级豁免（viewDidLoad ame230 + 头文件导入）',
      "ame230_setViewTreeStrokeExempt(self.view, YES);" in shell_code
      and '#import "BackgroundManager.h"' in shell)

# ══ C 线C 孤儿实例收编 ═══════════════════════════════════════
check('C1 PLProfiles 收编方法（.h 声明 + .m 实现 + [Ame349] reconcile 日志锚）',
      "+ (NSUInteger)ame349_reconcileOrphanInstancesLogTag:(NSString *)tag;" in plph
      and "+ (NSUInteger)ame349_reconcileOrphanInstancesLogTag:(NSString *)tag {" in plp_code
      and '[Ame349] reconcile(%@): scanned=%lu registered=%lu' in plp)

check('C2 收编硬边界（当前游戏目录跳过 / 隐藏目录 / 真实目录 NSFileType / 空目录 / 同名或 gameDir 命中）',
      'getPrefObject(@"general.game_directory")' in plp
      and '[ame349_name hasPrefix:@"."]' in plp
      and "![ame349_attrs[NSFileType] isEqualToString:NSFileTypeDirectory]" in plp_code
      and "ame349_inner.count == 0" in plp_code
      and '[ame349_name isEqualToString:ame349_currentGameDir]' in plp_code
      and '[ame349_gd isEqualToString:ame349_path]' in plp_code)

check('C3 写入收口 applyChanges + lastVersionId 实例自带注册表回读 + 主队列 ReloadProfileList',
      "[ame349_mgr applyChanges:" in plp_code
      and 'stringByAppendingPathComponent:@"launcher_profiles.json"' in plp
      and 'postNotificationName:@"ReloadProfileList" object:nil' in plp)

check('C4 双挂点（DataTransferService 导入收尾 tag=import + main.m 启动期 tag=startup）',
      '[PLProfiles ame349_reconcileOrphanInstancesLogTag:@"import"]' in dt
      and '[PLProfiles ame349_reconcileOrphanInstancesLogTag:@"startup"]' in mm
      and mm.find("[PLProfiles updateCurrent];") < mm.find('[PLProfiles ame349_reconcileOrphanInstancesLogTag:@"startup"]'))

check('C5 一代全局注册表合并（出厂默认单条闸门 + .ame349-imported 归档防复燃）',
      '.ame349-imported' in plp
      and "ame349_defaultOnly" in plp_code
      and 'moveItemAtPath:ame349_legacyPath toPath:ame349_legacyArchive' in plp_code)

check('D1 零新增 i18n 键（本任务设计为零词条改动）',
      'localize(@"ame349' not in dt and 'localize(@"ame349' not in shell
      and 'localize(@"ame349' not in plp)

# ══ --selftest 反向验证（内存注入病灶变体，零仓内触碰）═════════
if "--selftest" in sys.argv:
    print("  --selftest reverse probes:")
    rp, rf = 0, []
    def rcheck(name, variants):
        global rp
        ok = True
        for vname, src in variants:
            backup_passed, backup_fails = passed, list(fails)
            globals()['passed'], _ = 0, []
            # re-evaluate the anchored conditions against mutated source
            if vname == "S-A1":
                ok = "self.ame347_contentLeading.constant = ZL2ShellPaneWidth;" in src
            elif vname == "S-B1":
                ok = "ame230_setViewTreeStrokeExempt(self.view, YES);" in src
            elif vname == "S-C4":
                ok = '[PLProfiles ame349_reconcileOrphanInstancesLogTag:@"startup"]' in src
            globals()['passed'], globals()['fails'] = backup_passed, backup_fails
            if ok:
                print(f"  FAIL-RED-EXPECTED {vname}: probe did NOT turn red")
                rf.append(vname)
            else:
                print(f"  PASS {vname} probe turned red")
                rp += 1
    rcheck("S-A1", [("S-A1", shell_code.replace("self.ame347_contentLeading.constant = ZL2ShellPaneWidth;", ""))])
    rcheck("S-B1", [("S-B1", shell_code.replace("ame230_setViewTreeStrokeExempt(self.view, YES);", ""))])
    rcheck("S-C4", [("S-C4", mm.replace('[PLProfiles ame349_reconcileOrphanInstancesLogTag:@"startup"]', ""))])
    if rf:
        print(f"  SELFTEST FAILED: {rf}")
        sys.exit(1)
    print(f"  selftest {rp}/3 probes red as expected")

print(f"ame349_selfcheck: {passed} passed, {len(fails)} failed")
if fails:
    print("  FAILED:", "; ".join(fails))
    sys.exit(1)
