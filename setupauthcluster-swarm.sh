#!/bin/bash

if [ $# -ne 3 ]; then
	echo "You must specify CouchDB User as the first parameter, CouchDB Password as the second parameter, and the Identity URL as the third parameter"
else
	couchdb_user=$1
	couchdb_password=$2
	authority=$3

	export COUCHDB_USER=$couchdb_user
	export COUCHDB_PASSWORD=$couchdb_password

	./installcouchdbcluster-swarm.sh
	docker network create --driver overlay idnet
	./installauthorization-swarm.sh $authority
fi
