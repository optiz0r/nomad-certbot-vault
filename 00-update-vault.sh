#!/bin/sh
#
# Perform certificate updates in Vault.

set -eo pipefail

if ! vault token lookup > /dev/null; then
  echo "Login to Vault first."
  exit 1
fi

# Certificate renewal might take some time,
# so renew the token if possible
vault token renew > /dev/null

for domain in $RENEWED_DOMAINS; do

  # Wildcard certificates lead to domains like *.example.com
  # which should become example.com
  target=$domain
  case $target in \*\.*)
    target=${target#*.}
  esac

  vault kv put \
    "secret/lets-encrypt/certificates/$target" \
    "cert=@$RENEWED_LINEAGE/cert.pem" \
    "chain=@$RENEWED_LINEAGE/chain.pem" \
    "privkey=@$RENEWED_LINEAGE/privkey.pem"

  # In case of a multiple-domain certificate, there is no need to re-run this for next domains
  exit 0
done
