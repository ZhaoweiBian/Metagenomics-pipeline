#!/bin/bash
# dRep MAG 基因 CARD(RGI) 耐药注释（依赖 7.1）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_RGI}"

mkdir -p "$MAG_CARD_DIR"
check_dir "${CARD_DB_DIR}/localDB" || exit 1

shopt -s nullglob
ffns=("$MAG_GENE_PRED_DIR"/*.prefixed.ffn)
shopt -u nullglob

if [[ ${#ffns[@]} -eq 0 ]]; then
    log_error "未找到 prefixed.ffn: $MAG_GENE_PRED_DIR（请先运行 7.1 或 --phase mag_function）"
    exit 1
fi

for ffn in "${ffns[@]}"; do
    base=$(basename "$ffn" .prefixed.ffn)
    subdir="${MAG_CARD_DIR}/${base}"
    output_prefix="${subdir}/${base}_card"
    result_file="${output_prefix}.txt"
    mkdir -p "$subdir"

    if [[ -f "$result_file" ]]; then
        log_info "RGI 已存在，跳过: $base"
        continue
    fi

    log_info "RGI dRep MAG: $base"
    (
        cd "$CARD_DB_DIR"
        rgi main -i "$ffn" -o "$output_prefix" \
            -n "$THREADS_RGI" --local --clean --include_loose --include_nudge
    )
done

activate_conda_env "${CONDA_ENV_MAIN}"

send_notification "dRep MAG CARD注释通知" \
"完成 ${#ffns[@]} 个 dRep MAG
输出: $MAG_CARD_DIR"
