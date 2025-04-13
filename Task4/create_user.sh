#!/bin/bash
# https://blog.nashtechglobal.com/creating-a-user-in-kubernetes/

set -e

USERNAME="$1"
GROUP="$2"
if [[ -z "$USERNAME" ]]; then
  echo "Usage: $0 <username>"
  exit 1
fi

CSR_NAME="${USERNAME}-csr"
KUBECONFIG_OUT="${USERNAME}-kubeconfig"

CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA_CERT=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

openssl genrsa -out ${USERNAME}.key 2048
openssl req -new -key ${USERNAME}.key -out ${USERNAME}.csr -subj "/CN=${USERNAME}/O=${GROUP}"

CSR_BASE64=$(base64 < ${USERNAME}.csr | tr -d '\n')

cat <<EOF > ${CSR_NAME}.yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${CSR_NAME}
spec:
  groups:
  - system:authenticated
  request: ${CSR_BASE64}
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF

kubectl apply -f ${CSR_NAME}.yaml

kubectl certificate approve ${CSR_NAME}

kubectl get csr ${CSR_NAME} -o jsonpath='{.status.certificate}' | base64 -d > ${USERNAME}.crt

kubectl config set-cluster ${CLUSTER_NAME} \
  --server=${CLUSTER_SERVER} \
  --certificate-authority=<(echo "$CA_CERT") \
  --embed-certs=true \
  --kubeconfig=${KUBECONFIG_OUT}

kubectl config set-credentials ${USERNAME} \
  --client-certificate=${USERNAME}.crt \
  --client-key=${USERNAME}.key \
  --embed-certs=true \
  --kubeconfig=${KUBECONFIG_OUT}

kubectl config set-context ${USERNAME}@${CLUSTER_NAME} \
  --cluster=${CLUSTER_NAME} \
  --user=${USERNAME} \
  --kubeconfig=${KUBECONFIG_OUT}

kubectl config use-context ${USERNAME}@${CLUSTER_NAME} --kubeconfig=${KUBECONFIG_OUT}
