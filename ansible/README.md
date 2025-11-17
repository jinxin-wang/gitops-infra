# Ansible GitOps Infrastructure

完整的 Ansible 自动化配置，用于管理 K3s 集群和平台服务。

## 📁 目录结构

```
ansible/
├── ansible.cfg              # Ansible 配置文件
├── requirements.yml         # Ansible collections 依赖
├── inventory/               # 主机清单
│   └── local/
│       ├── hosts.ini       # 主机列表
│       └── group_vars/     # 组变量
│           ├── all.yml
│           ├── k3s_master.yml
│           └── k3s_workers.yml
├── playbooks/              # Ansible Playbooks
│   ├── 01-prepare-nodes.yml      # 准备节点
│   ├── 02-install-k3s.yml        # 安装 K3s
│   ├── 03-deploy-platform.yml    # 部署平台服务
│   └── 99-cleanup.yml            # 清理集群
└── roles/                  # Ansible Roles
    ├── common/            # 通用配置
    ├── k3s-master/        # K3s Master
    └── k3s-worker/        # K3s Worker
```

## 🚀 快速开始

### 1. 安装依赖

```bash
# 安装 Ansible collections
ansible-galaxy collection install -r requirements.yml

# 验证 Ansible 安装
ansible --version
```

### 2. 配置 Inventory

编辑 `inventory/local/hosts.ini`，更新 VM IP 地址：

```ini
[k3s_master]
vm1 ansible_host=<YOUR_VM1_IP> ansible_user=ubuntu

[k3s_workers]
vm2 ansible_host=<YOUR_VM2_IP> ansible_user=ubuntu
vm3 ansible_host=<YOUR_VM3_IP> ansible_user=ubuntu
```

### 3. 测试连接

```bash
# 测试 Ansible 连接
ansible all -m ping

# 查看主机信息
ansible all -m setup
```

### 4. 运行 Playbooks

```bash
# 准备所有节点（系统更新、安装依赖）
ansible-playbook playbooks/01-prepare-nodes.yml

# 安装 K3s 集群
ansible-playbook playbooks/02-install-k3s.yml

# 部署平台服务（Helm、命名空间）
ansible-playbook playbooks/03-deploy-platform.yml
```

## 📖 Playbooks 说明

### 01-prepare-nodes.yml
准备所有节点的基础环境：
- 更新系统包
- 安装必要的软件包
- 配置内核参数
- 禁用 swap
- 加载内核模块

### 02-install-k3s.yml
安装 K3s 集群：
- 在 master 节点安装 K3s server
- 在 worker 节点安装 K3s agent
- 配置集群网络
- 获取 kubeconfig
- 验证集群状态

### 03-deploy-platform.yml
部署平台服务：
- 安装 Helm
- 添加 Helm 仓库
- 创建命名空间（platform, dev, staging, production）
- 准备平台服务部署

### 99-cleanup.yml
清理 K3s 集群：
- 卸载 K3s
- 清理相关目录
- 删除本地 kubeconfig

## 🔧 常用命令

```bash
# 查看所有主机
ansible all --list-hosts

# 在所有主机上执行命令
ansible all -a "uptime"

# 查看 K3s 集群状态
ansible k3s_master -a "k3s kubectl get nodes"

# 重启所有节点
ansible all -b -a "reboot"

# 仅运行特定 tasks（使用 tags）
ansible-playbook playbooks/02-install-k3s.yml --tags "install"

# 检查语法
ansible-playbook playbooks/02-install-k3s.yml --syntax-check

# Dry run（不实际执行）
ansible-playbook playbooks/02-install-k3s.yml --check

# 显示详细输出
ansible-playbook playbooks/02-install-k3s.yml -v
# 或更详细
ansible-playbook playbooks/02-install-k3s.yml -vvv
```

## 🎯 使用场景

### 场景 1: 全新安装
```bash
cd ansible/
ansible-playbook playbooks/01-prepare-nodes.yml
ansible-playbook playbooks/02-install-k3s.yml
ansible-playbook playbooks/03-deploy-platform.yml
```

### 场景 2: 只更新配置
```bash
# 只在 master 节点运行
ansible-playbook playbooks/02-install-k3s.yml --limit k3s_master
```

### 场景 3: 添加新的 worker 节点
1. 在 inventory 中添加新节点
2. 运行：
```bash
ansible-playbook playbooks/01-prepare-nodes.yml --limit <new_node>
ansible-playbook playbooks/02-install-k3s.yml --limit k3s_workers
```

### 场景 4: 完全清理并重装
```bash
ansible-playbook playbooks/99-cleanup.yml
ansible-playbook playbooks/01-prepare-nodes.yml
ansible-playbook playbooks/02-install-k3s.yml
```

## ⚙️ 配置变量

主要配置变量位于 `inventory/local/group_vars/`：

### all.yml (全局变量)
- `k3s_version`: K3s 版本
- `timezone`: 时区设置
- `common_packages`: 通用软件包列表

### k3s_master.yml (Master 配置)
- `k3s_server_options`: K3s server 启动参数
- `k3s_server_config`: K3s server 配置

### k3s_workers.yml (Worker 配置)
- `k3s_agent_options`: K3s agent 启动参数

## 🔐 最佳实践

### 1. 使用 Ansible Vault 管理敏感信息
```bash
# 创建加密文件
ansible-vault create inventory/local/group_vars/vault.yml

# 编辑加密文件
ansible-vault edit inventory/local/group_vars/vault.yml

# 运行 playbook 时提供密码
ansible-playbook playbooks/02-install-k3s.yml --ask-vault-pass
```

### 2. 使用 Tags 控制执行
在 playbook 中添加 tags，然后选择性执行：
```bash
ansible-playbook playbooks/02-install-k3s.yml --tags "install,verify"
ansible-playbook playbooks/02-install-k3s.yml --skip-tags "verify"
```

### 3. 并行执行控制
```bash
# 限制并行数量
ansible-playbook playbooks/01-prepare-nodes.yml --forks 2

# 逐个执行（串行）
ansible-playbook playbooks/01-prepare-nodes.yml --forks 1
```

## 🐛 故障排查

### 问题 1: SSH 连接失败
```bash
# 测试 SSH 连接
ansible all -m ping -vvv

# 手动测试 SSH
ssh -i ~/.ssh/id_rsa ubuntu@<VM_IP>
```

### 问题 2: K3s 安装失败
```bash
# 查看 K3s 日志
ansible k3s_master -a "journalctl -u k3s -n 50"

# 手动安装测试
multipass exec vm1 -- bash -c "curl -sfL https://get.k3s.io | sh -"
```

### 问题 3: Playbook 执行卡住
```bash
# 使用 -vvv 查看详细输出
ansible-playbook playbooks/02-install-k3s.yml -vvv

# 设置超时
ansible-playbook playbooks/02-install-k3s.yml -e "timeout=300"
```

## 📚 参考文档

- [Ansible Documentation](https://docs.ansible.com/)
- [K3s Documentation](https://docs.k3s.io/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
