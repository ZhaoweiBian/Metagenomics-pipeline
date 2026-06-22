#!/bin/bash
# Fastp 质控 — 标准流程 QC 步骤（输出供 1.1 dehost 使用）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

mkdir -p "$QC_DIR"
check_file "$SAMPLE_LIST" || exit 1

start_time=$(date +%s)
sample_count=0

while IFS= read -r sample || [[ -n "$sample" ]]; do
    [[ -z "$sample" || "$sample" =~ ^# ]] && continue
    log_info "Processing $sample"

    r1="${RAW_DATA_DIR}/${sample}_1.fq.gz"
    r2="${RAW_DATA_DIR}/${sample}_2.fq.gz"
    check_file "$r1" || exit 1
    check_file "$r2" || exit 1

    fastp \
        -i "$r1" -I "$r2" \
        -o "${QC_DIR}/${sample}_1.clean.fq.gz" \
        -O "${QC_DIR}/${sample}_2.clean.fq.gz" \
        --thread "$THREADS_QC" \
        --detect_adapter_for_pe \
        --cut_front --cut_tail --cut_right \
        --cut_window_size 4 --cut_mean_quality 20 \
        --length_required 50 \
        --low_complexity_filter --complexity_threshold 30 \
        --html "${QC_DIR}/${sample}.fastp.html" \
        --json "${QC_DIR}/${sample}.fastp.json"

    log_info "$sample finished"
    sample_count=$((sample_count + 1))
done < "$SAMPLE_LIST"

runtime=$(format_runtime $(( $(date +%s) - start_time )))
log_info "All samples QC finished"

send_notification "Fastp质控通知" \
"脚本: 0.2_quality_control.sh
服务器: $(hostname)
样本数: $sample_count
耗时: $runtime
输出: $QC_DIR"
