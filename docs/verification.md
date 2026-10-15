# 验证方法与证据边界

执行 make test；Windows 为 .\run.ps1 test。实际编译、运行、比较；失败非零退出，不是仅打印 PASS。

## 检查层次

1. Verilator -Wall lint，全 RTL，警告作为失败。
2. Icarus 四态模块仿真：13,414 次运算结果比较、139 项缓存检查、10 项预测器检查。
3. Verilator 周期执行 + Spike 差分：6 组冒烟；46 组主回归、33,003 次正常提交。
4. 24 组基准：Python 独立整数期望值、CPU 中 C 结果验证、Spike 对照、全 RAM 比较。

Spike 固定提交 f8a060b7bea8da6f738f193ed1b66b665978d092。Xsimd 插件独立用 C++ 标量定义语义，不调用 RTL；这是两份实现加测试，不是第三方 ISA 认证。

## 比较对象

逐条比较 PC、编码、rd、结果、下一 PC、load 地址、store 地址和有效字节，不只比较最终 a0。参考运行停在链接符号 test_end，检查确实到达，有超时和指令上限。

异常 cause/tval 按本工程执行环境单独检查，不混同 Spike M 模式异常。正常内存测试末尾 FENCE 后，重放 **Spike store** 得到期望值，与 RTL 后端全部 1 MiB RAM 比较。

写回故障可能部分更新后端，故不做“所有旧 store 都已落盘”的错误断言，另检异常及模块级恢复。检测含 x0、异常无写入、缓存无重复标签/无效脏行等仿真断言。

## 覆盖

- 45 条 I/M + FENCE + 3 条 SIMD 真实执行，动态计数在 regression-summary.json。
- 算术边界、符号扩展、x0、六种分支、JALR 清 bit 0、M 除零/溢出。
- 缓存/预测开关矩阵；固定延迟、确定性 ready 反压、响应抖动。
- load-use、前递、除法依赖加载；冲刷路径不能写 MMIO/store 或触发年轻异常。
- 固定随机种子：1、7、42、73、101、257、65537、20261015。
- 同组 LRU、脏置换、部分字节写、FENCE、旁路。
- 填充/写回/FENCE 失败、模块级重试。
- ECALL、EBREAK、非法、CSR/FENCE.I 不支持、未对齐、取指/数据错误。
- 单独构建 ENABLE_SIMD=0，确认自定义编码非法。

这些是指令类型实际执行覆盖，不是代码行/翻转覆盖率，不等于遍历所有状态。尚未导入官方 riscv-arch-test 或形式化证明。

Icarus 12 会打印 constant selects 的敏感表提示及仿真断言不可综合提示；这些不等于测试失败，仍须看最终比较结果和退出码。断言受 SYNTHESIS 条件保护。冒烟 ELF 的 RWX 段提示来自简化裸机链接脚本；本系统无内存权限保护，不应把这个程序当作受保护 OS 应用。

## 真实缺陷记录

随机种子 20261015 曾发现：

~~~asm
li x6,1
li x17,1184
lw x6,0(x28)       # 缓存未命中，内存为 0
div x15,x17,x6
~~~

旧 RTL 得到 1184，正确为 0xFFFFFFFF（除零）。DIV 提前锁存了旧 x6；组合 ALU 能等到执行时重算，迭代除法不会自动重采样。

先缩成 div-load-hazard 重现失败，再让 div_start 等待 MEM 相关 load 返回。修复后最小用例和原随机种子均通过；用例保留。

## 波形与 CI

make wave 生成 build/smoke.fst。GTKWave 先看 TOP.rv32_system 的 commit_*，再看 core.e_valid/m_valid/w_valid、ea/eb、load_hazard、div_start、redirect，以及 cache.state/word_index。

CSV 的 cycle 为十进制，其余字段为十六进制。FST 每半周期增加 1 个仿真单位，不能直接说成实际 FPGA 纳秒。

GitHub Actions 执行 doctor/test/bench/wave 并上传 JSON/CSV/FST。验收必须核对当前提交的结果，历史提交绿色不代表新代码通过。
