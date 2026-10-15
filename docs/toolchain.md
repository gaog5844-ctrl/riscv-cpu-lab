# 工具链与本机环境

Windows 11；i5-11320H（4 核/8 线程）、约 16GB RAM。Ubuntu 24.04 WSL2，约 7.6GB RAM，虚拟磁盘位于 D 盘。源文件 D:/Projects/riscv-cpu-lab，Linux 为 /mnt/d/Projects/riscv-cpu-lab。

|工具|已核实版本/用途|
|---|---|
|Verilator|5.020，lint 和周期仿真|
|Icarus|12.0，四态模块测试|
|GTKWave|3.3.116，FST 查看|
|RISC-V GCC / Binutils|13.2.0 / 2.42，RV32IM/ILP32|
|宿主 G++ / Make|13.3 / 4.3|
|Spike|固定 f8a060b7bea8da6f738f193ed1b66b665978d092|
|Python|Ubuntu Python 3，独立 venv；pytest 8.3.5、pyelftools 0.32|
|Git / gh|Windows 已配置，远程公开仓库已建立|

构建 -j2 适应该机内存和 CPU。Linux 工具装在 D 盘 WSL 虚拟磁盘内。build/obj 在源码目录，不声称使用 WSL ext4 构建缓存。

Spike 提交和 Windows 下载 SHA-256 固定，Python 顶层依赖固定；Ubuntu 官方 apt 包会随更新变化，doctor / toolchain-versions.txt 记录实际版本，不宣称系统包完全冻结。

## 安装

Windows 执行 tools/bootstrap.ps1，要求已有 Ubuntu-24.04 WSL。Linux：

~~~bash
sudo bash tools/install-system.sh
bash tools/install-user.sh
make doctor
~~~

Spike 编译可能约十分钟，安装成功出现 BOOTSTRAP_PASS。WSL 无法连接 GitHub 时，Windows bootstrap 从官方源下载固定包、校验哈希，再交给 WSL；不绕过证书或改变代理。

doctor 只验证工具存在并可启动，test 才验证它们能编译和执行工程。

|PowerShell 入口|用途|
|---|---|
|.\run.ps1 doctor|工具路径/版本|
|.\run.ps1 unit|运算、缓存、预测模块测试|
|.\run.ps1 lint|全 RTL 静态检查|
|.\run.ps1 test|完整仿真回归和 Spike 对照|
|.\run.ps1 bench|24 组性能实验|
|.\run.ps1 wave|生成波形，不自动弹 GUI|
|.\run.ps1 synth|可选 Vivado 独立综合诊断|

用 WSLg 查看波形：

~~~powershell
wsl -d Ubuntu-24.04 --cd /mnt/d/Projects/riscv-cpu-lab -- gtkwave build/smoke.fst
~~~

## Vivado / ModelSim

原装 Vivado 2026.1、ModelSim Starter 10.5b 可启动；主回归不依赖它们。

原报告 xc7k325tffg900-2 当前未安装，实际返回 No parts matched。synth.tcl 默认已安装的 xc7a35tcsg324-1 做独立诊断，不冒充原板卡。

2026-10-15 实际重试：所有 RTL 模块均到达 done synthesizing module，但 Vivado 随后异常退出，返回 -1073740940，未生成通过标记和完整综合报告。**当前综合未通过**，不能把“模块读取/综合结束”写成完整综合完成。现有最小加法器工程也有类似退出；根因尚未定位，本期不宣称修复。

LAB_VIVADO 可指定 vivado.bat，LAB_FPGA_PART 可选已安装器件。结果在 build/synth；只有本次 exit=0 且新生成 SYNTH_PASS.txt 才算通过，旧文件不算。

即使独立综合通过，也不等于布局布线、时序收敛或上板成功。上板前仍需真实开发板、时钟、引脚、电平、存储器和外设资料；当前不生成位流。
