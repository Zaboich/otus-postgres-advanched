#!/bin/bash
#set -e
for VM_NAME in $(yc compute instance list --format=json | jq -r '.[].name'); do
  yc compute instance delete $VM_NAME
done
#yc compute instance list --format json | jq -r '.[].id' | xargs -I {} echo {} && yc compute instance delete {}

for DNS_NAME in $(yc dns zone list --format=json | jq -r '.[].name' | grep otus | sort -r); do yc dns zone delete $DNS_NAME; done

for SUBNET_NAME in $(yc vpc subnet list --format=json | jq -r '.[].name' | grep otus); do yc vpc subnet delete $SUBNET_NAME; done

for NET_NAME in $(yc vpc network list --format=json | jq -r '.[].name' | grep otus | sort -r); do yc vpc network delete $NET_NAME; done