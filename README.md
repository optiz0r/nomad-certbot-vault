# nomad-certbot-vault

This repo contains a dockerfile for building a docker image, and an job spec to run it under nomad to create and renew letsencrypt certificates, using vault for backend storage

## Motivations

* Nomad jobs can inject the certificates using the Nomad-Vault integration without the applications needing to be aware of letsencrypt
* Use of DNS RFC2136 means the applications themselves don't have to be publicly accessible
* Centralising the registration and renewal of certificates means dns keys for dynamic updates need only be configured in one place

## Origin

This is cribbed heavily from [[https://developer.epages.com/blog/tech-stories/managing-lets-encrypt-certificates-in-vault/]] and tweaked to use rfc2136 instead of dnsimple and to run under nomad.

# Setup

Start off by cloning this repository

## CA Certificate

Add the CA certificate used by your vault server to the root of your git clone as `ca.crt`.

## Vault

### Policy

```hcl
# certbot-nomad.policy
path "secret/metadata/lets-encrypt/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/lets-encrypt/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
```

Configure the policy in vault with:

```bash
vault policy write certbot-nomad certbot-nomad.policy
```

### Dynamic DNS Update key

Generate a tsig key to authenticate the dynamic update with

```bash
tsig-keygen -a hmac-sha512 certbot-nomad
```

This will print output like the following: 

```
key "certbot-nomad" {
        algorithm hmac-sha512;
        secret "V54YyKknsuHiSDFiIC2E4uzWHjxxusN2jJRcbYF6MYVkjGpejW8D0ECP09VI7hiwYQbhwZ0aA9nmXlekzuKRLA==";
};
```

Keep a copy of this output which you'll need for configuring the nameserver. Also, take the secret and write to vault, along with the key name (`certbot-nomad` as used in the `tsig-keygen` command), and server name that dynamic updates should be sent to

```bash
vault kv put secret/lets-encrypt/tsig-key \
  name=certbot-nomad \
  key=V54YyKknsuHiSDFiIC2E4uzWHjxxusN2jJRcbYF6MYVkjGpejW8D0ECP09VI7hiwYQbhwZ0aA9nmXlekzuKRLA== \
  server nameserver.example.com
```

## DNS Server

Allow updates using the tsig key you generated. For bind, this is done by adding the full output from `tsig-keygen` above into your config. Then allow dynamic updates on the specific zone with:

```
allow-update { key certbot; };
```

## Docker Image

Build a docker image and push it your registry with:

```bash
docker build -t myregistry.example.com:5000/certbot-nomad:latest .
docker push myregistry.example.com:5000/certbot-nomad
```

This image is customised with your CA certificate. There's nothing in it that's sensitive,
so this can be publihed publicly, but since it contains your CA cert it's only usable
with your vault cluster.

A future improvement would be to pass in the CA certificate at runtime.

## Initialise certbot

Run an instance of the container with

```bash
docker run --rm -it --name certbot-vault \
  -e "VAULT_ADDR=http://dev-vault:8200" \
  -e "VAULT_TOKEN=${VAULT_TOKEN}" \
  --network certbot-vault-net \
  certbot-vault sh
```

Create a Let's Encrypt account:

```bash
certbot register --non-interactive --agree-tos -m webmaster@example.com
```

Register the state in Vault:

```bash
export ACCOUNT_PARENT_PATH=/etc/letsencrypt/accounts/acme-v02.api.letsencrypt.org/directory
export ACCOUNT_ID=$(ls $ACCOUNT_PARENT_PATH)
vault kv put secret/lets-encrypt/account/extra_details "account_id=$ACCOUNT_ID"
for i in meta private_key regr; do
  vault kv put "secret/lets-encrypt/account/$i" "@$ACCOUNT_PARENT_PATH/$ACCOUNT_ID/$i.json"
done
```

## Nomad Job

Customise the nomad job with:
* Your nomad datacenter name
* Your registry URL for your docker image
* Your Vault URL

Submit the job to nomad with:

```bash
nomad job run certbot-nomad.hcl
```

# Requesting a certificate

Run a copy of the container with:

```bash
docker run --rm -it --name certbot-vault \
  -e "VAULT_ADDR=http://dev-vault:8200" \
  -e "VAULT_TOKEN=${VAULT_TOKEN}" \
  --network certbot-vault-net \
  certbot-vault sh
```

And request a certificate:

```bash
/usr/local/bin/intialize.sh
certbot certonly --dns-rfc2136 --dns-rfc2136-credentials /etc/letsencrypt/creds.ini \
  --deploy-hook /etc/letsencrypt/renewal-hooks/deploy/00-update-vault.sh \
  -d host.example.com -d alias.example.com
```
