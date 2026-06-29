#!/bin/bash
# 4.2 GTDB-Tk：dRep MAG 物种注释与系统发育树
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_GTDBTK}"

start_time=$(date +%s)
out_dir="${GTDBTK_HQ_OUT_DIR}"
shopt -s nullglob
mags=("$DREP_MAG_DIR"/*.fa)
mag_number=${#mags[@]}
shopt -u nullglob

if [[ "$mag_number" -eq 0 ]]; then
    log_error "dRep 输出 MAG 为空: $DREP_MAG_DIR（请先运行 4.1）"
    exit 1
fi

mkdir -p "$out_dir"
status="SUCCESS"

log_info "GTDB-Tk HQ/dRep 分类 ($mag_number MAGs) → $out_dir"
gtdbtk classify_wf \
    --genome_dir "$DREP_MAG_DIR" \
    --out_dir "$out_dir" \
    --extension fa \
    --cpus "$THREADS_GTDBTK" \
    --skip_ani_screen || status="FAIL"

msa_file="${out_dir}/align/gtdbtk.bac120.user_msa.fasta.gz"
if [[ -f "$msa_file" ]]; then
    log_info "构建 HQ MAG 系统发育树"
    gtdbtk infer --msa_file "$msa_file" --out_dir "$out_dir" \
        --cpus "$THREADS_GTDBTK" || status="FAIL"
fi

bac_number=0
arc_number=0
[[ -f "${out_dir}/gtdbtk.bac120.summary.tsv" ]] && \
    bac_number=$(awk 'END{print NR-1}' "${out_dir}/gtdbtk.bac120.summary.tsv")
[[ -f "${out_dir}/gtdbtk.ar53.summary.tsv" ]] && \
    arc_number=$(awk 'END{print NR-1}' "${out_dir}/gtdbtk.ar53.summary.tsv")

runtime=$(format_runtime $(( $(date +%s) - start_time )))

activate_conda_env "${CONDA_ENV_MAIN}"

send_notification "GTDB-Tk HQ任务通知" \
"GTDB-Tk HQ/dRep $status
输入MAG: $mag_number, 细菌: $bac_number, 古菌: $arc_number
耗时: $runtime
输出: $out_dir"

[[ "$status" == "SUCCESS" ]] || exit 1
