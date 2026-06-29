#!/bin/bash
# =============================================================================
# 宏基因组 Pipeline 主控脚本
#
# 用法:
#   ./run_pipeline.sh --list                     # 列出所有步骤
#   ./run_pipeline.sh --step 0.2                 # 运行单步
#   ./run_pipeline.sh --from 3.1 --to 3.6        # 运行步骤区间
#   ./run_pipeline.sh --phase dehost             # 运行某阶段
#   ./run_pipeline.sh --all                      # 运行完整流程
#
# 环境变量:
#   export PROJECT_ROOT=/path/to/project
#   ./run_pipeline.sh --project-root /path/to/project --all
#   或复制 project.env.example 为 project.env 并修改其中的 PROJECT_ROOT
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 预解析 --project-root（须在 source config.sh 之前）
_REMAINING=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root)
            export PROJECT_ROOT="${2:?--project-root 需要路径参数}"
            shift 2
            ;;
        *)
            _REMAINING+=("$1")
            shift
            ;;
    esac
done
set -- "${_REMAINING[@]}"

# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# 步骤注册表: ID|描述|脚本路径
declare -a PIPELINE_STEPS=(
    "0.1|下载原始数据|0.1_download_raw_data.sh"
    "0.2|Fastp 质控|0.2_quality_control.sh"
    "1.1|宿主去除|1.1_dehost.sh"
    "2.1|Kraken2+Bracken 物种注释|2.1_kraken_bracken.sh"
    "2.2|合并 Bracken 丰度表|2.2_merge_new_reads.py"
    "3.1|metaSPAdes 组装|3.1_contig_assembly.sh"
    "3.2|Contig 预处理(重命名+前缀)|3.2_preprocess_contigs.sh"
    "3.3|Bowtie2 建索引|3.3_contig_index.sh"
    "3.4|Reads 比对到 Contig|3.4_reads_mapping_contig.sh"
    "3.5|SAM 转 sorted BAM|3.5_sam_to_bam.sh"
    "3.6|Contig Depth 计算|3.6_contig_depth.sh"
    "3.7|MetaBAT2 Binning|3.7_binning.sh"
    "3.8|CheckM2 质量评估|3.8_bin_quality_assess.sh"
    "3.9|提取高质量 MAG|3.9_extract_high_quality_bins.sh"
    "4.1|dRep 去冗余|4.1_drep.sh"
    "4.2|GTDB-Tk dRep MAG 注释|4.2_GTDB_HQ_annotation.sh"
    "4.3|CoverM dRep MAG 丰度|4.3_coverm_MAG_abundance.sh"
    "5.1|Contig 基因预测(Prodigal)|5.1_contig_gene_predict.sh"
    "5.2|Contig 合并质量检查|5.2_contig_merge_quality_check.sh"
    "6.1|蛋白 CD-HIT 去冗余|6.1_contig_cdhit_protein.sh"
    "6.2|基因 CD-HIT-EST 去冗余|6.2_contig_cdhit_gene.sh"
    "6.3|提取 NR 蛋白序列|6.3_contig_extract_nr_protein_95.sh"
    "6.4|Salmon 基因丰度定量|6.4_contig_gene_quant.sh"
    "6.5|Contig 蛋白 eggNOG 注释|6.5_contig_protein_eggnog_annotation.sh"
    "6.6|Contig 注释质量检查|6.6_anntation_check.py"
    "6.7|Contig KO 功能丰度计算|6.7_function_abundance_calculate.py"
    "6.8|基因注释与丰度合并|6.8_gene_function_abundance_merge.py"
    "6.9|按 EC 提取目标基因|6.9_extract_EC_genes.py"
    "7.1|MAG 基因预测|7.1_MAG_gene_predict.sh"
    "7.2|MAG eggNOG 注释|7.2_MAG_function_annotate.sh"
    "7.3|MAG × KO 丰度矩阵|7.3_MAG_KO_abundance_matrix.py"
    "7.4|MAG 加权功能丰度|7.4_MAG_weighted_function_abundance.py"
    "8.1|Contig 蛋白 dbCAN CAZyme 注释|8.1_contig_protein_dbcan_annotation.sh"
    "8.2|Contig CAZyme 丰度计算|8.2_contig_cazyme_abundance.py"
    "8.3|dRep MAG dbCAN CAZyme 注释|8.3_MAG_dbcan_annotation.sh"
    "8.4|dRep MAG × CAZyme 丰度矩阵|8.4_MAG_cazyme_abundance_matrix.py"
    "8.5|dRep MAG 加权 CAZyme 丰度|8.5_MAG_weighted_cazyme_abundance.py"
    "9.1|Contig 基因 CARD(RGI) 耐药注释|9.1_contig_gene_card_annotation.sh"
    "9.2|Contig AMR 丰度计算|9.2_contig_amr_abundance.py"
    "9.3|dRep MAG CARD(RGI) 耐药注释|9.3_MAG_card_annotation.sh"
    "9.4|dRep MAG × AMR 丰度矩阵|9.4_MAG_amr_abundance_matrix.py"
    "9.5|dRep MAG 加权 AMR 丰度|9.5_MAG_weighted_amr_abundance.py"
)

