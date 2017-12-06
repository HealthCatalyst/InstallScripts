

kubectl delete -f ./nlp-kubernetes.yml
kubectl delete namespace fabricnlp

kubectl create namespace fabricnlp

kubectl create secret generic mysqlrootpassword --namespace=fabricnlp --from-literal=password=ILoveNLP2017!

kubectl create secret generic mysqlpassword --namespace=fabricnlp --from-literal=password=ILoveNLP2017!

kubectl create secret generic certhostname --namespace=fabricnlp --from-literal=value=imran.com

kubectl create secret generic certpassword --namespace=fabricnlp --from-literal=password=ILoveNLP2017!

kubectl create -f ./nlp-kubernetes.yml

kubectl get deployments,pods,services,ingress,secrets --namespace=fabricnlp

kubectl create -f ./nlp-kubernetes-public.yml
