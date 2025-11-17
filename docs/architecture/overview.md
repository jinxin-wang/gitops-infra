# 架构概览

## 1. 总体架构

### 1.1 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                    代码管理 (GitLab)                          │
│              (SaaS 或 Self-hosted 可选)                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         GitLab CI (Runner on K3s Cluster)                    │
│  • 触发CI流程  • 执行构建  • 推送镜像到Harbor                 │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              单个K3s集群 (3节点，共24GB内存)                   │
├─────────────────────────────────────────────────────────────┤
│ Namespace: platform    Namespace: dev    Namespace: staging  │
│ ├─ Harbor              ├─ App Services   └─ App Services     │
│ ├─ ArgoCD              ├─ PostgreSQL                          │
│ ├─ Prometheus          ├─ Redis                              │
│ ├─ Grafana             └─ Testing                            │
│ └─ Cert-Manager                                              │
│                       Namespace: production                  │
│                       └─ App Services (独立磁盘/网络)         │
└─────────────────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│            GitOps 仓库 (ArgoCD 监控)                         │
│  • 应用配置版本控制  • 配置与代码分离  • 快速回滚             │
└─────────────────────────────────────────────────────────────┘
```

## 2. 设计原则

### 2.1 核心理念

**简单胜于完美**
- 单集群架构支撑10-30个微服务
- 避免过度设计，快速迭代
- 保留未来扩展空间

**快速迭代**
- 从最小MVP开始
- 循序渐进完善功能
- 持续优化和改进

### 2.2 技术选型原则

| 维度 | 选型标准 |
|------|---------|
| **成熟度** | 社区活跃，文档完善 |
| **轻量级** | 资源占用小，适合初期规模 |
| **可扩展** | 支持平滑升级和横向扩展 |
| **云原生** | 遵循CNCF标准，避免厂商锁定 |

## 3. 核心组件

### 3.1 基础设施层

#### K3s集群
- **角色**：轻量级Kubernetes发行版
- **配置**：1个Master + 2个Worker节点
- **资源**：总计24GB内存，12核CPU
- **特点**：
  - 内存占用<1GB
  - 一键安装，易于维护
  - 完整Kubernetes API兼容

#### 存储方案
- **临时存储**：K3s默认local storage
- **持久化存储**：云厂商块存储（CBS/云盘）
- **对象存储**：Harbor镜像、备份数据

#### 网络配置
- **CNI**：K3s内置Flannel
- **负载均衡**：云厂商SLB/CLB + K3s Ingress
- **DNS**：云厂商DNS服务
- **证书**：Cert-Manager + Let's Encrypt

### 3.2 平台服务层

#### Harbor（镜像仓库）
```yaml
资源占用: ~1GB内存
功能:
  - Docker镜像存储和分发
  - 代理PyPI/npm/Go Mod等
  - 漏洞扫描（Trivy集成）
  - RBAC权限管理
  - 镜像签名和复制
部署方式: Helm Chart
命名空间: platform
```

#### ArgoCD（GitOps引擎）
```yaml
资源占用: ~0.3GB内存
功能:
  - 持续监控GitOps仓库
  - 自动同步应用到K8s
  - Web UI查看部署状态
  - 支持快速回滚
  - 多环境配置管理
部署方式: Helm Chart
命名空间: argocd
```

#### GitLab Runner（CI引擎）
```yaml
资源占用: <0.1GB内存（idle）
功能:
  - 接收GitLab Webhook
  - 在K8s Pod中执行CI任务
  - 并发支持10+个构建
  - 自动扩缩容
部署方式: Helm Chart
命名空间: gitlab-runner
```

#### 监控栈
```yaml
Prometheus:
  资源占用: ~1GB内存
  功能: 指标采集和存储
  
Grafana:
  资源占用: ~0.2GB内存
  功能: 可视化和告警

metrics-server:
  资源占用: ~0.05GB内存
  功能: kubectl top命令支持

部署方式: Helm Chart (kube-prometheus-stack)
命名空间: monitoring
```

#### Cert-Manager（证书管理）
```yaml
资源占用: ~0.1GB内存
功能:
  - 自动申请Let's Encrypt证书
  - 自动续期
  - 多域名支持
部署方式: Helm Chart
命名空间: cert-manager
```

### 3.3 应用层

#### 环境隔离
```yaml
dev环境:
  命名空间: dev
  副本数: 1
  资源限制: requests(0.2C/256Mi), limits(0.5C/512Mi)
  用途: 开发测试，快速迭代
  
staging环境:
  命名空间: staging
  副本数: 2
  资源限制: requests(0.5C/512Mi), limits(1C/1Gi)
  用途: UAT测试，完整配置验证
  
