#!/bin/bash
# 对 fastp QC 后的测序数据进行宿主去除 (Bowtie2)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

mkdir -p "$DEHOST_DIR" "${LOG_DIR}/dehost"
check_file "$SAMPLE_LIST" || exit 1

start_time=$(date +%s)
sample_count=0

while IFS= read -r sample || [[ -n "$sample" ]]; do
    [[ -z "$sample" || "$sample" =~ ^# ]] && continue
    log_info "Processing $sample"

    r1="${QC_DIR}/${sample}_1.clean.fq.gz"
    r2="${QC_DIR}/${sample}_2.clean.fq.gz"
    check_file "$r1" || exit 1
    check_file "$r2" || exit 1

    bowtie2 \
        -1 "$r1" -2 "$r2" \
        -x "$PIG_GENOME_INDEX" \
        --un-conc-gz "${DEHOST_DIR}/${sample}_dehost_R%.fq.gz" \
        -p "$THREADS_DEHOST" \
        > "${LOG_DIR}/dehost/${sample}_host.log" 2>&1

    log_info "Finished $sample"
    sample_count=$((sample_count + 1))
done < "$SAMPLE_LIST"

runtime=$(format_runtime $(( $(date +%s) - start_time )))
log_info "All samples dehost finished"

send_notification "宿主去除通知" \
"脚本: 1.1_dehost.sh
服务器: $(hostname)
样本数: $sample_count
耗时: $runtime
输出: $DEHOST_DIR"
