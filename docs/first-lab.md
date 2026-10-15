# 第一次实验：先看懂，再修改

## 1. 跑通

~~~powershell
cd D:\Projects\riscv-cpu-lab
.\run.ps1 test
~~~

PASS 只说明当前测试未发现差异，不等于你已理解 CPU。先读 tests/programs/smoke.S：常数、加法、存取内存、循环、乘除、点积，最后 a0=0、EBREAK。

## 2. 跟三条指令

打开 build/smoke-l1-p1.csv。每行是正式提交，不是刚进入 IF：

- pc：指令地址；insn：机器码。
- rd / data：写哪个寄存器、写多少。
- npc：下一 PC；trap=1 表示终止，EBREAK cause=3 是该程序的结束方式。

找“相加 → store → load”这一段，手算并与 CSV 对照。cycle 十进制，其他字段十六进制。

## 3. 看周期

运行 .\run.ps1 wave，再按工具链文档打开 GTKWave。先看 clk、commit_valid、commit_pc、commit_rd、commit_data，再添加 core.e_valid/m_valid/w_valid、load_hazard、redirect。

顺序：组合逻辑输出 → 时钟沿采样进入下一级 → 下一周期新状态生效。缓存、除法或分支会造成空拍，不一定是错误。

## 4. 最小改动

改变 smoke.S 一个普通加法输入，先不改预期，确认测试会失败；再改正确的预期，确认通过。掌握“修改 → 定位失败 → 修正”，再动 RTL。

然后关闭预测、提高内存延迟。结果应相同、周期可变化；run_smoke.py 已提供六种配置，无需重装工具。

## 5. 文件阅读顺序

1. rv32_alu.sv：组合逻辑输入/输出。
2. rv32_decode.sv：机器码到控制信号。
3. rv32_core.sv：先看 e/m/w 结构，再看握手和前递。
4. rv32_dcache.sv：状态转换、数据阵列、字节使能。
5. rv32_bpu.sv：标签、计数器、误预测恢复。
6. rv32_simd.sv + sw/include/xsimd.h：C 调用到机器码和运算。

先能解释缓存未命中时哪里停住、DIV 何时可启动、错误路径为何不能写内存，再评估更深流水。不要把“多加两级寄存器”直接当作已经证明有效的创新。
