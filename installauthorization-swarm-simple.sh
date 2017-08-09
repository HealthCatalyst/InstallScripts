#!/bin/bash

set -e

authority=$1
authcert=$2
authkey=$3
couchproxy=$4
appInsightsInstrumentationKey=$5
authorizationversion=$6

echo "creating authnet network"
docker network create --driver overlay authnet
docker network create --driver overlay idnet

echo "creating secrets"
docker secret create auth.cert $authcert
docker secret create auth.key $authkey

docker pull healthcatalyst/fabric.authorization:$authorizationversion
docker pull healthcatalyst/fabric.docker.nginx

echo "creating authorization service"
docker service create --name authorization \
	--env IdentityServerConfidentialClientSettings__Authority=$authority \
	--env CouchDbSettings__Server=$couchproxy \
	--env FABRIC_IDENTITY_URL=$authority \
	--env FABRIC_AUTH_URL=https://authorizationproxy \
	--env ApplicationInsights__Enabled=true \
	--env ApplicationInsights__InstrumentationKey=$appInsightsInstrumentationKey \
	--secret="CouchDbSettings__Username" \
	--secret="CouchDbSettings__Password" \
	--replicas 1 \
	--network authnet \
	--network idnet \
	--network dbnet \
	--detach false \
	healthcatalyst/fabric.authorization:$authorizationversion

echo "creating authorization nginx proxy"
docker service create --name authorizationproxy \
	--env HOST=authorization \
	--env REMOTEPORT=5004 \
	--env CERTIFICATE="auth.cert" \
	--env CERTIFICATE_KEY="auth.key" \
	--secret="auth.cert" \
	--secret="auth.key" \
	-p 80:80 -p 443:443 \
	--network authnet \
	--detach false \
	healthcatalyst/fabric.docker.nginx
