#!/usr/bin/env python3
# Task333 i18n：ame.super 完全接管 + ame333.repo.* 远程仓库键，四表一致追加
# （幂等：已存在即跳过）
import os

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
NAT = os.path.join(REPO, 'Natives', 'resources')

TABLES = {
    'en': [
        ('ame317.perm.ame.super.name', 'Full takeover (super)'),
        ('ame317.perm.ame.super.desc', 'Highest-level grant: the plugin can use ALL launcher APIs and every permission gate passes; all other switches are greyed out while enabled'),
        ('ame333.repo.section_remote', 'Official plugin repo'),
        ('ame333.repo.section_builtin', 'Bundled plugins'),
        ('ame333.repo.fetching', 'Fetching plugin repo index…'),
        ('ame333.repo.fetch_fail', 'Repo unreachable — check network and retry'),
        ('ame333.repo.fetch_empty', 'Repo index is empty'),
        ('ame333.repo.install', 'Install'),
        ('ame333.repo.update', 'Update'),
        ('ame333.repo.sha_mismatch', 'Download integrity check failed (sha256 mismatch), install aborted'),
    ],
    'zh-Hans': [
        ('ame317.perm.ame.super.name', '完全接管（超级权限）'),
        ('ame317.perm.ame.super.desc', '最高级别授权：插件可调用启动器全部 API 且所有权限闸直接放行；开启期间其余权限开关变灰禁用'),
        ('ame333.repo.section_remote', '官方插件仓库'),
        ('ame333.repo.section_builtin', '包内预置插件'),
        ('ame333.repo.fetching', '正在拉取插件仓库索引…'),
        ('ame333.repo.fetch_fail', '仓库不可达——请检查网络后重试'),
        ('ame333.repo.fetch_empty', '仓库索引为空'),
        ('ame333.repo.install', '安装'),
        ('ame333.repo.update', '可更新'),
        ('ame333.repo.sha_mismatch', '下载完整性校验失败（sha256 不符），已中止安装'),
    ],
    'zh-CN': [
        ('ame317.perm.ame.super.name', '完全接管（超级权限）'),
        ('ame317.perm.ame.super.desc', '最高级别授权：插件可调用启动器全部 API 且所有权限闸直接放行；开启期间其余权限开关变灰禁用'),
        ('ame333.repo.section_remote', '官方插件仓库'),
        ('ame333.repo.section_builtin', '包内预置插件'),
        ('ame333.repo.fetching', '正在拉取插件仓库索引…'),
        ('ame333.repo.fetch_fail', '仓库不可达——请检查网络后重试'),
        ('ame333.repo.fetch_empty', '仓库索引为空'),
        ('ame333.repo.install', '安装'),
        ('ame333.repo.update', '可更新'),
        ('ame333.repo.sha_mismatch', '下载完整性校验失败（sha256 不符），已中止安装'),
    ],
    'zh-Hant': [
        ('ame317.perm.ame.super.name', '完全接管（超級權限）'),
        ('ame317.perm.ame.super.desc', '最高級別授權：插件可呼叫啟動器全部 API 且所有權限閘直接放行；開啟期間其餘權限開關變灰停用'),
        ('ame333.repo.section_remote', '官方插件倉庫'),
        ('ame333.repo.section_builtin', '套件內預置插件'),
        ('ame333.repo.fetching', '正在擷取插件倉庫索引…'),
        ('ame333.repo.fetch_fail', '倉庫無法連線——請檢查網路後重試'),
        ('ame333.repo.fetch_empty', '倉庫索引為空'),
        ('ame333.repo.install', '安裝'),
        ('ame333.repo.update', '可更新'),
        ('ame333.repo.sha_mismatch', '下載完整性校驗失敗（sha256 不符），已中止安裝'),
    ],
}

def main():
    fails = 0
    for lang, keys in TABLES.items():
        path = os.path.join(NAT, f'{lang}.lproj', 'Localizable.strings')
        text = open(path, encoding='utf-8').read()
        added = 0
        with open(path, 'a', encoding='utf-8') as f:
            for k, v in keys:
                line = f'"{k}" = "{v}";\n'
                if f'"{k}"' in text:
                    print(f'SKIP {lang} {k} (exists)')
                    continue
                f.write(line)
                added += 1
        print(f'{lang}: +{added} keys')

if __name__ == '__main__':
    main()
