#!/usr/bin/env python3
"""Contig AMR 丰度：合并 Salmon TPM 与 RGI CARD 注释。"""
import argparse
import os
import socket
import sys
from datetime import datetime

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.notify import send_notification


def load_rgi_hits(path):
    hits = pd.read_csv(path, sep="\t", dtype=str)
    hits.columns = hits.columns.str.strip()
    if "ORF_ID" not in hits.columns:
        raise ValueError(f"RGI 结果缺少 ORF_ID 列: {path}")
    hits = hits.rename(columns={"ORF_ID": "gene"})
    aro_col = "Best_Hit_ARO" if "Best_Hit_ARO" in hits.columns else "ARO"
    hits = hits.rename(columns={aro_col: "ARO"})
    hits = hits.dropna(subset=["gene", "ARO"])
    hits = hits[hits["ARO"].astype(str).str.strip() != ""]
    hits["gene"] = hits["gene"].astype(str).str.split(" ", n=1).str[0]
    return hits[["gene", "ARO"]].drop_duplicates(subset=["gene", "ARO"])


def main():
    project_root = os.environ.get("PROJECT_ROOT", "/data1/bianzw/hlbw")
    gene_quant = os.path.join(project_root, "contig_function/gene_quant")
    contig_card = os.environ.get("CONTIG_CARD_DIR", os.path.join(gene_quant, "gene_function/card"))

    parser = argparse.ArgumentParser(description="Calculate contig AMR abundance")
    parser.add_argument(
        "--tpm",
        default=os.path.join(gene_quant, "salmon_matrix/gene.TPM.tsv"),
    )
    parser.add_argument(
        "--rgi",
        default=os.path.join(contig_card, "contig_card.txt"),
    )
    parser.add_argument(
        "--out-dir",
        default=os.path.join(gene_quant, "function_matrix/amr"),
    )
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    log_file = os.path.join(args.out_dir, "AMR_validation.log")

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

    print("========== Contig AMR 丰度计算 ==========")
    print(f"时间: {datetime.now()}\n")

    annot = load_rgi_hits(args.rgi)
    tpm = pd.read_csv(args.tpm, sep="\t")
    tpm.rename(columns={tpm.columns[0]: "gene"}, inplace=True)
    for col in tpm.columns[1:]:
        tpm[col] = pd.to_numeric(tpm[col], errors="coerce")

    merged = pd.merge(tpm, annot, on="gene", how="inner")
    expr_cols = list(tpm.columns[1:])
    print(f"耐药基因命中数: {merged.shape[0]}, 样本数: {len(expr_cols)}")

    aro_abundance = merged.groupby("ARO")[expr_cols].sum()
    aro_abundance.to_csv(os.path.join(args.out_dir, "amr_aro.TPM.tsv"), sep="\t")
    print(f"ARO 数: {aro_abundance.shape[0]}")
    print(f"输出: {args.out_dir}")

    send_notification(
        "Contig AMR丰度通知",
        f"脚本: 9.2_contig_amr_abundance.py\n"
        f"服务器: {socket.gethostname()}\n"
        f"命中基因: {merged.shape[0]}, ARO数: {aro_abundance.shape[0]}\n"
        f"输出: {args.out_dir}",
    )

    sys.stdout = sys.__stdout__
    log_f.close()


if __name__ == "__main__":
    main()
