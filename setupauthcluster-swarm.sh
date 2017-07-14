#!/bin/bash

# Usage
#    setupauthcluster-swarm.sh [couchdb_user] [coucdb_password] [authority] \
#        [authcert] [authkey]
#
#    couchdb_user      the username for couchdb
#    couchdb_password  the password for couchdb
#    authority         the base url for the identity service
#    authcert          the path to the cert for authorization
#    authkey           the path to the cert key for authorization

###############################################################################

if [ $# -ne 5 ]; then
	echo "Incorrect usage."
else
	couchdb_user=$1
	couchdb_password=$2
	authority=$3
	authcert=$4
	authkey=$5

	export COUCHDB_USER=$couchdb_user
	export COUCHDB_PASSWORD=$couchdb_password

	curl -sSL https://healthcatalyst.github.io/InstallScripts/installcouchdbcluster-swarm.sh | sh
	docker network create --driver overlay idnet
	docker secret create auth.cert $authcert
	docker secret create auth.key $authkey
	curl -sSL https://healthcatalyst.github.io/InstallScripts/installauthorization-swarm.sh | sh /dev/stdin $authority "auth.cert" "auth.key" http://couchproxy:5984
