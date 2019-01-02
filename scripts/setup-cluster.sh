#!/bin/bash

unset GREP_OPTIONS

BASE_DIR="$(dirname $0)"
source $BASE_DIR/env.sh

echo
echo "Configuring gcloud ..."
export GCLOUD_PROJECT=$(gcloud config get-value project)
export CLUSTER_NAME=${GCLOUD_PROJECT}-cluster
export CLUSTER_ADMIN=$(gcloud info --format="value(config.account)")
gcloud config set compute/zone ${GCLOUD_ZONE}
echo

echo "Enabling GCP Compute, Container and CloudBuild APIs ..."
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable cloudbuild.googleapis.com
echo

echo "Creating GKE cluster ..."
gcloud container clusters create ${CLUSTER_NAME} \
    --preemptible \
    --zone ${GCLOUD_ZONE} \
    --scopes cloud-platform \
    --enable-autoscaling --min-nodes 2 --max-nodes 6 \
    --num-nodes 2
echo

echo "GKE Cluster Info"
gcloud container clusters list
echo

echo "Configuring kubectl and bindings for RBAC ..."
gcloud container clusters get-credentials ${CLUSTER_NAME} --zone ${GCLOUD_ZONE}
kubectl create clusterrolebinding ambassador --clusterrole=cluster-admin --user=${CLUSTER_ADMIN} --serviceaccount=default:ambassador
sleep 30
echo

echo "Setting up helm ..."
sh $BASE_DIR/setup-helm.sh
sleep 60
echo

echo "Deploying application hwxpe ..."
helm install --name hwxpe $BASE_DIR/../helm/hwxpe
echo

echo "Enabling autoscaling ..."
kubectl autoscale deployment ve --cpu-percent=50 --min=2 --max=6
echo

echo "Deploying Prometheus Infra ..."
helm install stable/prometheus-operator --name prometheus-operator --namespace monitoring
sleep 30
echo

echo "Deploying Envoy Proxy w/ Ambassador ..."
kubectl apply -f $BASE_DIR/../k8s/ambassador/ambassador.yaml
kubectl apply -f $BASE_DIR/../k8s/ambassador/ambassador-svc.yaml
sleep 30
kubectl apply -f $BASE_DIR/../k8s/ambassador/ambassador-monitor.yaml
kubectl apply -f $BASE_DIR/../k8s/prometheus/prometheus.yaml

echo
echo "K8s Cluster Info | Monitoring"
kubectl get pods,deployment,statefulset,svc,serviceaccount -n monitoring
echo
echo "K8s Cluster Info | App"
kubectl get pods,deployment,statefulset,svc -n default

echo
echo "Waiting for cluster to bootstrap ..."
sleep 120
echo
echo "K8s Cluster Info | Monitoring"
kubectl get pods,deployment,statefulset,svc,serviceaccount -n monitoring
echo
echo "K8s Cluster Info | App"
kubectl get pods,deployment,statefulset,svc -n default

echo
echo "Adding Envoy route for Service ve-ctrl using Ambassador ..."
kubectl apply -f $BASE_DIR/../k8s/ambassador/ambassador-ve-svc.yaml
sleep 60

echo
echo "Forwarding ports for Prometheus, AlertManager and Grafana"
kubectl port-forward -n monitoring prometheus-prometheus-operator-prometheus-0 9090 &
kubectl port-forward -n monitoring alertmanager-prometheus-operator-alertmanager-0 9093 &
kubectl port-forward -n monitoring $(kubectl get  pods --selector=app=grafana -n  monitoring --output=jsonpath="{.items..metadata.name}") 3000 &
kubectl port-forward $(kubectl get pods -o go-template --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep ambassador) 8877 &

echo "Wait for service IP"
external_ip=""
while [ -z $external_ip ]; do
  echo "Waiting for end point..."
  external_ip=$(kubectl get svc ambassador --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}")
  [ -z "$external_ip" ] && sleep 10
done

echo "====================================================="
echo "=                                                   ="
echo "= hwxpe is available at ${external_ip}              ="
echo "=                                                   ="
echo "====================================================="