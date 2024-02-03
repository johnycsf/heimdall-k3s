Install LONGHORN via helm:

helm repo add longhorn https://charts.longhorn.io

helm repo up

helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace

kubectl -n longhorn-system get pod -w

Edit Longhorn service to expose via LoadBalancer:
kubectl edit svc longhorn-frontend -n longhorn-system

Change ClusterIP to LoadBalancer - Now any IP of the cluster will work!
