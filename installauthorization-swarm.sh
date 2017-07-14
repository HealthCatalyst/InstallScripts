#!/bin/bash

set -e

authority=$1
authcert=$2
authkey=$3
couchproxy=$4
ldapHost=$5
ldapUser=$6
ldapPassword=$7
groupFetcherPassword=$8

echo "creating authnet network"
docker network create --driver overlay authnet
docker network create --driver overlay idnet

echo "creating secrets"
cat > ldap.pwd << EOF
$ldapPassword
EOF

cat > group-fetcher.pwd << EOF
$groupFetcherPassword
EOF

docker secret create group-fetcher.pwd group-fetcher.pwd
docker secret create ldap.pwd ldap.pwd
docker secret create auth.cert $authcert
docker secret create auth.key $authkey

rm ldap.pwd
rm group-fetcher.pwd

echo "creating authorization service"
docker service create --name authorization \
	--env IdentityServerConfidentialClientSettings__Authority=$authority \
	--env CouchDbSettings__Server=$couchproxy \
	--env LDAP_HOST=$ldapHost \
	--env BINDING_DN=$ldapUser \
	--env FABRIC_IDENTITY_URL=$authority \
	--env FABRIC_AUTH_URL=https://authorizationproxy \
	--secret="CouchDbSettings__Username" \
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
