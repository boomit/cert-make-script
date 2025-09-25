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
CA_DIR="$OUTPUT_DIR/ca"
mkdir -p "$CA_DIR"

# 외부 CA 파일 처리
if [[ -n "$EXISTING_CA_PATH" ]]; then
    EXISTING_CA_CRT=$(find "$EXISTING_CA_PATH" -name "*.crt" | head -n1)
    EXISTING_CA_KEY=$(find "$EXISTING_CA_PATH" -name "*.key" | head -n1)
elif [[ -n "$EXISTING_CA_CRT" ]]; then
    EXISTING_CA_KEY="${EXISTING_CA_KEY:-${EXISTING_CA_CRT%.crt}.key}"
elif [[ -n "$EXISTING_CA_KEY" ]]; then
    EXISTING_CA_CRT="${EXISTING_CA_CRT:-${EXISTING_CA_KEY%.key}.crt}"
fi

if [[ -n "$EXISTING_CA_CRT" && -n "$EXISTING_CA_KEY" ]]; then
    check_ca_files "$EXISTING_CA_CRT" "$EXISTING_CA_KEY"
    echo "[INFO] Using external CA: $EXISTING_CA_CRT / $EXISTING_CA_KEY"
    CA_CRT="$EXISTING_CA_CRT"
    CA_KEY="$EXISTING_CA_KEY"
    USE_EXTERNAL_CA=true
    EXTERNAL_CA_FILENAME=$(basename "$EXISTING_CA_CRT")
else
    CA_CRT="$CA_DIR/ca.crt"
    CA_KEY="$CA_DIR/ca.key"
    USE_EXTERNAL_CA=false
fi

# -------------------------
# OpenSSL 기본 config
# -------------------------
OPENSSL_CNF=$(openssl version -d | awk -F'"' '{print $2}')/openssl.cnf
[[ ! -f "$OPENSSL_CNF" ]] && OPENSSL_CNF="/etc/ssl/openssl.cnf"


# -------------------------
# 인증서 생성 (SAN 지원)
# -------------------------
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

    # 엔티티별 폴더 생성
    local entity_dir
    if [[ "$name" == "ca" ]]; then
        entity_dir="$CA_DIR"
    else
        entity_dir="$OUTPUT_DIR/entities/$name"
    fi
    mkdir -p "$entity_dir"

    if [[ "$name" == "ca" && "$USE_EXTERNAL_CA" == true ]]; then
        echo "[INFO] External CA provided, skipping CA generation."
        return
    fi

    echo "🔑 Generating cert for [$name] CN=$CN, O=$O, SAN=$SAN"
    openssl genrsa -out "$entity_dir/${name}.key" 2048

    subj=""
    [[ -n "$C" ]] && subj+="/C=$C"
    [[ -n "$ST" ]] && subj+="/ST=$ST"
    [[ -n "$O" ]] && subj+="/O=$O"
    subj+="/CN=$CN"

    openssl req -new -key "$entity_dir/${name}.key" -subj "$subj" \
        -out "$entity_dir/${name}.csr"

    TMP_CNF=$(mktemp)
    cp "$OPENSSL_CNF" "$TMP_CNF"
    if [[ -n "$SAN" ]]; then
        echo "[SAN]" >> "$TMP_CNF"
        echo "subjectAltName=$SAN" >> "$TMP_CNF"
        EXT_OPT="-extfile $TMP_CNF -extensions SAN"
    else
        EXT_OPT=""
    fi

    if [[ "$name" == "ca" ]]; then
        openssl x509 -req -days 3650 -in "$entity_dir/ca.csr" \
            -signkey "$entity_dir/ca.key" -out "$entity_dir/ca.crt" $EXT_OPT
    else
        echo "[INFO] Using existing CA: $CA_CRT / $CA_KEY"
        check_ca_files "$CA_CRT" "$CA_KEY"
        openssl x509 -req -days 365 -in "$entity_dir/${name}.csr" \
            -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
            -out "$entity_dir/${name}.crt" $EXT_OPT

        # -------------------------
        # fullchain.crt 생성
        # -------------------------
        cat "$entity_dir/${name}.crt" "$CA_CRT" > "$entity_dir/${name}.fullchain.crt"
        echo "[INFO] Generated fullchain: $entity_dir/${name}.fullchain.crt"
    fi

    rm -f "$TMP_CNF"
}

# -------------------------
# 실행
# -------------------------
parse_ini

# CA 인증서 생성
gen_cert "ca" "$ca_C" "$ca_ST" "$ca_O" "$ca_CN" "DNS:ca"

# -------------------------
# 엔티티별 인증서 생성
# -------------------------
grep '^\[' "$CONFIG_FILE" | grep -v "\[ca\]" | tr -d '[]' | while read -r entity; do
    safe_entity="${entity//./_}"
    eval C=\${${safe_entity}_C:-}
    eval ST=\${${safe_entity}_ST:-}
    eval O=\${${safe_entity}_O:-}
    eval CN=\${${safe_entity}_CN:-}
    SAN="DNS:${CN}"
    gen_cert "$entity" "$C" "$ST" "$O" "$CN" "$SAN"
done

# -------------------------
# 외부 CA 파일 복사 (.crt, .srl)
# -------------------------
if [[ -n "$EXISTING_CA_CRT" ]]; then
    CA_CRT_COPY="$CA_DIR/$EXTERNAL_CA_FILENAME"
    cp -f "$EXISTING_CA_CRT" "$CA_CRT_COPY"
    echo "[INFO] External CA cert copied to $CA_CRT_COPY"

    EXISTING_CA_SRL="${EXISTING_CA_CRT%.crt}.srl"
    if [[ -f "$EXISTING_CA_SRL" ]]; then
        CA_SRL_COPY="$CA_DIR/$(basename "$EXISTING_CA_SRL")"
        cp -f "$EXISTING_CA_SRL" "$CA_SRL_COPY"
        echo "[INFO] External CA serial file copied to $CA_SRL_COPY"
    fi
fi

echo "✅ All certs generated under $OUTPUT_DIR/<entity>/"
