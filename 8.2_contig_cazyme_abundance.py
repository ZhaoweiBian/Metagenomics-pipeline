#!/usr/bin/env python3
"""Contig CAZyme 丰度：合并 Salmon TPM 与 dbCAN overview。"""
import argparse
import os
import re
import socket
import sys
from datetime import datetime

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.notify import send_notification

FAMILY_RE = re.compile(r"^([A-Za-z0-9_-]+)")


def parse_cazyme_family(row):
    for col in ("Recommend Results", "dbCAN_hmm", "DIAMOND", "dbCAN_sub"):
        val = str(row.get(col, "-")).strip()
        if not val or val == "-":
            continue
        m = FAMILY_RE.match(val.split("(")[0].strip())
        if m:
            return m.group(1)
    return None


def load_dbcan_overview(path):
    overview = pd.read_csv(path, sep="\t", dtype=str)
    overview.columns = overview.columns.str.strip()
    if "Gene ID" not in overview.columns:
        raise ValueError(f"overview 缺少 Gene ID 列: {path}")
    overview = overview.rename(columns={"Gene ID": "gene"})
    overview["CAZyme_family"] = overview.apply(parse_cazyme_family, axis=1)
    return overview[["gene", "CAZyme_family"]].dropna(subset=["CAZyme_family"])


def main():
    project_root = os.environ.get("PROJECT_ROOT", "/data1/bianzw/hlbw")
    gene_quant = os.path.join(project_root, "contig_function/gene_quant")
    contig_dbcan = os.environ.get(
        "CONTIG_DBCAN_DIR", os.path.join(gene_quant, "protein_function/dbCAN")
    )

    parser = argparse.ArgumentParser(description="Calculate contig CAZyme abundance")
    parser.add_argument(
        "--tpm",
        default=os.path.join(gene_quant, "salmon_matrix/gene.TPM.tsv"),
    )
    parser.add_argument(
        "--overview",
        default=os.path.join(contig_dbcan, "overview.tsv"),
    )
    parser.add_argument(
        "--out-dir",
        default=os.path.join(gene_quant, "function_matrix/cazyme"),
    )
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    log_file = os.path.join(args.out_dir, "CAZyme_validation.log")

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

    print("========== Contig CAZyme 丰度计算 ==========")
    print(f"时间: {datetime.now()}\n")

    annot = load_dbcan_overview(args.overview)
    tpm = pd.read_csv(args.tpm, sep="\t")
    tpm.rename(columns={tpm.columns[0]: "gene"}, inplace=True)
    for col in tpm.columns[1:]:
        tpm[col] = pd.to_numeric(tpm[col], errors="coerce")

    merged = pd.merge(tpm, annot, on="gene", how="left")
    expr_cols = list(tpm.columns[1:])
    print(f"基因数: {merged.shape[0]}, 样本数: {len(expr_cols)}")

    na_genes = merged["CAZyme_family"].isna().sum()
    print(f"未注释 CAZyme: {na_genes} ({na_genes / merged.shape[0]:.4f})")

    fam_df = merged.dropna(subset=["CAZyme_family"]).copy()
    family_abundance = fam_df.groupby("CAZyme_family")[expr_cols].sum()
    family_abundance.to_csv(os.path.join(args.out_dir, "cazyme_family.TPM.tsv"), sep="\t")
    print(f"CAZyme family 数: {family_abundance.shape[0]}")
    print(f"输出: {args.out_dir}")

    send_notification(
        "Contig CAZyme丰度通知",
        f"脚本: 8.2_contig_cazyme_abundance.py\n"
        f"服务器: {socket.gethostname()}\n"
        f"基因数: {merged.shape[0]}, CAZyme family数: {family_abundance.shape[0]}\n"
        f"输出: {args.out_dir}",
    )

    sys.stdout = sys.__stdout__
    log_f.close()


if __name__ == "__main__":
    main()
