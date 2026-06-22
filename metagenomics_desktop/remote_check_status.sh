#!/usr/bin/env bash
# 远程步骤完成状态检查（由桌面客户端通过 SSH 调用）
# 用法: remote_check_status.sh <PROJECT_ROOT>
set -euo pipefail

PR="${1:?用法: remote_check_status.sh PROJECT_ROOT}"

emit() {
    printf '%s\t%s\t%s\n' "$1" "$2" "$3"
}

has_glob() {
    compgen -G "$1" >/dev/null 2>&1
}

count_glob() {
    local n=0
    local f
    shopt -s nullglob
    local files=($1)
    shopt -u nullglob
    echo "${#files[@]}"
}

sample_n=0
if [[ -f "$PR/samplelist.txt" ]]; then
    sample_n=$(awk 'NF && $0 !~ /^#/' "$PR/samplelist.txt" | wc -l)
elif [[ -f "$PR/samplelist" ]]; then
    sample_n=$(awk 'NF && $0 !~ /^#/' "$PR/samplelist" | wc -l)
fi

# 0.x
if has_glob "$PR/qc/*_1.clean.fq.gz"; then
    emit "0.2" "done" "qc: $(count_glob "$PR/qc/*_1.clean.fq.gz") 对 reads"
else
    emit "0.2" "pending" "无 qc 输出"
fi

# 1.x
if has_glob "$PR/dehost/*_dehost_R1.fq.gz"; then
    emit "1.1" "done" "dehost: $(count_glob "$PR/dehost/*_dehost_R1.fq.gz") 样本"
else
    emit "1.1" "pending" "无 dehost 输出"
fi

# 2.x
if has_glob "$PR/kraken2/*.report"; then
    emit "2.1" "done" "kraken2 报告存在"
else
    emit "2.1" "pending" "无 kraken2"
fi
if [[ -f "$PR/bracken_merged/Species_abundance.tsv" ]]; then
    emit "2.2" "done" "bracken 合并表已生成"
else
    emit "2.2" "pending" "无 bracken_merged"
fi

# 3.x
spades_n=$(count_glob "$PR/assembly/contig/*_spades")
if [[ "$spades_n" -gt 0 ]]; then
    emit "3.1" "done" "${spades_n} 个组装目录"
else
    emit "3.1" "pending" "无组装结果"
fi
if [[ "$spades_n" -gt 0 ]] && has_glob "$PR/assembly/contig/*_spades/*.contigs.fasta"; then
    emit "3.2" "done" "contig 已预处理"
else
    emit "3.2" "pending" "未检测到预处理 contig"
fi
if has_glob "$PR/assembly/contig/*_spades/*.bt2"; then
    emit "3.3" "done" "bowtie2 索引存在"
else
    emit "3.3" "pending" "无索引"
fi
if has_glob "$PR/assembly/contig/*_spades/*.sort.bam"; then
    emit "3.4" "done" "BAM 已生成"
    emit "3.5" "done" "SAM→BAM 完成"
else
    emit "3.4" "pending" "无比对 BAM"
    emit "3.5" "pending" "无 BAM"
fi
depth_n=$(count_glob "$PR/assembly/contig/*_spades/*.depth.txt")
if [[ "$depth_n" -gt 0 ]]; then
    emit "3.6" "done" "${depth_n} 个 depth 文件"
else
    emit "3.6" "pending" "无 depth"
fi
if has_glob "$PR/assembly/contig/*_spades/binning/*.fa"; then
    emit "3.7" "done" "binning: $(count_glob "$PR/assembly/contig/*_spades/binning/*.fa") bins"
else
    emit "3.7" "pending" "无 binning"
fi
if has_glob "$PR/assembly/contig/*_spades/checkM2_result/quality_report.tsv"; then
    emit "3.8" "done" "CheckM2 完成"
else
    emit "3.8" "pending" "无 CheckM2"
fi
hq_n=$(count_glob "$PR/assembly/high_quality_bins/*.fa")
if [[ "$hq_n" -gt 0 ]]; then
    emit "3.9" "done" "HQ MAG: ${hq_n}"
else
    emit "3.9" "pending" "无 HQ MAG"
fi
mq_n=$(count_glob "$PR/assembly/medium_quality_bins/*.fa")
if [[ "$mq_n" -gt 0 ]]; then
    emit "3.10" "done" "MQ MAG: ${mq_n}"
else
    emit "3.10" "pending" "无 MQ MAG"
fi

# 4.x
drep_n=$(count_glob "$PR/assembly/drep/all_bins/dereplicated_genomes/*.fa")
if [[ "$drep_n" -gt 0 ]]; then
    emit "4.1" "done" "dRep MAG: ${drep_n}"
else
    emit "4.1" "pending" "无 dRep"
fi
if [[ -f "$PR/gtdbtk/gtdbtk.bac120.summary.tsv" ]] || [[ -f "$PR/gtdbtk/classify/gtdbtk.bac120.summary.tsv" ]]; then
    emit "4.2" "done" "GTDB-Tk HQ 完成"
else
    emit "4.2" "pending" "无 GTDB-Tk HQ"
fi
if [[ -f "$PR/gtdbtk_mq/gtdbtk.bac120.summary.tsv" ]] || [[ -f "$PR/gtdbtk_mq/classify/gtdbtk.bac120.summary.tsv" ]]; then
    emit "4.3" "done" "GTDB-Tk MQ 完成"
else
    emit "4.3" "pending" "无 GTDB-Tk MQ"
fi
if [[ -f "$PR/coverm/MAGs_abundance.tsv" ]]; then
    emit "4.4" "done" "CoverM 丰度完成"
else
    emit "4.4" "pending" "无 CoverM"
fi

# 5.x
if [[ -f "$PR/contig_function/all_proteins.faa" ]]; then
    emit "5.1" "done" "Prodigal 合并预测完成"
else
    emit "5.1" "pending" "无 contig 基因预测"
fi
if [[ -f "$PR/contig_function/contig_merge_check.txt" ]]; then
    emit "5.2" "done" "质量检查完成"
else
    emit "5.2" "pending" "无质量检查"
fi

# 6.x
if [[ -f "$PR/contig_function/all_proteins.nr95.faa" ]]; then
    emit "6.1" "done" "蛋白 CD-HIT 完成"
else
    emit "6.1" "pending" "无蛋白去冗余"
fi
if [[ -f "$PR/contig_function/gene_quant/NR_genes_95.fna" ]]; then
    emit "6.2" "done" "基因 CD-HIT 完成"
else
    emit "6.2" "pending" "无基因去冗余"
fi
if [[ -f "$PR/contig_function/gene_quant/proteins_based_nr_gene_95.faa" ]]; then
    emit "6.3" "done" "NR 蛋白提取完成"
else
    emit "6.3" "pending" "无 NR 蛋白"
fi
if [[ -f "$PR/contig_function/gene_quant/salmon_matrix/gene.TPM.tsv" ]]; then
    emit "6.4" "done" "Salmon 定量完成"
else
    emit "6.4" "pending" "无 Salmon"
fi
if [[ -f "$PR/contig_function/gene_quant/protein_function/eggNOG/eggnog.emapper.annotations" ]]; then
    emit "6.5" "done" "Contig eggNOG 完成"
else
    emit "6.5" "pending" "无 eggNOG"
fi
if [[ -f "$PR/contig_function/gene_quant/protein_function/eggNOG/eggnog.emapper.annotations" ]]; then
    emit "6.6" "done" "可与 6.5 一并检查"
else
    emit "6.6" "pending" "待 6.5 完成后运行"
fi
if [[ -f "$PR/contig_function/gene_quant/function_matrix/gene_with_KO_TPM.tsv" ]]; then
    emit "6.7" "done" "Contig KO 丰度完成"
else
    emit "6.7" "pending" "无 KO 丰度表"
fi
if [[ -f "$PR/contig_function/gene_quant/function_matrix/gene_with_full_annotation_TPM.tsv" ]]; then
    emit "6.8" "done" "基因注释×丰度合并完成"
else
    emit "6.8" "pending" "无全注释丰度表"
fi
if has_glob "$PR/contig_function/gene_quant/function_matrix/EC_*_genes.tsv"; then
    emit "6.9" "done" "EC 基因提取完成"
else
    emit "6.9" "pending" "无 EC 提取结果"
fi

# 7.x
mag_pred_n=$(count_glob "$PR/MAG_function/gene_prediction/*.prefixed.faa")
if [[ "$mag_pred_n" -gt 0 ]]; then
    emit "7.1" "done" "MAG Prodigal: ${mag_pred_n}"
else
    emit "7.1" "pending" "无 MAG 基因预测"
fi
mag_annot_n=0
if [[ -d "$PR/MAG_function/function_annotation" ]]; then
    mag_annot_n=$(find "$PR/MAG_function/function_annotation" -name '*.emapper.annotations' 2>/dev/null | wc -l)
fi
if [[ "$mag_annot_n" -gt 0 ]]; then
    emit "7.2" "done" "MAG eggNOG: ${mag_annot_n}"
else
    emit "7.2" "pending" "无 MAG eggNOG"
fi
if [[ -f "$PR/MAG_function/function_matrix/mag_ko_gene_count_matrix.tsv" ]]; then
    emit "7.3" "done" "MAG×KO 矩阵完成"
else
    emit "7.3" "pending" "无 MAG KO 矩阵"
fi
if [[ -f "$PR/MAG_function/function_matrix/mag_weighted_KO_TPM.tsv" ]]; then
    emit "7.4" "done" "MAG 加权丰度完成"
else
    emit "7.4" "pending" "无 MAG 加权丰度"
fi

echo "# samples: ${sample_n}" >&2
