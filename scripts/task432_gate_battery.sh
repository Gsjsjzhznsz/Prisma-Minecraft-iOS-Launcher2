#!/bin/bash
# Task432 门禁电池 —— 全量本地复跑（Task439 修幽灵门：run_sh 补定义，声明门数 =
#   实跑门数，每轮 RESULT 汇总行即真实门数；Task466 轮 = 44 门（Task465 41 门 +
#   ame341 正反双门幽灵门清偿登记（Task439 判例同族：门在库不在电池 = 静默漂移，
#   HEAD 实测 ame341 锚 3≠2 / fui v2.6.2≠2.2.0 已红而电池视而不见）+
#   task466 新门）+ Task467 轮 = 46 门（+task467 新门 + selftest 反向门）且总裁决移至全部门之后（461/462/464 历史追加越线修复；27 既有 runner +
#   task439 双新门 + task440/task442 自检门 + 括号审计 + ame366 自检门（★Task441/442 入册，
#   第 11 期报告 5.3 节验收项），历史头注「16 门」自第 9 期起已失实，Task439 校正）
#   Task468 轮 = 48 门（+ame468 MobileGL 旋钮门 + selftest 反向门）
# 用法: bash scripts/task432_gate_battery.sh
cd "$(dirname "$0")/.." || exit 1

RUN1() { echo "══ $* ══"; }
PY() { python3 "$1" "${@:2}" 2>&1; tail -4; }

declare -A RESULT

run_py() {
  local name="$1"; shift
  local out
  out=$(python3 "$@" 2>&1)
  local rc=$?
  if [ $rc -eq 0 ]; then RESULT[$name]="PASS"; else RESULT[$name]="FAIL(rc=$rc)"; fi
  echo "── $name (rc=$rc) ──"
  echo "$out" | tail -6
}

# ★Task439 幽灵门清偿（第 10 期报告 6.2 节）：run_sh 与 run_py 同形态的 rc 捕获
#   登记器。此前 task158_base 仅被声明从未定义，每轮 bash 报 command not found、
#   RESULT 永不登记，「27/27 ALL GREEN」被缺席精确凑齐——本定义落地后
#   task158_baseline_compare 门首次真实实跑。
run_sh() {
  local name="$1"; shift
  local out
  out=$(bash "$@" 2>&1)
  local rc=$?
  if [ $rc -eq 0 ]; then RESULT[$name]="PASS"; else RESULT[$name]="FAIL(rc=$rc)"; fi
  echo "── $name (rc=$rc) ──"
  echo "$out" | tail -6
}

run_py ame378       scripts/ame378_selfcheck.py
run_py ame378_self  scripts/ame378_selfcheck.py --selftest
run_py ame369       scripts/ame369_selfcheck.py
run_py ame379       scripts/ame379_selfcheck.py
run_py ame330       scripts/ame330_selfcheck.py
run_py ame339       scripts/ame339_selfcheck.py
run_py ame341       scripts/ame341_selfcheck.py
run_py ame341_self  scripts/ame341_selfcheck.py --selftest
run_py ame343       scripts/ame343_selfcheck.py
run_py ame348       scripts/ame348_selfcheck.py
run_py ame349       scripts/ame349_selfcheck.py
run_py ame353       scripts/ame353_selfcheck.py
run_py ame365       scripts/ame365_selfcheck.py
run_py ame366       scripts/ame366_selfcheck.py
run_py ame335       scripts/ame335_selfcheck.py
run_py task139      scripts/task139_syntax_gate.py
run_py task240_syn  scripts/task240_syntax_gate.py
run_py task240_imp  scripts/task240_import_sweep.py
run_py task158_bal  scripts/task158_objc_balance.py
run_sh task158_base scripts/task158_baseline_compare.sh
run_py task191      scripts/task191_validate_strings.py
run_py task248      scripts/task248_i18n_audit.py
run_py task250      scripts/task250_i18n_audit.py
run_py task393_r3   scripts/task393_r3_audit.py
run_py task433      scripts/task433_selfcheck.py
run_py task435      scripts/task435_renderer_hook_audit.py
run_py verify161    scripts/verify_task161.py
run_py verify219    scripts/verify_task219.py
run_py verify255    scripts/verify_task255.py
run_py i18n430      scripts/task430_i18n_audit.py
run_py task439      scripts/task439_selfcheck.py
run_py task439_tag  scripts/task439_buildtag_anchor.py
run_py task440      scripts/task440_selfcheck.py
run_py task442      scripts/task442_selfcheck.py
# ★Task452 收编轮：447/449/450/451 四门此前仅单跑未入电池（worklog 声称绿
#   但电池面缺失 = 覆盖口径诚实化），452 新门同步入列
run_py task447      scripts/task447_selfcheck.py
run_py task451      scripts/task451_selfcheck.py
run_py task452      scripts/task452_selfcheck.py
run_py task457      scripts/task457_selfcheck.py

