/*
 * Copyright (c) NeoForged and contributors
 * SPDX-License-Identifier: LGPL-2.1-only
 *
 * ★Ame483 PATCH SOURCE（不在 JavaApp/src 编译 glob 内；编译产物以
 * FatalErrorReporting.class.patch 形态提交于 JavaApp/libs/ame_patches/，
 * 由 PatchSVC agent 在 fml_loader 12.0.8 精确代际门下替换原类）。
 * 基线 = net.neoforged.fancymodloader:loader:12.0.8 官方 sources，唯一 delta
 * = reportFatalError(String)：iOS 无 Swing 显示面，模态对话框永不返回 =
 * 「无法启动」挂死表象；错误全文只进对话框 = 装机日志零可见。改为把完整
 * 错误链打进 stdout（latestlog 全量捕获）后干净 exit(1)，交由启动器
 * 看门狗（Task251/Task86/Ame251 marker）有序收尾。
 */

package net.neoforged.fml.startup;

import java.awt.GraphicsEnvironment;
import java.awt.Image;
import java.awt.image.BaseMultiResolutionImage;
import java.io.IOException;
import java.lang.reflect.InvocationTargetException;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import javax.imageio.ImageIO;
import javax.swing.ImageIcon;
import javax.swing.JOptionPane;
import javax.swing.UIManager;
import net.neoforged.fml.ModLoadingException;
import net.neoforged.fml.ModLoadingIssue;
import net.neoforged.fml.i18n.FMLTranslations;
import net.neoforged.fml.loading.ImmediateWindowHandler;
import org.jetbrains.annotations.Nullable;
import org.lwjgl.sdl.SDLMessageBox;

/**
 * Handles reporting of fatal errors for UI-based entrypoints (i.e. clients).
 */
public final class FatalErrorReporting {
    private FatalErrorReporting() {}

    private static Throwable unwrapException(Throwable t) {
        if (t == null) {
            return null;
        }
        var cause = t.getCause();
        if (cause == null) {
            return t; // Cannot unwrap without a cause.
        }

        if (t instanceof InvocationTargetException) {
            return cause;
        }
        return t;
    }

    public static void reportFatalError(Throwable t) {
        Path gameDir = null;
        if (t instanceof FatalStartupException fatalStartupException) {
            gameDir = fatalStartupException.getStartupArgs().gameDirectory();
        }
        reportFatalError(t, gameDir, null, null);
    }

    public static void reportFatalError(Throwable t, @Nullable Path gameDir, @Nullable Path logFile, @Nullable Path crashReport) {
        var issues = new ArrayList<ModLoadingIssue>();
        collectModLoadingIssues(t, issues);

        if (issues.isEmpty()) {
            t = unwrapException(t);

            if (t instanceof FatalStartupException e) {
                var errorText = new StringBuilder(e.getMessage());
                if (e.getCause() != null) {
                    errorText.append("\n\nTechnical Details:\n");
                    appendAbbreviatedExceptionChain(unwrapException(e.getCause()), errorText);
                }

                issues.add(ModLoadingIssue.error("fml.modloadingissue.technical_error", errorText).withCause(t));
            } else {
                var exceptionText = new StringBuilder();
                appendAbbreviatedExceptionChain(t, exceptionText);

                issues.add(ModLoadingIssue.error("fml.modloadingissue.technical_error", exceptionText).withCause(t));
            }
        }

        // This should exit after showing the error
        ImmediateWindowHandler.displayFatalErrorAndExit(
                issues,
                gameDir != null ? gameDir.resolve("mods") : null,
                logFile,
                crashReport);

        // When we get here, there was no immediate window provider loaded. We crashed before that got loaded.
        var errorReport = new StringBuilder();
        for (var issue : issues) {
            errorReport.append(FMLTranslations.translateIssue(issue));
        }
        reportFatalError(errorReport.toString());
    }

    private static void collectModLoadingIssues(Throwable t, List<ModLoadingIssue> issues) {
        if (t instanceof ModLoadingException e) {
            issues.addAll(e.getIssues());
        }

        for (var suppressed : t.getSuppressed()) {
            collectModLoadingIssues(suppressed, issues);
        }

        if (t.getCause() != null) {
            collectModLoadingIssues(t.getCause(), issues);
        }
    }

    private static void appendAbbreviatedExceptionChain(Throwable t, StringBuilder exceptionText) {
        boolean first = true;
        while (t != null) {
            if (first) {
                exceptionText.append("  ").append(t).append('\n');
                first = false;
            } else {
                exceptionText.append(" \u21b3").append(t).append('\n');
            }
            t = unwrapException(t.getCause());
        }
    }

    public static void reportFatalErrorOnConsole(Throwable t) {
        t = unwrapException(t);
        t.printStackTrace();
    }

    /**
     * Report a fatal startup error.
     * At this point, it doesn't matter if we double-classload from the system classloader, since we're about to exit.
     */
    public static void reportFatalError(String message) {
        message = message.replaceAll("\u00a7[0-9a-fk-or]", "");

        // ★Ame483（iOS 致命错可见化，本补丁唯一 delta）：
        // 完整错误链（含原始 Error 的类名与消息）直接进启动器日志，随后
        // exit(1)。桌面 Swing/SDL 分支整体退役——iOS 上两者都无法呈现/返回。
        System.out.println("[FML-FATAL] Fatal startup error (iOS dialog suppressed by ame483 patch). Full report follows:");
        System.out.println(message);
        System.out.flush();
        System.exit(1);
    }

    private static void showErrorUsingSwing(String message) {
        try {
            UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName());
        } catch (Exception ignored) {}
        String html = "<html><body width='400'><strong>Fatal Startup Error</strong>"
                + "<p><pre>";
        html += escapeHtmlContent(message);

        var icon = new ImageIcon(createMultiResImage());
        JOptionPane.showMessageDialog(null, html, "Fatal Error", JOptionPane.ERROR_MESSAGE, icon);
    }

    private static BaseMultiResolutionImage createMultiResImage() {
        var images = new ArrayList<Image>();
        readImage("crash-32x32.png", images);
        readImage("crash-64x64.png", images);
        readImage("crash-128x128.png", images);
        return new BaseMultiResolutionImage(images.toArray(Image[]::new));
    }

    private static void readImage(String filename, List<Image> images) {
        try {
            var image = ImageIO.read(FatalErrorReporting.class.getResource(filename));
            images.add(image);
        } catch (IOException ignored) {}
    }

    /**
     * & &amp;
     * < &lt;
     * > &gt;
     * " &quot;
     * ' &#x27;
     */
    private static String escapeHtmlContent(String content) {
        return content
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#x27;");
    }
}
