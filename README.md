# gen-certs.sh

## 설명
`gen-certs.sh` 스크립트는 지정된 구성 파일(`entities.conf`)을 기반으로  
CA 및 엔티티 인증서를 생성합니다.  
외부 CA를 사용할 수도 있고, CA가 없으면 자체적으로 생성합니다.

---

## 환경
- Bash (Linux / macOS)
- OpenSSL 설치 필요 (`openssl` 명령어 사용)

---

## 사용법
```bash
bash ./gen-certs.sh [옵션]
```

## 옵션:
- --config <file>       인증서 엔티티 정보가 담긴 INI 형식 구성 파일
- --outdir <dir>        인증서와 키 파일을 생성할 출력 디렉토리
- --ca-crt <file>       기존 CA 인증서 파일 (선택)
- --ca-key <file>       기존 CA 개인키 파일 (선택)
- --ca-path <dir>       기존 CA가 있는 디렉토리 (선택, ca.crt / ca.key 포함)

## 동작 방식:
1. 외부 CA 사용:
    - --ca-crt, --ca-key 또는 --ca-path 중 하나라도 유효하면 외부 CA를 사용
    - 기존 CA를 사용하여 엔티티 인증서를 발급
    - 자체 CA 생성은 생략

2. 자체 CA 생성:
    - 외부 CA 옵션이 없으면 스크립트가 CA 키와 인증서를 생성
    - 생성된 CA로 각 엔티티 인증서를 발급

3. 인증서 발급 과정:
    - 각 엔티티마다 새로운 RSA 개인키를 생성
    - CSR (Certificate Signing Request) 생성
    - CA 서명 후 CRT 파일 생성

## 출력:
- 출력 디렉토리(예: --outdir ./out/certs)에 아래 파일 생성
    - ca.key (자체 CA인 경우)
    - ca.crt (자체 CA인 경우)
    - <entity>.key
    - <entity>.csr
    - <entity>.crt

## 예시:
1. 자체 CA 생성:
bash ./gen-certs.sh --config entities.conf --outdir ./out/out-certs

2. 기존 CA 사용:
bash ./gen-certs.sh --config entities.conf --outdir ./out/out-certs5 --ca-path ./out/out-certs4

## 주의 사항:
--------
- openssl 명령어 실행 시 권한 문제가 없도록 주의하십시오.

## 구성 파일 예시 (entities.conf):
[ca]
C=KR
ST=Seoul
O=MyOrg
CN=MyRootCA

[abc.internal]
C=KR
ST=Seoul
O=InternalTeam
CN=gag.internal

## 라이선스:
본 스크립트는 자유롭게 사용 및 수정 가능합니다.