# 括号审计：本轮全部编辑文件逐个过状态机（file args 契约，Task431 判例口径）
EDITED=$(git diff --name-only HEAD --diff-filter=d -- 'Natives/*.m' 'Natives/*.h' 'Natives/**/*.m' 'Natives/**/*.h' 2>/dev/null | grep -v '^Natives/external/' | tr '\n' ' ')
local_rc=0
echo "── bracket (rc=$?) ──"
python3 scripts/ame_bracket_audit.py $EDITED > /tmp/task432_bracket.log 2>&1
local_rc=$?
tail -3 /tmp/task432_bracket.log
if [ $local_rc -eq 0 ]; then RESULT[bracket]="PASS"; else RESULT[bracket]="FAIL(rc=$local_rc)"; fi

# ★Task461 回退树组合执法（重应用四件防线 + 退役面归零 + 粉色钦定形态）
run_py task461     scripts/task461_selfcheck.py

# ★Task462 「其他修改找回」轮执法（449/450/455/460 修改面外科重应用 + 锁定面继承归零 + i18n 54 表回归）
run_py task462     scripts/task462_selfcheck.py
run_py task464     scripts/task464_selfcheck.py
run_py task465     scripts/task465_selfcheck.py

# ★Task466 metallum agent -cp 暴露条件化（Task341 排除面演进：26 会话 Knot
#   白名单恢复 agent jar 在场；旧会话排除保留；headless 不变）
run_py task466     scripts/task466_selfcheck.py

# ★Task467 双线轮（启动链 srg 保环 + 欢迎UI恢复）：ame158 门 BOOL 化 +
#   ame467 三层保环（搁浅回收/processor 自愈/指引弹窗）；Welcome 双文件
#   回注 + SceneDelegate 0.8s 呈现位回填 + 哨兵键回册
run_py task467     scripts/task467_selfcheck.py
run_py task467_self scripts/task467_selfcheck.py --selftest

# ★Task468 MobileGL/Magma 引擎性能旋钮层（抄 Witch-Launcher 调优面）+ 内置渲染器
#   上游更新扫描轮：12 个 MOBILEGL_* setenv（strings 反锚逐名验证 vendored dylib
#   真支持）+ 3 个上游新变量幽灵零引入 + unsetenv 对称清偿 + Task156/158 口径
#   零回归 + Task463 折叠面零污染 + MVK 参数缓冲偏好透传
run_py task468     scripts/ame468_selfcheck.py
run_py task468_self scripts/ame468_selfcheck.py --selftest

echo
echo "════════ 电池总裁决 ════════"
fails=0
for k in "${!RESULT[@]}"; do
  [ "${RESULT[$k]}" != "PASS" ] && { echo "FAIL  $k  ${RESULT[$k]}"; fails=$((fails+1)); }
done
echo "PASS $((${#RESULT[@]} - fails)) / ${#RESULT[@]}  FAIL $fails"
[ $fails -eq 0 ] && echo "Task432 gate battery ALL GREEN"
