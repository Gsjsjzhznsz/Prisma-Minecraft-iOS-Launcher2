#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task427 syncSkyPalette 方法体整块替换（锚点： '// ★Task426 天穹三停靠' → '// ★Task426 天气/环境粒子'）"""
import io, sys

PATH = "/home/z/my-project/work416/Natives/ZL2SkinPreviewView.m"

NEW = r'''// ★Task427 天穹五停靠渐变 + 晚霞辉光 + 雾色锚定 + 影罩着色（事件驱动：
//   时间/天气/世界变化）。MC 原版昼夜：天顶蓝→地平亮带；晨昏 = 暖橙混合
//   （低空权重高、天顶低）+ 辉光层（太阳屏位径向暖橙）；夜 = 近黑蓝 + 星空；
//   雾色 = 低空两停靠同源派生（远域地层熔入天穹地平带 = 零色带断裂，
//   Python E 组定量验证）；末地/下界 = 固定专属天穹（无昼夜混合）。
- (void)ame426_syncSkyPalette {
    if (!_ame425_skyLayer) return;
    NSInteger ame425_w = _ame425_world;
    if (ame425_w < AME425_WORLD_PLAINS) return;   // 纯色背景无天穹
    CGFloat ame426_day = [self ame426_daylightFactor];
    CGFloat ame426_s = sin(_ame426_time * 2.0 * M_PI);
    CGFloat ame426_warm = fmax(0.0, 1.0 - fabs(ame426_s) / 0.35);   // 晨昏带
    CGFloat ame426_vis = fmax(0.0, fmin(1.0, ame426_s * 4.0));
    CGFloat ame426_rain = (_ame426_weather == AME426_WEATHER_RAIN) ? 1.0 : 0.0;
    BOOL ame427_staticDim = (ame425_w == AME425_WORLD_END || ame425_w == AME425_WORLD_NETHER);
    if (ame427_staticDim) { ame426_warm = 0.0; ame426_rain = 0.0; ame426_vis = 0.0; }
    // 昼/夜五停靠基色（per world；MC 原版日间天穹蓝梯度 + 夜间近黑蓝）
    CGFloat ame427_D[5] = {0.30, 0.42, 0.55, 0.72, 0.83};
    CGFloat ame427_Dg[5] = {0.47, 0.60, 0.72, 0.84, 0.91};
    CGFloat ame427_Db[5] = {0.92, 0.95, 0.97, 0.99, 1.00};
    CGFloat ame427_N[5] = {0.010, 0.020, 0.040, 0.060, 0.080};
    CGFloat ame427_Ng[5] = {0.016, 0.030, 0.060, 0.090, 0.120};
    CGFloat ame427_Nb[5] = {0.045, 0.080, 0.130, 0.180, 0.220};
    if (ame425_w == AME425_WORLD_SNOW) {
        CGFloat ame427_sD[5] = {0.46, 0.58, 0.70, 0.83, 0.90};
        CGFloat ame427_sDg[5] = {0.60, 0.71, 0.80, 0.89, 0.94};
        CGFloat ame427_sDb[5] = {0.88, 0.92, 0.95, 0.97, 0.99};
        for (NSInteger ame427_i = 0; ame427_i < 5; ame427_i++) {
            ame427_D[ame427_i] = ame427_sD[ame427_i];
            ame427_Dg[ame427_i] = ame427_sDg[ame427_i];
            ame427_Db[ame427_i] = ame427_sDb[ame427_i];
        }
    } else if (ame425_w == AME425_WORLD_END) {
        CGFloat ame427_eD[5] = {0.012, 0.030, 0.055, 0.085, 0.110};
        CGFloat ame427_eDg[5] = {0.008, 0.020, 0.040, 0.060, 0.080};
        CGFloat ame427_eDb[5] = {0.025, 0.060, 0.100, 0.145, 0.180};
        for (NSInteger ame427_i = 0; ame427_i < 5; ame427_i++) {
            ame427_D[ame427_i] = ame427_eD[ame427_i];
            ame427_Dg[ame427_i] = ame427_eDg[ame427_i];
            ame427_Db[ame427_i] = ame427_eDb[ame427_i];
            ame427_N[ame427_i] = ame427_eD[ame427_i];
            ame427_Ng[ame427_i] = ame427_eDg[ame427_i];
            ame427_Nb[ame427_i] = ame427_eDb[ame427_i];
        }
    } else if (ame425_w == AME425_WORLD_NETHER) {
        CGFloat ame427_nD[5] = {0.10, 0.16, 0.24, 0.38, 0.55};
        CGFloat ame427_nDg[5] = {0.02, 0.04, 0.07, 0.12, 0.20};
        CGFloat ame427_nDb[5] = {0.02, 0.03, 0.04, 0.05, 0.06};
        for (NSInteger ame427_i = 0; ame427_i < 5; ame427_i++) {
            ame427_D[ame427_i] = ame427_nD[ame427_i];
            ame427_Dg[ame427_i] = ame427_nDg[ame427_i];
            ame427_Db[ame427_i] = ame427_nDb[ame427_i];
            ame427_N[ame427_i] = ame427_nD[ame427_i];
            ame427_Ng[ame427_i] = ame427_nDg[ame427_i];
            ame427_Nb[ame427_i] = ame427_nDb[ame427_i];
        }
    }
    CGFloat ame426_top[5], ame426_mid[5], ame426_bot[5];
    CGFloat ame427_warmW[5] = {0.30, 0.52, 0.98, 1.00, 1.00};   // 晨昏暖权重（天顶低、地平带高）
    for (NSInteger ame427_i = 0; ame427_i < 5; ame427_i++) {
        CGFloat ame427_c[3];
        CGFloat ame427_dn[3] = {ame427_D[ame427_i], ame427_Dg[ame427_i], ame427_Db[ame427_i]};
        CGFloat ame427_nn[3] = {ame427_N[ame427_i], ame427_Ng[ame427_i], ame427_Nb[ame427_i]};
        for (NSInteger ame427_j = 0; ame427_j < 3; ame427_j++) {
            ame427_c[ame427_j] = ame427_nn[ame427_j]
                + (ame427_dn[ame427_j] - ame427_nn[ame427_j]) * ame426_day;
        }
        // 晨昏暖橙混合（暮色靶：低空橙红 → 中带粉紫 → 天顶保持蓝）
        CGFloat ame427_t0 = 0.42 + 0.58 * ame427_warmW[ame427_i];
        CGFloat ame427_t1 = 0.65 - 0.35 * ame427_warmW[ame427_i];
        CGFloat ame427_t2 = 0.62 - 0.40 * ame427_warmW[ame427_i];
        CGFloat ame427_mix = ame426_warm * 0.62 * ame427_warmW[ame427_i];
        ame427_c[0] += (ame427_t0 - ame427_c[0]) * ame427_mix;
        ame427_c[1] += (ame427_t1 - ame427_c[1]) * ame427_mix;
        ame427_c[2] += (ame427_t2 - ame427_c[2]) * ame427_mix;
        // 雨天降饱和压暗（朝灰蓝靠拢）
        CGFloat ame427_rm = ame426_rain * 0.55 * ame426_day;
        ame427_c[0] += (0.42 - ame427_c[0]) * ame427_rm;
        ame427_c[1] += (0.47 - ame427_c[1]) * ame427_rm;
        ame427_c[2] += (0.55 - ame427_c[2]) * ame427_rm;
        ame426_top[ame427_i] = ame427_c[0];
        ame426_mid[ame427_i] = ame427_c[1];
        ame426_bot[ame427_i] = ame427_c[2];
    }
    // 雾色 = 低空两停靠同源派生（★雾-天穹锚定）+ 暮色补暖
    CGFloat ame426_fog[3];
    for (NSInteger ame427_j = 0; ame427_j < 3; ame427_j++) {
        CGFloat ame427_lo = ame426_mid[ame427_j] * 0.55 + ame426_bot[ame427_j] * 0.45;
        CGFloat ame427_wt = (ame427_j == 0) ? 1.0 : (ame427_j == 1) ? 0.60 : 0.32;
        ame426_fog[ame427_j] = ame427_lo + (ame427_wt - ame427_lo) * ame426_warm * 0.30;
    }
    _ame426_fogTint = [UIColor colorWithRed:ame426_fog[0] green:ame426_fog[1] blue:ame426_fog[2] alpha:1.0];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _ame425_skyLayer.colors = @[
        (id)[UIColor colorWithRed:ame426_top[0] green:ame426_mid[0] blue:ame426_bot[0] alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:ame426_top[1] green:ame426_mid[1] blue:ame426_bot[1] alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:ame426_top[2] green:ame426_mid[2] blue:ame426_bot[2] alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:ame426_top[3] green:ame426_mid[3] blue:ame426_bot[3] alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:ame426_top[4] green:ame426_mid[4] blue:ame426_bot[4] alpha:1.0].CGColor];
    if (_ame426_glowLayer) {
        _ame426_glowLayer.opacity = ame426_warm * ame426_vis * 0.62;
    }
    if (_ame426_starLayer) {
        _ame426_starLayer.opacity = (ame425_w == AME425_WORLD_END)
            ? 0.85 : (1.0 - ame426_day) * 0.9 * (1.0 - ame426_rain * 0.7);
    }
    if (_ame426_gradeLayer) {
        // 色调映射层择主：夜蓝 / 晨昏暖橙 / 雨灰蓝 / 维度暗幕 / 晴零
        if (ame425_w == AME425_WORLD_NETHER) {
            _ame426_gradeLayer.backgroundColor = [UIColor colorWithRed:0.55 green:0.12 blue:0.03 alpha:1.0].CGColor;
            _ame426_gradeLayer.opacity = 0.10;
        } else if (ame425_w == AME425_WORLD_END) {
            _ame426_gradeLayer.backgroundColor = [UIColor colorWithRed:0.22 green:0.10 blue:0.34 alpha:1.0].CGColor;
            _ame426_gradeLayer.opacity = 0.10;
        } else if (ame426_rain > 0.0 && ame426_day > 0.3) {
            _ame426_gradeLayer.backgroundColor = [UIColor colorWithRed:0.32 green:0.40 blue:0.52 alpha:1.0].CGColor;
            _ame426_gradeLayer.opacity = 0.12 * ame426_day;
        } else if (1.0 - ame426_day > ame426_warm) {
            _ame426_gradeLayer.backgroundColor = [UIColor colorWithRed:0.12 green:0.18 blue:0.38 alpha:1.0].CGColor;
            _ame426_gradeLayer.opacity = 0.12 * (1.0 - ame426_day);
        } else if (ame426_warm > 0.02) {
            _ame426_gradeLayer.backgroundColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.20 alpha:1.0].CGColor;
            _ame426_gradeLayer.opacity = 0.16 * ame426_warm;
        } else {
            _ame426_gradeLayer.opacity = 0.0;
        }
    }
    // ★Task427 世界面雾色 + 模型影罩/白亮罩着色（Photon 彩色光照：影随天色、
    //   亮随日光色温；事件驱动一次性写 = 逐帧热路径零开销）
    for (ZL2SkinViewFace *ame427_wf in _ame425_groundFaces) {
        if (ame427_wf.shade) ame427_wf.shade.backgroundColor = _ame426_fogTint.CGColor;
    }
    CGFloat ame427_shD[3] = {0.02, 0.04, 0.10};
    CGFloat ame427_shN[3] = {0.05, 0.09, 0.22};
    CGFloat ame427_sh[3];
    for (NSInteger ame427_j = 0; ame427_j < 3; ame427_j++) {
        ame427_sh[ame427_j] = ame427_shN[ame427_j] + (ame427_shD[ame427_j] - ame427_shN[ame427_j]) * ame426_day;
        if (ame427_j == 0) ame427_sh[ame427_j] += ame426_warm * 0.30;
        else if (ame427_j == 1) ame427_sh[ame427_j] += ame426_warm * 0.05;
    }
    _ame426_shadowTint = [UIColor colorWithRed:fmin(1.0, ame427_sh[0]) green:ame427_sh[1] blue:ame427_sh[2] alpha:1.0];
    _ame426_hlTint = [UIColor colorWithRed:1.0 green:(1.0 - 0.18 * ame426_warm) blue:(1.0 - 0.45 * ame426_warm) alpha:1.0];
    for (ZL2SkinViewFace *ame427_mf in _ame413_faceLayers) {
        if (ame427_mf.shade) ame427_mf.shade.backgroundColor = _ame426_shadowTint.CGColor;
        if (ame427_mf.hl) ame427_mf.hl.backgroundColor = _ame426_hlTint.CGColor;
    }
    [CATransaction commit];
}

'''

with io.open(PATH, "r", encoding="utf-8") as f:
    src = f.read()

start_anchor = "// ★Task426 天穹三停靠渐变 + 星空 + 色调映射层（事件驱动：时间/天气/世界变化）"
end_anchor = "// ★Task426 天气/环境粒子（CAEmitterLayer）"
si = src.index(start_anchor)
ei = src.index(end_anchor)
src2 = src[:si] + NEW + src[ei:]
with io.open(PATH, "w", encoding="utf-8") as f:
    f.write(src2)
print("syncSkyPalette spliced: removed %d chars, inserted %d chars" % (ei - si, len(NEW)))