production环境:
  命名空间: production
  副本数: 3+
  资源限制: requests(1C/2Gi), limits(2C/4Gi)
  用途: 生产流量，高可用
```

## 4. 数据流

### 4.1 CI/CD流程

```
1. 开发者提交代码
   ↓ (git push / merge PR)
   
2. GitLab Webhook触发
   ↓ (POST /webhook)
   
3. GitLab Runner执行CI
   ├─ 单元测试
   ├─ 代码检查
   ├─ 构建镜像
   └─ 推送Harbor
   ↓
   
4. 更新GitOps仓库
   ↓ (git commit + push)
   
5. ArgoCD检测变更
   ↓ (每3分钟轮询)
   
6. 自动部署到K8s
   ↓ (kubectl apply)
   
7. 应用启动运行
   └─ (健康检查通过)
```

### 4.2 监控数据流

```
应用指标 → Prometheus → Grafana → 告警
   ↓           ↓           ↓
  /metrics   TSDB存储   可视化图表
```

### 4.3 日志流

```
应用日志 → stdout/stderr → kubectl logs
   ↓
容器日志 → 云厂商日志服务（可选）
```

## 5. 网络架构

### 5.1 网络拓扑

```
Internet
    ↓
云厂商负载均衡器 (SLB/CLB)
    ↓
K3s Ingress Controller
    ↓
┌─────────────────────────────────┐
│         Service Network          │
│  (ClusterIP: 10.43.0.0/16)      │
├─────────────────────────────────┤
│  dev-svc    staging-svc  prod-svc│
└─────────────────────────────────┘
    ↓
┌─────────────────────────────────┐
│          Pod Network             │
│  (PodCIDR: 10.42.0.0/16)        │
├─────────────────────────────────┤
│   app-pods   db-pods  cache-pods │
└─────────────────────────────────┘
```

### 5.2 端口规划

| 服务 | 内部端口 | 外部端口 | 协议 |
|------|---------|---------|------|
| **Harbor** | 80 | 443 | HTTPS |
| **ArgoCD** | 8080 | 443 | HTTPS |
| **Grafana** | 3000 | 443 | HTTPS |
| **应用API** | 8000-9000 | 443 | HTTPS |
| **K3s API** | 6443 | - | HTTPS（内部） |

### 5.3 防火墙规则

```yaml
入站规则:
  - 80/443 (HTTP/HTTPS): 0.0.0.0/0 允许
  - 22 (SSH): 仅运维网络 允许
  - 6443 (K8s API): 仅内网 允许

出站规则:
  - 全部允许 (拉取依赖包、镜像)
```

## 6. 安全架构

### 6.1 认证授权

```yaml
K8s RBAC:
  - ServiceAccount per namespace
  - Role/RoleBinding限制权限
  - 禁用匿名访问

Harbor RBAC:
  - 项目级别权限
  - 基于角色的镜像推送/拉取
  - Webhook集成

ArgoCD RBAC:
  - SSO集成（可选）
  - 项目级别权限
  - 审计日志
```

### 6.2 镜像安全

```yaml
Trivy扫描:
  - 推送时自动扫描
  - 定期扫描已部署镜像
  - 阻止高危漏洞镜像部署

镜像签名:
  - Harbor Content Trust（可选）
  - 验证镜像来源
```

### 6.3 密钥管理

```yaml
初期方案:
  - K8s Secrets存储敏感信息
  - base64编码
  - RBAC限制访问

未来升级:
  - Sealed Secrets (加密存储在Git)
  - HashiCorp Vault (集中式密钥管理)
```

### 6.4 网络安全

```yaml
NetworkPolicy:
  - 命名空间间隔离
  - 生产环境严格入站规则
  - 仅允许必要的Pod间通信

TLS加密:
  - 所有外部流量HTTPS
  - Let's Encrypt自动证书
  - 内部服务可选mTLS
```

## 7. 高可用设计

### 7.1 K3s集群高可用

```yaml
Master节点:
  - 单Master（初期）
  - etcd内嵌
  - 计划升级为3 Master HA（未来）

Worker节点:
  - 2个Worker节点
  - Pod自动调度
  - 节点故障自动驱逐
```

### 7.2 应用高可用

```yaml
副本策略:
  dev: 1副本（资源优先）
  staging: 2副本（验证高可用）
  production: 3+副本（高可用）

反亲和性:
  - 生产环境Pod分散不同节点
  - 避免单点故障

健康检查:
  - livenessProbe: 存活检查
  - readinessProbe: 就绪检查
  - startupProbe: 启动检查
