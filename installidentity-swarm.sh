#!/bin/bash

set -e

couchproxy=$1
pfxpassword=$2
pfxpath=$3
identitycert=$4
identitykey=$5
appInsightsInstrumentationKey=$6

docker secret create pfxpassword $pfxpassword
docker secret create identity.pfx $pfxpath

echo "creating idnet network"
docker network create --driver overlay idnet



echo "creating identity service"
docker service create --name identity \
	--env HostingOptions__UseInMemoryStores=false \
	--env HostingOptions__UseTestUsers=false \
	--env CouchDbSettings__Server=$couchproxy \
	--env SigningCertificateSettings__UseTemporarySigningCredential=false \
	--env SigningCertificateSettings__PrimaryCertificatePath=//run/secrets/identity.pfx \
	--env SigningCertificateSettings__PrimaryCertificatePasswordPath=//run/secrets/pfxpassword \
	--env ApplicationInsights__Enabled=true \
	--env ApplicationInsights__InstrumentationKey=$appInsightsInstrumentationKey \
	-p 5001:5001 \
	--secret="pfxpassword" \
	--secret="identity.pfx" \
	--secret="CouchDbSettings__Username" \
	--secret="CouchDbSettings__Password" \
	--replicas 1 \
	--network idnet \
	--network dbnet \
	healthcatalyst/fabric.identity

echo "creating identity nginx proxy"
docker service create --name identityproxy \
	--env HOST=identity \
	--env REMOTEPORT=5001 \
	--env CERTIFICATE=$identitycert \
	--env CERTIFICATE_KEY=$identitykey \
	--secret $identitycert \
	--secret $identitykey \
	-p 80:80 -p 443:443 \
	--network idnet \
	healthcatalyst/fabric.docker.nginx
