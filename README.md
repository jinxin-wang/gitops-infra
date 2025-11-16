# 高性能混合云 CI/CD 架构设计方案

## 1. 架构总览

本方案旨在设计一套端到端的 CI/CD 流程，以应对高频提交 (High Commit Frequency) 和混合云部署 (Hybrid Cloud) 的挑战。架构以 Kubernetes 为核心，采用 IaC (Terraform) 管理基础设施，GitOps (ArgoCD) 管理应用部署，并通过 BuildKite + Tekton 的组合实现高效、安全的 CI 流程。

- CI (持续集成): 运行在本地数据中心 (On-Prem)，确保源代码和构建过程的安全性。
- CD (持续交付): 跨越本地 (Testbed) 和云端 (Staging, Production)，通过 GitOps 实现自动化和一致性部署。
- CO (持续运维): 确保应用能够可靠、安全、高效地运行，并具备自我修复能力。
- CF (持续反馈): 负责将CO阶段收集到的数据转化为行动，也就是说用户体验数据、性能指标、错误日志、安全漏洞等，都会被收集起来。这些数据被分析后，形成新的需求或改进方案，重新投入到 CI 阶段，从而推动产品迭代和质量提升。
## 2. 核心设计理念

1. 基础设施即代码 (IaC): 所有基础设施（K8s 集群、VPC、Harbor/Nexus 实例）均由 Terraform 声明式管理，确保环境的可重复性和一致性。

2. GitOps 持续交付: ArgoCD 作为唯一的部署引擎，以 GitOps 配置仓库作为部署的单一事实来源 (SSOT)，实现声明式、自动化的应用交付。

3. 混合云模式 (Hybrid Cloud):
 - CI/Testbed 在本地 (On-Prem): 源代码的编译、测试和打包在本地数据中心完成，代码不离开内网，保障安全。
 - Staging/Prod 在云端 (Cloud): 利用云服务商（如腾讯云 TKE、阿里云 ACK）的弹性和高可用性。
 
4. 编排与执行分离:
 - BuildKite (编排器): 作为 SaaS 控制平面，负责 CI/CD 流程的编排、调度、UI 展示和人工审批。Agent 部署在本地，确保安全。
 - Tekton (执行引擎): 作为 K8s 原生 CI 引擎，在本地 K8s 集群中动态创建 Pod 执行所有 CI 任务（Lint, Test, Build）。
 
5. 高效增量构建 (CI 效率):
 - BuildKite 动态流水线: 在 CI 启动时首先分析 git diff，动态生成最小化的Tekton 流水线，只运行受变更影响的任务。
 - Bazel 智能缓存: 作为构建工具，利用其强大的远程缓存和增量构建能力，跳过所有未发生变化的代码模块的编译。

6. 统一集群管理: Rancher 作为统一的管理平台，导入并管理本地和云端的 K8s 集群，提供单一视图 (Single Pane of Glass) 进行运维和 RBAC 管理。

7. 专业化制品库:
 - Nexus OSS: 部署在本地，作为 Python (PyPI)、Go Mod、JavaScript (npm) 等语言依赖包的私有仓库和公网缓存。
 - Harbor: 部署两套实例，作为容器镜像和 Helm Chart仓库，并通过复制规则连接本地与云端。
 
## 3. 环境与部署策略

|环境|位置|K8s集群|核心服务(CI/CD)|应用部署|
|---|---|---|---|---|
|本地开发|开发者本地|N/A (Docker Desktop)|N/A|本地应用|
|CI / Testbed|本地数据中心 (On-Prem)|K8s 集群 (On-Prem)|Rancher, BuildKite Agents, Tekton, Bazel 缓存, Nexus, SonarQube, Harbor-OnPrem, ArgoCD-OnPrem|Testbed 环境应用|
|Staging|云端 (Cloud)|K8s 集群 (Cloud)|Harbor-Cloud, ArgoCD-Cloud|Staging 环境应用|
|Production|云端 (Cloud)|K8s 集群 (Cloud)|Harbor-Cloud, ArgoCD-Cloud|Production 环境应用|


## 4. 组件与角色分工

