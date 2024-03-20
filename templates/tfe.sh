#!/bin/bash

tls_is_certbot() {
  apt-get install -y certbot 
  certbot certonly --test-cert --standalone --agree-tos -m ${tfe_cert_email} -d ${tfe_fqdn} -n
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
      TFE_TLS_CERT_FILE: "/etc/ssl/private/terraform-enterprise/fullchain1.pem"
      TFE_TLS_KEY_FILE: "/etc/ssl/private/terraform-enterprise/privkey1.pem"
      TFE_TLS_CA_BUNDLE_FILE: "/etc/ssl/private/terraform-enterprise/fullchain1.pem"
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
        source: /etc/letsencrypt/archive/${tfe_fqdn}/
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

install() {
    cd /home/ubuntu
    REGISTRY_URL="images.releases.hashicorp.com/hashicorp/terraform-enterprise"
    TFE_RELEASE=${tfe_release}
    IMAGE="$REGISTRY_URL:$TFE_RELEASE"
    USERNAME="terraform"
    PASSWORD=${tfe_lic}

    docker login -u $USERNAME images.releases.hashicorp.com -p $PASSWORD
    docker pull $IMAGE
    docker compose up --detach

    sleep 120


    x=1
    while [ $x -le 10 ] 
    do
        echo $x >> /home/ubuntu/x_count
        docker compose exec tfe tfe-health-check-status 2>&1 > /home/ubuntu/health_check

    if [[ $(cat /home/ubuntu/health_check | grep "All checks passed.") ]]
        then
        CONTAINER_ID=$(docker ps | grep terraform-enterprise | awk '{print $1}')
        echo $CONTAINER_ID > /home/ubuntu/CONTAINER_ID

        ADMIN_TOKEN=$(docker exec $CONTAINER_ID tfectl admin token)
        echo $ADMIN_TOKEN > /home/ubuntu/ADMIN_TOKEN

        tee /home/ubuntu/payload.json > /dev/null <<EOF
{
  "username": "admin",
  "email": "${tfe_cert_email}",
  "password": "${tfe_auth_password}"
}
EOF

        echo https://${tfe_fqdn}/admin/initial-admin-user?token=$ADMIN_TOKEN >> /home/ubuntu/curl_check

        curl --insecure \
        --header "Content-Type: application/json" \
        --request POST \
        --data @payload.json \
        https://${tfe_fqdn}/admin/initial-admin-user?token=$ADMIN_TOKEN


    # else 
    #     sleep 30
    #     x=$(( $x +1 ))
    fi
        x=$(( $x +1 ))
        sleep 30
    done

}

## MAIN ##

tls_is_certbot
prerequisites
install