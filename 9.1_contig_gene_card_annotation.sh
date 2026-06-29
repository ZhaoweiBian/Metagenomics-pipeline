#!/bin/bash
# Contig NR 基因 CARD(RGI) 耐药注释（依赖 6.2 基因序列）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_RGI}"

input_fna="${GENE_QUANT_DIR}/NR_genes_95.fna"
output_dir="${CONTIG_CARD_DIR}"
output_prefix="${output_dir}/contig_card"
result_file="${output_prefix}.txt"

mkdir -p "$output_dir"
check_file "$input_fna" || exit 1
check_dir "${CARD_DB_DIR}/localDB" || exit 1

if [[ -f "$result_file" ]]; then
    log_info "RGI 结果已存在，跳过: $result_file"
else
    log_info "RGI 注释 Contig 基因: $(basename "$input_fna")"
    (
        cd "$CARD_DB_DIR"
        rgi main -i "$input_fna" -o "$output_prefix" \
            -n "$THREADS_RGI" --local --clean --include_loose --include_nudge
    )
fi

gene_num=$(grep -c "^>" "$input_fna")
hit_num=$(awk 'END{print NR-1}' "$result_file" 2>/dev/null || echo 0)

activate_conda_env "${CONDA_ENV_MAIN}"

send_notification "Contig CARD注释通知" \
"基因: $gene_num
耐药命中: $hit_num
输出: $output_dir"
