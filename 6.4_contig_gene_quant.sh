#!/bin/bash
# Salmon 基因丰度定量 + 矩阵合并
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

gene_fna="${GENE_QUANT_DIR}/NR_genes_95.fna"
index_dir="${GENE_QUANT_DIR}/salmon_index_nr95"
quant_dir="${GENE_QUANT_DIR}/salmon_quant"
matrix_dir="${GENE_QUANT_DIR}/salmon_matrix"

mkdir -p "$quant_dir" "$matrix_dir"
check_file "$gene_fna" || exit 1
check_file "$SAMPLE_LIST" || exit 1

start_time=$(date +%s)
sample_count=0
failed=0

if [[ ! -d "$index_dir" ]] || [[ -z "$(ls -A "$index_dir" 2>/dev/null)" ]]; then
    log_info "构建 Salmon index"
    salmon index -t "$gene_fna" -i "$index_dir" -p "$THREADS_SALMON"
else
    log_info "Salmon index 已存在，跳过"
fi

while IFS= read -r sample || [[ -n "$sample" ]]; do
    [[ -z "$sample" || "$sample" =~ ^# ]] && continue

    R1="${DEHOST_DIR}/${sample}_dehost_R1.fq.gz"
    R2="${DEHOST_DIR}/${sample}_dehost_R2.fq.gz"
    out_sample="${quant_dir}/${sample}.quant"

    if [[ ! -f "$R1" || ! -f "$R2" ]]; then
        log_warn "缺失 reads: $sample"
        continue
    fi
    if [[ -d "$out_sample" ]]; then
        log_info "已存在: $sample, 跳过"
        continue
    fi

    log_info "Salmon quant: $sample"
    mkdir -p "$out_sample"
    if ! salmon quant -i "$index_dir" -l A -p "$THREADS_SALMON" --meta \
        -1 "$R1" -2 "$R2" --validateMappings --gcBias --seqBias \
        -o "$out_sample"; then
        log_error "Salmon failed: $sample"
        failed=$((failed + 1))
        continue
    fi
    sample_count=$((sample_count + 1))
done < "$SAMPLE_LIST"

if [[ $failed -gt 0 ]]; then
    log_error "Salmon 失败样本数: $failed"
    exit 1
fi

log_info "合并丰度矩阵"
salmon quantmerge --quants "${quant_dir}"/*.quant --column TPM \
    -o "${matrix_dir}/gene.TPM.tsv"
salmon quantmerge --quants "${quant_dir}"/*.quant --column NumReads \
    -o "${matrix_dir}/gene.count.tsv"
sed -i '1s/\.quant//g' "${matrix_dir}/gene."*

send_notification "Salmon定量通知" "输出: $matrix_dir"