# 阶段分组
declare -A PHASE_STEPS=(
    [download]="0.1"
    [qc]="0.2"
    [dehost]="1.1"
    [taxonomy]="2.1 2.2"
    [assembly]="3.1 3.2 3.3 3.4 3.5 3.6"
    [binning]="3.7 3.8 3.9"
    [mag]="4.1 4.2 4.3"
    [contig_function]="5.1 5.2 6.1 6.2 6.3 6.4 6.5 6.6 6.7 6.8 6.9"
    [mag_function]="7.1 7.2 7.3 7.4"
    [function]="5.1 5.2 6.1 6.2 6.3 6.4 6.5 6.6 6.7 6.8 6.9 7.1 7.2 7.3 7.4 8.1 8.2 8.3 8.4 8.5 9.1 9.2 9.3 9.4 9.5"
    [cazyme]="8.1 8.2 8.3 8.4 8.5"
    [card]="9.1 9.2 9.3 9.4 9.5"
)

get_step_script() {
    local target="$1"
    for entry in "${PIPELINE_STEPS[@]}"; do
        IFS='|' read -r id desc script <<< "$entry"
        if [[ "$id" == "$target" ]]; then
            echo "${SCRIPT_DIR}/${script}"
            return 0
        fi
    done
    return 1
}

list_steps() {
    echo "=========================================="
    echo "宏基因组 Pipeline 步骤列表"
    echo "项目根目录: ${PROJECT_ROOT}"
    echo "样本列表:   ${SAMPLE_LIST}"
    echo "=========================================="
    printf "%-6s %s\n" "ID" "描述"
    printf "%-6s %s\n" "----" "----"
    for entry in "${PIPELINE_STEPS[@]}"; do
        IFS='|' read -r id desc script <<< "$entry"
        printf "%-6s %s\n" "$id" "$desc"
    done
    echo ""
    echo "阶段 (--phase): download | qc | dehost | taxonomy | assembly | binning | mag | contig_function | mag_function | function | cazyme | card"
}

run_single_step() {
    local step_id="$1"
    local script
    script=$(get_step_script "$step_id") || { log_error "未知步骤: $step_id"; return 1; }

    log_info "======== 执行步骤 ${step_id}: $(basename "$script") ========"

    case "$step_id" in
        2.2)
            activate_conda_env "${CONDA_ENV_MAIN}"
            mkdir -p "${PROJECT_ROOT}/bracken_merged"
            for level_dir in Species Genus Family Order Class Phylum; do
                local suffix
                case "$level_dir" in
                    Species) suffix="S" ;;
                    Genus)   suffix="G" ;;
                    Family)  suffix="F" ;;
                    Order)   suffix="O" ;;
                    Class)   suffix="C" ;;
                    Phylum)  suffix="P" ;;
                esac
                python3 "$script" \
                    -i "${BRACKEN_DIR}/${level_dir}" \
                    -o "${PROJECT_ROOT}/bracken_merged/${level_dir}_abundance.tsv" \
                    -l "$suffix"
            done
            send_notification "Bracken合并通知" \
"脚本: 2.2_merge_new_reads.py
服务器: $(hostname)
状态: 成功
输出: ${PROJECT_ROOT}/bracken_merged"
            ;;
        6.6|6.7|6.8|6.9|7.3|7.4|8.2|8.4|8.5|9.2|9.4|9.5)
            activate_conda_env "${CONDA_ENV_MAIN}"
            python3 "$script"
            ;;
        *)
            bash "$script"
            ;;
    esac
}

