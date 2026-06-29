#!/bin/bash
# dRep MAG 蛋白 dbCAN CAZyme 注释（依赖 7.1）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_DBCAN}"

mkdir -p "$MAG_DBCAN_DIR"
shopt -s nullglob
faas=("$MAG_GENE_PRED_DIR"/*.prefixed.faa)
shopt -u nullglob

if [[ ${#faas[@]} -eq 0 ]]; then
    log_error "未找到 prefixed.faa: $MAG_GENE_PRED_DIR（请先运行 7.1 或 --phase mag_function）"
    exit 1
fi

for faa in "${faas[@]}"; do
    base=$(basename "$faa" .prefixed.faa)
    subdir="${MAG_DBCAN_DIR}/${base}"
    overview_file="${subdir}/overview.tsv"
    mkdir -p "$subdir"

    if [[ -f "$overview_file" ]]; then
        log_info "dbCAN 已存在，跳过: $base"
        continue
    fi

    log_info "run_dbcan dRep MAG: $base"
    run_dbcan CAZyme_annotation \
        --mode protein \
        --input_raw_data "$faa" \
        --output_dir "$subdir" \
        --db_dir "$DBCAN_DB" \
        --methods diamond,hmm,dbCANsub \
        --threads "$THREADS_DBCAN"
done

activate_conda_env "${CONDA_ENV_MAIN}"

send_notification "dRep MAG dbCAN注释通知" \
"完成 ${#faas[@]} 个 dRep MAG
输出: $MAG_DBCAN_DIR"
