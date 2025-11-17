# 虚拟机集群的验证部署与测试

Harbor、ArgoCD、Prometheus/Grafana、Cert-Manager 部署在 K3s 集群的虚拟机上.

```
本地服务器
├─ kubectl (管理工具)
├─ helm (部署工具)
├─ terraform (IaC工具)
└─ ansible (配置管理)
    ↓ 通过SSH/API远程管理
    ↓
K3s集群 (3台虚拟机)
├─ Master节点 (VM1)
│   └─ K3s控制平面
├─ Worker节点 (VM2)
│   ├─ Harbor (作为Pod运行)
│   └─ ArgoCD (作为Pod运行)
└─ Worker节点 (VM3)
    ├─ Prometheus/Grafana (作为Pod运行)
    └─ Cert-Manager (作为Pod运行)
```

## 部署工具职责划分

### 1. Ansible 的职责（基础设施层）
- ✅ 创建和配置虚拟机
- ✅ 安装操作系统依赖
- ✅ 部署 K3s 集群
- ✅ 配置节点网络和存储
- ✅ 设置系统级别的安全策略

### 2. Helm 的职责（应用层）
- ✅ 部署 Kubernetes 应用（Harbor、ArgoCD等）
- ✅ 管理应用配置（通过 values.yaml）
- ✅ 应用版本升级和回滚
- ✅ 依赖组件自动管理
- ✅ 应用生命周期管理

### 3. 协作模式
```
Ansible → 搭建集群 → K3s Ready
    ↓
Helm → 部署应用 → Harbor/ArgoCD/Prometheus Running
    ↓
ArgoCD → 管理业务应用 → 微服务部署
```

## 部署流程

### Phase 1: 集群搭建（Ansible）
```bash
cd ansible/
ansible-playbook -i inventory/local/hosts.ini playbooks/k3s-install.yml
```

### Phase 2: 平台服务部署（Helm）
```bash
# 手动方式
helm install harbor harbor/harbor -n harbor -f configs/harbor/values-local.yaml

# 自动化方式（推荐）
ansible-playbook -i inventory/local/hosts.ini playbooks/platform-setup.yml
```

### Phase 3: 业务应用部署（ArgoCD）
```bash
# ArgoCD 自动监控 GitOps 仓库，无需手动操作
argocd app create myapp --repo https://github.com/org/gitops-infra --path gitops/apps/base
```
