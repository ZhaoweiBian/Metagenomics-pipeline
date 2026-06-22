#!/bin/bash
# 从 NR genes 提取对应蛋白序列
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

nr_gene_fna="${GENE_QUANT_DIR}/NR_genes_95.fna"
all_protein_faa="${CONTIG_FUNCTION_DIR}/all_proteins.faa"
output_faa="${GENE_QUANT_DIR}/proteins_based_nr_gene_95.faa"

mkdir -p "$GENE_QUANT_DIR"
check_file "$nr_gene_fna" || exit 1
check_file "$all_protein_faa" || exit 1

log_info "提取 NR 对应蛋白序列"
awk '
FNR==NR {
    if ($0 ~ /^>/) { sub(/^>/,""); split($0,a," "); id[a[1]]=1 }
    next
}
{
    if ($0 ~ /^>/) {
        split($0,a," ")
        gene_id=substr(a[1],2)
        keep=(gene_id in id)
    }
    if (keep) print
}
' "$nr_gene_fna" "$all_protein_faa" > "$output_faa"

gene_num=$(grep -c "^>" "$nr_gene_fna")
protein_num=$(grep -c "^>" "$output_faa")

if [[ "$gene_num" -ne "$protein_num" ]]; then
    log_warn "gene ($gene_num) ≠ protein ($protein_num), 请检查 ID 匹配"
fi

log_info "NR gene: $gene_num, NR protein: $protein_num"
send_notification "NR蛋白提取通知" "gene: $gene_num, protein: $protein_num"
