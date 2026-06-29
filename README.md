# 宏基因组分析 Pipeline

标准化、可重复的猪粪便宏基因组分析流程，共 **42 步（0.1–9.5，不含 MQ MAG 步骤）**，涵盖原始数据下载、组装、MAG、dRep 去冗余、eggNOG 功能注释，以及 **CAZyme（dbCAN）** 与 **耐药基因（CARD/RGI）** 专项分析。

## 快速开始

```bash
cd /data1/bianzw/metagenomics/script

# 指定项目根目录（三选一）
export PROJECT_ROOT=/data1/bianzw/sg              # 方式 1：环境变量
# cp project.env.example project.env && nano project.env  # 方式 2：project.env
# ./run_pipeline.sh --project-root /path/to/project ...   # 方式 3：命令行

# 准备项目目录下的文件
#   ${PROJECT_ROOT}/samplelist.txt  — 每行一个样本名
#   ${PROJECT_ROOT}/linklist.txt    — 原始测序下载链接（仅 0.1 需要）

./run_pipeline.sh --list
./run_pipeline.sh --project-root /data1/bianzw/sg --all   # 完整流程 0.1–9.5
```

## Pipeline 总流程图

每个 `--phase` 名称后标注对应步骤编号。

```
[download]  0.1  下载原始数据（可选，raw/ 已有则跳过）
    ↓
[qc]        0.2  Fastp 质控
    ↓
[dehost]    1.1  宿主去除
    ↓
[taxonomy]  2.1  Kraken2 + Bracken 物种注释
            2.2  合并 Bracken 丰度表
    ↓
[assembly]  3.1  metaSPAdes 组装
            3.2  Contig 预处理（重命名 + 前缀）
            3.3  Bowtie2 建索引
            3.4  Reads 比对到 Contig
            3.5  SAM → sorted BAM
            3.6  Contig Depth 计算
    ↓
[binning]   3.7  MetaBAT2 Binning
            3.8  CheckM2 质量评估
            3.9  提取高质量 MAG（HQ，Completeness≥90, Contamination≤5）
    ↓
[mag]       4.1  dRep 去冗余（输入：3.9 HQ MAG）
            4.2  GTDB-Tk dRep MAG 分类
            4.3  CoverM dRep MAG 丰度 → coverm/MAG_tpm.csv
    ↓
[contig_function]  5.1  Contig 基因预测（Prodigal）
                   5.2  Contig 合并质量检查
                   6.1  蛋白 CD-HIT 去冗余
                   6.2  基因 CD-HIT-EST 去冗余
                   6.3  提取 NR 蛋白序列
                   6.4  Salmon 基因丰度定量
                   6.5  Contig 蛋白 eggNOG 注释
                   6.6  Contig 注释质量检查
                   6.7  Contig KO 功能丰度计算
                   6.8  基因注释与丰度合并
                   6.9  按 EC 提取目标基因
    ↓
[mag_function]     7.1  dRep MAG 基因/蛋白预测（Prodigal，**MAG 首次预测，7/8/9 共用**）
                   7.2  dRep MAG eggNOG 注释（读 7.1 蛋白）
                   7.3  MAG × KO 丰度矩阵
                   7.4  MAG 加权 KO 丰度（依赖 4.3 CoverM）
    ↓
[cazyme]    8.1  Contig 蛋白 dbCAN CAZyme 注释
            8.2  Contig CAZyme 丰度
            8.3  dRep MAG dbCAN CAZyme 注释（读 7.1 蛋白）
            8.4  dRep MAG × CAZyme 丰度矩阵
            8.5  dRep MAG 加权 CAZyme 丰度（依赖 4.3）
    ↓
[card]      9.1  Contig 基因 CARD(RGI) 耐药注释
            9.2  Contig AMR 丰度
            9.3  dRep MAG CARD(RGI) 注释（读 7.1 基因）
            9.4  dRep MAG × AMR 丰度矩阵
            9.5  dRep MAG 加权 AMR 丰度（依赖 4.3）
```

**组合阶段：**

