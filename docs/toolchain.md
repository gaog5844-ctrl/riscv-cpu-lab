# 环境配置

## 开发环境

2026-10-15 使用的环境为 Windows 11、i5-11320H（4 核 / 8 线程）和约 16GB 内存。Ubuntu 24.04 运行在 WSL2 中，可用内存约 7.6GB，虚拟磁盘位于 D 盘。

仓库路径为 `D:/Projects/riscv-cpu-lab`，在 WSL 中对应 `/mnt/d/Projects/riscv-cpu-lab`。构建使用两个并行任务（`-j2`），产物保存在源码目录下的 `build/obj`；Linux 工具装在 WSL 虚拟磁盘内。

|工具|版本和用途|
|---|---|
|Verilator|5.020，RTL 检查和周期仿真|
|Icarus|12.0，四态模块仿真|
|GTKWave|3.3.116，查看 FST 波形|
|RISC-V GCC / Binutils|13.2.0 / 2.42，编译 RV32IM/ILP32 程序|
|宿主 G++ / Make|13.3 / 4.3|
|Spike|提交 `f8a060b7bea8da6f738f193ed1b66b665978d092`|
|Python|Ubuntu Python 3，使用独立 venv；pytest 8.3.5、pyelftools 0.32|
|Git / gh|Windows 中已配置，用于版本管理和 GitHub 操作|

Spike 固定到上述提交，Windows 下载脚本还会校验源码包的 SHA-256。Python 顶层依赖固定版本；Ubuntu 系统包从官方 apt 仓库安装，会随仓库更新而变化。`doctor` 和 `toolchain-versions.txt` 记录实际使用的版本。

## 安装

Windows 中运行 `tools/bootstrap.ps1`，需要已有名为 `Ubuntu-24.04` 的 WSL 发行版。Linux 中运行：

~~~bash
sudo bash tools/install-system.sh
bash tools/install-user.sh
make doctor
~~~

Spike 首次编译约需十分钟，完成后脚本输出 `BOOTSTRAP_PASS`。如果 WSL 无法连接 GitHub，可以使用 Windows 安装脚本下载并校验源码包，再交给 WSL 构建。

`doctor` 检查工具路径、版本和启动情况。安装后还应运行 `test`，检查编译及仿真是否正常。

## 常用命令

以下命令在仓库目录的 PowerShell 中运行。Linux / WSL 对应 `make doctor`、`make test` 等同名目标。

|命令|用途|
|---|---|
|`.\run.ps1 doctor`|检查工具路径和版本|
|`.\run.ps1 unit`|运行运算、缓存和预测器模块测试|
|`.\run.ps1 lint`|检查全部 RTL|
|`.\run.ps1 test`|运行回归测试和 Spike 对照|
|`.\run.ps1 bench`|运行 24 组性能测试|
|`.\run.ps1 wave`|生成波形，不自动打开 GUI|
|`.\run.ps1 synth`|调用 Vivado 做独立综合检查|

用 WSLg 打开波形：

~~~powershell
wsl -d Ubuntu-24.04 --cd /mnt/d/Projects/riscv-cpu-lab -- gtkwave build/smoke.fst
~~~

## Vivado 和 ModelSim

本机已有 Vivado 2026.1 和 ModelSim Starter 10.5b，均可启动。默认回归使用 Verilator 和 Icarus。

原报告使用的 `xc7k325tffg900-2` 器件支持未安装，Vivado 返回 `No parts matched`。`synth.tcl` 因此默认使用已安装的 `xc7a35tcsg324-1` 做综合检查，该器件不是原报告中的板卡目标。

2026-10-16 已生成 `rv32_system` 的综合网表并通过 DCP 回读检查。综合占用 12,221 个 LUT、15,736 个触发器和 4 个 DSP；10ns 约束下 WNS 为 -5.763ns，未满足时序目标。详细结果见 [设计报告](design-report.md)。

本机此前在模块展开后以 `0xC0000374` 退出。脚本为带非 ASCII 主机名的 Windows 环境设置独立英文 RTL 临时目录，并复制后续阶段所需的 `elab.rtd`。传给 Vivado 的临时路径统一使用 `/`，避免生成 Tcl 时将反斜杠解释成转义符。未改动计算机名、系统区域或 Vivado 安装文件。这一兼容处理使用内部参数，在 Vivado 2026.1 上验证；升级后需重新检查。

本机的并行优化子进程仍不可用，Vivado 自动回退到单核继续运行。这一修复提供本工程可用的批处理综合路径，不等于修复了 Vivado 的所有并行或 GUI 工程问题。

可通过 `LAB_VIVADO` 指定 `vivado.bat`，通过 `LAB_FPGA_PART` 指定已安装器件。也可以直接运行：

~~~powershell
.\tools\synth.ps1 -Part xc7a35tcsg324-1 -ClockPeriodNs 10
~~~

每次综合使用独立的 `build/synth/runs/<run-id>/`，`build/synth/result.json` 指向最近结果。只有退出码为 0、日志无 ERROR、本次报告及检查点非空、DCP 重新打开并通过检查，脚本才报告成功。综合成功不要求 WNS 为正；时序是否满足需另看 `timing.txt`。

尚未完成布局布线或上板测试。板级工程还需要具体开发板的时钟、引脚、电平、存储器和外设资料。

## 报告导出

`docs/design-report.md` 是报告正文，框图位于 `docs/images/`。Windows 中可用以下命令导出 HTML 和 PDF；PDF 使用系统自带的宋体、黑体。

~~~powershell
python -m venv build/report-venv
.\build\report-venv\Scripts\python.exe -m pip install -r tools/report-requirements.txt
.\build\report-venv\Scripts\python.exe tools/render-report.py
~~~

输出为 `output/design-report.html`、`output/pdf/design-report.pdf`。HTML 内嵌框图，可直接打开；PDF 包含目录、书签和页码。导出文件和排版检查图片不加入 Git。
