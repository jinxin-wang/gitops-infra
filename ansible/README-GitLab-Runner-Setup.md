# GitLab Runner 部署指南

## 概述

GitLab Runner 是 GitLab CI/CD 的执行器，部署在 K3s 集群中，使用 Kubernetes Executor 模式在独立的 Pod 中运行每个 CI/CD 任务。

## 部署架构

```
┌─────────────────────────────────────────────────────────┐
│                    GitLab Server                        │
│              (gitlab.com 或自托管实例)                   │
└──────────────────────┬──────────────────────────────────┘
                       │ Webhook 触发
                       │ Runner 注册
                       ▼
┌─────────────────────────────────────────────────────────┐
│              K3s Cluster (gitlab-runner namespace)      │
│  ┌───────────────────────────────────────────────┐     │
│  │  GitLab Runner Pod (Manager)                 │     │
│  │  - 监听 GitLab 任务队列                       │     │
│  │  - 接收 CI/CD Job                            │     │
│  │  - 创建 Executor Pod 执行任务                 │     │
│  └───────────────────────────────────────────────┘     │
│                       │                                 │
│                       ▼ 动态创建                         │
│  ┌─────────────────────────────────────────────┐       │
│  │  Job Executor Pods (临时)                   │       │
│  │  ├─ ubuntu:20.04 (默认镜像)                 │       │
│  │  ├─ 特权模式 (支持 Docker-in-Docker)        │       │
│  │  ├─ 资源限制: 1C/512Mi                      │       │
│  │  └─ 任务完成后自动删除                       │       │
│  └─────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────┘
```

## 前置准备

### 1. 获取 GitLab Runner Registration Token

#### 方式 A: GitLab.com (SaaS)

**项目级别 Runner（推荐用于测试）：**
1. 打开你的项目: `https://gitlab.com/<username>/<project>`
2. 进入 **Settings** > **CI/CD**
3. 展开 **Runners** 部分
4. 找到 **Registration token** (形如 `GR1348941...`)
5. 复制此 token

**组级别 Runner（推荐用于多项目）：**
1. 打开你的组: `https://gitlab.com/groups/<groupname>`
2. 进入 **Settings** > **CI/CD**
3. 展开 **Runners** 部分
4. 复制 **Registration token**

#### 方式 B: 自托管 GitLab

**实例级别 Runner（管理员权限）：**
1. 以管理员身份登录
2. 进入 **Admin Area** > **Overview** > **Runners**
3. 复制 **Registration token**

### 2. 配置 Ansible 变量

编辑 `ansible/group_vars/all.yml`：

```yaml
# 修改 GitLab URL（如果使用自托管实例）
gitlab_url: "https://gitlab.com/"  # 或 "https://gitlab.yourdomain.com/"

# 替换为实际的 Registration Token
gitlab_runner_token: "GR1348941abcdefg..."  # 从上面步骤获取

# 可选: 调整并发数
gitlab_runner_concurrent: 10  # 同时运行的最大任务数
```

## 部署步骤

### 方式 1: 完整 Playbook 部署

```bash
cd ansible

# 部署包含 GitLab Runner 在内的所有平台服务
ansible-playbook -i inventory/local/hosts.ini playbooks/04-helm-deploy.yml
```

### 方式 2: 仅部署 GitLab Runner

```bash
cd ansible

# 使用 tags 仅部署 GitLab Runner（如果后续添加了 tags）
ansible-playbook -i inventory/local/hosts.ini playbooks/04-helm-deploy.yml \
  --tags gitlab-runner

# 或手动运行 Helm 命令
helm repo add gitlab https://charts.gitlab.io
helm repo update

cat > /tmp/runner-values.yaml <<EOF
gitlabUrl: https://gitlab.com/
runnerRegistrationToken: YOUR_TOKEN_HERE

runners:
  config: |
    [[runners]]
      [runners.kubernetes]
        namespace = "gitlab-runner"
        image = "ubuntu:20.04"
        privileged = true
EOF

helm install gitlab-runner gitlab/gitlab-runner \
  -n gitlab-runner --create-namespace \
  -f /tmp/runner-values.yaml
```

## 验证部署

### 1. 检查 Pod 状态

```bash
# 查看 GitLab Runner Pod
kubectl get pods -n gitlab-runner

# 期望输出:
# NAME                              READY   STATUS    RESTARTS   AGE
# gitlab-runner-xxxxxxxxxx-xxxxx    1/1     Running   0          2m

# 查看详细信息
kubectl describe pod -n gitlab-runner -l app=gitlab-runner
```

