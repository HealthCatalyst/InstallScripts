
#
# This script is meant for quick & easy install via:
#   curl -sSL https://healthcatalyst.github.io/InstallScripts/nlp/runondevmachine.sh | sh

echo "Version 1.01"

docker stack rm fabricnlp

# echo "sleeping for network to clean up"
# sleep 20s;

while docker network inspect -f "{{ .Name }}" fabricnlp_nlpnet &>/dev/null; do echo "."; sleep 1; done

docker secret rm MySQLPassword || echo ""
echo 'yourpassword' | docker secret create MySQLPassword -

docker secret rm MySQLRootPassword || echo ""
echo "new-password" |  docker secret create MySQLRootPassword -

docker secret rm ExternalHostName || echo ""
echo "localhost" | docker secret create ExternalHostName  -

export SHARED_DRIVE=c:/tmp

export SHARED_DRIVE_LOGS=c:/tmp/fluentd
mkdir -p c:/tmp/fluentd

export SHARED_DRIVE_SOLR=c:/tmp/solr
mkdir -p c:/tmp/solr
export SHARED_DRIVE_MYSQL=c:/tmp/mysql_nlp
mkdir -p c:/tmp/mysql_nlp


# use docker stack deploy to start up all the services
stackfilename="nlp-stack.yml"

echo "running stack: $stackfilename"

echo "https://healthcatalyst.github.io/InstallScripts/nlp/${stackfilename}"

# curl -sSL "https://healthcatalyst.github.io/InstallScripts/nlp/${stackfilename}" | docker stack deploy --compose-file - fabricnlp

docker stack deploy -c $stackfilename fabricnlp
