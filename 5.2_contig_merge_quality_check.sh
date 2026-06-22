#!/bin/bash
# Contig 合并质量检查
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

all_contigs="${CONTIG_FUNCTION_DIR}/all_contigs.fasta"
all_genes="${CONTIG_FUNCTION_DIR}/all_genes.fna"
all_proteins="${CONTIG_FUNCTION_DIR}/all_proteins.faa"
output_file="${CONTIG_FUNCTION_DIR}/contig_merge_check.txt"
status="SUCCESS"

exec > >(tee "$output_file") 2>&1

count_seq() { grep -c "^>" "$1" 2>/dev/null || echo 0; }

echo "===== Contig 合并质量检查 ====="
echo "时间: $(date)"

for f in "$all_contigs" "$all_genes" "$all_proteins"; do
    if [[ -f "$f" ]]; then
        echo "文件: $(basename "$f"), 序列数: $(count_seq "$f")"
    else
        echo "文件不存在: $f"; status="FAIL"
    fi
done

sum=0
for d in "$ASSEMBLY_CONTIG_DIR"/*_spades; do
    [[ -d "$d" ]] || continue
    sample=$(basename "$d" | sed 's/_spades//')
    file="${d}/${sample}_contigs.fasta"
    if [[ -f "$file" ]]; then
        c=$(count_seq "$file")
        echo "$sample : $c"
        sum=$((sum + c))
    else
        echo "缺失: $file"; status="FAIL"
    fi
done

echo "合并前 contigs 总和: $sum"
if [[ -f "$all_contigs" ]]; then
    merged=$(count_seq "$all_contigs")
    echo "合并后 contigs 数: $merged"
    if [[ "$merged" -eq "$sum" ]]; then
        echo "一致"
    else
        echo "不一致 (差值: $((merged - sum)))"; status="FAIL"
    fi
fi

send_notification "Contig检查通知" \
"脚本: 5.2_contig_merge_quality_check.sh
检查 $status, 结果: $output_file"