### 2. 检查 Runner 日志

```bash
# 查看 Runner 日志
kubectl logs -n gitlab-runner -l app=gitlab-runner --tail=100 -f

# 期望看到类似输出:
# Runtime platform  arch=amd64 os=linux
# Running in kubernetes executor mode
# Configuration loaded from /home/gitlab-runner/.gitlab-runner/config.toml
# Checking for jobs... received job=123456
```

### 3. 在 GitLab UI 验证

1. 打开 GitLab 项目/组/实例的 **Settings** > **CI/CD** > **Runners**
2. 应该看到新注册的 Runner：
   - 状态: **绿色圆点** (online)
   - 标签: 显示平台信息
   - 描述: `gitlab-runner-xxxxxxxxxx`

### 4. 测试 CI/CD Pipeline

创建测试项目和 `.gitlab-ci.yml`：

```yaml
# .gitlab-ci.yml
stages:
  - test
  - build

test-job:
  stage: test
  script:
    - echo "Testing in Kubernetes Runner"
    - uname -a
    - pwd
    - ls -la

build-job:
  stage: build
  script:
    - echo "Building application"
    - date
```

提交代码后，观察 Pipeline 是否被 Runner 执行。

## 配置详解

### Runner 配置项

```yaml
# gitlab-runner-values.yaml (生成在 /tmp/)

# GitLab 实例地址
gitlabUrl: https://gitlab.com/

# 注册 Token
runnerRegistrationToken: "YOUR_TOKEN"

# Runner 行为配置
runners:
  config: |
    concurrent = 10              # 最多同时运行 10 个任务
    check_interval = 30          # 每 30 秒检查新任务
    
    [[runners]]
      executor = "kubernetes"    # 使用 K8s Executor
      
      [runners.kubernetes]
        namespace = "gitlab-runner"
        image = "ubuntu:20.04"   # 默认基础镜像
        privileged = true        # 允许 Docker-in-Docker
        
        # 资源限制（每个 Job Pod）
        cpu_request = "100m"
        memory_request = "128Mi"
        cpu_limit = "1"
        memory_limit = "512Mi"
        
        # Service account
        service_account = "gitlab-runner"
        
      # Docker 证书挂载（DinD 需要）
      [[runners.kubernetes.volumes.empty_dir]]
        name = "docker-certs"
        mount_path = "/certs/client"
        medium = "Memory"

# Runner Manager Pod 资源
resources:
  limits:
    memory: 256Mi
    cpu: 200m
  requests:
    memory: 128Mi
    cpu: 100m
```

### 高级配置

#### 1. 配置私有镜像仓库

如果 CI/CD 需要从 Harbor 拉取镜像：

```yaml
runners:
  config: |
    [[runners]]
      [runners.kubernetes]
        image_pull_secrets = ["harbor-registry"]
```

创建 Secret：

```bash
kubectl create secret docker-registry harbor-registry \
  --docker-server=harbor.yourdomain.com \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n gitlab-runner
```

#### 2. 使用缓存加速构建

```yaml
runners:
  config: |
    [[runners]]
      [runners.cache]
        Type = "s3"
        Shared = true
        [runners.cache.s3]
          ServerAddress = "minio.platform.svc.cluster.local:9000"
          BucketName = "runner-cache"
```

#### 3. 配置特定标签的 Runner

```yaml
runners:
  tags: "docker,k8s,prod"
  runUntagged: false  # 仅运行带标签的任务
```

## 故障排查

### 问题 1: Runner 显示为离线

**症状**: GitLab UI 中 Runner 状态为灰色/红色

**排查步骤**:

```bash
# 1. 检查 Pod 状态
kubectl get pods -n gitlab-runner

# 2. 查看日志是否有连接错误
kubectl logs -n gitlab-runner -l app=gitlab-runner

# 3. 检查网络连通性
kubectl exec -it -n gitlab-runner deployment/gitlab-runner -- \
  curl -I https://gitlab.com

# 4. 验证 Token 是否正确
kubectl get secret -n gitlab-runner gitlab-runner -o yaml | grep token
```

**解决方法**:
- 确认 `gitlab_url` 正确
- 确认 `gitlab_runner_token` 未过期
- 检查防火墙是否允许出站连接

