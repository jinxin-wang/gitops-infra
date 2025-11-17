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

1. 云原生最佳实践
- 这些服务都是 Kubernetes 原生应用
- 部署在 K3s 内可以享受自动调度、故障恢复、滚动更新等特性
-  统一管理，避免维护两套环境

2. 资源利用
- K3s 集群有 24GB 内存（3台×8GB）
- 本地服务器只负责管理，不承载运行负载
- 资源分配更合理

3. 模拟生产环境
- 本地 Multipass 环境是为了验证云上部署
- 部署位置应与云上环境保持一致
- 便于后续迁移到云端

4. 网络连通性
- 这些平台服务需要与应用 Pod 在同一网络
- 部署在集群内可以使用 Service 内网通信
- 避免跨网络配置复杂度

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
