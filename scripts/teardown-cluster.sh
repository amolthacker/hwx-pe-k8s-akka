#!/bin/bash

BASE_DIR="$(dirname $0)"
source $BASE_DIR/env.sh

echo "Configuring gcloud ..."
export GCLOUD_PROJECT=$(gcloud config get-value project)
export CLUSTER_NAME=${GCLOUD_PROJECT}-cluster

echo "Tearing Down ..."
gcloud container clusters delete ${CLUSTER_NAME} --quiet
gcloud container clusters list
