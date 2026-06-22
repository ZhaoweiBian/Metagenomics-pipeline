#!/bin/bash
# 4.3 GTDB-Tk：全部中高质量 MAG 物种注释（3.10 medium_quality_bins，含 HQ+MQ）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_GTDBTK}"

start_time=$(date +%s)
out_dir="${GTDBTK_MQ_OUT_DIR}"
status="SUCCESS"

shopt -s nullglob
mags=("$MQ_MAG_DIR"/*.fa)
mag_number=${#mags[@]}
shopt -u nullglob

if [[ "$mag_number" -eq 0 ]]; then
    log_error "中高质量 MAG 目录为空: $MQ_MAG_DIR（请先运行 3.10）"
    exit 1
fi

mkdir -p "$out_dir"
log_info "GTDB-Tk 中高质量 MAG 分类 ($mag_number MAGs) → $out_dir"

if ! gtdbtk classify_wf \
    --genome_dir "$MQ_MAG_DIR" \
    --out_dir "$out_dir" \
    --extension fa \
    --cpus "$THREADS_GTDBTK" \
    --skip_ani_screen; then
    status="FAIL"
fi

bac_number=0
arc_number=0
[[ -f "${out_dir}/gtdbtk.bac120.summary.tsv" ]] && \
    bac_number=$(awk 'END{print NR-1}' "${out_dir}/gtdbtk.bac120.summary.tsv")
[[ -f "${out_dir}/gtdbtk.ar53.summary.tsv" ]] && \
    arc_number=$(awk 'END{print NR-1}' "${out_dir}/gtdbtk.ar53.summary.tsv")

runtime=$(format_runtime $(( $(date +%s) - start_time )))

activate_conda_env "${CONDA_ENV_MAIN}"

send_notification "GTDB-Tk MQ任务通知" \
"GTDB-Tk 中高质量MAG $status
输入MAG: $mag_number, 细菌: $bac_number, 古菌: $arc_number
耗时: $runtime
输出: $out_dir"

[[ "$status" == "SUCCESS" ]] || exit 1
