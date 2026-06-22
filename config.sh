#!/bin/bash
# =============================================================================
# 宏基因组 Pipeline 统一配置文件
# 所有步骤脚本通过 source 本文件获取路径与参数，保证可重复性
#
# 项目根目录 PROJECT_ROOT 优先级（高 → 低）：
#   1. 运行前 export PROJECT_ROOT=/path/to/project
#   2. run_pipeline.sh --project-root /path/to/project
#   3. script/project.env（可复制 project.env.example 后修改）
#   4. 下方默认值
# =============================================================================

_CONFIG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${PROJECT_ROOT:-}" ]] && [[ -f "${_CONFIG_SCRIPT_DIR}/project.env" ]]; then
    # shellcheck source=project.env
    source "${_CONFIG_SCRIPT_DIR}/project.env"
fi

# --- 项目根目录 ---
export PROJECT_ROOT="${PROJECT_ROOT:-/data1/bianzw/hlbw}"

# --- 样本列表 ---
export SAMPLE_LIST="${SAMPLE_LIST:-${PROJECT_ROOT}/samplelist.txt}"

# --- 原始测序数据（0.1 从 linklist 下载到项目 raw/）---
export LINKLIST="${LINKLIST:-${PROJECT_ROOT}/linklist.txt}"
export RAW_DATA_DIR="${RAW_DATA_DIR:-${PROJECT_ROOT}/raw}"
export QC_DIR="${QC_DIR:-${PROJECT_ROOT}/qc}"
export DEHOST_DIR="${DEHOST_DIR:-${PROJECT_ROOT}/dehost}"
export LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"

# --- 物种注释 ---
export KRAKEN2_DIR="${KRAKEN2_DIR:-${PROJECT_ROOT}/kraken2}"
export BRACKEN_DIR="${BRACKEN_DIR:-${PROJECT_ROOT}/bracken}"

# --- 组装与 MAG ---
export ASSEMBLY_CONTIG_DIR="${ASSEMBLY_CONTIG_DIR:-${PROJECT_ROOT}/assembly/contig}"
export HQ_MAG_DIR="${HQ_MAG_DIR:-${PROJECT_ROOT}/assembly/high_quality_bins}"
export MQ_MAG_DIR="${MQ_MAG_DIR:-${PROJECT_ROOT}/assembly/medium_quality_bins}"
export DREP_OUT_DIR="${DREP_OUT_DIR:-${PROJECT_ROOT}/assembly/drep/all_bins}"
export DREP_MAG_DIR="${DREP_MAG_DIR:-${DREP_OUT_DIR}/dereplicated_genomes}"

# --- GTDB-Tk 物种注释（4.2 HQ/dRep，4.3 全部中高质量 MAG）---
export GTDBTK_HQ_OUT_DIR="${GTDBTK_HQ_OUT_DIR:-${PROJECT_ROOT}/gtdbtk}"
export GTDBTK_MQ_OUT_DIR="${GTDBTK_MQ_OUT_DIR:-${PROJECT_ROOT}/gtdbtk_mq}"
export GTDBTK_OUT_DIR="${GTDBTK_OUT_DIR:-${GTDBTK_HQ_OUT_DIR}}"

export COVERM_OUT_DIR="${COVERM_OUT_DIR:-${PROJECT_ROOT}/coverm}"

# --- 功能注释 ---
export CONTIG_FUNCTION_DIR="${CONTIG_FUNCTION_DIR:-${PROJECT_ROOT}/contig_function}"
export GENE_QUANT_DIR="${GENE_QUANT_DIR:-${CONTIG_FUNCTION_DIR}/gene_quant}"
export MAG_FUNCTION_DIR="${MAG_FUNCTION_DIR:-${PROJECT_ROOT}/MAG_function}"
export MAG_GENE_PRED_DIR="${MAG_GENE_PRED_DIR:-${MAG_FUNCTION_DIR}/gene_prediction}"
export MAG_ANNOT_DIR="${MAG_ANNOT_DIR:-${MAG_FUNCTION_DIR}/function_annotation}"
export MAG_FUNCTION_MATRIX_DIR="${MAG_FUNCTION_MATRIX_DIR:-${MAG_FUNCTION_DIR}/function_matrix}"
export FUNCTION_MATRIX_DIR="${FUNCTION_MATRIX_DIR:-${GENE_QUANT_DIR}/function_matrix}"

