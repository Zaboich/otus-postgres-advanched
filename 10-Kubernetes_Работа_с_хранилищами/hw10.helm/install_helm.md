
Установка kubectl
```
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm -f kubectl
kubectl version --client
```

Установка minikube
```
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm -f minikube-linux-amd64
minikube version
```

Установка Helm
```
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

helm repo add bitnami https://bitnami.com

https://repo.broadcom.com/bitnami-files/

$ helm repo add bitnami https://charts.bitnami.com/bitnami  

$ helm search repo bitnami

helm search repo bitnami | grep postgres

$ helm install my-release bitnami/<chart>

helm install my-postgres bitnami/postgresql --version 14.0.0 --set image.tag=14

helm install my-postgres-ha bitnami/postgresql-ha --set image.tag=14
