# 规范与工具来源

- RISC-V 非特权规范：https://docs.riscv.org/reference/isa/
- Verilator：https://github.com/verilator/verilator（LGPL-3.0 / Artistic-2.0，依上游许可）
- Spike：https://github.com/riscv-software-src/riscv-isa-sim（BSD-3-Clause）；固定提交 `f8a060b7bea8da6f738f193ed1b66b665978d092`。
- GNU RISC-V GCC / Binutils：Ubuntu 24.04 官方软件包，依上游许可。
- Icarus Verilog、GTKWave：Ubuntu 24.04 官方软件包，依上游许可。
- 研究背景：https://github.com/ggml-org/llama.cpp 中 RISC-V 的量化点积实现。仅用于说明 INT8 点积与推理的联系，不把本项目等同于完整 LLM 推理后端。

原竞赛 PDF 为本地参考资料，不上传其正文、截图、队员信息或平台资料。原创代码版权按仓库 LICENSE；第三方代码或测试如有引入，逐项保留来源及许可。
