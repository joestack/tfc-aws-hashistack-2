#!/bin/bash

tls_is_certbot() {
  apt-get install -y certbot 
  certbot certonly --standalone --agree-tos -m ${tfe_cert_email} -d ${tfe_fqdn} -n
}

prerequisites() {

    mkdir /home/ubuntu/tfe_disk
    chown -R ubuntu:ubuntu /home/ubuntu/tfe_disk

    tee /home/ubuntu/compose.yaml > /dev/null <<EOF
---
name: terraform-enterprise
services:
  tfe:
    image: images.releases.hashicorp.com/hashicorp/terraform-enterprise:${tfe_release}
    environment:
      TFE_LICENSE: "${tfe_lic}"
      TFE_HOSTNAME: "${tfe_fqdn}"
      TFE_ENCRYPTION_PASSWORD: "${tfe_enc_password}"
      TFE_OPERATIONAL_MODE: "disk"
      TFE_DISK_CACHE_VOLUME_NAME: "${node_name}_terraform-enterprise-cache"
      TFE_TLS_CERT_FILE: "/etc/letsencrypt/live/${tfe_fqdn}/fullchain.pem"
      TFE_TLS_KEY_FILE: "/etc/letsencrypt/live/${tfe_fqdn}/privkey.pem"
      TFE_TLS_CA_BUNDLE_FILE: "/etc/letsencrypt/live/${tfe_fqdn}/fullchain.pem"
      TFE_IACT_SUBNETS: "172.16.0.0/16"
    cap_add:
      - IPC_LOCK
    read_only: true
    tmpfs:
      - /tmp:mode=01777
      - /run
      - /var/log/terraform-enterprise
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - type: bind
        source: /var/run/docker.sock
        target: /run/docker.sock
      - type: bind
        source: /etc/letsencrypt/live/${tfe_fqdn}/
        target: /etc/ssl/private/terraform-enterprise
      - type: bind
        source: /home/ubuntu/tfe_disk
        target: /var/lib/terraform-enterprise
      - type: volume
        source: terraform-enterprise-cache
        target: /var/cache/tfe-task-worker/terraform
volumes:
  terraform-enterprise-cache:

EOF
}


## MAIN ##

tls_is_certbot
prerequisites