
sudo kubeadm reset
sudo yum remove -y kubelet-1.9.2-0 kubeadm-1.9.2-0 kubectl-1.9.2-0 kubernetes-cni-0.6.0-0

sudo yum -y remove docker-engine.x86_64 docker-ce docker-engine-selinux.noarch docker-cimprov.x86_64 
sudo rm -rf /var/lib/docker

