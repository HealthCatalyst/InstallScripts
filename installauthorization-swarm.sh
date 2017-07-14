#!/bin/bash

set -e

authority=$1
authcert=$2
authkey=$3
couchproxy=$4

echo "creating authnet network"
docker network create --driver overlay authnet

echo "creating authorization service"
docker service create --name authorization \
	--env IdentityServerConfidentialClientSettings__Authority=$authority \
	--env CouchDbSettings__Server=$couchproxy \
	--secret-"CouchDbSettings__Username" \
	--secret="CouchDbSettings__Password" \
	--replicas 1 \
	--network authnet \
	--network idnet \
	--network dbnet \
	healthcatalyst/fabric.authorization

echo "creating authorization nginx proxy"
docker service create --name authorizationproxy \
	--env HOST=authorization \
	--env REMOTEPORT=5004 \
	--env CERTIFICATE=$authcert \
	--env CERTIFICATE_KEY=$authkey \
	--secret $authcert \
	--secret $authkey \
	-p 80:80 -p 443:443 \
	--network authnet \
	healthcatalyst/fabric.docker.nginx
