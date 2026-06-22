#!/bin/bash
# dRep 高质量 MAG 去冗余
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

start_time=$(date +%s)
quality_tsv="${ASSEMBLY_CONTIG_DIR}/all_bins_quality.tsv"
output_csv="${ASSEMBLY_CONTIG_DIR}/all_high_quality_bin_quality.csv"
tmp_list="${LOG_DIR}/high_quality_bins.txt"

mkdir -p "$LOG_DIR" "$DREP_OUT_DIR"
shopt -s nullglob

bins=("$HQ_MAG_DIR"/*.fa)
if [[ ${#bins[@]} -eq 0 ]]; then
    log_error "高质量 MAG 目录为空: $HQ_MAG_DIR"
    exit 1
fi

log_info "Step1: 生成高质量 bin 质量 CSV"
{
    echo "genome,completeness,contamination"
    for binfile in "${bins[@]}"; do
        bin_name=$(basename "$binfile")
        line=$(awk -v name="$bin_name" 'NR>1 && $2==name {print; exit}' "$quality_tsv")
        if [[ -n "$line" ]]; then
            echo "$bin_name,$(echo "$line" | awk '{print $3","$4}')"
        else
            log_warn "$bin_name not found in quality tsv"
        fi
    done
} > "$output_csv"

bin_number=${#bins[@]}
log_info "高质量 bin 数量: $bin_number"

log_info "Step2: 运行 dRep"
status="SUCCESS"
if ! dRep dereplicate "$DREP_OUT_DIR" \
    -g "$HQ_MAG_DIR"/*.fa \
    -p "$THREADS_DREP" \
    -comp "$DREP_COMP" -con "$DREP_CON" \
    -pa "$DREP_PA" -sa "$DREP_SA" \
    --genomeInfo "$output_csv"; then
    status="FAIL"
fi

shopt -u nullglob
derep_number=$(find "${DREP_OUT_DIR}/dereplicated_genomes" -name '*.fa' 2>/dev/null | wc -l)
runtime=$(format_runtime $(( $(date +%s) - start_time )))

send_notification "dRep任务通知" \
"dRep $status
输入MAG: $bin_number, 去冗余后: $derep_number
耗时: $runtime
输出: $DREP_OUT_DIR"

[[ "$status" == "SUCCESS" ]] || exit 1
