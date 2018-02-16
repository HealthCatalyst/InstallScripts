
sudo kubeadm reset
sudo yum remove -y kubelet kubeadm kubectl kubernetes-cni

sudo yum -y remove docker-engine.x86_64 docker-ce docker-engine-selinux.noarch docker-cimprov.x86_64 
sudo rm -rf /var/lib/docker

sudo shutdown -r now
