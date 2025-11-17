# 问题排查与解决方案总结

## 日期：2025-11-18

---

## 问题 1：Multipass ld.so.preload 错误

### 现象
```bash
ERROR: ld.so: object '/usr/local/lib/AppProtection/libAppProtection.so' 
from /etc/ld.so.preload cannot be preloaded (failed to map segment from shared object): ignored.
```

每次运行 `multipass` 命令都会出现大量此类错误信息。

### 根本原因
- `/etc/ld.so.preload` 文件中引用了不存在或损坏的共享库
- AppProtection 库文件路径 `/usr/local/lib/AppProtection/libAppProtection.so` 无效
- 该文件可能是某个已卸载的软件残留

### 解决方案
```bash
# 1. 查看问题文件内容
cat /etc/ld.so.preload

# 2. 删除无效的库引用
sudo sed -i '/AppProtection/d' /etc/ld.so.preload

# 3. 验证修复
multipass list  # 应该不再出现错误
```

### 预防措施
- 卸载软件时检查是否清理 `/etc/ld.so.preload` 中的条目
- 定期审查该文件内容

---

## 问题 2：ArgoCD Helm 安装失败 - "name is still in use"

### 现象
```bash
Error: INSTALLATION FAILED: cannot re-use a name that is still in use
```

### 根本原因
- ArgoCD 之前的安装留有残留资源
- Kubernetes 资源未完全清理
- 命名空间处于 Terminating 状态，无法创建新资源

### 解决方案
```bash
# 1. 删除整个命名空间
kubectl delete namespace platform

# 2. 如果命名空间卡在 Terminating 状态，强制清理
kubectl get namespace platform -o json | \
  jq ".spec.finalizers = []" | \
  kubectl replace --raw /api/v1/namespaces/platform/finalize -f -

# 3. 验证命名空间已删除
kubectl get ns platform
```

---

## 问题 3：ArgoCD Pod 崩溃 - "exec format error"

### 现象
```bash
# Pod 状态
NAME                              READY   STATUS              RESTARTS   AGE
argocd-server-xxx                 0/1     CrashLoopBackOff    6          8m

# Pod 日志
exec /usr/bin/tini: exec format error
```

### 根本原因
**不是架构不兼容**，而是 Helm Chart 版本或配置问题：
- 使用的 ArgoCD Helm Chart 版本 `5.51.6` 存在问题
- 某些镜像版本可能有损坏或配置不当
- Helm Chart 的默认配置与环境不匹配

### 环境信息
```bash
# 系统架构（正常）
multipass exec vm1 -- uname -m
# 输出: x86_64

multipass exec vm1 -- dpkg --print-architecture
# 输出: amd64

# 使用的镜像
Image: quay.io/argoproj/argocd:v2.9.3
```

### 解决方案

#### 方案 A：使用官方 Manifest（推荐 ✅）
```bash
# 1. 卸载失败的 Helm 安装
helm uninstall argocd -n platform

# 2. 创建新的命名空间
kubectl create namespace argocd

# 3. 使用官方稳定版 manifest
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 4. 等待 Pod 启动
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=300s

# 5. 修改服务类型为 NodePort
kubectl patch svc argocd-server -n argocd -p \
  '{"spec":{"type":"NodePort","ports":[{"port":80,"nodePort":30003,"name":"http"},{"port":443,"nodePort":30443,"name":"https"}]}}'

# 6. 获取初始管理员密码
kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d
```

#### 方案 B：更新 Helm Chart（备选）
```bash
# 尝试更新 Helm 仓库
helm repo update

# 使用最新的 chart 版本
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 6.0.0 \  # 使用更新的版本
  --set server.service.type=NodePort \
  --wait
```

### 验证部署
```bash
# 检查所有 Pod 状态（应该都是 Running）
kubectl get pods -n argocd

# 预期输出：
# NAME                                                READY   STATUS    RESTARTS   AGE
# argocd-applicationset-controller-xxx                1/1     Running   0          5m
# argocd-notifications-controller-xxx                 1/1     Running   0          5m
# argocd-repo-server-xxx                              1/1     Running   0          5m
# argocd-server-xxx                                   1/1     Running   0          5m
# argocd-redis-xxx                                    1/1     Running   0          5m
# argocd-dex-server-xxx                               1/1     Running   0          5m
# argocd-application-controller-0                     1/1     Running   0          5m

# 获取服务信息
kubectl get svc -n argocd argocd-server
```

---

## 最终部署状态

### 成功部署的服务

| 服务 | 命名空间 | 安装方式 | 端口 | 状态 |
|------|---------|---------|------|------|
| Cert-Manager | platform | Helm | 9402 | ✅ Running |
| Harbor | platform | Helm | 30002 | ✅ Running |
| ArgoCD | argocd | kubectl apply | 30003 | ✅ Running |

### 访问信息

#### Harbor
- URL: `http://<node-ip>:30002`
- 用户名: `admin`
- 密码: `Harbor12345`

#### ArgoCD
- URL: `http://<node-ip>:30003`
- 用户名: `admin`
- 密码: 运行以下命令获取
  ```bash
  kubectl get secret argocd-initial-admin-secret \
    -n argocd -o jsonpath="{.data.password}" | base64 -d
  ```

#### 节点 IP 列表
- 10.62.56.80
- 10.62.56.199
- 10.62.56.81

---

## 经验教训

### 1. 命名空间清理
- 删除命名空间前备份重要数据
- 使用 finalizers 强制清理卡住的命名空间
- 验证资源完全删除后再重建

### 2. Helm vs Kubectl
- **Helm 优势**: 版本管理、回滚、配置管理
- **kubectl apply 优势**: 官方支持、稳定性好、问题少
- 对于关键组件，优先使用官方推荐的安装方式

### 3. 排查步骤
1. 检查 Pod 状态: `kubectl get pods -n <namespace>`
2. 查看 Pod 日志: `kubectl logs <pod-name> -n <namespace>`
3. 描述 Pod 详情: `kubectl describe pod <pod-name> -n <namespace>`
4. 检查事件: `kubectl get events -n <namespace> --sort-by='.lastTimestamp'`
5. 验证架构兼容性: `uname -m` 和镜像架构

### 4. 调试技巧
```bash
# 实时监控 Pod 状态
watch kubectl get pods -n argocd

# 跟踪 Pod 日志
kubectl logs -f <pod-name> -n <namespace>

# 查看 Init Container 日志
kubectl logs <pod-name> -n <namespace> -c <init-container-name>

# 进入运行中的容器
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh
```

---

## 后续优化建议

1. **自动化检查脚本**
   - 创建健康检查脚本
   - 定期验证服务状态

2. **Playbook 改进**
   - 添加更好的错误处理
   - 支持 ArgoCD 的 kubectl 安装方式
   - 添加回滚机制

3. **监控告警**
   - 部署 Prometheus + Grafana
   - 配置 Pod 崩溃告警
   - 监控资源使用情况

4. **文档更新**
   - 记录所有已知问题
   - 维护故障排查手册
   - 更新安装文档

---

## 参考资源

- [ArgoCD 官方文档](https://argo-cd.readthedocs.io/)
- [Helm 故障排查](https://helm.sh/docs/faq/troubleshooting/)
- [Kubernetes 调试指南](https://kubernetes.io/docs/tasks/debug/)
- [K3s 文档](https://docs.k3s.io/)

