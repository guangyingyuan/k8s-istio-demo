#!/bin/bash -eux

minikube_install() {
  # Make root mounted as rshared to fix kube-dns issues.
  sudo mount --make-rshared /

  # Download minikube.
  curl -sLo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && chmod +x minikube && sudo mv minikube /usr/local/bin/

  # Star minikube.
  export CHANGE_MINIKUBE_NONE_USER=true
  sudo --preserve-env minikube start --vm-driver=none --kubernetes-version=${KUBERNETES_VERSION}

  # Fix the kubectl context, as it's often stale.
  minikube update-context

  # Wait for Kubernetes to be up and ready.
  JSONPATH='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'; until kubectl get nodes -o jsonpath="$JSONPATH" 2>&1 | grep -q "Ready=True"; do sleep 1; done
}

kind_install() {
  #sudo apt-get install -y -qq golang > /dev/null
  curl -s https://storage.googleapis.com/golang/getgo/installer_linux --output installer_linux
  chmod +x installer_linux
  ./installer_linux
  export GOPATH=$HOME/.go
  export PATH=$PATH:$GOPATH/bin
  echo $SHELL
  go version
  go get sigs.k8s.io/kind
  kind create cluster
  export KUBECONFIG="$(kind get kubeconfig-path)"
}

kubeadm-dind-cluster_install() {
  wget https://github.com/kubernetes-sigs/kubeadm-dind-cluster/releases/download/v0.1.0/dind-cluster-v1.13.sh
  chmod +x dind-cluster-v1.13.sh

  # start the cluster
  ./dind-cluster-v1.13.sh up

  # add kubectl directory to PATH
  export PATH="$HOME/.kubeadm-dind-cluster:$PATH"
}

export TERM=linux
export DEBIAN_FRONTEND=noninteractive

sudo apt-get update -qq
sudo --preserve-env apt-get install -qq -y curl ebtables jq npm siege socat unzip > /dev/null
which docker || sudo apt-get install -qq -y docker.io > /dev/null


# Install Terraform
export TERRAFORM_LATEST_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r -M '.current_version')
curl --silent --location https://releases.hashicorp.com/terraform/${TERRAFORM_LATEST_VERSION}/terraform_${TERRAFORM_LATEST_VERSION}_linux_amd64.zip --output /tmp/terraform_linux_amd64.zip
sudo unzip -q -o /tmp/terraform_linux_amd64.zip -d /usr/local/bin/

# Install markdownlint and markdown-link-check
sudo -E npm install -g markdownlint-cli markdown-link-check > /dev/null

# Markdown check
echo '"line-length": false' > markdownlint_config.json
markdownlint -c markdownlint_config.json README.md

# Link Checks
echo '{ "ignorePatterns": [ { "pattern": "^(http|https)://localhost" } ] }' > config.json
markdown-link-check --config config.json ./README.md

# Generate ssh key if needed
test -f $HOME/.ssh/id_rsa || ( install -m 0700 -d $HOME/.ssh && ssh-keygen -b 2048 -t rsa -f $HOME/.ssh/id_rsa -q -N "" )

# Terraform checks
cat > terraform.tfvars << EOF
openstack_instance_image_name  = "test"
openstack_password             = "test"
openstack_tenant_name          = "test"
openstack_user_domain_name     = "test"
openstack_user_name            = "test"
openstack_auth_url             = "test"
openstack_instance_flavor_name = "test"
EOF

terraform init     -var-file=terraform.tfvars terrafrom/openstack
terraform validate -var-file=terraform.tfvars terrafrom/openstack

sudo swapoff -a

# Find out latest kubernetes version
export KUBERNETES_VERSION=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)

# Download kubectl, which is a requirement for using minikube.
curl -sLo kubectl https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Start kubernetes
#minikube_install
kind_install
kubectl cluster-info

# k8s commands (use everything starting from Helm installation 'curl https://raw.githubusercontent.com/helm/helm/master/scripts/get | bash')
sed -n '/^```bash/,/^```/p' README.md | sed '/^```*/d' | sed -n '/^curl -s https:\/\/raw.githubusercontent.com\/helm\/helm\/master\/scripts\/get | bash/,$p' | bash -eux

# TravisCI: sed -n '/^```bash/,/^```/p' README.md | sed '/^```*/d' | sed -n '/^curl https:\/\/raw.githubusercontent.com\/helm\/helm\/master\/scripts\/get | bash/,$p' | sed '/^helm repo add rook-stable/,/kubectl get -l app=fluent-bit svc,pods --all-namespaces -o wide/d' | sh -eux
