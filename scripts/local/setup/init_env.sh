# !/bin/bash
# 环境准备脚本
set -e

# IP adresses for the servers (if needed, otherwise will use multipass assigned IPs)
# SERVER1_IP=""
# SERVER2_IP=""
# SERVER3_IP=""

# create conda environment
ENV_NAME="devops_k3s_env"
if conda info --envs | grep -q "^$ENV_NAME\s"; then
    echo "Conda environment '$ENV_NAME' already exists."
else
    echo "Creating conda environment '$ENV_NAME'..."
    conda create -y -n $ENV_NAME python=3.12
    conda activate $ENV_NAME
fi

# install multipass if not already installed
if ! command -v multipass &> /dev/null
then
    echo "Multipass could not be found, installing..."
    sudo snap install multipass
fi

# create a multipass VM named vm1 with 4GB memory and 2 CPUs, 40GB disk
multipass launch --name vm1 --memory 8G --cpus 2 --disk 40G
multipass launch --name vm2 --memory 4G --cpus 2 --disk 40G
multipass launch --name vm3 --memory 4G --cpus 2 --disk 40G

# ip addresses of the VMs
K3s_MASTER_IP=$(multipass info vm1 | grep IPv4 | awk '{print $2}')
K3s_AGENT1_IP=$(multipass info vm2 | grep IPv4 | awk '{print $2}')
K3s_AGENT2_IP=$(multipass info vm3 | grep IPv4 | awk '{print $2}')

# ping the VMs to ensure they are up
echo "Pinging VMs to ensure they are up..."
ping -c 3 $K3s_MASTER_IP ;
ping -c 3 $K3s_AGENT1_IP ;
ping -c 3 $K3s_AGENT2_IP ;

# set up passwordless SSH between the host and the VMs
echo "=== SSH Key Setup for Multipass VMs ==="
echo ""

# Step 1: Check if SSH directory exists
if [ ! -d ~/.ssh ]; then
    echo "Creating ~/.ssh directory..."
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
fi

# Step 2: Generate SSH key pair if it doesn't exist
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "Generating RSA SSH key pair..."
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""
    echo "SSH key pair generated successfully"
else
    echo "SSH key pair already exists at ~/.ssh/id_rsa"
fi

echo ""
echo "=== Copying public key to all VMs ==="

# Step 3: Copy public key to all VMs
# for vm in $K3s_MASTER_IP $K3s_AGENT1_IP $K3s_AGENT2_IP ; do
for vm in vm1 vm2 vm3; do
    echo "Configuring $vm..." ;
    cat ~/.ssh/id_rsa.pub | multipass exec $vm -- bash -c "cat >> ~/.ssh/authorized_keys" ;
    # cat ~/.ssh/id_rsa.pub | ssh ubuntu@$vm "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" ;
done

# Step 4: Test SSH connection
for vm in vm1 vm2 vm3; do
    VM_IP=$(multipass info $vm | grep IPv4 | awk '{print $2}')
    echo -n "Testing $vm ($VM_IP): "
    ssh -o StrictHostKeyChecking=no ubuntu@$VM_IP hostname
done

# Install K3s server on vm1
multipass exec vm1 -- bash -c "curl -sfL https://get.k3s.io | sh -"
K3S_TOKEN=$(multipass exec vm1 -- sudo cat /var/lib/rancher/k3s/server/node-token)
K3S_SERVER_IP=$(multipass info vm1 | grep IPv4 | awk '{print $2}')

# check if K3s server is running on vm1
multipass exec vm1 -- sudo systemctl status k3s

# Install K3s agents on vm2 and vm3
multipass exec vm2 -- bash -c "curl -sfL https://get.k3s.io | K3S_URL=https://$K3S_SERVER_IP:6443 K3S_TOKEN=$K3S_TOKEN sh -"
multipass exec vm3 -- bash -c "curl -sfL https://get.k3s.io | K3S_URL=https://$K3S_SERVER_IP:6443 K3S_TOKEN=$K3S_TOKEN sh -"

# check if K3s agents are running on vm2 and vm3
multipass exec vm2 -- sudo systemctl status k3s-agent
multipass exec vm3 -- sudo systemctl status k3s-agent

# install ansible if not already installed
if ! command -v ansible &> /dev/null
then
    echo "Ansible could not be found, installing..."
    conda install -y -c conda-forge ansible
fi

# configure nodes using ansible, echo the configurations to files for inventory and playbook
ANSIBLE_INVENTORY=inventory.ini
echo "[k3s_cluster]" > $ANSIBLE_INVENTORY
echo "vm1 ansible_host=$(multipass info vm1 | grep IPv4 | awk '{print $2}') ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3" >> $ANSIBLE_INVENTORY
echo "vm2 ansible_host=$(multipass info vm2 | grep IPv4 | awk '{print $2}') ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3" >> $ANSIBLE_INVENTORY
echo "vm3 ansible_host=$(multipass info vm3 | grep IPv4 | awk '{print $2}') ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3" >> $ANSIBLE_INVENTORY
echo "" >> $ANSIBLE_INVENTORY
echo "[k3s_cluster:vars]
ansible_python_interpreter=/usr/bin/python3" >> $ANSIBLE_INVENTORY

ANSIBLE_PLAYBOOK=playbook.yml
echo "- hosts: k3s_cluster
  become: yes
  tasks:
    - name: Update and upgrade apt packages
      apt:
        update_cache: yes
        upgrade: dist
    - name: Install necessary packages
      apt:
        name:
          - vim
          - git
        state: present
" > $ANSIBLE_PLAYBOOK

# run ansible playbook with disabled host key checking
echo "Running Ansible playbook..."
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i $ANSIBLE_INVENTORY $ANSIBLE_PLAYBOOK

# cleanup temporary files
rm $ANSIBLE_INVENTORY
rm $ANSIBLE_PLAYBOOK

echo "Environment setup complete. K3s cluster is running on vm1, vm2, and vm3."

# check if K3s cluster is working
multipass exec vm1 -- sudo k3s kubectl get nodes
multipass exec vm1 -- sudo k3s kubectl get pods --all-namespaces

