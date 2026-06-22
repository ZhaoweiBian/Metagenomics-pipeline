#!/bin/bash
# 基因序列 CD-HIT-EST 去冗余 (95% identity)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

input_fna="${CONTIG_FUNCTION_DIR}/all_genes.fna"
output_fna="${GENE_QUANT_DIR}/NR_genes_95.fna"
filtered_fna="${GENE_QUANT_DIR}/all_genes.${CDHIT_MIN_GENE_LEN}.fna"

mkdir -p "$GENE_QUANT_DIR"
check_file "$input_fna" || exit 1

seq_number=$(grep -c "^>" "$input_fna")
log_info "过滤短基因 (<${CDHIT_MIN_GENE_LEN}bp)"
seqkit seq -m "$CDHIT_MIN_GENE_LEN" -g "$input_fna" > "$filtered_fna"
filtered_number=$(grep -c "^>" "$filtered_fna")

log_info "CD-HIT-EST 去冗余"
cd-hit-est -i "$filtered_fna" -o "$output_fna" \
    -c "$CDHIT_IDENTITY" -n 10 -T "$THREADS_CDHIT_EST" -M 0 \
    -aS "$CDHIT_COVERAGE" -g 1 -G 0

nr_seq_number=$(grep -c "^>" "$output_fna")
log_info "输入: $seq_number, 过滤后: $filtered_number, 去冗余后: $nr_seq_number"
send_notification "CD-HIT基因通知" "去冗余后: $nr_seq_number"
