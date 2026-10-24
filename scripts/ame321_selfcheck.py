#!/usr/bin/env python3
# Task321 旧版升级自动迁移 + 兄弟迁移优化 综合静态自查
# ① main.m：init_migrateLegacyUpgrade 定义 + 调用位次（先于 MultiDir/PCLLayout）
# ② main.m：init_setupPCLLayout step④ AI 新者为准合并分支 + providers.json Task275 特护
# ③ DataTransferService.h：Ame321SiblingMigrationMode 枚举 + ame321 两方法声明 + kind 文档
# ④ DataTransferService.m：ame260 委托 Overwrite / ame321 智能合并实现 / 排除清单双侧 /
#    收编链（MultiDir+PCLLayout）/ 迁移档案落档与读取
# ⑤ Welcome：状态机（隐藏/增量同步变体）+ desc2 来源标注 + 双语义确认框 + ame321 调用
# ⑥ 设置页：desc2 + 双语义确认框 + ame321 调用
# ⑦ i18n：12 键 × 四表一致 + 占位符个数校验（desc2=%1$@+%2$@ / done=4×%ld / done.overwrite=1×%ld）
# ⑧ 标记文件名跨文件一致性（.ame321_sibling_migration.plist / .ame321_upgrade_record.plist）
import os, re, sys

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
NAT = os.path.join(REPO, 'Natives')
fails = []

def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + (f' -- {detail}' if detail and not ok else ''))
    if not ok: fails.append(name)

main_m = open(os.path.join(NAT, 'main.m'), encoding='utf-8').read()
dts_h = open(os.path.join(NAT, 'DataTransferService.h'), encoding='utf-8').read()
dts_m = open(os.path.join(NAT, 'DataTransferService.m'), encoding='utf-8').read()
welcome = open(os.path.join(NAT, 'WelcomeViewController.m'), encoding='utf-8').read()
prefs = open(os.path.join(NAT, 'LauncherPreferencesViewController.m'), encoding='utf-8').read()

# ── ① main.m 升级识别函数与调用位次 ──────────────────────
check('main.m: init_migrateLegacyUpgrade defined',
      'void init_migrateLegacyUpgrade()' in main_m)
check('main.m: upgrade snapshot record path',
      '.ame321_upgrade_record.plist' in main_m)
check('main.m: fingerprint needs accounts/instances',
      'ame321_accDir' in main_m and 'ame321_instDir' in main_m)
call_up = main_m.find('    init_migrateLegacyUpgrade();')
call_multi = main_m.find('    init_setupMultiDir();\n    init_setupPCLLayout();')
check('main.m: call order migrate -> MultiDir -> PCLLayout',
      0 < call_up < call_multi,
      f'up={call_up} multi={call_multi}')
check('main.m: comment says read-only + record discipline',
      '只读 + 落档' in main_m)

# ── ② main.m step④ AI 新者为准合并 ──────────────────────
pcl_start = main_m.find('void init_setupPCLLayout()')
pcl_end = main_m.find('void init_setupResolvConf()')
pcl = main_m[pcl_start:pcl_end] if 0 < pcl_start < pcl_end else ''
check('main.m: step4 else-branch newer-wins merge present',
      'newer-wins' in pcl and 'Task321' in pcl and 'legacyAIDir' in pcl)
check('main.m: providers.json never lands in Prisma2/AI (Task275 guard in merge)',
      'providers.json' in pcl and 'Application Support' in pcl)
check('main.m: merge keeps newer mtime winner',
      'NSFileModificationDate' in pcl and
      '[ame321_sM compare:ame321_dM] == NSOrderedDescending' in pcl)
check('main.m: no dot-syntax modificationDate on NSDictionary (CI r1 实锤)',
      '.modificationDate' not in pcl and '.modificationDate' not in dts_m)

# ── ③ DataTransferService.h 声明面 ───────────────────────
check('dts.h: Ame321SiblingMigrationMode enum',
      'typedef NS_ENUM(NSInteger, Ame321SiblingMigrationMode)' in dts_h)
check('dts.h: Smart/Overwrite both declared',
      'Ame321SiblingMigrationModeSmart = 0' in dts_h and
      'Ame321SiblingMigrationModeOverwrite = 1' in dts_h)
check('dts.h: ame321_migrateFromSiblingHome declared',
      'ame321_migrateFromSiblingHome:(NSString *)srcPath' in dts_h and
      'mode:(Ame321SiblingMigrationMode)mode' in dts_h)
check('dts.h: ame321_lastSiblingMigrationRecord declared',
      'ame321_lastSiblingMigrationRecord' in dts_h)
check('dts.h: scan doc mentions kind taxonomy',
      'prisma1' in dts_h and 'prisma-plugins' in dts_h and 'kind' in dts_h)

# ── ④ DataTransferService.m 实现面 ───────────────────────
check('dts.m: ame260 delegates to Overwrite (back-compat)',
      re.search(r'ame260_migrateFromSiblingHome:\(NSString \*\)srcPath.*?Ame321SiblingMigrationModeOverwrite', dts_m, re.S) is not None)
check('dts.m: smart mode skips unchanged (size+mtime, 1s tolerance)',
      'fabs(ame321_dsec) < 1.0' in dts_m and 'ame321_unchanged++' in dts_m)
check('dts.m: smart mode keeps newer destination',
      'ame321_dsec > 1.0' in dts_m and 'ame321_newerKept++' in dts_m)
