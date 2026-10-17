# RISC-V CPU Lab

[![RTL tests](https://github.com/gaog5844-ctrl/riscv-cpu-lab/actions/workflows/verify.yml/badge.svg)](https://github.com/gaog5844-ctrl/riscv-cpu-lab/actions/workflows/verify.yml)

SystemVerilog 实现的五级 RV32IM 处理器，带 1KB 数据缓存、动态分支预测和三条定长 SIMD 指令。仓库包含 RTL、Verilator 仿真环境、Spike 参考扩展及 C 测试程序。

## 处理器

| 项目 | 配置 |
| --- | --- |
| 流水线 | IF / ID / EX / MEM / WB，单发射、顺序执行 |
| 整数指令 | RV32I 的 37 条计算、访存与控制指令，8 条 M 扩展指令 |
| 数据缓存 | 1KB，2 路组相联，32B 缓存行，LRU，写回、写分配 |
| 分支预测 | 64 项带标签 BTB，64 个两位饱和计数器 |
| SIMD | `xadd8`、`xadd16`、`xdot8`，复用 32 位通用寄存器 |
| 存储接口 | 独立 I/D 请求与响应通道，valid/ready 握手 |

支持数据前递、load-use 停顿、分支冲刷，以及 FENCE、ECALL、EBREAK。异常通过提交接口报告后停机，尚未实现 CSR、特权级切换和中断。SIMD 使用 custom-0 编码，不是标准 RVV。

顶层为 [`rv32_system`](rtl/rv32_system.sv)，由处理器核心和数据缓存组成。RAM、MMIO 及程序加载由仿真环境提供；开发板尚未确定。

缓存使能在复位时锁存，不支持运行中切换。保留 RAM 内容并重启前需完成 FENCE；写回错误会报告异常，已写入后端的字不回滚。接口约定见 [处理器结构](docs/architecture.md)。

## 开始运行

Windows 需要名为 `Ubuntu-24.04` 的 WSL 发行版。首次使用：

~~~powershell
git clone https://github.com/gaog5844-ctrl/riscv-cpu-lab.git D:\Projects\riscv-cpu-lab
cd D:\Projects\riscv-cpu-lab
.\tools\bootstrap.ps1
.\run.ps1 test
~~~

Ubuntu 24.04 原生环境：

~~~bash
git clone https://github.com/gaog5844-ctrl/riscv-cpu-lab.git
cd riscv-cpu-lab
sudo bash tools/install-system.sh
bash tools/install-user.sh
make test
~~~

`test` 运行 RTL 检查、模块测试和 Spike 差分测试。首次构建包含 Spike 编译，需要较长时间。版本及安装说明见 [环境配置](docs/toolchain.md)。

| 命令 | 用途 |
| --- | --- |
| `.\run.ps1 doctor` | 检查工具链 |
| `.\run.ps1 test` | 运行功能回归 |
| `.\run.ps1 bench` | 比较标量与 SIMD 程序 |
| `.\run.ps1 wave` | 生成 `build/smoke.fst` |
| `.\run.ps1 synth` | 使用本机 Vivado 综合核心 |

Linux / WSL 中使用 `make doctor`、`make test` 等同名目标。仿真不依赖 Vivado。

Vivado 2026.1 裸核综合使用 `xc7a35tcsg324-1`：12,566 LUT、15,731 FF、4 DSP。10ns 约束下 WNS 为 -5.763ns，未满足时序目标；尚未布局布线和上板。

## SIMD 性能

下表使用 GCC `-O2 -march=rv32im -mabi=ilp32`。缓存和分支预测开启，后端响应延迟为 1 周期；每次复位后从冷缓存开始计时，包含函数调用与 FENCE 写回，不包含输入生成和结果检查。

| 程序 | 标量周期 | SIMD 周期 | 加速比 |
| --- | ---: | ---: | ---: |
| INT8 点积，259 元素 | 3,247 | 1,071 | 3.03× |
| 逐字节加法，259 元素 | 4,285 | 1,531 | 2.80× |
| INT8 矩阵向量乘，12 × 67 | 9,691 | 3,148 | 3.08× |

这是同一核心上两种程序实现的仿真周期比较，不是与其他处理器的性能比较。关闭缓存及增加内存延迟的结果见 [性能测试](docs/benchmarks.md)。

## 测试

回归测试按指令比较 RTL 与 Spike 的 PC、编码、写回值、下一 PC 和访存记录。正常访存用例还会在 FENCE 后比较整个 1MiB RAM。

目前有 46 组主回归、25 组审查补充回归、6 组冒烟和 24 组性能配置。另有比较器负向测试、68,683 组独立 SIMD 数学对照，以及缓存逐字故障与恢复检查。测试方法和异常约定见 [测试说明](docs/verification.md)；尚未接入官方架构测试套件或形式化验证。

## 代码与文档

| 路径 | 内容 |
| --- | --- |
| `rtl/` | 核心、译码、运算单元、缓存和预测器 |
| `sim/` | Verilator 驱动及 Spike 自定义指令扩展 |
| `tests/` | 模块测试、汇编用例和随机回归 |
| `sw/` | SIMD C 接口头文件（`include/xsimd.h`） |
| `benchmarks/` | 点积、数组加法和矩阵向量乘测试 |
| `tools/` | 安装、环境检查及综合脚本 |

- [设计报告](docs/design-report.md)
- [流水线与存储接口](docs/architecture.md)
- [SIMD 编码与 C 接口](docs/xsimd.md)
- [首次运行与代码阅读](docs/first-lab.md)
- [开发记录](docs/implementation.md)
- [审查意见核对与处理](docs/review-response.md)

## 来源与许可

项目按一份 CPU 设计竞赛报告的功能配置重新实现，未使用原工程 RTL。参考资料列在 [sources.md](docs/sources.md)，原报告及私有板卡资料未随仓库分发。

代码使用 [MIT 许可证](LICENSE)。
