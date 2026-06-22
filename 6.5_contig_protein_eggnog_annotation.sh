#!/bin/bash
# NR protein eggNOG-mapper 功能注释
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# eggNOG-mapper 在独立 conda 环境中运行
activate_conda_env "${CONDA_ENV_EGGNOG}"

input_faa="${GENE_QUANT_DIR}/proteins_based_nr_gene_95.faa"
output_dir="${GENE_QUANT_DIR}/protein_function/eggNOG"

mkdir -p "$output_dir"
check_file "$input_faa" || exit 1

if [[ ! -f "${output_dir}/eggnog_process.emapper.seed_orthologs" ]]; then
    log_info "eggNOG seed ortholog search"
    emapper.py --no_annot --no_file_comments --override \
        --data_dir "$EGGNOG_DB" -i "$input_faa" -m diamond \
        --cpu "$THREADS_EGGNOG" -o "${output_dir}/eggnog_process"
else
    log_info "seed ortholog 已存在，跳过"
fi

if [[ ! -f "${output_dir}/eggnog.emapper.annotations" ]]; then
    log_info "eggNOG annotation"
    emapper.py \
        --annotate_hits_table "${output_dir}/eggnog_process.emapper.seed_orthologs" \
        --data_dir "$EGGNOG_DB" --cpu "$THREADS_EGGNOG" \
        --no_file_comments --override -o "${output_dir}/eggnog"
else
    log_info "注释结果已存在，跳过"
fi

protein_num=$(grep -c "^>" "$input_faa")
annot_num=$(grep -cv "^#" "${output_dir}/eggnog.emapper.annotations" 2>/dev/null || echo 0)
log_info "蛋白: $protein_num, 注释: $annot_num"

# 恢复主分析环境，供后续步骤使用
activate_conda_env "${CONDA_ENV_MAIN}"

send_notification "eggNOG注释通知" "蛋白: $protein_num, 注释: $annot_num"