|工具|角色|部署位置/运行方式|核心职责|
|---|---|---|---|
|GitLab/GitHub|SCM (代码仓库)|本地 (On-Prem) 或 SaaS|存储应用代码和 GitOps 配置；发送 Webhook。|
|Terraform|IaC (基础设施)|命令行工具 (由 BuildKite 调用或本地执行)|创建 K8s 集群 (On-Prem & Cloud)、VPC、数据库、Harbor、Nexus 等。|
|Rancher|K8s 管理平台|K8s Deployment (任一集群)|统一导入和管理所有 K8s 集群，提供 UI、RBAC 和应用商店。|
|BuildKite|CI/CD 编排器|控制平面 (SaaS) + Agent (On-Prem K8s)|总指挥。 接收 Webhook，调度 Agent，管理动态流水线和人工审批。|
|Tekton|CI 执行引擎|K8s 原生 (On-Prem)|执行者。 被 BuildKite 触发，在 K8s 中创建 Pods 运行 CI 任务。|
|Bazel|高效构建系统|命令行工具 (在 Tekton Pod 中运行)|编译/构建。 高效编译代码，利用缓存跳过重复构建。|
|Nexus OSS|语言依赖包仓库|K8s Deployment (On-Prem)|存储/代理 PyPI, npm, Go Mod 等。|
|Harbor|容器镜像仓库|k8s Deployment (On-Prem & Cloud)|存储 Docker/OCI 镜像，漏洞扫描 (Trivy)，负责本地到云端的镜像复制。|
|SonarQube|静态代码分析|K8s Deployment (On-Prem)|质量关卡 (Quality Gate)。 分析代码质量、安全漏洞、技术债务。|
|Kaniko/Buildah|容器镜像打包|命令行工具 (在 Tekton Pod 中运行)|在 K8s Pod 中安全地（无 Daemon）将 Bazel 的编译结果打包成镜像。
|ArgoCD|CD/GitOps 引擎|K8s Deployment (On-Prem & Cloud)|部署者。 监控 GitOps 仓库，自动同步应用到所有 K8s 环境。|

## 5. 详细流程分解

### 阶段 0: 基础设施供应与平台搭建 (Terraform & Rancher)

1. 执行 IaC (Terraform): 运维团队通过 Terraform 脚本在本地 (On-Prem) 和云端 (Cloud) 创建所有 K8s 集群（例如 TKE, ACK）。

2. 部署 Rancher & 导入集群:

 - Terraform (或 Helm) 部署 Rancher 管理平台（可部署在任一集群，如 On-Prem）。
 - Terraform 配置 Rancher 自动导入 (Import) 所有由 Terraform 创建的 K8s 集群 (On-Prem, Staging, Production)。

3. 部署平台服务 (Rancher App Catalog):
 - Rancher 提供统一的应用商店 (App Catalog)。运维团队通过 Rancher UI，使用 Helm Chart 将 CI/CD 核心服务部署到正确的集群：
   - On-Prem 集群: 部署 Harbor-OnPrem, Nexus OSS, ArgoCD-OnPrem, SonarQube, Tekton, BuildKite Agents。
   - Cloud 集群: 部署 Harbor-Cloud, ArgoCD-Cloud。

4. 统一运维 (Rancher):
 - 此时，所有基础设施和服务均已部署。
 - Rancher 作为统一管理入口，为运维团队提供了单一视图 (Single Pane of Glass) 来监控所有环境的健康状况、管理 CI/CD 服务的生命周期（升级、回滚）以及配置跨集群的 RBAC 权限。

### 阶段 1: 持续集成 (CI) — 从 Commit 到 本地 Harbor (On-Prem)

1. 触发 (Git $\to$ BuildKite): 开发者 git push 到 GitLab。GitLab 发送 Webhook 通知给 BuildKite (SaaS)。

2. 动态流水线 (BuildKite):
 - BuildKite 调度一个轻量级 Bootstrap Agent (On-Prem K8s)。
 - Agent 运行 git diff 或 bazel query 分析变更。
 - Agent 动态生成一个最小化的 Tekton 流水线 YAML，并 buildkite-agent pipeline upload 回 BuildKite。

3. 执行 CI (BuildKite $\to$ Tekton): BuildKite 调度 Tekton (On-Prem) 来执行这个动态生成的流水线。

4. Tekton 运行质量门 (On-Prem Pods):
 - Task 1: 静态检测 (Lint & SAST): Tekton 创建 Pod 运行 golangci-lint, pylint 等。同时运行 sonar-scanner，连接到 SonarQube (On-Prem)。Tekton 轮询 API 等待质量关卡 (Quality Gate) 返回 "PASS"。失败则 Pipeline 停止。
 - Task 2: 单元测试 (Unit Tests): Tekton 创建 Pod 运行 pytest, go test 等。测试脚本从 Nexus (On-Prem) 拉取依赖包。失败则 Pipeline 停止。