# --- Contig 功能：按 EC 提取基因（6.9，默认 LDH EC 1.1.1.27）---
export EXTRACT_EC="${EXTRACT_EC:-1.1.1.27}"

# --- Conda 环境 ---
export CONDA_BASE="${CONDA_BASE:-/opt/miniconda3}"
export CONDA_ENV_MAIN="${CONDA_ENV_MAIN:-metagenomics}"
export CONDA_ENV_CHECKM2="${CONDA_ENV_CHECKM2:-checkm2}"
export CONDA_ENV_GTDBTK="${CONDA_ENV_GTDBTK:-gtdbtk-2.5.2}"
export CONDA_ENV_EGGNOG="${CONDA_ENV_EGGNOG:-eggnog_env}"

# --- 参考数据库 ---
export PIG_GENOME_INDEX="${PIG_GENOME_INDEX:-/data1/resource/pig_genome/pig_genome}"
export KRAKEN2_DB="${KRAKEN2_DB:-/data1/resource/kraken2}"
export CHECKM2_DB="${CHECKM2_DB:-/data1/resource/CheckM2_database/uniref100.KO.1.dmnd}"
export EGGNOG_DB="${EGGNOG_DB:-/data1/resource/eggNOG}"

# --- 计算资源 ---
export THREADS_QC="${THREADS_QC:-16}"
export THREADS_DEHOST="${THREADS_DEHOST:-128}"
export THREADS_KRAKEN="${THREADS_KRAKEN:-96}"
export THREADS_ASSEMBLY="${THREADS_ASSEMBLY:-24}"
export THREADS_INDEX="${THREADS_INDEX:-96}"
export THREADS_MAPPING="${THREADS_MAPPING:-128}"
export THREADS_SAMTOOLS="${THREADS_SAMTOOLS:-256}"
export THREADS_BINNING="${THREADS_BINNING:-128}"
export THREADS_CHECKM2="${THREADS_CHECKM2:-128}"
export THREADS_DREP="${THREADS_DREP:-128}"
export THREADS_GTDBTK="${THREADS_GTDBTK:-128}"
export THREADS_COVERM="${THREADS_COVERM:-96}"
export THREADS_CDHIT="${THREADS_CDHIT:-128}"
export THREADS_CDHIT_EST="${THREADS_CDHIT_EST:-256}"
export THREADS_SALMON="${THREADS_SALMON:-256}"
export THREADS_EGGNOG="${THREADS_EGGNOG:-256}"

# --- SPAdes 参数 ---
export SPADES_MEMORY="${SPADES_MEMORY:-256}"

# --- Kraken2/Bracken 参数 ---
export BRACKEN_READLEN="${BRACKEN_READLEN:-150}"

# --- Binning/MAG 筛选标准 ---
export MIN_CONTIG_BINNING="${MIN_CONTIG_BINNING:-1500}"
export MAG_COMPLETENESS="${MAG_COMPLETENESS:-90}"
export MAG_CONTAMINATION="${MAG_CONTAMINATION:-5}"
export MAG_MQ_COMPLETENESS="${MAG_MQ_COMPLETENESS:-50}"
export MAG_MQ_CONTAMINATION="${MAG_MQ_CONTAMINATION:-10}"

# --- dRep 参数 ---
export DREP_COMP="${DREP_COMP:-50}"
export DREP_CON="${DREP_CON:-10}"
export DREP_PA="${DREP_PA:-0.90}"
export DREP_SA="${DREP_SA:-0.95}"

# --- CD-HIT 参数 ---
export CDHIT_IDENTITY="${CDHIT_IDENTITY:-0.95}"
export CDHIT_COVERAGE="${CDHIT_COVERAGE:-0.9}"
export CDHIT_MIN_GENE_LEN="${CDHIT_MIN_GENE_LEN:-150}"

# --- 邮件通知（设 ENABLE_EMAIL=true 开启）---
export ENABLE_EMAIL="${ENABLE_EMAIL=true}"
export EMAIL_TO="${EMAIL_TO:-bzw02052021@163.com}"
export EMAIL_FROM="${EMAIL_FROM:-13701213826@163.com}"
