#!/bin/bash
# Prodigal 蛋白序列 CD-HIT 去冗余 (95% identity)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

input_faa="${CONTIG_FUNCTION_DIR}/all_proteins.faa"
output_faa="${CONTIG_FUNCTION_DIR}/all_proteins.nr95.faa"

check_file "$input_faa" || exit 1
seq_number=$(grep -c "^>" "$input_faa")

log_info "CD-HIT 蛋白去冗余, 输入: $seq_number"
cd-hit -i "$input_faa" -o "$output_faa" \
    -c "$CDHIT_IDENTITY" -n 5 -T "$THREADS_CDHIT" -M 0 \
    -aS "$CDHIT_COVERAGE" -g 1 -G 0

nr_seq_number=$(grep -c "^>" "$output_faa")
log_info "去冗余后: $nr_seq_number"
send_notification "CD-HIT蛋白通知" "输入: $seq_number, 输出: $nr_seq_number"