5. 高效构建与推送 (Tekton $\to$ Bazel $\to$ Kaniko $\to$ Harbor):
 - Task 3: 构建与打包:
   - a) 编译 (Bazel): Pod 内运行 Bazel。Bazel 利用远程缓存，仅编译发生变更的代码，生成二进制文件。
   - b) 打包 (Kaniko): Pod 内运行 Kaniko，读取 Dockerfile 和 Bazel 的编译结果，安全地（无 Daemon）构建出一个新的 Docker 镜像 (例如 myapp:v1.2.3-commitSHA)。
   - c) 推送 (Harbor-OnPrem): Kaniko 将新镜像推送到 Harbor-OnPrem。Harbor 自动触发漏洞扫描。

### 阶段 2: 持续交付 (CD) — 从 Testbed 到 Production (Hybrid)

6. CI/CD 交接 (GitOps 更新): 最后一个 Tekton 任务 git clone GitOps 配置仓库，将 testbed/ 路径下的 YAML 镜像标签更新为 myapp:v1.2.3-commitSHA，然后 git push。

7. 部署 Testbed (ArgoCD On-Prem):
 - ArgoCD-OnPrem 检测到 GitOps 仓库 testbed/ 目录的变更。
 - ArgoCD 自动同步，从 Harbor-OnPrem 拉取新镜像，并将其部署到 Testbed 环境 (On-Prem K8s)。

8. 晋升 Staging (人工审批 + 混合云桥梁):
 - (在 Testbed 自动运行 E2E 测试...)
 - 测试通过后，BuildKite 流水线暂停，等待 QA 负责人点击 "Approve" 按钮。
 - 审批通过后，BuildKite 触发两个动作：
   - 1. Harbor 复制: 触发 Harbor-OnPrem 将 myapp:v1.2.3-commitSHA 镜像复制 (Replicate) 到 Harbor-Cloud。GitOps 更新: 更新 
   - 2. GitOps 仓库中的 staging/ 目录，指向该镜像标签。

9. 部署 Staging (ArgoCD Cloud):
 - ArgoCD-Cloud 检测到 staging/ 目录的变更。
 - ArgoCD 自动同步，从 Harbor-Cloud 拉取新镜像，并将其部署到 Staging 集群 (Cloud K8s)。

10. 晋升 Production (人工审批):
 - (在 Staging 环境进行 UAT 和性能测试...)
 - 发布经理在预定的发布窗口，批准 GitOps 仓库中从 staging/ 到 production/ 的 PR。
 - ArgoCD-Cloud 检测到 production/ 目录的变更，执行同步，完成生产环境的蓝绿/金丝雀部署。


## 6. CI 效率策略： (应对大量Commit)

**核心思想：** 从“为每个 Commit 运行所有任务”转变为“只运行与本次 Commit 相关的、最小化的任务”。我们将结合使用 **BuildKite 的动态流水线** 和 **Bazel 的智能缓存** 来实现这一点。

#### 1 动态流水线 (Dynamic Pipelines) - BuildKite 的优势

我们将 CI 流程分为两个阶段，由 BuildKite 调度：

* **阶段 A: 引导流水线 (Bootstrap Pipeline)**
    1.  **触发：** 开发者 `git commit`。BuildKite 接收到 Webhook。
    2.  **调度：** BuildKite 调度一个**轻量级的 Agent Pod (Bootstrap Pod)**。
    3.  **分析变更：** 这个 Pod 的**唯一**任务是运行一个脚本，该脚本使用 `git diff` 或 `bazel query` 来分析**哪些文件被更改了**。
    4.  **动态生成：** 该脚本根据分析结果，**动态生成**一个 YAML 文件，其中*仅包含*受影响服务所需的 CI 步骤（例如：只包含 `service-A` 的 Lint 和 Test）。
    5.  **上传：** 脚本将这个新生成的 YAML `buildkite-agent pipeline upload` 回 BuildKite。

* **阶段 B: 执行流水线 (Dynamic Execution)**
    1.  **调度：** BuildKite 收到动态生成的 YAML，并将其作为当前流水线的剩余步骤。
    2.  **Tekton 执行：** BuildKite 开始调度这些（现在是最小化的）Tekton `Task`。如果只更改了 `service-A`，那么 `service-B` 和 `service-C` 的所有 CI 任务都会被**完全跳过**。

