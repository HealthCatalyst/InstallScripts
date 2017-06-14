#!/bin/bash

set -e

if [ $# -ne 4 ]; then
	echo "You must specify CouchDB User as first argument and CouchDB Password as second argument"
else
	export COUCHDB_USER=$1
	export COUCHDB_PASSWORD=$2
	pfxpassword=$3
	pfxpath=$4
	./installcouchdbcluster-swarm.sh
	./installidentity-swarm.sh http://couchproxy:5984 $pfxpassword $pfxpath
	./installauthorization-swarm.sh http://identity:5001
fi