run_steps() {
    local -a steps=("$@")
    local failed=0
    local total=${#steps[@]}
    local current=0

    for step_id in "${steps[@]}"; do
        current=$((current + 1))
        log_info "进度: [${current}/${total}] 步骤 ${step_id}"
        if ! run_single_step "$step_id"; then
            log_error "步骤 ${step_id} 失败，Pipeline 中止"
            failed=1
            break
        fi
    done
    return $failed
}

get_all_steps() {
    local -a steps=()
    for entry in "${PIPELINE_STEPS[@]}"; do
        IFS='|' read -r id desc script <<< "$entry"
        steps+=("$id")
    done
    echo "${steps[@]}"
}

get_steps_in_range() {
    local from="$1" to="$2"
    local -a result=()
    local in_range=false
    for entry in "${PIPELINE_STEPS[@]}"; do
        IFS='|' read -r id desc script <<< "$entry"
        [[ "$id" == "$from" ]] && in_range=true
        if $in_range; then
            result+=("$id")
        fi
        [[ "$id" == "$to" ]] && break
    done
    echo "${result[@]}"
}

usage() {
    cat <<EOF
宏基因组 Pipeline 主控脚本

用法:
  $0 --list                          列出所有步骤
  $0 --project-root <DIR>            指定项目根目录（也可用环境变量 PROJECT_ROOT）
  $0 --step <ID>                     运行单个步骤 (如 3.1)
  $0 --from <ID> --to <ID>           运行步骤区间 (如 --from 3.1 --to 3.6)
  $0 --phase <name>                  运行某阶段
  $0 --all                           运行完整流程

阶段名称: download, qc, dehost, taxonomy, assembly, binning, mag, contig_function, mag_function, function, cazyme, card

--all 运行全部步骤（0.1–9.5）。

项目根目录（任选其一）:
  export PROJECT_ROOT=/path/to/project
  $0 --project-root /path/to/project --all
  编辑 script/project.env（见 project.env.example）
EOF
}

# --- 参数解析 ---
STEP=""
FROM=""
TO=""
PHASE=""
RUN_ALL=false
LIST=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)       LIST=true; shift ;;
        --step)       STEP="$2"; shift 2 ;;
        --from)       FROM="$2"; shift 2 ;;
        --to)         TO="$2"; shift 2 ;;
        --phase)      PHASE="$2"; shift 2 ;;
        --all)        RUN_ALL=true; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            log_error "未知参数: $1"; usage; exit 1 ;;
    esac
done

if $LIST; then
    list_steps
    exit 0
fi

log_info "Pipeline 启动 | 项目: ${PROJECT_ROOT}"

pipeline_start=$(date +%s)
pipeline_status=0
pipeline_mode=""
declare -a pipeline_steps=()

if [[ -n "$STEP" ]]; then
    pipeline_mode="单步 ${STEP}"
    pipeline_steps=("$STEP")
    run_single_step "$STEP" || pipeline_status=$?
elif [[ -n "$FROM" && -n "$TO" ]]; then
    pipeline_mode="区间 ${FROM}-${TO}"
    # shellcheck disable=SC2206
    pipeline_steps=($(get_steps_in_range "$FROM" "$TO"))
    run_steps "${pipeline_steps[@]}" || pipeline_status=$?
elif [[ -n "$PHASE" ]]; then
    if [[ -z "${PHASE_STEPS[$PHASE]:-}" ]]; then
        log_error "未知阶段: $PHASE"
        exit 1
    fi
    pipeline_mode="阶段 ${PHASE}"
    # shellcheck disable=SC2206
    pipeline_steps=(${PHASE_STEPS[$PHASE]})
    run_steps "${pipeline_steps[@]}" || pipeline_status=$?
elif $RUN_ALL; then
    pipeline_mode="完整流程"
    # shellcheck disable=SC2206
    pipeline_steps=($(get_all_steps))
    run_steps "${pipeline_steps[@]}" || pipeline_status=$?
else
    usage
    exit 1
fi

pipeline_runtime=$(format_runtime $(( $(date +%s) - pipeline_start )))
if [[ $pipeline_status -eq 0 ]]; then
    log_info "Pipeline 全部任务完成"
    pipeline_result="成功"
else
    log_error "Pipeline 执行失败"
    pipeline_result="失败"
fi

send_notification "Pipeline总控通知" \
"脚本: run_pipeline.sh
服务器: $(hostname)
模式: ${pipeline_mode}
状态: ${pipeline_result}
步骤数: ${#pipeline_steps[@]}
耗时: ${pipeline_runtime}
项目: ${PROJECT_ROOT}"

exit $pipeline_status
