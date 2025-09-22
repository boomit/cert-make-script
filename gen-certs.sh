#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-entities.conf}"
OUTPUT_DIR="${2:-certs}"
mkdir -p "$OUTPUT_DIR"

parse_ini() {
    local section=""
    while IFS='= ' read -r key value; do
        if [[ $key =~ ^\[(.*)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            section="${section//./_}"  # 점(.) -> 언더바(_)
        elif [[ -n $key && $key != \#* ]]; then
            eval "${section}_${key}='${value}'"
        fi
    done < "$CONFIG_FILE"
}

gen_cert() {
    local name=$1
    local C=${2:-}
    local ST=${3:-}
    local O=${4:-}
    local CN=${5:-}

    if [[ -z "$CN" ]]; then
        echo "[ERROR] CN is required for $name"
        return 1
    fi

    echo "🔑 Generating cert for [$name] CN=${CN}, O=${O}"

    openssl genrsa -out "$OUTPUT_DIR/${name}.key" 2048

    # subj 구성: C, ST, O는 선택, CN은 필수
    subj=""
    [[ -n "$C" ]] && subj+="/C=$C"
    [[ -n "$ST" ]] && subj+="/ST=$ST"
    [[ -n "$O" ]] && subj+="/O=$O"
    subj+="/CN=$CN"

    openssl req -new -key "$OUTPUT_DIR/${name}.key" -subj "$subj" \
        -out "$OUTPUT_DIR/${name}.csr"

    if [[ "$name" == "ca" ]]; then
        openssl x509 -req -days 3650 -in "$OUTPUT_DIR/${name}.csr" \
            -signkey "$OUTPUT_DIR/${name}.key" -out "$OUTPUT_DIR/${name}.crt"
    else
        openssl x509 -req -days 365 -in "$OUTPUT_DIR/${name}.csr" \
            -CA "$OUTPUT_DIR/ca.crt" -CAkey "$OUTPUT_DIR/ca.key" -CAcreateserial \
            -out "$OUTPUT_DIR/${name}.crt"
    fi
}

# 메인 실행
parse_ini

# CA 먼저 생성
gen_cert "ca" "$ca_C" "$ca_ST" "$ca_O" "$ca_CN"

# 나머지 엔티티 처리
for entity in $(grep '^\[' "$CONFIG_FILE" | grep -v "\[ca\]" | tr -d '[]'); do
    safe_entity="${entity//./_}"

    eval C=\${${safe_entity}_C:-}
    eval ST=\${${safe_entity}_ST:-}
    eval O=\${${safe_entity}_O:-}
    eval CN=\${${safe_entity}_CN:-}

    gen_cert "$entity" "$C" "$ST" "$O" "$CN"
done

echo "✅ All certs generated in $OUTPUT_DIR/"

