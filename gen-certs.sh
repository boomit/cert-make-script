#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="entities.conf"
OUTPUT_DIR="certs"
EXISTING_CA_CRT=""
EXISTING_CA_KEY=""
EXISTING_CA_PATH=""

# -------------------------
# 옵션 파싱
# -------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --outdir) OUTPUT_DIR="$2"; shift 2 ;;
        --ca-crt) EXISTING_CA_CRT="$2"; shift 2 ;;
        --ca-key) EXISTING_CA_KEY="$2"; shift 2 ;;
        --ca-path) EXISTING_CA_PATH="$2"; shift 2 ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 --config <file> --outdir <dir> [--ca-crt <file>] [--ca-key <file>] [--ca-path <dir>]"
            exit 1
            ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

# -------------------------
# CA 존재 확인
# -------------------------
check_ca_files() {
    local crt=$1
    local key=$2
    if [[ ! -f "$crt" || ! -f "$key" ]]; then
        echo "[ERROR] CA files not found or invalid: $crt / $key"
        exit 1
    fi
}

# -------------------------
# INI 파서
# -------------------------
parse_ini() {
    local section=""
    while IFS='= ' read -r key value; do
        if [[ $key =~ ^\[(.*)\]$ ]]; then
            section="${BASH_REMATCH[1]//./_}"
        elif [[ -n $key && $key != \#* ]]; then
            eval "${section}_${key}='${value}'"
        fi
    done < "$CONFIG_FILE"
}

# -------------------------
# CA 경로 결정
# -------------------------
if [[ -n "$EXISTING_CA_PATH" ]]; then
    EXISTING_CA_CRT="${EXISTING_CA_PATH}/ca.crt"
    EXISTING_CA_KEY="${EXISTING_CA_PATH}/ca.key"
elif [[ -n "$EXISTING_CA_CRT" ]]; then
    EXISTING_CA_KEY="${EXISTING_CA_KEY:-${EXISTING_CA_CRT%.crt}.key}"
elif [[ -n "$EXISTING_CA_KEY" ]]; then
    EXISTING_CA_CRT="${EXISTING_CA_CRT:-${EXISTING_CA_KEY%.key}.crt}"
fi

if [[ -n "$EXISTING_CA_CRT" && -n "$EXISTING_CA_KEY" ]]; then
    check_ca_files "$EXISTING_CA_CRT" "$EXISTING_CA_KEY"
    echo "[INFO] Using existing CA: $EXISTING_CA_CRT / $EXISTING_CA_KEY"
    CA_CRT="$EXISTING_CA_CRT"
    CA_KEY="$EXISTING_CA_KEY"
    USE_EXTERNAL_CA=true
else
    CA_CRT="$OUTPUT_DIR/ca.crt"
    CA_KEY="$OUTPUT_DIR/ca.key"
    USE_EXTERNAL_CA=false
fi

# -------------------------
# 인증서 생성 (SAN 지원)
# -------------------------
gen_cert() {
    local name=$1
    local C=${2:-}
    local ST=${3:-}
    local O=${4:-}
    local CN=${5:-}
    local SAN=${6:-}

    [[ -z "$CN" ]] && { echo "[ERROR] CN required for $name"; exit 1; }

    if [[ "$name" == "ca" && "$USE_EXTERNAL_CA" == true ]]; then
        echo "[INFO] External CA provided, skipping CA generation."
        return
    fi

    echo "🔑 Generating cert for [$name] CN=$CN, O=$O, SAN=$SAN"
    openssl genrsa -out "$OUTPUT_DIR/${name}.key" 2048

    subj=""
    [[ -n "$C" ]] && subj+="/C=$C"
    [[ -n "$ST" ]] && subj+="/ST=$ST"
    [[ -n "$O" ]] && subj+="/O=$O"
    subj+="/CN=$CN"

    openssl req -new -key "$OUTPUT_DIR/${name}.key" -subj "$subj" \
        -out "$OUTPUT_DIR/${name}.csr"

    # SAN 포함을 위한 임시 config 생성
    TMP_CNF=$(mktemp)
    cp /etc/ssl/openssl.cnf "$TMP_CNF"
    if [[ -n "$SAN" ]]; then
        echo "[SAN]" >> "$TMP_CNF"
        echo "subjectAltName=$SAN" >> "$TMP_CNF"
        EXT_OPT="-extfile $TMP_CNF -extensions SAN"
    else
        EXT_OPT=""
    fi

    if [[ "$name" == "ca" ]]; then
        openssl x509 -req -days 3650 -in "$OUTPUT_DIR/ca.csr" \
            -signkey "$OUTPUT_DIR/ca.key" -out "$OUTPUT_DIR/ca.crt" $EXT_OPT
    else
        check_ca_files "$CA_CRT" "$CA_KEY"
        openssl x509 -req -days 365 -in "$OUTPUT_DIR/${name}.csr" \
            -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
            -out "$OUTPUT_DIR/${name}.crt" $EXT_OPT
    fi

    rm -f "$TMP_CNF"
}

# -------------------------
# 실행
# -------------------------
parse_ini

# CA 인증서 생성
gen_cert "ca" "$ca_C" "$ca_ST" "$ca_O" "$ca_CN" "DNS:ca"

# 엔티티별 인증서 생성
for entity in $(grep '^\[' "$CONFIG_FILE" | grep -v "\[ca\]" | tr -d '[]'); do
    safe_entity="${entity//./_}"
    eval C=\${${safe_entity}_C:-}
    eval ST=\${${safe_entity}_ST:-}
    eval O=\${${safe_entity}_O:-}
    eval CN=\${${safe_entity}_CN:-}
    SAN="DNS:${CN}"  # CN을 SAN으로 추가
    gen_cert "$entity" "$C" "$ST" "$O" "$CN" "$SAN"
done

echo "✅ All certs generated in $OUTPUT_DIR/"

