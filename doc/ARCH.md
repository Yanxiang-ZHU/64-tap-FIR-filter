# CSEE W4823 — 64-tap FIR Filter Project: Architecture Decision Record

> 状态：baseline v1（Report #1 定稿依据）
> 规格来源：`Project_export/Project FIR v02.pdf` + 2026-10-29 课堂转录

## 1. 硬规格（不可协商）

| 项 | 值 |
|---|---|
| 抽头数 | 64 |
| 输入 / 系数 | 16-bit Q1.15 signed, x, b ∈ [-1, +1) |
| 输入速率 | 100 MS/s，`clk1` = 100 MHz |
| 输出速率 | 100 MS/s，16-bit **Q7.9** signed |
| 系数加载 | 预先加载，经 `cin` / `caddr` / `cload` 单写端口 |
| 核时钟 | `clk2` 自选，必须 > 100 MHz |
| clk1 / clk2 相位 | **不同步**（必须做 CDC） |
| DUT 必备块 | ALU、CMEM、Registers、Synchronizer、Controller |
| 延迟 | 规格未约束（可用延迟换面积） |
| 评分 | FOM = Throughput / (Energy-per-sample × Area)，吞吐固定 100 MS/s ⇒ 比的是面积和能耗 |

## 2. 关键结论：精度不是瓶颈，面积/能耗才是

**A. Verilog 实测**（`rtl/` + `tb/`，10000 样本，float32 golden，clk2 相位 0.31 ns，见 `doc/results_r1.txt`）：

| 乘积字宽 | 平均 NRMSE | 最坏 NRMSE | 最大误差 |
|---|---|---|---|
| 16b Q2.14（round） | 0.0029 % | 0.0074 % | 0.76 LSB |
| **20b Q2.18（round）★** | **0.0028 %** | **0.0049 %** | **0.51 LSB** |
| 24b Q2.22（round） | 0.0028 % | 0.0049 % | 0.50 LSB |
| 32b Q2.30（全精度） | 0.0028 % | 0.0048 % | 0.50 LSB |

**B. Python 定点模型交叉验证**（为单独验证截断/取整策略，另跑 12b 及「直接截断」两个 RTL 未实现的点）：

| 乘积字宽 | 平均 NRMSE | 最坏 NRMSE | 直流偏置 |
|---|---|---|---|
| 16b Q2.14（**四舍五入**） | 0.0025 % | 0.0059 % | +0.0001 % |
| 16b Q2.14（直接截断） | 0.0087 % | 0.0140 % | −0.0083 % |
| 12b Q2.10（round） | 0.133 % | 0.179 % | — |

**怎么读这张表：**

1. 课上的 NRMSE 目标是「低个位数百分比，最好 < 2%」。全精度方案实测 **0.0028%**，即比目标低 **3 个数量级**。
2. 误差地板由**输出格式 Q7.9 本身**决定：LSB = 2⁻⁹，量化噪声 RMS = LSB/√12 ≈ 5.6e-4，而 y 的动态范围实测 span ≈ 20.1 ⇒ 地板 ≈ 0.0028%。**最大误差 0.51 LSB 说明 DUT 的输出正好停在这个地板上**，再怎么提高内部精度也压不下去。
3. 所以「保留全精度 vs 截断」这道老师给的权衡题，在本题的参数下答案很明确：**截断到 20 位甚至 16 位（带四舍五入）都测不出差别**，可以直接拿去省面积/省功耗。
4. 截断必须配**四舍五入**：直接截断（朝 −∞）在 64 抽头上会累积出可测的负向 DC 偏置（−0.0083% @16b），取整后偏置降到 +0.0001%。

**因此 baseline 取：乘积保留 Q2.18（20-bit，round-to-nearest）+ 32-bit 累加器。** 留 6-bit 余量给后续综合时往下压；`PWL ∈ {16, 20, 24, 32}` 作为 Report #2 / #4 的面积-精度扫描变量。

### 2.1 溢出/饱和

|y| < 64 严格成立（|x|<1, |b|<1, 64 tap）。最坏输入（x=b=32767）实测 y = 63.996 < Q7.9 上限 63.998，**不会溢出**，但仍保留饱和逻辑防御。实测随机数据 sum|p| 上界 = 2³⁶（Q2.30 下），换算 32-bit 累加器足够容纳 Q2.18 的部分和（上界 2²⁵）。

## 3. 吞吐/并行度：核心权衡

100 MS/s ⇒ 每个输出 10 ns 内要完成 64 次 MAC。

| 并行 MAC 数 P | 每输出周期数 K | 需要 clk2 | 备注 |
|---|---|---|---|
| 1 | 64 | 6.4 GHz | 不可行 |
| 4 | 16 | 1.6 GHz | 时序吃紧 |
| **8** | **8** | **800 MHz** | **baseline（老师 PPT 点名 0.8 GHz「probably will work」）** |
| 16 | 4 | 400 MHz | 面积换时序裕量 |
| 32 | 2 | 200 MHz | 乘法器数量爆炸 |

**baseline：P = 8，K = 8，clk2 = 800 MHz。** 理由：乘法器数量最少（面积最小）；1.25 ns 周期内完成 16×16 乘 + 20 位加法树，在深流水下可达；`P ∈ {4, 8, 16}` 留给 Report #2 用真实综合数据做扫描，Report #4 用 FOM 定最终点。

