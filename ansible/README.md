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

### 4. 配置 GitLab Runner Token（重要）

在运行 `04-helm-deploy.yml` 之前，需要配置 GitLab Runner 注册令牌：

```bash
# 编辑配置文件
vim group_vars/all.yml

# 修改以下变量：
# gitlab_url: "https://gitlab.com/"  # 你的 GitLab 实例地址
# gitlab_runner_token: "YOUR_GITLAB_RUNNER_TOKEN_HERE"  # 从 GitLab 获取
```

获取 Token 方式：
- **项目级别**: `Settings > CI/CD > Runners > Registration token`
- **组级别**: `Group > Settings > CI/CD > Runners`
- 详细说明见: [README-GitLab-Runner-Setup.md](README-GitLab-Runner-Setup.md)

### 5. 运行 Playbooks

```bash
# 步骤 1: 准备所有节点（系统更新、安装依赖）
ansible-playbook playbooks/01-prepare-nodes.yml

# 步骤 2: 安装 K3s 集群
ansible-playbook playbooks/02-install-k3s.yml

# 步骤 3: 部署平台基础（Helm、命名空间）
ansible-playbook playbooks/03-deploy-platform.yml

# 步骤 4: 部署平台核心服务（Harbor、ArgoCD、GitLab Runner）
ansible-playbook playbooks/04-helm-deploy.yml
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

### 04-helm-deploy.yml
使用 Helm 部署平台核心服务：
- **Cert-Manager**: 自动化证书管理
- **Harbor**: 容器镜像仓库（带 Trivy 漏洞扫描）
- **ArgoCD**: GitOps 持续部署引擎（支持 manifest/helm 两种安装方式）
- **GitLab Runner**: CI/CD 执行器（Kubernetes Executor 模式）

特性：
- 自动检测已安装的服务，避免重复部署
- 支持 ArgoCD 多种安装方式（manifest 推荐，helm 备选）
- 自动获取和显示 ArgoCD 初始密码
- 配置 NodePort 暴露服务（Harbor: 30002, ArgoCD: 30003）
- 生成快速访问脚本 `/tmp/platform-access.sh`
- 完整的部署验证和状态检查

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

### 场景 1: 全新安装（完整流程）
```bash
cd ansible/

# 步骤 1-3: 基础设施搭建
ansible-playbook playbooks/01-prepare-nodes.yml
ansible-playbook playbooks/02-install-k3s.yml
ansible-playbook playbooks/03-deploy-platform.yml

# 步骤 4: 部署平台核心服务（Harbor + ArgoCD + GitLab Runner）
# 注意: 运行前确保已配置 gitlab_runner_token
ansible-playbook playbooks/04-helm-deploy.yml

# 验证部署
kubectl get pods -n platform
kubectl get pods -n argocd
kubectl get pods -n gitlab-runner

# 访问服务（使用生成的脚本）
/tmp/platform-access.sh
```

### 场景 2: 只部署特定平台服务
```bash
# 只部署 Harbor 和 ArgoCD（跳过 GitLab Runner）
# 在 group_vars/all.yml 中临时注释掉 gitlab_runner_token
ansible-playbook playbooks/04-helm-deploy.yml

# 后续单独部署 GitLab Runner（配置好 token 后）
ansible-playbook playbooks/04-helm-deploy.yml
```

### 场景 3: 只更新配置
```bash
# 只在 master 节点运行
ansible-playbook playbooks/02-install-k3s.yml --limit k3s_master

# 升级平台服务
helm upgrade harbor harbor/harbor -n platform
helm upgrade argocd argo/argo-cd -n argocd
```

### 场景 4: 添加新的 worker 节点
1. 在 inventory 中添加新节点
2. 运行：
```bash
ansible-playbook playbooks/01-prepare-nodes.yml --limit <new_node>
ansible-playbook playbooks/02-install-k3s.yml --limit k3s_workers
```

### 场景 5: 完全清理并重装
```bash
# 完全清理（包括删除 Helm releases）
ansible-playbook playbooks/99-cleanup.yml

# 重新安装
ansible-playbook playbooks/01-prepare-nodes.yml
ansible-playbook playbooks/02-install-k3s.yml
ansible-playbook playbooks/03-deploy-platform.yml
ansible-playbook playbooks/04-helm-deploy.yml
```

### 场景 6: 验证平台服务状态
```bash
# 检查所有平台服务
kubectl get pods -n platform
kubectl get pods -n argocd
kubectl get pods -n gitlab-runner

# 检查 Helm releases
helm list -n platform
helm list -n argocd
helm list -n gitlab-runner

# 查看服务访问信息
/tmp/platform-access.sh

# 验证 GitLab Runner 是否在线
# 访问 GitLab: Settings > CI/CD > Runners（应显示绿色圆点）
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

### 问题 4: Harbor 部署失败或 Pod 崩溃
```bash
# 查看 Harbor Pod 状态
kubectl get pods -n platform -l app=harbor

# 查看具体 Pod 日志
kubectl logs -n platform <harbor-pod-name>

# 检查 PVC 状态（Harbor 需要持久化存储）
kubectl get pvc -n platform

# 重新部署 Harbor
helm uninstall harbor -n platform
ansible-playbook playbooks/04-helm-deploy.yml
```

### 问题 5: ArgoCD Pod 崩溃 (exec format error)
```bash
# 症状: argocd-server 或其他 Pod 显示 CrashLoopBackOff
# 原因: ARM64 架构与 Helm Chart 镜像不兼容

# 解决方案: 切换到 manifest 安装方式
vim group_vars/all.yml
# 修改: argocd_install_method: "manifest"

# 清理并重新部署
kubectl delete namespace argocd
ansible-playbook playbooks/04-helm-deploy.yml
```

### 问题 6: GitLab Runner 显示离线
```bash
# 检查 Runner Pod 状态
kubectl get pods -n gitlab-runner
kubectl logs -n gitlab-runner -l app=gitlab-runner

# 验证 Token 是否正确
kubectl get secret -n gitlab-runner gitlab-runner -o yaml | grep token

# 测试网络连通性
kubectl exec -it -n gitlab-runner deployment/gitlab-runner -- \
  curl -I https://gitlab.com

# 常见问题:
# 1. gitlab_runner_token 配置错误或过期
# 2. 防火墙阻止出站连接
# 3. GitLab URL 配置错误

# 解决方案: 重新配置并部署
vim group_vars/all.yml  # 更新 token
helm uninstall gitlab-runner -n gitlab-runner
ansible-playbook playbooks/04-helm-deploy.yml
```

### 问题 7: 平台服务资源不足
```bash
# 检查节点资源使用情况
kubectl top nodes
kubectl top pods -n platform
kubectl top pods -n argocd

# 检查资源配额
kubectl describe node

# 如果资源不足，考虑:
# 1. 增加 VM 资源配置
# 2. 添加更多 worker 节点
# 3. 调整服务资源限制（编辑 Helm values）
```

## 📚 参考文档

### 核心文档
- [Ansible Documentation](https://docs.ansible.com/)
- [K3s Documentation](https://docs.k3s.io/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)

### 平台服务文档
- [Harbor Documentation](https://goharbor.io/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [GitLab Runner Documentation](https://docs.gitlab.com/runner/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)

### 项目内部文档
- [ArgoCD 应用测试流程](../gitops/argocd/README.md)
- [GitLab Runner 安装指南](README-GitLab-Runner-Setup.md)
- [ArgoCD 安装说明](README-ArgoCD-Installation.md)
- [故障排查指南](troubleshooting/TROUBLESHOOTING.md)
