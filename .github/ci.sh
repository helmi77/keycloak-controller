#!/bin/bash
#
# ci for keycloak-controller
#

set -o errexit

KEYCLOAK_CHART_VERSION="${1}"
KEYCLOAK_CONTROLLER_CHART_VERSION="${2}"
K8S_VERSION="${3}"
NAMESPACE="keycloak"

echo -e "\n##### show versions #####\n"
echo "helm version:                       ${HELM_VERSION}"
echo "kubernetes version:                 ${K8S_VERSION}"
echo "keycloak chart version:             ${KEYCLOAK_CHART_VERSION}"
echo "keycloak-controller chart version:  ${KEYCLOAK_CONTROLLER_CHART_VERSION}"
echo ""

echo -e "\n##### install mvn & java #####\n"
sudo apt-get update > /dev/null
sudo apt-get install -y maven openjdk-11-jdk > /dev/null

echo -e "\n##### build keycloak-controller #####\n"
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
mvn package --quiet

echo -e "\n##### create docker image with tag ci-snapshot #####\n"
docker build -t kiwigrid/keycloak-controller:ci-snapshot ./target
echo "${DOCKER_PASSWORD}" | docker login -u "${DOCKER_USERNAME}" --password-stdin
docker push kiwigrid/keycloak-controller:ci-snapshot

echo -e "\n##### install kubectl #####\n"
curl --silent --show-error --fail --location --output kubectl "https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

echo -e "\n##### install helm #####\n"
curl --silent --show-error --fail --location --output get_helm.sh https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get
chmod 700 get_helm.sh
./get_helm.sh --version "${HELM_VERSION}"

echo -e "\n##### add helm repos #####\n"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add codecentric https://codecentric.github.io/helm-charts
helm repo add kiwigrid https://kiwigrid.github.io

echo -e "\n##### update helm repos #####\n"
helm repo update

echo -e "\n##### create keycloak namespace #####\n"
kubectl create namespace "${NAMESPACE}"

echo -e "\n##### install keycloak #####\n"
helm upgrade -i keycloak codecentric/keycloak --wait --namespace "${NAMESPACE}" --version "${KEYCLOAK_CHART_VERSION}"

echo -e "\n##### install keycloak-controller #####\n"
helm upgrade -i keycloak-controller kiwigrid/keycloak-controller --wait --namespace "${NAMESPACE}" --version "${KEYCLOAK_CONTROLLER_CHART_VERSION}" --set image.tag=ci-snapshot

echo -e "\n##### install keycloak-controller crds #####\n"
while IFS= read -r CRD; do
    kubectl apply -f "${CRD}"
done < <(find src/main/k8s/ -type f)

echo -e "\n##### test controller crds #####\n"
kubectl get -A keycloakclients.k8s.kiwigrid.com
kubectl get -A keycloakclientscopes.k8s.kiwigrid.com
kubectl get -A keycloakrealms.k8s.kiwigrid.com
kubectl get -A keycloaks.k8s.kiwigrid.com
