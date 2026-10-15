# RISC-V CPU Lab

独立实现、先仿真后上板的五级 RV32IM CPU 学习与实验工程。

目标：五级流水线、冒险处理、1KB 两路数据缓存、64 项分支预测，以及四路 INT8 SIMD 点积扩展。各阶段以测试证据验收，不把目标功能当作已经实现的功能。

## 开发状态

项目正在实施。进度、验收条件和已知问题见 [实施记录](docs/implementation.md)。

## 工具与运行

Windows 使用 Ubuntu 24.04 WSL2。工具安装入口为 `tools/bootstrap.ps1`，统一运行入口为 `run.ps1`。Linux 使用 Makefile 中相同名称的目标。

RTL 使用可综合 SystemVerilog；Verilator 执行周期级仿真，Spike 提供独立指令参考，GTKWave 查看波形。工具版本由安装后生成的记录锁定。

## 参考与边界

参考用户提供的《基于 RISC-V 的 CPU 设计》竞赛报告中的功能目标，从工程原理独立实现。没有原工程源码，不声称逐行还原原作者实现或兼容其专用远程板卡平台。原 PDF 不随仓库分发。

指令语义以 [RISC-V 官方规范](https://docs.riscv.org/reference/isa/) 为准。SIMD 为自定义定长整数运算，不宣称兼容标准 V/P 扩展。

本仓库原创代码采用 MIT 许可证。第三方工具和测试保持各自许可证，见 [来源](docs/sources.md)。
