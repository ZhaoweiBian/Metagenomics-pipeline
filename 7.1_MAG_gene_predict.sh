#!/bin/bash
# dRep 去冗余 MAG 的 Prodigal 基因预测
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

mkdir -p "$MAG_GENE_PRED_DIR"
shopt -s nullglob
mags=("$DREP_MAG_DIR"/*.fa)
shopt -u nullglob

if [[ ${#mags[@]} -eq 0 ]]; then
    log_error "MAG 目录为空: $DREP_MAG_DIR"
    exit 1
fi

for MAG in "${mags[@]}"; do
    base=$(basename "$MAG" .fa)
    prefixed_faa="${MAG_GENE_PRED_DIR}/${base}.prefixed.faa"
    prefixed_ffn="${MAG_GENE_PRED_DIR}/${base}.prefixed.ffn"

    if [[ -f "$prefixed_faa" && -f "$prefixed_ffn" ]]; then
        log_info "已存在，跳过 Prodigal: $base"
        continue
    fi

    log_info "Prodigal: $base"

    prodigal -i "$MAG" \
        -a "${MAG_GENE_PRED_DIR}/${base}.faa" \
        -d "${MAG_GENE_PRED_DIR}/${base}.ffn" \
        -f gff -o "${MAG_GENE_PRED_DIR}/${base}.prodigal.gff" \
        -p single

    awk -v mag="$base" '/^>/ { sub(/^>/, ">" mag "|"); print; next } { print }' \
        "${MAG_GENE_PRED_DIR}/${base}.faa" > "${MAG_GENE_PRED_DIR}/${base}.prefixed.faa"
    awk -v mag="$base" '/^>/ { sub(/^>/, ">" mag "|"); print; next } { print }' \
        "${MAG_GENE_PRED_DIR}/${base}.ffn" > "${MAG_GENE_PRED_DIR}/${base}.prefixed.ffn"
done

send_notification "MAG Prodigal通知" "完成 ${#mags[@]} 个 MAG, 输出: $MAG_GENE_PRED_DIR"