| `--phase` | 包含步骤 | 说明 |
|-----------|----------|------|
| `function` | 5.1–9.5 | 全部功能分析（**不含** mag 4.1–4.3，需预先完成） |
| `--all` | 0.1–9.5 | 完整流程，推荐从头跑时使用 |

## 各阶段说明

| 阶段 | 步骤 | 做什么 | 主要工具 | 输出目录 |
|------|------|--------|----------|----------|
| **download** | 0.1 | 下载原始测序数据 | wget | `raw/` |
| **qc** | 0.2 | 质控、去接头 | fastp | `qc/` |
| **dehost** | 1.1 | 去除猪宿主序列 | bowtie2 | `dehost/` |
| **taxonomy** | 2.1–2.2 | 物种注释与丰度合并 | Kraken2, Bracken | `kraken2/`, `bracken_merged/` |
| **assembly** | 3.1–3.6 | 组装、比对、depth | metaSPAdes, bowtie2 | `assembly/contig/` |
| **binning** | 3.7–3.9 | MAG 分箱与 HQ 提取 | MetaBAT2, CheckM2 | `assembly/high_quality_bins/` |
| **mag** | 4.1–4.3 | dRep 去冗余、GTDB 分类、MAG 丰度 | dRep, GTDB-Tk, CoverM | `assembly/drep/`, `gtdbtk/`, `coverm/` |
| **contig_function** | 5.1–6.9 | Contig 水平 KO/EC 功能 | Prodigal, CD-HIT, Salmon, eggNOG | `contig_function/` |
| `mag_function` | 7.1–7.4 | dRep MAG 首次 Prodigal + eggNOG/KO（7.1 产出供 8/9 共用） | Prodigal, eggNOG, CoverM | `MAG_function/gene_prediction/` |
| **cazyme** | 8.1–8.5 | 碳水化合物酶（Contig + dRep MAG） | run_dbcan | `contig_function/`, `MAG_function/` |
| **card** | 9.1–9.5 | 耐药基因（Contig + dRep MAG） | RGI/CARD | `contig_function/`, `MAG_function/` |

## 阶段命令

```bash
./run_pipeline.sh --phase download        # 0.1
./run_pipeline.sh --phase qc              # 0.2
./run_pipeline.sh --phase dehost          # 1.1
./run_pipeline.sh --phase taxonomy        # 2.1–2.2
./run_pipeline.sh --phase assembly        # 3.1–3.6
./run_pipeline.sh --phase binning         # 3.7–3.9
./run_pipeline.sh --phase mag             # 4.1–4.3
./run_pipeline.sh --phase contig_function # 5.1–6.9
./run_pipeline.sh --phase mag_function    # 7.1–7.4
./run_pipeline.sh --phase function        # 5.1–9.5（需预先完成 mag）
./run_pipeline.sh --phase cazyme          # 8.1–8.5
./run_pipeline.sh --phase card            # 9.1–9.5
./run_pipeline.sh --all                   # 0.1–9.5 完整流程

./run_pipeline.sh --from 3.1 --to 3.6     # 步骤区间
./run_pipeline.sh --step 8.1              # 单步
```

## 步骤依赖关系

```
                    ┌── contig_function (5–6) ──→ cazyme 8.1–8.2 / card 9.1–9.2
                    │
binning (3.9 HQ) ──→ mag (4.1 dRep, 4.3 CoverM)
                           │
                           └──→ mag_function 7.1 Prodigal（MAG 唯一基因/蛋白预测，7/8/9 共用）
                                      ├── 7.2–7.4 eggNOG/KO
                                      ├── 8.3 dbCAN（读蛋白）
                                      └── 9.3 RGI（读基因）
```

**7.1 是 Pipeline 中对 dRep MAG 的首次、也是唯一一次 Prodigal 预测**，输出目录 `MAG_function/gene_prediction/` 供 Phase 7/8/9 共用；该步骤在流程中不可省略（重跑时若结果已存在则跳过重复计算，但首次必须执行）。