check('dts.m: post-adoption chain MultiDir + PCLLayout',
      'init_setupPCLLayout();' in dts_m and 'init_setupMultiDir();' in dts_m)
check('dts.m: migration record written + readable',
      '.ame321_sibling_migration.plist' in dts_m and
      'ame321_lastSiblingMigrationRecord' in dts_m)
sweep_fn = dts_m[dts_m.find('ame217_shouldSkipExportEntry'):dts_m.find('ame217_progressAlertWithTitle')]
check('dts.m: export sweep excludes ame321 records + ame316 marker',
      all(k in sweep_fn for k in ('.ame321_sibling_migration.plist',
                                  '.ame321_upgrade_record.plist',
                                  'ame316_filelayout.done')))
copy_loop = dts_m[dts_m.find('ame321_migrateFromSiblingHome:(NSString *)srcPath'):]
check('dts.m: sibling copy loop excludes ame321 records + ame316 marker',
      all(k in copy_loop for k in ('.ame321_sibling_migration.plist',
                                   '.ame321_upgrade_record.plist',
                                   'ame316_filelayout.done')))
check('dts.m: scan emits kind field',
      '@"kind": ame321_kind' in dts_m and 'ame321_kind = @"prisma1"' in dts_m)
check('dts.m: done message uses ame321 keys',
      'ame321.migrate.done' in dts_m and 'ame321.migrate.done.overwrite' in dts_m)

# ── ⑤ Welcome 状态机与双语义 ─────────────────────────────
check('welcome: migration record state machine',
      'ame321_lastSiblingMigrationRecord' in welcome and
      'already migrated -- card hidden' in welcome)
check('welcome: sync variant strings',
      'welcome.data.sibling.title.sync' in welcome and
      'welcome.data.sibling.action.sync' in welcome)
check('welcome: desc2 with kind + size',
      'welcome.data.sibling.desc2' in welcome and
      'welcome.data.sibling.kind.' in welcome)
check('welcome: dual-mode confirm + ame321 call',
      'welcome.data.sibling.confirm.smart' in welcome and
      'welcome.data.sibling.confirm.overwrite' in welcome and
      'ame321_migrateFromSiblingHome:ame260_src mode:ame321_mode' in welcome)

# ── ⑥ 设置页 ─────────────────────────────────────────────
check('prefs: desc2 + kind label',
      'welcome.data.sibling.desc2' in prefs and
      'welcome.data.sibling.kind.' in prefs)
check('prefs: dual-mode confirm + ame321 call',
      'welcome.data.sibling.confirm.smart' in prefs and
      'ame321_migrateFromSiblingHome:ame261_src mode:ame321_mode' in prefs)

# ── ⑦ i18n 12 键 × 四表 + 占位符 ─────────────────────────
KEYS = [
    'welcome.data.sibling.desc2',
    'welcome.data.sibling.kind.prisma1',
    'welcome.data.sibling.kind.prisma2',
    'welcome.data.sibling.kind.plugins',
    'welcome.data.sibling.kind.legacy',
    'welcome.data.sibling.title.sync',
    'welcome.data.sibling.desc.sync',
    'welcome.data.sibling.action.sync',
    'welcome.data.sibling.confirm.smart',
    'welcome.data.sibling.confirm.overwrite',
    'ame321.migrate.done',
    'ame321.migrate.done.overwrite',
]
for lang in ['en', 'zh-Hans', 'zh-CN', 'zh-Hant']:
    txt = open(os.path.join(NAT, 'resources', f'{lang}.lproj', 'Localizable.strings'),
               encoding='utf-8').read()
    missing = [k for k in KEYS if f'"{k}"' not in txt]
    check(f'i18n[{lang}]: all 12 keys present', not missing, f'missing={missing}')

val = {}
for lang in ['en', 'zh-Hans', 'zh-CN', 'zh-Hant']:
    txt = open(os.path.join(NAT, 'resources', f'{lang}.lproj', 'Localizable.strings'),
               encoding='utf-8').read()
    m = re.search(r'"welcome\.data\.sibling\.desc2"\s*=\s*"([^"]*)"', txt)
    check(f'i18n[{lang}]: desc2 has 2 positional placeholders',
          m is not None and '%1$@' in (m.group(1) if m else '') and '%2$@' in (m.group(1) if m else ''))
    m2 = re.search(r'"ame321\.migrate\.done"\s*=\s*"([^"]*)"', txt)
    check(f'i18n[{lang}]: done has 4 x %ld',
          m2 is not None and (m2.group(1) if m2 else '').count('%ld') == 4)
    m3 = re.search(r'"ame321\.migrate\.done\.overwrite"\s*=\s*"([^"]*)"', txt)
    check(f'i18n[{lang}]: done.overwrite has 1 x %ld',
          m3 is not None and (m3.group(1) if m3 else '').count('%ld') == 1)

# ── ⑧ 标记文件名跨文件一致 ────────────────────────────────
check('marker name consistency: sibling record in main/dts',
      '.ame321_sibling_migration.plist' in dts_m and
      '.ame321_upgrade_record.plist' in main_m and
      '.ame321_upgrade_record.plist' in dts_m)
check('no stray legacy Task260 done-format left in welcome/prefs',
      'ame260_migrateFromSiblingHome:ame260_src' not in welcome and
      'ame260_migrateFromSiblingHome:ame261_src' not in prefs)

print()
if fails:
    print(f'FAILED: {len(fails)} checks')
    sys.exit(1)
print('ALL PASS')
