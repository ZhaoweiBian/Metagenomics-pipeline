#!/bin/bash
# =============================================================================
# Pipeline 公共函数库
# =============================================================================

# 定位脚本目录并加载配置
_pipeline_init() {
    local caller="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    SCRIPT_DIR="$(cd "$(dirname "$caller")" && pwd)"
    # 若从 lib/ 调用，则上一级为 script 根目录
    if [[ "$(basename "$SCRIPT_DIR")" == "lib" ]]; then
        SCRIPT_DIR="$(dirname "$SCRIPT_DIR")"
    fi
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/config.sh"
    _apply_gui_project_paths
    mkdir -p "$LOG_DIR"
}

# 将所有下载/分析输入输出目录归到 PROJECT_ROOT（GUI 或环境变量传入）
_apply_gui_project_paths() {
    local root="${PROJECT_ROOT:-}"
    [[ -n "$root" ]] || return 0
    root="${root%/}"
    export PROJECT_ROOT="$root"

    export SAMPLE_LIST="${root}/samplelist.txt"
    export LINKLIST="${root}/linklist.txt"
    export RAW_DATA_DIR="${RAW_DATA_DIR:-${root}/raw}"
    export QC_DIR="${root}/qc"
    export DEHOST_DIR="${root}/dehost"
    export LOG_DIR="${root}/logs"
    export KRAKEN2_DIR="${root}/kraken2"
    export BRACKEN_DIR="${root}/bracken"
    export ASSEMBLY_CONTIG_DIR="${root}/assembly/contig"
    export HQ_MAG_DIR="${root}/assembly/high_quality_bins"
    export DREP_OUT_DIR="${root}/assembly/drep/all_bins"
    export DREP_MAG_DIR="${DREP_OUT_DIR}/dereplicated_genomes"
    export GTDBTK_HQ_OUT_DIR="${root}/gtdbtk"
    export GTDBTK_OUT_DIR="${root}/gtdbtk"
    export COVERM_OUT_DIR="${root}/coverm"
    export CONTIG_FUNCTION_DIR="${root}/contig_function"
    export GENE_QUANT_DIR="${CONTIG_FUNCTION_DIR}/gene_quant"
    export MAG_FUNCTION_DIR="${root}/MAG_function"
    export MAG_GENE_PRED_DIR="${MAG_FUNCTION_DIR}/gene_prediction"
    export MAG_ANNOT_DIR="${MAG_FUNCTION_DIR}/function_annotation"
    export MAG_FUNCTION_MATRIX_DIR="${MAG_FUNCTION_DIR}/function_matrix"
    export FUNCTION_MATRIX_DIR="${GENE_QUANT_DIR}/function_matrix"
    export CONTIG_DBCAN_DIR="${GENE_QUANT_DIR}/protein_function/dbCAN"
    export CONTIG_CARD_DIR="${GENE_QUANT_DIR}/gene_function/card"
    export MAG_DBCAN_DIR="${MAG_FUNCTION_DIR}/dbcan_annotation"
    export MAG_CARD_DIR="${MAG_FUNCTION_DIR}/card_annotation"
}

# 日志
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
log_warn()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" >&2; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; }

# 检查文件/目录
check_file() {
    if [[ ! -f "$1" ]]; then
        log_error "文件不存在: $1"
        return 1
    fi
}

check_dir() {
    if [[ ! -d "$1" ]]; then
        log_error "目录不存在: $1"
        return 1
    fi
}

# Conda 环境切换
_init_conda() {
    if [[ -z "${_CONDA_INITIALIZED:-}" ]]; then
        # shellcheck source=/dev/null
        source "${CONDA_BASE}/etc/profile.d/conda.sh"
        _CONDA_INITIALIZED=1
    fi
}

activate_conda_env() {
    local env_name="$1"
    _init_conda
    if [[ "${CONDA_DEFAULT_ENV:-}" == "$env_name" ]]; then
        log_info "已在 conda 环境: ${env_name}"
        return 0
    fi
    if [[ -n "${CONDA_DEFAULT_ENV:-}" ]]; then
        log_info "退出 conda 环境: ${CONDA_DEFAULT_ENV}"
        conda deactivate
    fi
    log_info "激活 conda 环境: ${env_name}"
    # conda openjdk_activate.sh 在 set -u 下要求 JAVA_LD_LIBRARY_PATH 已定义
    if [[ -z "${JAVA_HOME:-}" && -n "${CONDA_PREFIX:-}" ]]; then
        export JAVA_HOME="${CONDA_PREFIX}"
    fi
    if [[ -n "${JAVA_HOME:-}" ]]; then
        export JAVA_LD_LIBRARY_PATH="${JAVA_LD_LIBRARY_PATH:-${JAVA_HOME}/lib/server}"
    else
        export JAVA_LD_LIBRARY_PATH="${JAVA_LD_LIBRARY_PATH:-}"
    fi
    conda activate "$env_name"
}

# 读取样本列表（跳过空行和注释）
read_samples() {
    local list="${1:-$SAMPLE_LIST}"
    check_file "$list" || return 1
    grep -v '^\s*$' "$list" | grep -v '^\s*#'
}

# 邮件通知
send_notification() {
    local subject="$1"
    local body="$2"
    if [[ "${ENABLE_EMAIL}" == "true" ]] && command -v mail &>/dev/null; then
        echo -e "$body" | mail -r "${EMAIL_FROM}" -s "$subject" -a "From: ${EMAIL_FROM}" "${EMAIL_TO}"
    fi
}

# 运行时间格式化
format_runtime() {
    local seconds=$1
    local h=$((seconds / 3600))
    local m=$(((seconds % 3600) / 60))
    local s=$((seconds % 60))
    printf "%dh %dm %ds" "$h" "$m" "$s"
}

# 任务计时包装
run_step() {
    local step_name="$1"
    shift
    local start end runtime
    start=$(date +%s)
    log_info "开始: ${step_name}"
    if "$@"; then
        end=$(date +%s)
        runtime=$((end - start))
        log_info "完成: ${step_name} (耗时: $(format_runtime "$runtime"))"
        return 0
    else
        log_error "失败: ${step_name}"
        return 1
    fi
}

# 遍历 *_spades 组装目录
iter_spades_dirs() {
    local base="${1:-$ASSEMBLY_CONTIG_DIR}"
    for dir in "$base"/*_spades; do
        [[ -d "$dir" ]] || continue
        echo "$dir"
    done
}

# 获取样本名（从 *_spades 目录名）
sample_from_spades_dir() {
    basename "$1" _spades
}

# 各步骤脚本均为 source config.sh 后再 source 本文件，此处统一覆盖旧版 config 中的绝对路径
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _apply_gui_project_paths
fi
