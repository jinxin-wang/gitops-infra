#!/bin/bash
# 环境初始化脚本 - 重构版（使用 Ansible）
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印函数
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo ""
    echo "============================================"
    echo "$1"
    echo "============================================"
}

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"

print_section "GitOps Infrastructure Setup"
print_info "Project root: $PROJECT_ROOT"

# Step 1: 检查并安装 multipass
print_section "Step 1: Check Multipass"
if ! command -v multipass &> /dev/null; then
    print_warn "Multipass not found, installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install multipass
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo snap install multipass
    else
        print_error "Unsupported OS for automatic installation"
        exit 1
    fi
else
    print_info "Multipass already installed: $(multipass version)"
fi

# Step 2: 创建虚拟机
print_section "Step 2: Create Multipass VMs"

VMs=("vm1:8G:2:40G" "vm2:4G:2:40G" "vm3:4G:2:40G")

for vm_config in "${VMs[@]}"; do
    IFS=':' read -r vm_name memory cpus disk <<< "$vm_config"
    
    if multipass list | grep -q "^$vm_name"; then
        print_info "VM $vm_name already exists, skipping..."
    else
        print_info "Creating VM: $vm_name (${memory} RAM, ${cpus} CPUs, ${disk} disk)..."
        multipass launch --name "$vm_name" --memory "$memory" --cpus "$cpus" --disk "$disk"
    fi
done

# Step 3: 获取 VM IP 地址
print_section "Step 3: Get VM IP Addresses"
VM1_IP=$(multipass info vm1 | grep IPv4 | awk '{print $2}')
VM2_IP=$(multipass info vm2 | grep IPv4 | awk '{print $2}')
VM3_IP=$(multipass info vm3 | grep IPv4 | awk '{print $2}')

print_info "vm1: $VM1_IP"
print_info "vm2: $VM2_IP"
print_info "vm3: $VM3_IP"

# Step 4: 设置 SSH 密钥
print_section "Step 4: Setup SSH Keys"

if [ ! -d ~/.ssh ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
fi

if [ ! -f ~/.ssh/id_rsa ]; then
    print_info "Generating SSH key pair..."
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""
else
    print_info "SSH key pair already exists"
fi

# 将公钥复制到所有 VM
for vm in vm1 vm2 vm3; do
    print_info "Copying SSH key to $vm..."
    cat ~/.ssh/id_rsa.pub | multipass exec "$vm" -- bash -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
done

# 测试 SSH 连接
print_info "Testing SSH connections..."
for vm in vm1 vm2 vm3; do
    VM_IP=$(multipass info "$vm" | grep IPv4 | awk '{print $2}')
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@"$VM_IP" hostname &>/dev/null; then
        print_info "✓ $vm ($VM_IP) - SSH OK"
    else
        print_error "✗ $vm ($VM_IP) - SSH FAILED"
        exit 1
    fi
done

# Step 5: 检查并安装 Ansible
print_section "Step 5: Check Ansible"
if ! command -v ansible &> /dev/null; then
    print_warn "Ansible not found, installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install ansible
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt update
        sudo apt install -y ansible
    fi
else
    print_info "Ansible already installed: $(ansible --version | head -n1)"
fi

# Step 6: 更新 Ansible inventory
print_section "Step 6: Update Ansible Inventory"
INVENTORY_FILE="$ANSIBLE_DIR/inventory/local/hosts.ini"

cat > "$INVENTORY_FILE" << EOF
[k3s_master]
vm1 ansible_host=$VM1_IP ansible_user=ubuntu node_name=k3s-master

[k3s_workers]
vm2 ansible_host=$VM2_IP ansible_user=ubuntu node_name=k3s-worker-1
vm3 ansible_host=$VM3_IP ansible_user=ubuntu node_name=k3s-worker-2

[k3s_cluster:children]
k3s_master
k3s_workers

[k3s_cluster:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

print_info "Inventory updated: $INVENTORY_FILE"

# Step 7: 安装 Ansible collections
print_section "Step 7: Install Ansible Collections"
if [ -f "$ANSIBLE_DIR/requirements.yml" ]; then
    print_info "Installing Ansible collections..."
    ansible-galaxy collection install -r "$ANSIBLE_DIR/requirements.yml"
fi

# Step 8: 测试 Ansible 连接
print_section "Step 8: Test Ansible Connectivity"
cd "$ANSIBLE_DIR"
if ansible all -m ping; then
    print_info "✓ Ansible connectivity test passed"
else
    print_error "✗ Ansible connectivity test failed"
    exit 1
fi

# Step 9: 运行 Ansible playbooks
print_section "Step 9: Run Ansible Playbooks"

read -p "Do you want to prepare nodes? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Running playbook: 01-prepare-nodes.yml"
    ansible-playbook playbooks/01-prepare-nodes.yml
fi

read -p "Do you want to install K3s cluster? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Running playbook: 02-install-k3s.yml"
    ansible-playbook playbooks/02-install-k3s.yml
fi

read -p "Do you want to deploy platform services? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Running playbook: 03-deploy-platform.yml"
    ansible-playbook playbooks/03-deploy-platform.yml
fi

# Step 10: 完成
print_section "Setup Complete!"
print_info "K3s cluster is ready!"
print_info ""
print_info "Quick commands:"
print_info "  • Access master node: multipass shell vm1"
print_info "  • View cluster: export KUBECONFIG=~/.kube/config-k3s-local && kubectl get nodes"
print_info "  • Run playbooks: cd $ANSIBLE_DIR && ansible-playbook playbooks/<playbook>.yml"
print_info "  • Cleanup cluster: ansible-playbook playbooks/99-cleanup.yml"
print_info ""
print_info "Next steps:"
print_info "  1. Configure kubectl: export KUBECONFIG=~/.kube/config-k3s-local"
print_info "  2. Deploy Harbor: See docs/operations/installation.md"
print_info "  3. Deploy ArgoCD: See docs/operations/installation.md"
