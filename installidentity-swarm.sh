#!/bin/bash

set -e

couchproxy=$1
pfxpassword=$2
pfxpath=$3

docker secret create pfxpassword $pfxpassword
docker secret create identity.pfx $pfxpath

echo "creating idnet network"
docker network create --driver overlay idnet



echo "creating identity service"
docker service create --name identity \
	--env HostingOptions__UseInMemoryStores=false \
	--env CouchDbSettings__Server=$couchproxy \
	--env CouchDbSettings__Username=$COUCHDB_USER \
	--env CouchDbSettings__Password=$COUCHDB_PASSWORD \
	--env SigningCertificateSettings__UseTemporarySigningCredential=false \
	--env SigningCertificateSettings__PrimaryCertificatePath=//run/secrets/identity.pfx \
	--env SigningCertificateSettings__PrimaryCertificatePasswordPath=//run/secrets/pfxpassword \
	-p 5001:5001 \
	--secret="pfxpassword" \
	--secret="identity.pfx" \
	--replicas 1 \
	--network idnet \
	--network dbnet \
	healthcatalyst/fabric.identity

echo "creating identity nginx proxy"
docker service create --name identityproxy \
	--env HOST=identity \
	--env REMOTEPORT=5001 \
	-p 80:80 -p 443:443 \
	--network idnet \
	healthcatalyst/fabric.docker.nginx