能耗视角的先验：每输出固定 64 次 MAC，**MAC 运算本身的开关能耗与 P 无关**；随 P 变化的只有时钟树功耗（∝ f2 × 时钟单元数）与加法树并行度。所以最优点大概在中段，必须靠 DC/PT 实测，不能靠猜。

## 4. DUT 架构（baseline）

```
              clk1 域                      │            clk2 = 800 MHz 域
                                           │
 din ──► [ Synchronizer: async FIFO ] ─────┼──► [ Sample Window ]──┐
 valid_in   depth 4, gray pointer,         │    8 banks × 8 × 16b  │
            2FF synchronizer 双向           │    每 bank 1R1W        │
                                           │                       ▼
 cin  ──► [ CMEM 8 banks × 8 × 16b ] ──────┼───────────────► [ ALU: 8 × MAC ]
 caddr      1W (caddr/cload) / 8R          │                 16×16 → Q2.18
 cload                                     │                 3 级加法树 + 32b acc
                                           │                  round + sat → Q7.9
                                           │                       │
                     [ Controller / FSM ] ─┼───────────────────────┴──► dout / valid_out
```

### 4.1 分块规格

| 块 | 规格 | 设计要点 |
|---|---|---|
| **Synchronizer** | async FIFO，depth 4，16-bit 数据 + valid；写指针在 clk1 域，读指针在 clk2 域，gray 码 + 双向 2FF 同步 | 100 MS/s 恒定流入、核侧每 8 拍消化 1 个 ⇒ 需要 ≥2 深度吸收相位抖动；单寄存器会丢数 |
| **Sample Window** | 64 × 16b = 1024 flop，分成 **8 banks × 8 entries**，每 bank 1R1W | 关键技巧：bank p 存 x[n−p]、x[n−p−8]、…，第 j 步 MAC p 读 bank p 的 entry j ⇒ 每 bank 只要一个 8:1 mux，**不需要 8 读端口的 64 选 1 大 mux** |
| **CMEM** | 64 × 16b = 1 kb，同样 **8 banks × 8**，1W / 8R（每 bank 1R） | 与 sample bank 同构：第 j 步 MAC p 读 bank p 的 entry j 拿系数 b[p+8j]；写端口由 caddr 译码（64 拍加载完） |
| **ALU** | 8 × (16×16 → Q2.18) 乘法器 + 3 级 8→1 加法树 + 32b 累加器 + round/saturate 到 Q7.9 | 每拍 8 个 MAC，8 拍凑满 64；可把加法树拆到流水级里换时序 |
| **Registers** | 32b 累加器、16b dout、输出 valid、状态/计数寄存器 | — |
| **Controller** | FSM：`IDLE → CLOAD → RUN{ ACCEPT → COMPUTE(j=0..7) → OUT }` | 见 Report #1 的 ASM chart |

### 4.2 时序预算（clk2 = 800 MHz，1.25 ns）

`16×16 乘法（截断到 Q2.18，可省掉低位部分积行）≈ 0.6–0.7 ns` + `20-bit 加法树 3 级 ≈ 0.3 ns` + `32b 累加 ≈ 0.15 ns` ≈ 1.05–1.15 ns。**属于能塞进 1.25 ns 但没裕量的区间** ⇒ Report #2 要么把加法树切流水（K 不变、延迟 +2 拍，延迟无约束所以免费），要么降到 P=16 @ 400 MHz。这正是 Report #2 要回答的问题。

## 5. 精度/误差计划

- 黄金模型：**Verilog/SV `shortreal`（真 float32）**，跑同样的 16-bit 量化输入与系数。
- 测试平台自校验：逐样本比对，累积平方误差、跟踪 y_max/y_min、输出 10000 样本上的 **worst-case 与 average NRMSE**。
- 定点基线：**avg 0.0028% / wc 0.0049%**（Verilog 实测）。
- CDC 验证：clk2 相位在 0 – 1.1 ns 扫 8 个点，NRMSE 完全一致（0.0028/0.0049），说明异步 FIFO 对两域相位关系不敏感。

## 6. 里程碑

| # | 内容 | 分值 | 判定标准 |
|---|---|---|---|
| **1** | 黄金模型 + 激励 + DUT 伪码 + ASM chart + 数据通路框图 + 各块规格 | 4 | 仿真跑通 10000 样本并打印 NRMSE；2 页 IEEE 双栏 PDF |
| **2** | ALU RTL → 综合 → 功能验证 → PT 时序/功耗 → PPA + 架构更新 | 3 | 门级网表 + SDF 反标 PT 报告 + 数据画图 |
| **3** | CMEM / REG RTL → 同上 | 3 | 同上 |
| **4** | 整核 RTL → 综合 → 验证 → PPA → 指标表 + FOM | 15 | 自包含最终文档 + metric 表填满 |

## 7. 待确认

1. **DC / PrimeTime / VCS 的访问方式**（本机没有，WSL 只有 verilator + iverilog）：Report #2–4 必须用真实综合数据，这决定能不能这两天一起做完。
2. clk2 最终取 800 MHz（P=8，面积最小）还是 400 MHz（P=16，时序保守）。
