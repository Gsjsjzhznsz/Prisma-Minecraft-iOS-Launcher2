# libMobileGL.dylib / libMoltenVK.dylib 产物出处档案（Task469）

- 升级轮：Task469 · 2026-11-23（用户钦定「继续优化和真正的升级渲染器」）
- libMobileGL.dylib
  - sha256: `fd907f655061aaa919970e372d3514924423cb8213ea6692a11749bd0db68c60`
  - size: 16447088 B（旧代 e7a8043b… = 85757760 B 未剥离构建，同轮退役）
  - 构建: GIT@8df5508 · Timestamp 2026-10-16T06:50:27 · vulkan-sdk-1.4.321.0-49-g07244428 基线
  - 来源: Ynnyny/MobileGL-fix（Witch-Launcher 的 MobileGL fork）@ 8df55081
    「fix(ios): DirectGLES MetalANGLE GLES32 shim + loader/EGL iOS fixes」
    （上游 = MobileGL-Dev/MobileGL，Desktop OpenGL 4.6 over DirectVulkan/DirectGLES，
    Magma = Vulkan 后端 / Espryt = GLES 后端）
  - 自带修复面: MC 26.3 几何/UI 间歇性损坏修复（fff9d639 resident buffer ordering）+
    VMA 块尺寸配置（a5201690）+ iOS loader/EGL 修复 + MetalANGLE GLES32 shim（8df55081）
- libMoltenVK.dylib
  - sha256: `3378bf8d6fd1e5bdc9bb4ae5b6c8157e3f0f9529c0c3719d483d610d2cdceba1`
  - size: 14769224 B（旧代 73cb7379… = 4904816 B 同轮退役）
  - 与新 dylib 同仓配套（Vulkan 1.4 SDK 配套面），@rpath/libMoltenVK.dylib 运行时解析
- 幽灵旋钮转正: MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB（默认32，钳8..256）/
  MOBILEGL_LARGE_BUFFER_ADOPT_MB（默认4，钳1..64）/ MOBILEGL_ANGLE_BACKEND（tgles|vulkan）
  —— fork 源码级实锚（MobileGL/ConfigLoader.cpp + MG_Util/BackendLoaders/OpenGL/Loader.cpp）
- 门禁: scripts/ame468_selfcheck.py S10（尺寸 + sha256 + GIT@ 标记 + 本档案互证）；
  装机日志锚 [JavaLauncher] Task469: MobileGL perf knobs applied
- 旧代出处（留档）: Amethyst-iOS-MyRemastered vendor 线，sha256 e7a8043b…（85757760 B，
  GIT@874b9e8 · 2026-09-05T02:34:22）
