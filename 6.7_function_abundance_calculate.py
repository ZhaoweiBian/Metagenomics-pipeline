#!/usr/bin/env python3
"""KO 功能丰度计算：合并 Salmon TPM 与 eggNOG 注释。"""
import argparse
import os
import random
import socket
import sys
from datetime import datetime
from io import StringIO

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.notify import send_notification


def load_annotations(annot_file):
    with open(annot_file) as f:
        lines = [line for line in f if not line.startswith("##")]
    annot = pd.read_csv(StringIO("".join(lines)), sep="\t", dtype=str)
    annot.columns = annot.columns.str.strip()
    annot.rename(columns=lambda x: x.replace("#", ""), inplace=True)
    annot.rename(columns={"query": "gene"}, inplace=True)
    return annot


def main():
    project_root = os.environ.get("PROJECT_ROOT", "/data1/bianzw/hlbw")
    gene_quant = os.path.join(project_root, "contig_function/gene_quant")

    parser = argparse.ArgumentParser(description="Calculate KO functional abundance")
    parser.add_argument("--tpm", default=os.path.join(gene_quant, "salmon_matrix/gene.TPM.tsv"))
    parser.add_argument("--annot", default=os.path.join(
        gene_quant, "protein_function/eggNOG/eggnog.emapper.annotations"))
    parser.add_argument("--out-dir", default=os.path.join(gene_quant, "function_matrix"))
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    log_file = os.path.join(args.out_dir, "KO_validation.log")

    class Tee:
        def __init__(self, fh):
            self.fh = fh
            self.stdout = sys.stdout
        def write(self, msg):
            self.stdout.write(msg)
            self.fh.write(msg)
        def flush(self):
            self.stdout.flush()
            self.fh.flush()

    log_f = open(log_file, "w")
    sys.stdout = Tee(log_f)

    print("========== KO 功能丰度计算 ==========")
    print(f"时间: {datetime.now()}\n")

    annot = load_annotations(args.annot)
    tpm = pd.read_csv(args.tpm, sep="\t")
    tpm.rename(columns={tpm.columns[0]: "gene"}, inplace=True)
    for col in tpm.columns[1:]:
        tpm[col] = pd.to_numeric(tpm[col], errors="coerce")

    merged = pd.merge(tpm, annot, on="gene", how="left")
    expr_cols = list(tpm.columns[1:])
    print(f"基因数: {merged.shape[0]}, 样本数: {len(expr_cols)}")

    na_genes = merged["KEGG_ko"].isna().sum()
    print(f"未注释: {na_genes} ({na_genes / merged.shape[0]:.4f})")

    ko_df = merged.dropna(subset=["KEGG_ko"]).copy()
    ko_df = ko_df[ko_df["KEGG_ko"] != "-"]
    ko_df = ko_df.assign(KEGG_ko=ko_df["KEGG_ko"].str.split(",")).explode("KEGG_ko")
    ko_df["KEGG_ko"] = ko_df["KEGG_ko"].str.strip()
    ko_df = ko_df[ko_df["KEGG_ko"].str.match(r"ko:K\d+", na=False)]
    ko_df["KEGG_ko"] = ko_df["KEGG_ko"].str.replace("ko:", "", regex=False)

    ko_abundance = ko_df.groupby("KEGG_ko")[expr_cols].sum()
    ko_abundance.to_csv(os.path.join(args.out_dir, "gene_with_KO_TPM.tsv"), sep="\t")
    print(f"KO数量: {ko_abundance.shape[0]}")

    merged_agg = merged.copy()
    merged_agg["KEGG_ko"] = merged_agg["KEGG_ko"].replace("-", pd.NA).fillna("unannotated")
    merged_agg = merged_agg.assign(KEGG_ko=merged_agg["KEGG_ko"].str.split(",")).explode("KEGG_ko")
    merged_agg["KEGG_ko"] = merged_agg["KEGG_ko"].str.strip().replace("", "unannotated")
    merged_abundance = merged_agg.groupby("KEGG_ko")[expr_cols].sum()
    merged_abundance.to_csv(os.path.join(args.out_dir, "gene_with_annotation_all_TPM.tsv"), sep="\t")

    random.seed(args.seed)
    n = min(50, len(ko_abundance))
    match_count = mismatch_count = 0
    for ko in random.sample(list(ko_abundance.index), n):
        manual = ko_df[ko_df["KEGG_ko"] == ko][expr_cols].sum()
        script = ko_abundance.loc[ko]
        if manual.round(6).equals(script.round(6)):
            match_count += 1
        else:
            mismatch_count += 1
            print(f"{ko} 不一致")

    print(f"\n验证: 一致 {match_count}, 不一致 {mismatch_count}")
    print(f"输出: {args.out_dir}")

    send_notification(
        "KO功能丰度计算通知",
        f"脚本: 6.7_function_abundance_calculate.py\n"
        f"服务器: {socket.gethostname()}\n"
        f"基因数: {merged.shape[0]}, KO数: {ko_abundance.shape[0]}\n"
        f"验证: 一致 {match_count}, 不一致 {mismatch_count}\n"
        f"输出: {args.out_dir}",
    )

    sys.stdout = sys.__stdout__
    log_f.close()


if __name__ == "__main__":
    main()