| 7.1 产出 | 用途 |
|----------|------|
| `*.prefixed.faa` | 7.2 eggNOG、8.3 dbCAN（蛋白注释） |
| `*.prefixed.ffn` | 9.3 RGI/CARD（核酸注释） |
| `*.prodigal.gff` | 基因坐标（备用） |

Contig 水平的基因预测在 **5.1**（`contig_function/`），与 MAG 的 7.1 相互独立。

| 若单独运行 | 必须先完成 |
|------------|------------|
| `mag` | binning（3.9 产出 HQ MAG） |
| `mag_function` | mag（4.1 dRep MAG） |
| `cazyme` | contig_function（6.3–6.4）、mag（4.1）、mag_function（7.1）、mag（4.3 加权用） |
| `card` | contig_function（6.2–6.4）、mag_function（7.1）、mag（4.3 加权用） |
| `function` | **mag（4.1–4.3）**（该 phase 本身不含 mag 步骤） |

## 主要输出结果

### 基础分析（0.x–4.x）

| 目录/文件 | 内容 |
|-----------|------|
| `raw/`, `qc/`, `dehost/` | 原始 / 质控 / 去宿主 reads |
| `kraken2/`, `bracken_merged/*_abundance.tsv` | 物种注释与丰度 |
| `assembly/contig/*_spades/` | 组装 contig、BAM、depth |
| `assembly/high_quality_bins/*.fa` | HQ MAG（3.9，**4.1 dRep 唯一输入**） |
| `assembly/drep/all_bins/dereplicated_genomes/` | dRep MAG（7/8/9 MAG 分析共用） |
| `gtdbtk/` | GTDB-Tk dRep MAG 分类 |
| `coverm/MAG_tpm.csv` | dRep MAG 样本 TPM（7.4 / 8.5 / 9.5） |

### Contig 功能（5.x–6.x）

| 文件 | 内容 |
|------|------|
| `contig_function/gene_quant/salmon_matrix/gene.TPM.tsv` | 基因 TPM |
| `contig_function/gene_quant/function_matrix/gene_with_KO_TPM.tsv` | KO 功能丰度 |
| `contig_function/gene_quant/protein_function/eggNOG/` | eggNOG 注释 |

### MAG 功能 dRep（7.x）

| 文件 | 内容 |
|------|------|
| `MAG_function/gene_prediction/*.prefixed.{faa,ffn}` | dRep MAG 蛋白/基因（**7.1 唯一产出，7/8/9 共用**） |
| `MAG_function/function_matrix/mag_ko_gene_count_matrix.tsv` | MAG × KO |
| `MAG_function/function_matrix/mag_weighted_KO_TPM.tsv` | 样本加权 KO |

### CAZyme（8.x，`--phase cazyme`）

| 步骤 | 关键输出 |
|------|----------|
| 8.1 | `contig_function/gene_quant/protein_function/dbCAN/overview.tsv` |
| 8.2 | `contig_function/gene_quant/function_matrix/cazyme/cazyme_family.TPM.tsv` |
| 8.3 | `MAG_function/dbcan_annotation/{MAG}/overview.tsv` |
| 8.4 | `MAG_function/function_matrix/mag_cazyme_gene_count_matrix.tsv` |
| 8.5 | `MAG_function/function_matrix/mag_weighted_cazyme_TPM.tsv` |

### CARD 耐药（9.x，`--phase card`）

| 步骤 | 关键输出 |
|------|----------|
| 9.1 | `contig_function/gene_quant/gene_function/card/contig_card.txt` |
| 9.2 | `contig_function/gene_quant/function_matrix/amr/amr_aro.TPM.tsv` |
| 9.3 | `MAG_function/card_annotation/{MAG}/{MAG}_card.txt` |
| 9.4 | `MAG_function/function_matrix/mag_amr_gene_count_matrix.tsv` |
| 9.5 | `MAG_function/function_matrix/mag_weighted_amr_TPM.tsv` |

## 配置说明

