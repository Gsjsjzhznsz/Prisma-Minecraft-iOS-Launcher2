#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task467 i18n 双键全量填充（启动链 srg 保环 Tier C 指引弹窗）：
  i18n_str_ame467_srg_missing_title / i18n_str_ame467_srg_missing
54 表同步（zh 家族中文 / ja 日文 / 其余英文兜底）；幂等（已存在即跳过）；
换行风格按各表现状自适应（CRLF/LF）。用法：python3 scripts/task467_i18n.py
"""
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RES = REPO / "Natives" / "resources"

ZH = {
    "i18n_str_ame467_srg_missing_title": "无法启动：NeoForge 映射产物缺失",
    "i18n_str_ame467_srg_missing": "缺少 NeoForge 安装时由本机处理器生成的映射 jar（%@）。\\n\\n请在版本管理中重新安装 NeoForge，或重新导入该实例后再启动游戏。",
}
JA = {
    "i18n_str_ame467_srg_missing_title": "起動できません：NeoForge マップ済み成果物が不足",
    "i18n_str_ame467_srg_missing": "NeoForge インストール時にローカル プロセッサが生成するマッピング jar（%@）が見つかりません。\\n\\nバージョン管理から NeoForge を再インストールするか、このインスタンスを再インポートしてからゲームを起動してください。",
}
EN = {
    "i18n_str_ame467_srg_missing_title": "Cannot launch: NeoForge mapped artifacts missing",
    "i18n_str_ame467_srg_missing": "The NeoForge mapping jar (%@), which is generated locally by installer processors, is missing.\\n\\nReinstall NeoForge from version management, or re-import this instance, then launch the game again.",
}

KEYS = ("i18n_str_ame467_srg_missing_title", "i18n_str_ame467_srg_missing")


def pick(lang):
    if lang.startswith("zh"):
        return ZH
    if lang == "ja":
        return JA
    return EN


def main():
    if not RES.is_dir():
        print("[FAIL] resources dir missing")
        return 1
    tables = sorted(RES.glob("*.lproj/Localizable.strings"))
    if not tables:
        print("[FAIL] no strings tables found")
        return 1
    added, skipped = 0, 0
    for table in tables:
        lang = table.parent.name.replace(".lproj", "")
        values = pick(lang)
        text = table.read_text(encoding="utf-8")
        crlf = "\r\n" in text
        nl = "\r\n" if crlf else "\n"
        pending = [k for k in KEYS if f'"{k}"' not in text]
        if not pending:
            skipped += 1
            continue
        if text and not text.endswith(("\n", "\r")):
            text += nl
        for k in pending:
            text += f'"{k}" = "{values[k]}";' + nl
            added += 1
        table.write_text(text, encoding="utf-8", newline="")
        print(f"  +{len(pending)} {lang}  ({'CRLF' if crlf else 'LF'})")
    print(f"[DONE] tables={len(tables)} added={added} tables-already-complete={skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