```

### 7.3 数据高可用

```yaml
有状态服务:
  - PostgreSQL: 云厂商RDS（推荐）
  - Redis: 云厂商Redis（推荐）
  - 避免在K8s内运行数据库

持久化数据:
  - 云盘挂载
  - 自动快照备份
  - 跨AZ复制（生产环境）
```

## 8. 资源规划

### 8.1 集群资源分配

```yaml
总资源: 24GB内存, 12核CPU

平台服务层 (~4GB):
  - Harbor: 1GB
  - Prometheus: 1GB
  - GitLab Runner: 0.5GB
  - ArgoCD: 0.3GB
  - Grafana: 0.2GB
  - Cert-Manager: 0.1GB
  - 其他: 0.9GB

应用层 (~16GB):
  - dev环境: 3GB (10个微服务 × 256Mi)
  - staging环境: 5GB (10个微服务 × 512Mi)
  - production环境: 8GB (10个微服务 × 2副本 × 512Mi)

系统预留 (~4GB):
  - K3s组件: 1GB
  - OS系统: 2GB
  - Buffer: 1GB
```

### 8.2 扩容触发条件

```yaml
CPU扩容:
  - 持续利用率 > 80% 持续30分钟
  - 应对: 增加Worker节点或升级规格

内存扩容:
  - 持续利用率 > 80% 持续30分钟
  - 应对: 增加内存或优化Pod配置

存储扩容:
  - 磁盘使用 > 90%
  - 应对: 清理旧镜像或扩容磁盘
```

## 9. 演进路线

### 9.1 当前阶段（0-6个月）

```yaml
规模: 10个微服务, 3节点集群
架构: 单集群, 命名空间隔离
监控: 基础监控 (Prometheus + Grafana)
CI/CD: GitLab CI + ArgoCD
目标: 快速验证业务，稳定运行
```

### 9.2 扩展阶段（6-12个月）

```yaml
条件:
  - 微服务数量 > 20
  - 内存利用率持续 > 75%
  - 部署频率 > 50次/天

升级方案:
  - 增加Worker节点（4-5个节点）
  - 引入镜像缓存加速构建
  - 配置Harbor云存储后端
  - 部署Sealed Secrets
```

### 9.3 多集群阶段（12个月+）

```yaml
条件:
  - 微服务数量 > 30
  - 需要跨地域部署
  - 出现合规/审计需求

升级方案:
  - 分离CI集群和应用集群
  - Staging/Production独立集群
  - 引入Service Mesh (Cilium/Istio)
  - 多集群管理工具 (Rancher/Karmada)
  - 集中式密钥管理 (Vault)
```

## 10. 设计决策记录

### 10.1 为什么选择K3s而非K8s？
- **轻量级**：内存占用<1GB，适合资源受限环境
- **易维护**：一键安装，自动化程度高
- **完整性**：100% Kubernetes API兼容
- **生产就绪**：CNCF认证，大规模生产使用案例

### 10.2 为什么选择单集群而非多集群？
- **初期规模小**：10个微服务不需要多集群
- **降低复杂度**：避免跨集群网络、服务发现问题
- **降低成本**：单集群节省资源和运维成本
- **保留扩展性**：命名空间隔离支持未来拆分

### 10.3 为什么选择GitLab CI而非Tekton？
- **成熟度高**：GitLab CI社区活跃，文档完善
- **学习曲线低**：YAML配置简单，团队易上手
- **功能完整**：内置Runner、缓存、制品管理
- **维护成本低**：Tekton需要额外维护组件

### 10.4 为什么选择ArgoCD而非Flux？
- **UI友好**：提供Web界面，直观查看部署状态
- **易于调试**：日志和事件可视化
- **功能完整**：支持Helm、Kustomize、多集群
- **社区活跃**：CNCF孵化项目，持续更新

## 11. 参考资源

### 11.1 官方文档
- [K3s Documentation](https://docs.k3s.io/)
- [Harbor Documentation](https://goharbor.io/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Prometheus Documentation](https://prometheus.io/docs/)

### 11.2 相关规范
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [12-Factor App](https://12factor.net/)
- [GitOps Principles](https://opengitops.dev/)

### 11.3 架构决策记录
- [ADR-001: 为什么选择K3s](../adr/001-why-k3s.md)
- [ADR-002: 单集群vs多集群](../adr/002-single-vs-multi-cluster.md)
- [ADR-003: GitOps工具选型](../adr/003-gitops-tool-selection.md)

---

**文档版本**: v1.0  
**最后更新**: 2025-01-17  
**维护者**: DevOps Team  
**审阅周期**: 每季度