**PROJECT_ROOT 优先级：** `export PROJECT_ROOT` > `--project-root` > `project.env` > `config.sh` 默认值。

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MAG_COMPLETENESS` / `MAG_CONTAMINATION` | 90 / 5 | 3.9 HQ MAG 筛选阈值 |
| `DREP_MAG_DIR` | `assembly/drep/.../dereplicated_genomes` | dRep 输出 MAG |
| `DBCAN_DB` | `/data1/resource/dbcan_db` | dbCAN 数据库 |
| `CARD_DB_DIR` | `/data1/resource/card` | CARD/RGI 本地库 |
| `MAG_DBCAN_DIR` | `MAG_function/dbcan_annotation` | dRep MAG dbCAN |
| `MAG_CARD_DIR` | `MAG_function/card_annotation` | dRep MAG RGI |

## 前置依赖

| Conda 环境 | 用途 |
|------------|------|
| `metagenomics` | 主流程 |
| `checkm2` | 3.8 |
| `gtdbtk-2.5.2` | 4.2 |
| `eggnog_env` | 6.5/7.2 |
| `dbcan_env` | 8.1/8.3 |
| `rgi_env` | 9.1/9.3 |

## 推荐运行顺序

**从头跑（推荐）：**

```bash
export PROJECT_ROOT=/data1/bianzw/sg
./run_pipeline.sh --all
```

**分阶段跑：**

```bash
export PROJECT_ROOT=/data1/bianzw/sg

./run_pipeline.sh --phase qc
./run_pipeline.sh --phase dehost
./run_pipeline.sh --phase taxonomy
./run_pipeline.sh --phase assembly
./run_pipeline.sh --phase binning
./run_pipeline.sh --phase mag              # dRep + CoverM，后续 MAG 功能必需
./run_pipeline.sh --phase contig_function
./run_pipeline.sh --phase mag_function     # 7.1 为 cazyme/card 共用
./run_pipeline.sh --phase cazyme
./run_pipeline.sh --phase card
```

## 注意事项

- 原始数据已在项目外目录时，在 `project.env` 设置 `RAW_DATA_DIR`，从 `--phase qc` 开始
- 无 `linklist.txt` 但 `raw/` 已有 fastq 时，0.1 自动跳过
- 6.9 默认提取 EC `1.1.1.27`（`config.sh` 中 `EXTRACT_EC`）
- **全流程仅使用 HQ MAG**：3.9 筛选 → 4.1 dRep → 后续 7/8/9 全基于 dRep MAG；已移除 MQ MAG（原 3.10）及其中高质量 MAG GTDB 注释（原 4.3）
- Phase 7/8/9 的 MAG 部分：**7.1 是 dRep MAG 唯一 Prodigal 步骤，不可省略**；共用 `gene_prediction/` 及 4.3 CoverM 丰度
- `--phase function` 不含 mag 步骤，单独使用前须先完成 `--phase mag`

## Pipeline 审查记录

以下为当前版本已知设计与已修复项（2025-06 审查）：

| 类型 | 说明 | 状态 |
|------|------|------|
| 设计 | `--phase function` 不含 4.1–4.3，单独跑会在 7.1 失败 | 文档已说明；用 `--all` 或先跑 `mag` |
| 变更 | 移除 3.10 MQ MAG 提取、4.3 MQ GTDB 注释 | **仅保留 HQ MAG 路径** |
| 变更 | CoverM 步骤重编号 4.4 → **4.3** | mag phase = 4.1–4.3 |
| 设计 | `cazyme`/`card` 单独跑依赖 `mag` + `mag_function`（至少 7.1） | 文档已说明 |
| 优化 | 7.1 重跑时重复 Prodigal | **已修复**：已有 `.prefixed.faa/ffn` 则跳过 |
| 优化 | 8.3/8.5 与 7.1/4.3 重复 | **已删除**旧步骤并重编号为 8.3–8.5 |
| 优化 | 脚本名含 `_hq_` 与实际 dRep MAG 不符 | **已重命名**为 `*_MAG_*` |
| 正常 | 3.9 HQ MAG → 4.1 dRep → 7/8/9 MAG 分析 | 符合预期 |
| 正常 | `--all` 顺序 4.x → 5.x → 7.x → 8.x → 9.x | 依赖满足 |
