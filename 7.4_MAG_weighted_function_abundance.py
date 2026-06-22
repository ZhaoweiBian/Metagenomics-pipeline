#!/usr/bin/env python3
"""结合 CoverM MAG TPM 与 MAG × KO 矩阵，计算样本加权功能丰度。"""
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


def load_mag_ko_matrix(matrix_file):
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
    matrix_dir = os.environ.get("MAG_FUNCTION_MATRIX_DIR", os.path.join(mag_function, "function_matrix"))
    default_matrix = os.path.join(matrix_dir, "mag_ko_gene_count_matrix.tsv")
    default_tpm = os.path.join(coverm_dir, "MAG_tpm.csv")
    default_out = matrix_dir

    parser = argparse.ArgumentParser(description="Calculate MAG-weighted KO abundance")
    parser.add_argument("--mag-ko-matrix", default=default_matrix, help="MAG x KO matrix from 7.3")
    parser.add_argument("--mag-tpm", default=default_tpm, help="CoverM MAG TPM matrix")
    parser.add_argument("--out-dir", default=default_out, help="Output directory")
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    log_file = os.path.join(args.out_dir, "MAG_weighted_KO_validation.log")

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

    print("========== MAG 加权功能丰度 ==========")
    print(f"时间: {datetime.now()}\n")

    mag_ko = load_mag_ko_matrix(args.mag_ko_matrix)
    mag_tpm = load_mag_tpm(args.mag_tpm)

    common_mags = mag_ko.index.intersection(mag_tpm.index)
    missing_in_tpm = sorted(set(mag_ko.index) - set(mag_tpm.index))
    missing_in_ko = sorted(set(mag_tpm.index) - set(mag_ko.index))

    print(f"MAG × KO 矩阵: {mag_ko.shape[0]} MAG, {mag_ko.shape[1]} KO")
    print(f"CoverM TPM: {mag_tpm.shape[0]} MAG, {mag_tpm.shape[1]} 样本")
    print(f"匹配 MAG: {len(common_mags)}")
    if missing_in_tpm:
        print(f"仅在 KO 矩阵中的 MAG: {len(missing_in_tpm)}")
    if missing_in_ko:
        print(f"仅在 TPM 矩阵中的 MAG: {len(missing_in_ko)}")

    mag_ko = mag_ko.loc[common_mags]
    mag_tpm = mag_tpm.loc[common_mags]

    weighted = mag_tpm.T.dot(mag_ko)
    weighted.index.name = "sample"
    weighted.columns.name = "KO"

    weighted_path = os.path.join(args.out_dir, "mag_weighted_KO_TPM.tsv")
    contribution_path = os.path.join(args.out_dir, "mag_ko_sample_contribution_long.tsv")

    weighted.to_csv(weighted_path, sep="\t")
    print(f"\n加权 KO 数: {weighted.shape[1]}")
    print(f"输出: {weighted_path}")

    contributions = []
    for sample in mag_tpm.columns:
        sample_tpm = mag_tpm[sample]
        for mag in common_mags:
            tpm_value = sample_tpm.loc[mag]
            if tpm_value <= 0:
                continue
            mag_counts = mag_ko.loc[mag]
            active_kos = mag_counts[mag_counts > 0]
            for ko, gene_count in active_kos.items():
                contributions.append(
                    {
                        "sample": sample,
                        "MAG": mag,
                        "KO": ko,
                        "gene_count": int(gene_count),
                        "MAG_TPM": float(tpm_value),
                        "weighted_contribution": float(tpm_value * gene_count),
                    }
                )

    contrib_df = pd.DataFrame(contributions)
    contrib_df.to_csv(contribution_path, sep="\t", index=False)
    print(f"贡献明细: {contribution_path}")

    send_notification(
        "MAG加权功能丰度通知",
        f"脚本: 7.4_MAG_weighted_function_abundance.py\n"
        f"服务器: {socket.gethostname()}\n"
        f"匹配MAG: {len(common_mags)}, KO数: {weighted.shape[1]}, 样本数: {weighted.shape[0]}\n"
        f"输出: {args.out_dir}",
    )

    sys.stdout = sys.__stdout__
    log_f.close()


if __name__ == "__main__":
    main()
