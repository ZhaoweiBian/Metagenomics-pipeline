#!/bin/bash
# 合并所有样本 contigs 并进行 Prodigal 基因预测
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

start_time=$(date +%s)
merged_contigs="${CONTIG_FUNCTION_DIR}/all_contigs.fasta"
faa_file="${CONTIG_FUNCTION_DIR}/all_proteins.faa"
fna_file="${CONTIG_FUNCTION_DIR}/all_genes.fna"
gff_file="${CONTIG_FUNCTION_DIR}/all_prodigal.gff"

mkdir -p "$CONTIG_FUNCTION_DIR"
status="SUCCESS"

log_info "合并所有样本 contigs"
> "$merged_contigs"

for d in "$ASSEMBLY_CONTIG_DIR"/*_spades; do
    sample=$(basename "$d" | sed 's/_spades//')
    file="${d}/${sample}_contigs.fasta"
    if [[ -f "$file" ]]; then
        cat "$file" >> "$merged_contigs"
    else
        log_warn "缺失: $file"
    fi
done

if [[ ! -s "$merged_contigs" ]]; then
    log_error "合并 contigs 失败（文件为空）"
    exit 1
fi

log_info "运行 Prodigal"
prodigal -i "$merged_contigs" -a "$faa_file" -d "$fna_file" \
    -f gff -o "$gff_file" -p meta || status="FAIL"

runtime=$(format_runtime $(( $(date +%s) - start_time )))
send_notification "Prodigal基因预测通知" \
"Prodigal $([ "$status" = SUCCESS ] && echo 成功 || echo 失败)
耗时: $runtime
输出: $CONTIG_FUNCTION_DIR"

[[ "$status" == "SUCCESS" ]] || exit 1
