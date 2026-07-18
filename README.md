# nabu Droidspaces + ReKernel-X kernel builder

为小米 Pad 5（`nabu`）构建基于 neokoni 4.14 内核的可替换内核镜像，保留：

- KernelSU（rsuntk fork，内置模式）
- Droidspaces 所需的 PID/IPC/Mount/UTS/User namespace 与 devtmpfs
- ReKernel-X 墓碑内核支持

仓库只保存可审计的构建流程，不复制上游内核源码。所有上游依赖均锁定到明确提交。

`configs/nabu-running.config` 直接提取自已验证可启动的 Droidspaces boot；构建只在其基础上启用 ReKernel-X，避免误用上游通用 ARM64 配置。

构建将厂商配置中的 Full LTO 切换为内核原生支持的 ThinLTO，以控制 GitHub Runner 最终链接阶段的内存峰值；LTO 本身仍保持启用。

## 产物

GitHub Actions 会生成：

- `Image`：用于替换现有可启动 boot 中的 kernel
- `build-info.txt`：源码、KernelSU、ReKernel-X 与编译器版本
- `.config`：实际构建配置

> 此仓库不会自动刷机，也不会覆盖当前稳定 boot。

## 锁定版本

- Kernel: `neokoni/android_kernel_xiaomi_nabu@79ac1a92d69a248e76a032f7ab37ab8acee8f17c`
- KernelSU: `rsuntk/KernelSU@648e5988cf421172769f80ce07f86331b548c053`
- ReKernel-X: `myflavor/ReKernel-X@6f9f96dfc725ce12410c8258464a6edd7ec8ca36`
- Clang: Android `clang-r563880c`