#### 2 智能构建缓存 (Bazel 的优势)

* **缓存命中：** 即使是运行 `service-A` 的 `Task`，当 Tekton Pod 启动并执行 **Bazel** 命令时，Bazel 依然会连接到其**远程缓存**。
* **增量构建：** Bazel 知道 `service-A` 中只有 `file.go` 被修改了，它将只重新编译 `file.go` 及其直接依赖项，所有其他未受影响的部分（占 99%）将直接从缓存中拉取。

**效率结果：** 一个只修改了单个文件的 Commit，其 CI 流程从（可能的）30 分钟缩短到（可能的）1-2 分钟。

---

## 7. 混合环境应对策略：(本地网络 + 云)

**核心思想：** 将基础设施分为两个“域”（On-Prem 和 Cloud），并使用 **Rancher** 进行统一管理，使用 **Harbor 复制**来桥接制品流。

### 1 架构部署图 (Hybrid Cloud)

| 环境 | 位置 | Kubernetes 集群 | 核心服务 (CI/CD) | 应用 |
| :--- | :--- | :--- | :--- | :--- |
| **Local Dev** | 本地 (On-Prem) | N/A (Docker Desktop) | N/A | N/A |
| **Testbed / CI** | **本地 (On-Prem)** | **K8s 集群 (On-Prem)** | **BuildKite Agent, Tekton, Bazel 缓存, Nexus, `Harbor-OnPrem`** | **Testbed App** |
| **Staging** | **云 (Cloud)** | **K8s 集群 (Cloud)** | **`ArgoCD-Cloud`, `Harbor-Cloud`** | **Staging App** |
| **Production** | **云 (Cloud)** | **K8s 集群 (Cloud)** | `ArgoCD-Cloud`, `Harbor-Cloud` | **Production App** |

### 2 关键组件的部署策略

1.  **Rancher (统一管理层):**
    * Rancher UI 部署在任一集群（推荐 Cloud）。
    * Rancher **导入并管理** `K8s On-Prem` 和 `K8s Cloud` 两个集群。
    * **价值：** 运维团队拥有一个**单一入口**来管理所有环境、部署应用（通过 Rancher App Catalog）和配置 RBAC 权限。

2.  **BuildKite Agent (CI 执行器):**
    * Agent **只部署在 `K8s On-Prem` 集群**。
    * **价值 (安全/效率)：** 源代码永远不会离开您的本地网络进行编译或测试。Agent 访问 `Nexus-OnPrem` 速度极快。

3.  **Harbor (镜像仓库 - 关键桥梁):**
    * **`Harbor-OnPrem`：** 部署在本地 K8s。Tekton/Bazel/Kaniko 在本地构建完镜像后，**推送**到这里。`ArgoCD-OnPrem` 从这里拉取镜像部署到 Testbed。
    * **`Harbor-Cloud`：** 部署在云端 K8s。`Staging` 和 `Production` 集群从这里拉取镜像。
    * **Harbor 复制 (Replication)：**
        * 我们配置一个**复制规则**：当 Testbed 测试通过后（例如 BuildKite 审批后），**Harbor-OnPrem 自动将该镜像标签复制（推送）到 Harbor-Cloud**。
        * 这是连接本地网络和云端环境的**安全制品通道**。

4.  **ArgoCD (GitOps 引擎):**
    * **`ArgoCD-OnPrem`：** 部署在本地 K8s，只负责监控 GitOps 仓库中的 `testbed/` 目录，并将应用部署到 `Testbed` 环境。
    * **`ArgoCD-Cloud`：** 部署在云端 K8s，负责监控 `staging/` 和 `production/` 目录，并将应用部署到相应环境。

5.  **Terraform (IaC):**
    * 您的 Terraform 代码库将分为两个主要工作区：
        * **`tf-onprem`：** 负责创建本地 K8s 集群、Nexus、`Harbor-OnPrem` 等。
        * **`tf-cloud`：** 负责创建云端 VPC、TKE/ACK 集群、`Harbor-Cloud` 等。

### 3. 细化后的完整流程 (Hybrid + Efficient)

