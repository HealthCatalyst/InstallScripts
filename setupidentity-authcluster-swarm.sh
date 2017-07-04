#!/bin/bash

# Usage:
#     setupidentity-authcluster-swarm.sh [couchdb_user] [couchdb-password] \
#	[pfxpassword] [pfxpath] [identitycert] [identitykey] [authcert] [authkey]

#     couchdb_user      the username for couchdb
#     couchdb_password  the password for couchdb
#     pfxpassword       the path to the file that contains the password for the pfx
#     pfxpath           the path to the pfx file
#     identitycert      the path to the certificate for identity
#     identitykey       the path to the cert key for identity
#     authcert          the path to the cert for authorization
#     authkey           the path to the cert key for authorization

###############################################################################
set -e

if [ $# -ne 8 ]; then
	echo "Incorrect usage."
else
	export COUCHDB_USER=$1
	export COUCHDB_PASSWORD=$2
	pfxpassword=$3
	pfxpath=$4
	identitycert=$5
	identitykey=$6
	authcert=$7
	authkey=$8
	
	./installcouchdbcluster-swarm.sh
	
	docker secret create identity.cert $identitycert
	docker secret create identity.key $identitykey
	
	./installidentity-swarm.sh http://couchproxy:5984 $pfxpassword $pfxpath "identity.cert" "identity.key"
	
	docker secret create auth.cert $authcert
	docker secret create auth.key $authkey
	./installauthorization-swarm.sh https://identityproxy "auth.cert" "auth.key"
fi