### 问题 2: Pipeline 卡在 Pending

**症状**: CI/CD Job 一直显示 "This job is stuck"

**排查步骤**:

```bash
# 1. 检查 Runner 是否启用
# GitLab UI: Runners > Edit > Ensure "Run untagged jobs" is checked

# 2. 查看 Runner 日志
kubectl logs -n gitlab-runner -l app=gitlab-runner

# 3. 检查资源是否充足
kubectl top nodes
kubectl top pods -n gitlab-runner
```

**解决方法**:
- 在 GitLab UI 启用 "Run untagged jobs"
- 增加 K3s 节点资源
- 调整 `concurrent` 参数

### 问题 3: Docker-in-Docker 失败

**症状**: 构建 Docker 镜像时报错 "permission denied"

**排查步骤**:

```bash
# 检查 privileged 模式是否启用
kubectl get pod -n gitlab-runner -l app=gitlab-runner -o yaml | grep privileged
```

**解决方法**:

确保配置中有：

```yaml
runners:
  config: |
    [[runners]]
      [runners.kubernetes]
        privileged = true  # 必须为 true
```

重新部署：

```bash
helm upgrade gitlab-runner gitlab/gitlab-runner \
  -n gitlab-runner \
  -f /tmp/gitlab-runner-values.yaml
```

### 问题 4: 资源不足

**症状**: Job 失败，日志显示 OOMKilled 或 CPU Throttling

**解决方法**:

调整资源限制：

```yaml
runners:
  config: |
    [[runners]]
      [runners.kubernetes]
        cpu_request = "200m"      # 增加请求
        memory_request = "256Mi"
        cpu_limit = "2"           # 增加限制
        memory_limit = "1Gi"
```

## 管理操作

### 更新 Runner 配置

```bash
# 1. 修改 values 文件
vim /tmp/gitlab-runner-values.yaml

# 2. 升级 Helm Release
helm upgrade gitlab-runner gitlab/gitlab-runner \
  -n gitlab-runner \
  -f /tmp/gitlab-runner-values.yaml

# 3. 验证更新
kubectl rollout status deployment/gitlab-runner -n gitlab-runner
```

### 卸载 Runner

```bash
# 使用 Helm 卸载
helm uninstall gitlab-runner -n gitlab-runner

# 删除命名空间（可选）
kubectl delete namespace gitlab-runner
```

### 查看 Runner 版本

```bash
kubectl exec -it -n gitlab-runner deployment/gitlab-runner -- \
  gitlab-runner --version
```

## 性能优化

### 1. 调整并发数

根据集群资源调整：

```yaml
concurrent: 20  # 如果有足够资源，可增加到 20
```

### 2. 使用节点亲和性

将 Runner 调度到特定节点：

```yaml
nodeSelector:
  node-role: ci-runner

tolerations:
  - key: "ci-workload"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
```

### 3. 配置构建缓存

使用 MinIO 或云对象存储：

```yaml
runners:
  config: |
    [[runners]]
      [runners.cache]
        Type = "s3"
        Shared = true
```

## 安全最佳实践

1. **最小权限原则**: 使用项目级别 Runner，避免实例级别
2. **定期轮换 Token**: 每季度更换 Registration Token
3. **镜像扫描**: 在 Harbor 中启用 Trivy 扫描 CI 产出的镜像
4. **网络隔离**: 使用 NetworkPolicy 限制 Runner 的网络访问
5. **审计日志**: 定期检查 Runner 日志，发现异常行为

## 参考资料

- [GitLab Runner 官方文档](https://docs.gitlab.com/runner/)
- [Kubernetes Executor](https://docs.gitlab.com/runner/executors/kubernetes.html)
- [Helm Chart 配置](https://gitlab.com/gitlab-org/charts/gitlab-runner)
- [Docker-in-Docker 最佳实践](https://docs.gitlab.com/ee/ci/docker/using_docker_build.html)

## 下一步

完成 GitLab Runner 部署后，你可以：

1. ✅ 创建第一个 CI/CD Pipeline 测试 Runner
2. ✅ 配置自动构建 Docker 镜像并推送到 Harbor
3. ✅ 集成 ArgoCD 实现完整的 GitOps 工作流
4. ✅ 添加自动化测试（单元测试、集成测试）
5. ✅ 配置多环境部署（dev → staging → production）

参考：`gitops/argocd/README.md` 了解完整的测试和部署流程。
