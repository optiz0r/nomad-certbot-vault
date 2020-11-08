#!/bin/sh
# Initialize the environment for certbot
# Requires vault and jq

set -eo pipefail

if ! vault token lookup > /dev/null; then
  echo "Login to Vault first."
  exit 1
fi

# Get account path
ACCOUNT_PARENT_PATH=/etc/letsencrypt/accounts/acme-v02.api.letsencrypt.org/directory
ACCOUNT_ID=$(vault kv get --format=json secret/lets-encrypt/account/extra_details | jq -r '.data.data.account_id')
ACCOUNT_PATH="$ACCOUNT_PARENT_PATH/$ACCOUNT_ID"

mkdir -p "$ACCOUNT_PATH"

for i in meta private_key regr; do
  vault kv get --format=json "secret/lets-encrypt/account/$i" | \
    jq -c '.data.data' \
    > "$ACCOUNT_PATH/$i.json"
done

TSIG_KEY=$(vault kv get --format=json secret/lets-encrypt/tsig-key)

cat > /etc/letsencrypt/creds.ini <<EOF
dns_rfc2136_server = $(echo ${TSIG_KEY} | jq -r '.data.data.server')
dns_rfc2136_port = 53
dns_rfc2136_name = $(echo ${TSIG_KEY} | jq -r '.data.data.name')
dns_rfc2136_secret = $(echo  ${TSIG_KEY} | jq -r '.data.data.key')
dns_rfc2136_algorithm = HMAC-SHA512

EOF
chmod 600 /etc/letsencrypt/creds.ini

CERTIFICATES_TO_CHECK=$(vault kv list --format=json secret/lets-encrypt/certificates | jq -r '.[]')

mkdir -p /etc/letsencrypt/renewal

for certificate in $CERTIFICATES_TO_CHECK; do
  CERTIFICATE_DATA=$(vault kv get --format=json "secret/lets-encrypt/certificates/${certificate}")
  mkdir -p "/etc/letsencrypt/archive/${certificate}"
  mkdir -p "/etc/letsencrypt/live/${certificate}"
  for field in cert chain privkey; do
    cat > "/etc/letsencrypt/archive/${certificate}/${field}1.pem" <<EOF
$(echo "${CERTIFICATE_DATA}" | jq -r ".data.data.${field}")
EOF
    ln \
      -s "../../archive/${certificate}/${field}1.pem" \
      "/etc/letsencrypt/live/${certificate}/${field}.pem"
  done

  cat \
    "/etc/letsencrypt/archive/${certificate}/cert1.pem" \
    "/etc/letsencrypt/archive/${certificate}/chain1.pem" \
    > "/etc/letsencrypt/archive/${certificate}/fullchain1.pem"
  ln \
    -s "../../archive/${certificate}/fullchain1.pem" \
    "/etc/letsencrypt/live/${certificate}/fullchain.pem"

  cat > "/etc/letsencrypt/renewal/$certificate.conf" <<EOF
version = 0.33.1
archive_dir = /etc/letsencrypt/archive/$certificate
cert = /etc/letsencrypt/live/$certificate/cert.pem
privkey = /etc/letsencrypt/live/$certificate/privkey.pem
chain = /etc/letsencrypt/live/$certificate/chain.pem
fullchain = /etc/letsencrypt/live/$certificate/fullchain.pem
# Options used in the renewal process
[renewalparams]
authenticator = dns-rfc2136
account = $ACCOUNT_ID
dns_rfc2136_credentials = /etc/letsencrypt/creds.ini
server = https://acme-v02.api.letsencrypt.org/directory
EOF
done