1.  **Commit (On-Prem):** 开发者 `git push` 到本地 GitLab。
2.  **Webhook $\to$ BuildKite (Cloud):** GitLab 通知 BuildKite SaaS。
3.  **Bootstrap (On-Prem):** BuildKite 调度一个 **Bootstrap Agent**（在 `K8s On-Prem`）。
4.  **Dynamic Pipeline (On-Prem):** Agent 运行 `bazel query` 分析变更，并动态上传一个**最小化的 Tekton 流水线**。
5.  **CI 运行 (On-Prem):** BuildKite 调度 Tekton 在 `K8s On-Prem` 上运行 Lint、Test、Build 任务。
    * 依赖从 **`Nexus-OnPrem`** 拉取。
    * 构建由 **Bazel** (使用 On-Prem 缓存) 高效完成。
    * 镜像由 **Kaniko** 打包并推送到 **`Harbor-OnPrem`**。
6.  **更新 Testbed (On-Prem):** 最后一个 Tekton 任务更新 **GitOps 仓库**中的 `testbed/` 目录。
7.  **部署 Testbed (On-Prem):** **`ArgoCD-OnPrem`** 检测到变更，从 `Harbor-OnPrem` 拉取镜像，部署到 `Testbed`。
8.  **（E2E 测试运行...）**
9.  **晋升 Staging (On-Prem $\to$ Cloud):**
    * QA 在 BuildKite 上点击 **"Approve"**。
    * BuildKite 触发两个动作：
        1.  **Harbor 复制：** `Harbor-OnPrem` 将镜像推送到 `Harbor-Cloud`。
        2.  **GitOps 更新：** 更新 GitOps 仓库中的 `staging/` 目录。
10. **部署 Staging (Cloud):**
    * **`ArgoCD-Cloud`** 检测到变更。
    * 它从 **`Harbor-Cloud`** 拉取新镜像，并将其部署到 `K8s Cloud` 集群的 `Staging` 命名空间。
11. **晋升 Production (Cloud):** 重复 Staging 的审批和 GitOps 流程，将应用部署到 `Production` 命名空间。

## 8. 持续运维与反馈 (CO/CF) - 修订版

### 8.1 可观测性分层架构

#### 层级 1: 集群级监控 (Rancher 原生)
| 组件 | 来源 | 职责 |
|------|------|------|
| **Prometheus** | Rancher Monitoring | 集群资源监控 (CPU/内存/磁盘) |
| **AlertManager** | Rancher Monitoring | 基础设施告警 (节点宕机、Pod重启) |
| **Grafana** | Rancher 内置 | 单集群快速查看 |

#### 层级 2: 平台级聚合 (独立部署)
| 组件 | 部署位置 | 职责 |
|------|---------|------|
| **Grafana Cloud/Mimir** | Cloud (SaaS或自建) | 跨集群指标聚合、长期存储 |
| **Loki** | On-Prem & Cloud | 日志聚合 (Rancher Logging 后端) |
| **Grafana (中心)** | Cloud | 统一可视化入口 |

#### 层级 3: 应用级可观测 (APM)
| 组件 | 部署位置 | 职责 |
|------|---------|------|
| **Jaeger/Tempo** | Cloud | 分布式追踪 |
| **OpenTelemetry Collector** | 各K8s集群 | 应用指标/日志/追踪采集 |
| **Sentry** | SaaS | 错误追踪与前端性能 |

### 8.2 与 Rancher 的集成方式

```yaml
# Rancher Monitoring 配置
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: rancher-monitoring-prometheus
spec:
  # 保留本地查询能力
  retention: 7d
  
  # 远程写入到中心化存储
  remoteWrite:
  - url: https://mimir.example.com/api/v1/push
    queueConfig:
      capacity: 10000
      maxShards: 50
```

### 8.3 职责划分

| 角色 | 使用的工具 | 场景 |
|------|-----------|------|
| **K8s 运维** | Rancher UI + Monitoring | 日常巡检、快速排查 |
| **SRE 团队** | 中心 Grafana + PagerDuty | 跨集群分析、容量规划 |
| **开发团队** | Jaeger + Sentry | 应用性能调优、Bug追踪 |
| **产品经理** | 自定义业务 Dashboard | 业务指标监控 |

## 9. 安全加固方案

### 9.1 镜像安全

- **OPA/Kyverno**：准入控制策略
  - 强制要求镜像来自 Harbor
  - 拒绝 Critical/High 漏洞的镜像部署
- **Cosign**：镜像签名与验证
  ```bash
  # Tekton 流水线中签名
  cosign sign --key cosign.key harbor.local/myapp:v1.2.3
  
  # K8s 准入控制器验证
  cosign verify --key cosign.pub harbor.local/myapp:v1.2.3
  ```

