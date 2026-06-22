#!/bin/bash
# MAG eggNOG-mapper 功能注释
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# eggNOG-mapper 在独立 conda 环境中运行
activate_conda_env "${CONDA_ENV_EGGNOG}"

mkdir -p "$MAG_ANNOT_DIR"
shopt -s nullglob
faas=("$MAG_GENE_PRED_DIR"/*.prefixed.faa)
shopt -u nullglob

if [[ ${#faas[@]} -eq 0 ]]; then
    log_error "未找到 prefixed.faa 文件: $MAG_GENE_PRED_DIR"
    exit 1
fi

for faa in "${faas[@]}"; do
    base=$(basename "$faa" .prefixed.faa)
    subdir="${MAG_ANNOT_DIR}/${base}"
    mkdir -p "$subdir"

    log_info "eggNOG: $base"
    emapper.py --no_annot --no_file_comments --override \
        --data_dir "$EGGNOG_DB" -i "$faa" -m diamond \
        --cpu "$THREADS_EGGNOG" -o "${subdir}/${base}.seed"

    emapper.py \
        --annotate_hits_table "${subdir}/${base}.seed.emapper.seed_orthologs" \
        --data_dir "$EGGNOG_DB" --cpu "$THREADS_EGGNOG" \
        --no_file_comments --override -o "${subdir}/${base}"
done

# 恢复主分析环境，供后续步骤使用
activate_conda_env "${CONDA_ENV_MAIN}"

send_notification "MAG eggNOG通知" "完成 ${#faas[@]} 个 MAG, 输出: $MAG_ANNOT_DIR"
