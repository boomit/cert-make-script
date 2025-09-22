#!/bin/bash
OUT_PATH=./out/out-certs11

rm $OUT_PATH -rf

# bash ./gen-certs.sh --config entities.conf --outdir $OUT_PATH
# bash ./gen-certs.sh --config entities.conf --outdir $OUT_PATH --ca-path ./out/out-certs9/
# bash ./gen-certs.sh --config entities.conf --outdir $OUT_PATH --ca-crt ./out/out-certs4/ca2.crt
bash ./gen-certs.sh --config entities.conf --outdir $OUT_PATH --ca-key ./out/out-certs9/ca.key

