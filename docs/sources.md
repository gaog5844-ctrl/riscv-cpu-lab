# 参考资料

## 指令与设计

- [RISC-V 非特权指令集规范](https://docs.riscv.org/reference/isa/)：基础指令和 M 扩展的语义依据。
- CPU 设计竞赛报告：功能配置的参考。原 PDF 仅用于本地阅读，未将正文、截图、队员信息或私有平台资料加入仓库。
- [llama.cpp](https://github.com/ggml-org/llama.cpp)：量化点积与推理的相关背景资料。本项目实现的是整数运算内核，尚无完整推理后端。

## 工具

- [Verilator](https://github.com/verilator/verilator)：RTL 检查和仿真，许可证为 LGPL-3.0 / Artistic-2.0，具体条款以上游为准。
- [Spike](https://github.com/riscv-software-src/riscv-isa-sim)：指令参考模型，BSD-3-Clause 许可证。使用提交 `f8a060b7bea8da6f738f193ed1b66b665978d092`。
- GNU RISC-V GCC、Binutils、Icarus Verilog、GTKWave：通过 Ubuntu 24.04 官方软件包安装，各自遵循上游许可证。

仓库代码采用 [MIT 许可证](../LICENSE)。第三方工具不包含在本仓库的许可范围内。
