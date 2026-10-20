# Vendored third-party sources

这份目录登记 `Packages/MoonlightClient` 内所有随源码分发的上游组件的来源。上游原样文件按上游目录结构保存在 `Sources/` 内，本地修改直接落在源文件上。

## moonlight-common-c

- 仓库：https://github.com/moonlight-stream/moonlight-common-c
- 固定提交：`f900dd4767759c7b9d0e93bcea666b55c69ea62f`（子模块指针来源：moonlight-ios `02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a`）
- 位置：`Sources/CMoonlightCore/common`（`src/`）、`Sources/CMoonlightCore/enet`（enet 子模块）、`Sources/CMoonlightCore/nanors`（nanors 子模块）
- 未编译：`nanors/rs16*.c`、`nanors/deps/obl/oblas16*.c`（上游 CMake 同样不编译）
- 许可：GPLv3 全文 + App Store Distribution Exception，`Vendor/Licenses/moonlight-common-c-LICENSE.txt`

## OpenSSL

- 由 `Scripts/build_openssl.sh` 构建为 `Vendor/OpenSSL/OpenSSL.xcframework`（不进入版本控制）
- 静态头快照：`Sources/COpenSSL/include/openssl`

## libopus

- 由 `Scripts/build_libopus.sh` 构建为 `Vendor/Opus/Opus.xcframework`（不进入版本控制）
- 静态头快照：`Sources/COpus/include/opus`

## moonlight-ios 迁移代码

- 仓库：https://github.com/moonlight-stream/moonlight-ios
- 固定提交：`02dc9780496eeeac6d01c8bbdccb8b6fe71ef28a`
- 迁移文件逐个在 `Sources/MoonlightBridge` 内标注上游路径（文件头注释）；修改记录在文件内。
