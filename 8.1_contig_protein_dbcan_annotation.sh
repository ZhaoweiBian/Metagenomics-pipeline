#!/bin/bash
# Contig NR 蛋白 dbCAN CAZyme 注释（依赖 6.3 蛋白序列）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_DBCAN}"

input_faa="${GENE_QUANT_DIR}/proteins_based_nr_gene_95.faa"
output_dir="${CONTIG_DBCAN_DIR}"
overview_file="${output_dir}/overview.tsv"

mkdir -p "$output_dir"
check_file "$input_faa" || exit 1

if [[ -f "$overview_file" ]]; then
    log_info "dbCAN overview 已存在，跳过: $overview_file"
else
    log_info "run_dbcan CAZyme 注释: $(basename "$input_faa")"
    run_dbcan CAZyme_annotation \
        --mode protein \
        --input_raw_data "$input_faa" \
        --output_dir "$output_dir" \
        --db_dir "$DBCAN_DB" \
        --methods diamond,hmm,dbCANsub \
        --threads "$THREADS_DBCAN"
fi

protein_num=$(grep -c "^>" "$input_faa")
annot_num=$(awk -F'\t' 'NR>1 && ($4!="-" || $5!="-" || $6!="-" || $8!="-") {c++} END{print c+0}' "$overview_file")
log_info "蛋白: $protein_num, CAZyme 注释基因: $annot_num"

activate_conda_env "${CONDA_ENV_MAIN}"

send_notification "Contig dbCAN注释通知" \
"蛋白: $protein_num
CAZyme注释基因: $annot_num
输出: $output_dir"