### 9.2 密钥管理

- **HashiCorp Vault**（推荐）或 **External Secrets Operator**
  - On-Prem: Vault 主节点
  - Cloud: Vault Agent Injector
  - 与 K8s ServiceAccount 集成

### 9.3 网络隔离

- **Cilium/Calico Network Policy**
  - Testbed 只允许来自 CI Pod 的流量
  - Staging/Prod 拒绝 On-Prem 直连（除 Harbor 复制）
- **Service Mesh (Istio/Linkerd)**
  - mTLS 加密集群内通信
  - 细粒度的访问控制

## 10. 高可用架构

### 10.1 控制平面 HA

| 服务 | HA 方案 | RTO | RPO |
|------|---------|-----|-----|
| **Rancher** | 3节点集群 + 外部 etcd | <5min | 0 |
| **Harbor** | 主从复制 + S3后端 | <10min | <1min |
| **ArgoCD** | 多副本 + Redis 哨兵 | <5min | 0 |
| **Nexus** | 主备热切换 + NFS | <15min | <5min |

### 10.2 跨云灾备

- **定期演练**：每季度一次 On-Prem 故障切换到 Cloud
- **Velero**：每日备份所有 K8s 资源到云端对象存储
- **Harbor 双向复制**：确保镜像在两地都有副本
- **GitOps 优势**：配置在 Git，天然多地容灾

### 10.3 监控告警

- **SLO 定义**：
  - CI 流水线可用性 > 99.5%
  - 部署成功率 > 99%
  - P95 部署时长 < 10min
- **告警分级**：P0/P1 直接触发 PagerDuty


## 11. 成本优化策略

### 11.1 云资源优化

- **Spot/Preemptible 实例**：
  - Staging 环境使用竞价实例（节省 60-90%）
  - Karpenter/Cluster Autoscaler 混合调度
- **资源配额**：
  - Namespace ResourceQuota 限制
  - LimitRange 防止资源滥用

### 11.2 缓存策略

- **Bazel 缓存分层**：
  - 热数据：Redis (7天)
  - 温数据：MinIO (30天)
  - 冷数据：S3 Glacier (90天后归档)
- **Harbor GC 策略**：
  - 自动清理 30 天未使用的镜像
  - 保留 Production 标签永久

### 11.3 效率指标

| 指标 | 目标 | 监控工具 |
|------|------|---------|
| 缓存命中率 | >85% | Bazel Metrics |
| 平均构建时长 | <5min | BuildKite Analytics |
| 云端成本 | 月环比<5% | Kubecost/CloudHealth |


## 12. 流程简化与规范

### 12.1 统一 GitOps 仓库结构

```
gitops-repo/
├── _base/                 # 通用模板
├── testbed/
│   ├── kustomization.yaml
│   └── patches/
├── staging/
│   └── kustomization.yaml
└── production/
    └── kustomization.yaml
```

### 12.2 RBAC 最佳实践

- **Rancher 项目隔离**：
  - CI/CD 团队：管理 Testbed
  - SRE 团队：管理 Staging/Prod
  - 开发团队：只读访问
  
- **ArgoCD RBAC**：
  ```yaml
  policy.csv: |
    p, role:dev, applications, get, */*, allow
    p, role:sre, applications, *, */prod-*, allow
  ```

### 12.3 自助服务平台

- **Backstage** 或 **Port**：
  - 开发者自助创建新服务模板
  - 一键生成 CI/CD 配置
  - 可视化环境状态

### 12.4 文档与培训

- 维护 Runbook 手册（故障处理指南）
- 录制操作视频（Harbor 复制、ArgoCD 回滚等）
- 季度培训新人


## 13. 全面测试体系

### 13.1 测试金字塔

```
          /\
         /E2E\          (少量，高置信度)
        /------\
       /集成测试 \       (适量，验证交互)
      /----------\
     /  单元测试   \     (大量，快速反馈)
    /--------------\
```

### 13.2 测试类型补充

- **性能测试**：k6/JMeter 在 Staging 定期执行
- **混沌工程**：Chaos Mesh 定期故障注入
- **安全测试**：OWASP ZAP API 扫描
- **契约测试**：Pact 验证微服务接口

### 13.3 测试数据管理

- **Testcontainers**：本地集成测试用
- **数据脱敏工具**：生产数据同步到测试环境前脱敏
- **测试数据即代码**：Git 管理种子数据


