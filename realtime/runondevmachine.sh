
docker stack rm fabricrealtime

sleep 5s;

docker secret rm CertPassword || echo ""
echo "roboconf2" |  docker secret create CertPassword -

docker secret rm RabbitMqMgmtUiPassword || echo ""
echo 'roboconf2' | docker secret create RabbitMqMgmtUiPassword -

docker secret rm MySQLPassword || echo ""
echo 'roboconf2' | docker secret create MySQLPassword -

export CERT_HOSTNAME=IAmAHost
export CERT_PASSWORD=roboconf2
export MySQLRootPassword=roboconf2
export SHARED_DRIVE=c:/tmp
export SHARED_DRIVE_CERTS=c:/tmp/certs
export SHARED_DRIVE_RABBITMQ=c:/tmp/rabbitmq
export SHARED_DRIVE_MYSQL=c:/tmp/mysql

# docker-compose -f realtime-stack.yml up


docker stack deploy -c realtime-stack.yml fabricrealtime

