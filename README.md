# RISC-V CPU Lab

五级 RV32IM CPU 的独立实现与可复现实验：SystemVerilog RTL → Verilator 周期仿真 → Spike 逐条指令对照 → 自定义 INT8 SIMD 性能实验。

不是原竞赛源码的搬运，也不是用软件解释器冒充硬件。复现给定功能目标，不宣称精确还原原作者的内部结构、频率或平台。

## 已实现

- IF / ID / EX / MEM / WB，单发射、顺序执行与提交；前递、停顿、冲刷。
- RV32I 37 条计算/访存/控制指令、8 条 M；FENCE；终止式异常接口。
- 1KB D-cache：16 组 × 2 路 × 32 字节行，LRU、写回、写分配。
- 64 项带标签 BTB + 64 个两位 BHT 计数器。
- 自定义 xadd8、xadd16、xdot8；C 内联封装与独立 Spike 扩展。
- 自动测试、FST 波形、三个标量/SIMD 基准、GitHub Actions。

当前交付是**仿真版本**。没有完整特权架构、CSR、中断、OS、标准 RVV、双发射或原板卡适配。见 [架构边界](docs/architecture.md) 和 [实施记录](docs/implementation.md)。

## 从这里运行

本机 Windows PowerShell，已完成工具安装：

~~~powershell
cd D:\Projects\riscv-cpu-lab
.\run.ps1 doctor
.\run.ps1 test
.\run.ps1 bench
.\run.ps1 wave
~~~

Linux / WSL 对应命令：make doctor test bench wave。

另一台 Ubuntu 24.04 首次安装：

~~~bash
sudo bash tools/install-system.sh
bash tools/install-user.sh
make doctor test bench wave
~~~

Windows 首次安装使用 tools/bootstrap.ps1，要求已有 Ubuntu-24.04 WSL 发行版；不会自动新建或删除发行版。详细安装与可选 Vivado 配置见 [工具链](docs/toolchain.md)。

|生成文件|内容|
|---|---|
|build/regression-summary.json|46 组回归、固定随机种子、真实指令覆盖|
|build/benchmarks.md / benchmarks.json|24 组基准周期、指令数与设置|
|build/smoke.fst|真实 RTL 波形|
|build/各测试名.csv|每次提交的 PC、结果、访存及异常|

## 验证摘要

本地验收：13,414 次运算单元比较；139 项缓存检查；10 项预测器检查；46 组回归中的 33,003 次正常提交与 Spike 一致。另有六组冒烟和 24 组基准。异常值按本工程执行环境单独检查，不冒充官方架构认证。

缓存/预测开启，后端响应延迟 1 周期、无随机等待：

|内核|标量周期|SIMD 周期|周期加速比|
|---|---:|---:|---:|
|259 元素 INT8 点积|3,247|1,071|3.03×|
|259 元素逐字节模 256 加法|4,285|1,531|2.80×|
|12 × 67 INT8 矩阵向量乘|9,691|3,148|3.08×|

这里是**周期数**，不是板级 MHz、功耗或 LLM tokens/s。缓存有时反而变慢，见 [完整实验](docs/benchmarks.md)。

## 阅读顺序

1. [第一次实验](docs/first-lab.md)：先跑程序，观察真实提交。
2. [架构与接口](docs/architecture.md)：流水线、缓存、预测、异常。
3. [自定义 SIMD](docs/xsimd.md)：编码、语义、C 调用与 RVV 区别。
4. [验证方法](docs/verification.md)：参考模型、随机测试、真实缺陷。
5. [验收清单](docs/implementation.md)：已完成项和仍不支持的范围。

## 来源与许可

原创代码为 MIT。指令语义依据 [RISC-V 官方规范](https://docs.riscv.org/reference/isa/)，第三方工具保留其许可，见 [来源](docs/sources.md)。原竞赛 PDF、队员信息、截图及私有平台资料不随仓库分发。
