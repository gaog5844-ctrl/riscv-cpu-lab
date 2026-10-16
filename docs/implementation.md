# 开发记录

## 2026-10-15：仿真版本

完成五级 RV32IM 核心、1KB 两路数据缓存和 64 项 BHT/BTB，并加入 `xadd8`、`xadd16`、`xdot8` 三条指令。仓库同时包含 C 调用封装、Spike 扩展、测试程序和波形生成脚本。

开发环境为 Windows 11、Ubuntu 24.04 WSL2，处理器 i5-11320H，内存约 16GB。具体版本见 [环境配置](toolchain.md)。

### 测试记录

`make doctor test bench wave` 全部通过，结果如下：

- 运算单元比较 13,414 次，缓存检查 139 项，预测器检查 10 项。
- 主回归共 46 组配置，33,003 次正常指令提交与 Spike 一致；另有 6 组冒烟配置。
- 24 组性能测试均通过数学结果检查、Spike 比较和 FENCE 后的 RAM 比较。
- 从 GitHub 重新克隆，在没有旧构建产物的目录中依次运行 `run.ps1 doctor/test/bench/wave`，回归和性能结果与原目录一致。检查副本保留在 `D:/Projects/riscv-cpu-lab-cleancheck-20261015`。
- Markdown 本地链接检查通过。原 PDF 和私有平台资料未加入 Git。

对应的 CI 记录：

|提交|内容|结果|
|---|---|---|
|`a4c4a53`|缓存、Spike 对照和 SIMD 基准|[通过](https://github.com/gaog5844-ctrl/riscv-cpu-lab/actions/runs/38757609741)|
|`7b36020`|文档和运行入口|[通过](https://github.com/gaog5844-ctrl/riscv-cpu-lab/actions/runs/38759320761)|
|`086b3c9`|main 分支仿真版本|[通过](https://github.com/gaog5844-ctrl/riscv-cpu-lab/actions/runs/38759877042)|

### Vivado 问题

原报告使用的 `xc7k325tffg900-2` 器件支持未安装。改用已安装的 `xc7a35tcsg324-1` 后，各模块综合结束，但 Vivado 随后以 `-1073740940` 退出。最小四位加法器工程也有类似现象；当日未完成综合。

日志保存在 `build/synth/`。目前没有位流、布局布线结果或上板测试记录。

## 2026-10-16：综合与设计报告

为 RTL 引擎设置独立英文临时目录，复制后续优化使用的 `elab.rtd` 后，完整 CPU 综合通过。DCP 保存时的附加元数据路径错误，通过将 `-tempDir` 参数中的反斜杠改为 `/` 消除；独立保存、重新打开 DCP 的复测无 ERROR，读回 32,785 个层次单元和一个 clk 约束。

最终从 RTL 完整复跑的记录为 `build/synth/runs/20261016-143704-c8e8bddd/`：退出码 0、ERROR 数量 0、报告和 DCP 齐全、检查点回读通过。负向测试模拟“退出码 0、产物齐全但日志包含 ERROR”，脚本正确拒绝并恢复调用者的环境变量。

本次综合使用 12,221 个 LUT、15,736 个触发器和 4 个 DSP，没有推断出 RAM。10ns 约束下 WNS 为 -5.763ns，尚未达到时序目标。资源和关键路径记录在 [设计报告](design-report.md)。

综合脚本改为每次新建结果目录，并检查退出码、ERROR 日志、报告、DCP 和回读结果，避免使用旧的通过标记。`make doctor test bench wave` 再次通过，回归与性能 JSON 的 SHA-256 与修改前相同。此次未修改 RTL。

提交 `815b13e` 的 [GitHub CI](https://github.com/gaog5844-ctrl/riscv-cpu-lab/actions/runs/38862404326) 通过。下载其验证产物后，`regression-summary.json` 和 `benchmarks.json` 与本机文件逐字节一致。CI 验证仿真和编译流程，不包含 Vivado 综合。

## 待办

- 调整缓存 RAM 推断和乘法相关关键路径，减少面积及组合延迟。
- 确认可用开发板及其时钟、引脚、存储器和外设配置，再做板级适配。
- 测试热缓存、突发访存后端和更大输入规模下的性能。

当前版本未实现更深流水、双发射、完整 RVV/P、CSR、中断或操作系统支持。后续是否加入这些功能，需要结合综合结果和性能瓶颈决定。
