# 宏基因组分析 Pipeline

标准化、可重复的猪粪便宏基因组分析流程，涵盖原始数据下载到功能丰度计算的完整链路。

## 快速开始

```bash
cd /data1/bianzw/metagenomics/script

# 指定项目根目录（三选一）
export PROJECT_ROOT=/data1/bianzw/hlbw          # 方式 1：环境变量
# cp project.env.example project.env && nano project.env  # 方式 2：project.env
# ./run_pipeline.sh --project-root /path/to/project ...   # 方式 3：命令行

# 准备项目目录下的文件
#   ${PROJECT_ROOT}/samplelist.txt  — 每行一个样本名
#   ${PROJECT_ROOT}/linklist.txt    — 原始测序下载链接（仅 0.1 需要）

./run_pipeline.sh --list
./run_pipeline.sh --phase binning
```

## Pipeline 流程图

```
原始数据 (0.1，可选)
    ↓
Fastp 质控 (0.2)
    ↓
宿主去除 (1.1)
    ↓
Kraken2 + Bracken (2.1) → 合并丰度表 (2.2)
    ↓
metaSPAdes 组装 (3.1) → Contig 预处理 (3.2) → 建索引 (3.3)
    ↓
Reads 比对 (3.4) → SAM→BAM (3.5) → Depth (3.6)
    ↓
MetaBAT2 Binning (3.7) → CheckM2 (3.8) → 提取 HQ MAG (3.9) → 提取 MQ MAG (3.10)
    ↓
dRep 去冗余 (4.1) → GTDB-Tk HQ (4.2) → GTDB-Tk MQ (4.3) → CoverM 丰度 (4.4)
    ↓
Prodigal 基因预测 (5.1) → 质量检查 (5.2)
    ↓
Contig 功能: CD-HIT (6.1/6.2) → NR 蛋白 (6.3) → Salmon (6.4) → eggNOG (6.5)
    → QC (6.6) → KO 丰度 (6.7) → 全注释合并 (6.8) → EC 提取 (6.9)
    ↓
MAG 功能: MAG 基因预测 (7.1) → MAG eggNOG (7.2) → MAG×KO 矩阵 (7.3) → 加权丰度 (7.4)
```

## 各阶段说明

| 阶段 | 步骤 | 主要工具 | 输出目录 |
|------|------|----------|----------|
| 下载 | 0.1 | wget | `${PROJECT_ROOT}/raw/` |
| 质控 | 0.2 | fastp | `qc/` |
| 去宿主 | 1.1 | bowtie2 | `dehost/` |
| 物种注释 | 2.1-2.2 | kraken2, bracken | `kraken2/`, `bracken_merged/` |
| 组装 | 3.1-3.6 | metaSPAdes, bowtie2, samtools | `assembly/contig/` |
| Binning | 3.7-3.10 | MetaBAT2, CheckM2 | `assembly/high_quality_bins/`, `assembly/medium_quality_bins/` |
| MAG | 4.1-4.4 | dRep, GTDB-Tk, CoverM | `assembly/drep/`, `gtdbtk/`, `gtdbtk_mq/`, `coverm/` |
| Contig 功能 | 5.1-6.9 | CD-HIT, Salmon, eggNOG | `contig_function/` |
| MAG 功能 | 7.1-7.4 | Prodigal, eggNOG, CoverM | `MAG_function/` |

## 配置说明

**PROJECT_ROOT 优先级**：`export PROJECT_ROOT` > `--project-root` > `project.env` > `config.sh` 默认值。

按阶段运行示例：

```bash
./run_pipeline.sh --phase download   # 0.1：从 linklist 下载
./run_pipeline.sh --phase qc           # 0.2：fastp 质控
./run_pipeline.sh --phase dehost       # 1.1：bowtie2 去宿主
./run_pipeline.sh --phase binning
./run_pipeline.sh --from 3.7 --to 7.4
```

hlbw 项目已在 `project.env` 中配置 `RAW_DATA_DIR=/data1/bianzw/project/data_raw`。

## 前置依赖

- **Conda 环境**: `metagenomics`（主流程）、`checkm2`（3.8）、`gtdbtk-2.5.2`（4.2/4.3）、`eggnog_env`（6.5/7.2）
- **Python**: pandas（6.6–6.9, 7.3, 7.4）
- **输入**: `samplelist.txt` + 双端测序 `sample_1.fq.gz` / `sample_2.fq.gz`

## 注意事项

- 原始数据已在项目外目录时，在 `project.env` 设置 `RAW_DATA_DIR`，从 `--phase qc` 开始
- 无 `linklist.txt` 但 `RAW_DATA_DIR` 已有 fastq 时，0.1 自动跳过
- 6.9 默认提取 EC `1.1.1.27`（`config.sh` 中 `EXTRACT_EC`）
- hlbw 重跑工具：`./tools/prepare_hlbw_rerun.sh status`
