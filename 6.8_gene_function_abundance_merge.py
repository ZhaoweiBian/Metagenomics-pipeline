#!/usr/bin/env python3
"""合并 Salmon 基因丰度与 eggNOG 全功能注释（基因级，含 EC/KO/GO 等）。"""
import argparse
import os
import socket
import sys
from datetime import datetime
from io import StringIO

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.notify import send_notification

ANNOT_PRIORITY = [
    "seed_ortholog",
    "evalue",
    "score",
    "Preferred_name",
    "Description",
    "EC",
    "KEGG_ko",
    "KEGG_Pathway",
    "KEGG_Module",
    "KEGG_Reaction",
    "KEGG_rclass",
    "COG_category",
    "GOs",
    "eggNOG_OGs",
    "max_annot_lvl",
    "CAZy",
    "PFAMs",
    "BRITE",
    "KEGG_TC",
    "BiGG_Reaction",
]


def load_annotations(annot_file):
    with open(annot_file) as f:
        lines = [line for line in f if not line.startswith("##")]
    annot = pd.read_csv(StringIO("".join(lines)), sep="\t", dtype=str)
    annot.columns = annot.columns.str.strip().str.replace("#", "", regex=False)
    annot = annot.rename(columns={"query": "gene"})
    return annot


def load_matrix(path, value_name):
    df = pd.read_csv(path, sep="\t")
    df = df.rename(columns={df.columns[0]: "gene"})
    sample_cols = [c for c in df.columns if c != "gene"]
    for col in sample_cols:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    if value_name:
        df = df.rename(columns={c: f"{c}_{value_name}" for c in sample_cols})
    return df, sample_cols


def order_columns(merged, tpm_cols, count_renamed):
    skip = {"gene", *tpm_cols, *count_renamed}
    annot_cols = [c for c in merged.columns if c not in skip]
    priority = [c for c in ANNOT_PRIORITY if c in annot_cols]
    rest = [c for c in annot_cols if c not in priority]
    return ["gene"] + priority + rest + tpm_cols + count_renamed


def main():
    project_root = os.environ.get("PROJECT_ROOT", "/data1/bianzw/hlbw")
    gene_quant = os.path.join(project_root, "contig_function/gene_quant")
    default_matrix = os.path.join(gene_quant, "function_matrix")

    parser = argparse.ArgumentParser(
        description="Merge gene TPM/count with full eggNOG functional annotations"
    )
    parser.add_argument("--tpm", default=os.path.join(gene_quant, "salmon_matrix/gene.TPM.tsv"))
    parser.add_argument("--count", default=os.path.join(gene_quant, "salmon_matrix/gene.count.tsv"))
    parser.add_argument(
        "--annot",
        default=os.path.join(gene_quant, "protein_function/eggNOG/eggnog.emapper.annotations"),
    )
    parser.add_argument("--out-dir", default=default_matrix)
    parser.add_argument(
        "--out",
        default="gene_with_full_annotation_TPM.tsv",
        help="Output filename under --out-dir",
    )
    parser.add_argument("--with-count", action="store_true", default=True)
    parser.add_argument("--no-count", dest="with_count", action="store_false")
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    log_path = os.path.join(args.out_dir, "gene_annotation_merge.log")

    with open(log_path, "w") as log_f:

        def log(msg):
            print(msg)
            log_f.write(msg + "\n")

        log("========== 基因注释 × 丰度合并 ==========")
        log(f"时间: {datetime.now()}\n")

        annot = load_annotations(args.annot)
        tpm, tpm_cols = load_matrix(args.tpm, value_name="")

        if args.with_count and os.path.isfile(args.count):
            count_df, count_cols = load_matrix(args.count, value_name="NumReads")
            count_renamed = [f"{c}_NumReads" for c in count_cols]
            expr = tpm.merge(count_df, on="gene", how="left")
        else:
            count_cols = []
            count_renamed = []
            expr = tpm

        merged = expr.merge(annot, on="gene", how="left")
        merged = merged[order_columns(merged, tpm_cols, count_renamed)]

        out_path = os.path.join(args.out_dir, args.out)
        merged.to_csv(out_path, sep="\t", index=False)

        has_ec = merged["EC"].notna() & (merged["EC"] != "-") if "EC" in merged.columns else pd.Series(False)
        has_ko = merged["KEGG_ko"].notna() & (merged["KEGG_ko"] != "-") if "KEGG_ko" in merged.columns else pd.Series(False)

        log(f"基因数: {merged.shape[0]}")
        log(f"样本数: {len(tpm_cols)}")
        log(f"含 EC 注释: {has_ec.sum()} ({has_ec.mean():.2%})")
        log(f"含 KO 注释: {has_ko.sum()} ({has_ko.mean():.2%})")
        log(f"注释列数: {len(merged.columns) - 1 - len(tpm_cols) - len(count_renamed)}")
        log(f"输出: {out_path}")

    send_notification(
        "基因注释丰度合并通知",
        f"脚本: 6.8_gene_function_abundance_merge.py\n"
        f"服务器: {socket.gethostname()}\n"
        f"基因数: {merged.shape[0]}, 样本数: {len(tpm_cols)}\n"
        f"输出: {out_path}",
    )


if __name__ == "__main__":
    main()
