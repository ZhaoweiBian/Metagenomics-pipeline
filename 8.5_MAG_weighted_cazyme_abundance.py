#!/usr/bin/env python3
"""结合 CoverM dRep MAG TPM 与 MAG × CAZyme 矩阵，计算样本加权 CAZyme 丰度。"""
import argparse
import os
import socket
import sys
from datetime import datetime

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.notify import send_notification


def normalize_mag_name(name):
    for suffix in (".fa", ".fasta", ".fna"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name


def load_mag_matrix(matrix_file):
    matrix = pd.read_csv(matrix_file, sep="\t", index_col=0)
    matrix.index = matrix.index.map(normalize_mag_name)
    matrix.columns = matrix.columns.astype(str)
    return matrix


def load_mag_tpm(tpm_file):
    tpm = pd.read_csv(tpm_file)
    mag_col = tpm.columns[0]
    tpm = tpm.rename(columns={mag_col: "MAG"})
    tpm["MAG"] = tpm["MAG"].map(normalize_mag_name)
    tpm = tpm[~tpm["MAG"].str.lower().eq("unmapped")]
    for col in tpm.columns[1:]:
        tpm[col] = pd.to_numeric(tpm[col], errors="coerce").fillna(0)
    return tpm.set_index("MAG")


def main():
    project_root = os.environ.get("PROJECT_ROOT", "/data1/bianzw/hlbw")
    mag_function = os.environ.get("MAG_FUNCTION_DIR", os.path.join(project_root, "MAG_function"))
    coverm_dir = os.environ.get("COVERM_OUT_DIR", os.path.join(project_root, "coverm"))
    matrix_dir = os.environ.get(
        "MAG_FUNCTION_MATRIX_DIR", os.path.join(mag_function, "function_matrix")
    )
    default_matrix = os.path.join(matrix_dir, "mag_cazyme_gene_count_matrix.tsv")
    default_tpm = os.path.join(coverm_dir, "MAG_tpm.csv")

    parser = argparse.ArgumentParser(description="Calculate dRep MAG-weighted CAZyme abundance")
    parser.add_argument("--mag-cazyme-matrix", default=default_matrix)
    parser.add_argument("--mag-tpm", default=default_tpm)
    parser.add_argument("--out-dir", default=matrix_dir)
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    log_file = os.path.join(args.out_dir, "MAG_weighted_CAZyme_validation.log")

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

    print("========== dRep MAG 加权 CAZyme 丰度 ==========")
    print(f"时间: {datetime.now()}\n")

    mag_cazyme = load_mag_matrix(args.mag_cazyme_matrix)
    mag_tpm = load_mag_tpm(args.mag_tpm)

    common_mags = mag_cazyme.index.intersection(mag_tpm.index)
    print(f"MAG × CAZyme: {mag_cazyme.shape[0]} MAG, {mag_cazyme.shape[1]} family")
    print(f"CoverM TPM: {mag_tpm.shape[0]} MAG, {mag_tpm.shape[1]} 样本")
    print(f"匹配 MAG: {len(common_mags)}")

    mag_cazyme = mag_cazyme.loc[common_mags]
    mag_tpm = mag_tpm.loc[common_mags]

    weighted = mag_tpm.T.dot(mag_cazyme)
    weighted.index.name = "sample"
    weighted.columns.name = "CAZyme_family"

    weighted_path = os.path.join(args.out_dir, "mag_weighted_cazyme_TPM.tsv")
    weighted.to_csv(weighted_path, sep="\t")
    print(f"\n加权 CAZyme family 数: {weighted.shape[1]}")
    print(f"输出: {weighted_path}")

    send_notification(
        "dRep MAG加权CAZyme丰度通知",
        f"脚本: 8.5_MAG_weighted_cazyme_abundance.py\n"
        f"服务器: {socket.gethostname()}\n"
        f"匹配MAG: {len(common_mags)}, family数: {weighted.shape[1]}, 样本数: {weighted.shape[0]}\n"
        f"输出: {args.out_dir}",
    )

    sys.stdout = sys.__stdout__
    log_f.close()


if __name__ == "__main__":
    main()
