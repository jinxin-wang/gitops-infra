# 快速开始 - ArgoCD 安装配置

## 🚀 三步完成部署

### 步骤 1: 选择安装方式

编辑配置文件：
```bash
vim ~/Workspace/gitops-infra/ansible/group_vars/all.yml
```

修改这一行：
```yaml
argocd_install_method: "manifest"  # 推荐
# 或
argocd_install_method: "helm"      # 备选
```

### 步骤 2: 运行 Playbook

```bash
cd ~/Workspace/gitops-infra/ansible
~/.conda/bin/ansible-playbook playbooks/04-helm-deploy.yml
```

### 步骤 3: 获取访问信息

```bash
# 在 vm1 上运行
multipass exec vm1 -- /tmp/platform-access.sh

# 或手动获取密码
multipass exec vm1 -- bash -c '
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  kubectl get secret argocd-initial-admin-secret \
    -n argocd -o jsonpath="{.data.password}" | base64 -d
'
```

---

## 🎯 一键命令（不修改配置文件）

```bash
# 使用 manifest 方式（推荐）
cd ~/Workspace/gitops-infra/ansible && \
~/.conda/bin/ansible-playbook playbooks/04-helm-deploy.yml \
  -e "argocd_install_method=manifest"

# 使用 Helm 方式
cd ~/Workspace/gitops-infra/ansible && \
~/.conda/bin/ansible-playbook playbooks/04-helm-deploy.yml \
  -e "argocd_install_method=helm"
```

---

## 📊 验证部署

```bash
# 检查所有 pods（应该都是 Running）
multipass exec vm1 -- bash -c '
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  kubectl get pods -n argocd
'

# 获取服务信息
multipass exec vm1 -- bash -c '
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  kubectl get svc -n argocd argocd-server
'
```

---

## 🌐 访问服务

### ArgoCD
- **URL**: `http://<node-ip>:30003`
- **用户名**: `admin`
- **密码**: 运行上面的命令获取

### Harbor
- **URL**: `http://<node-ip>:30002`
- **用户名**: `admin`
- **密码**: `Harbor12345`

**节点 IP**: 10.62.56.80, 10.62.56.199, 10.62.56.81

---

## 🔧 常见问题

### Pod 崩溃？
```bash
# 切换到 manifest 方式
sed -i 's/argocd_install_method: "helm"/argocd_install_method: "manifest"/' \
  ~/Workspace/gitops-infra/ansible/group_vars/all.yml

# 清理并重新部署
multipass exec vm1 -- kubectl delete namespace argocd
~/.conda/bin/ansible-playbook playbooks/04-helm-deploy.yml
```

### 需要重新部署？
```bash
# 删除 ArgoCD
multipass exec vm1 -- bash -c '
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  kubectl delete namespace argocd
'

# 重新运行 playbook
cd ~/Workspace/gitops-infra/ansible
~/.conda/bin/ansible-playbook playbooks/04-helm-deploy.yml
```

---

## 📚 更多信息

- **完整文档**: [README-ArgoCD-Installation.md](./README-ArgoCD-Installation.md)
- **故障排查**: [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
- **改进说明**: [改进总结.md](./改进总结.md)

---

## 💡 推荐配置

| 配置项 | 推荐值 | 说明 |
|--------|--------|------|
| `argocd_install_method` | `"manifest"` | 稳定可靠 |
| `argocd_namespace` | `argocd` | 独立命名空间 |
| `argocd_http_nodeport` | `30003` | 标准端口 |

---

**提示**: 如果是第一次部署，使用默认的 manifest 方式即可。✨
