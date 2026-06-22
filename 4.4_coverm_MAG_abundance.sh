#!/bin/bash
# 4.4 CoverM：dRep MAG 在各样本中的丰度 (TPM / relative abundance)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

start_time=$(date +%s)
abundance_file="${COVERM_OUT_DIR}/MAGs_abundance.tsv"
tpm_matrix="${COVERM_OUT_DIR}/MAG_tpm.csv"
ra_matrix="${COVERM_OUT_DIR}/MAG_relative_abundance.csv"

mkdir -p "$COVERM_OUT_DIR"
shopt -s nullglob

mags=("$DREP_MAG_DIR"/*.fa)
mag_number=${#mags[@]}
R1_LIST=("$DEHOST_DIR"/*_dehost_R1.fq.gz)
R2_LIST=("$DEHOST_DIR"/*_dehost_R2.fq.gz)
shopt -u nullglob

if [[ "$mag_number" -eq 0 ]]; then
    log_error "MAG 目录为空"
    exit 1
fi
if [[ ${#R1_LIST[@]} -ne ${#R2_LIST[@]} ]]; then
    log_error "R1/R2 数量不一致"
    exit 1
fi

COUPLED_READS=""
for R1 in "${R1_LIST[@]}"; do
    R2="${R1/_R1.fq.gz/_R2.fq.gz}"
    check_file "$R2" || exit 1
    COUPLED_READS+=" $R1 $R2"
done

log_info "CoverM: $mag_number MAGs, ${#R1_LIST[@]} samples"
status="SUCCESS"

if ! coverm genome \
    --coupled $COUPLED_READS \
    --genome-fasta-directory "$DREP_MAG_DIR" \
    --genome-fasta-extension fa \
    --methods relative_abundance mean tpm rpkm \
    --min-read-aligned-percent 75 \
    --min-read-percent-identity 95 \
    --threads "$THREADS_COVERM" \
    --output-file "$abundance_file"; then
    status="FAIL"
fi

awk '
BEGIN{FS="\t";OFS=","}
NR==1{
    printf "MAG"
    for(i=2;i<=NF;i++){
        if(tolower($i) ~ /tpm$/){
            name=$i; gsub("_dehost_R1.fq.gz","",name)
            printf ","name; col[c++]=i
        }
    }
    printf "\n"; next
}
{ printf $1; for(i=0;i<c;i++) printf ","$(col[i]); printf "\n" }
' "$abundance_file" > "$tpm_matrix"

awk '
BEGIN{FS="\t";OFS=","}
NR==1{
    printf "MAG"
    for(i=2;i<=NF;i++){
        if(tolower($i) ~ /relative abundance/){
            name=$i; gsub("_dehost_R1.fq.gz","",name)
            printf ","name; col[c++]=i
        }
    }
    printf "\n"; next
}
{ printf $1; for(i=0;i<c;i++) printf ","$(col[i]); printf "\n" }
' "$abundance_file" > "$ra_matrix"

sed -i '/^unmapped/d' "$tpm_matrix" "$ra_matrix"
sed -i 's/_dehost_R1.fq.gz//g' "$tpm_matrix" "$ra_matrix"

runtime=$(format_runtime $(( $(date +%s) - start_time )))
send_notification "CoverM丰度通知" \
"CoverM $status
MAG: $mag_number, 样本: ${#R1_LIST[@]}
耗时: $runtime
输出: $COVERM_OUT_DIR"

[[ "$status" == "SUCCESS" ]] || exit 1
