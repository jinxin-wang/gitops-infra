# 网络设计

## 1. 网络架构概览

### 1.1 整体网络拓扑

```
                          ┌─────────────────────────────────────┐
                          │         Internet                    │
                          └──────────────┬──────────────────────┘
                                         │
                          ┌──────────────▼──────────────────────┐
                          │   云厂商负载均衡器 (SLB/CLB)        │
                          │   • 公网IP: xxx.xxx.xxx.xxx         │
                          │   • 端口: 80/443                    │
                          │   • SSL终止                          │
                          └──────────────┬──────────────────────┘
                                         │
                          ┌──────────────▼──────────────────────┐
                          │   K3s Ingress Controller            │
                          │   • Traefik (K3s内置)               │
                          │   • 路由规则管理                     │
                          │   • TLS证书绑定                      │
                          └──────────────┬──────────────────────┘
                                         │
                ┌────────────────────────┼────────────────────────┐
                │                        │                        │
    ┌───────────▼──────────┐ ┌──────────▼──────────┐ ┌──────────▼──────────┐
    │   K3s Master Node    │ │  K3s Worker Node 1   │ │  K3s Worker Node 2   │
    │   10.0.1.10          │ │  10.0.1.11           │ │  10.0.1.12           │
    ├──────────────────────┤ ├──────────────────────┤ ├──────────────────────┤
    │ • etcd               │ │ • App Pods           │ │ • App Pods           │
    │ • API Server         │ │ • Harbor             │ │ • Platform Services  │
    │ • Controller Manager │ │ • ArgoCD             │ │ • Monitoring         │
    │ • Scheduler          │ │                      │ │                      │
    └──────────────────────┘ └──────────────────────┘ └──────────────────────┘
                │                        │                        │
                └────────────────────────┼────────────────────────┘
                                         │
                          ┌──────────────▼──────────────────────┐
                          │   Flannel Overlay Network           │
                          │   • Pod CIDR: 10.42.0.0/16          │
                          │   • Service CIDR: 10.43.0.0/16      │
                          │   • VXLAN封装                        │
                          └─────────────────────────────────────┘
```

### 1.2 网络分层

```yaml
第一层 - 物理/云网络层:
  功能: 云服务器之间的基础网络连接
  技术: VPC (Virtual Private Cloud)
  CIDR: 10.0.0.0/16
  
第二层 - K3s节点网络:
  功能: K3s节点间通信
  技术: 云厂商VPC子网
  CIDR: 10.0.1.0/24
  
第三层 - Pod网络:
  功能: Pod之间的通信
  技术: Flannel CNI (VXLAN)
  CIDR: 10.42.0.0/16
  
第四层 - Service网络:
  功能: 服务发现和负载均衡
  技术: Kubernetes Service (ClusterIP/NodePort/LoadBalancer)
  CIDR: 10.43.0.0/16
  
第五层 - Ingress层:
  功能: 外部流量路由到集群内部服务
  技术: Traefik Ingress Controller
```

## 2. IP地址规划

### 2.1 网络CIDR分配

| 网络类型 | CIDR | 地址数量 | 用途 |
|---------|------|---------|------|
| **VPC网络** | 10.0.0.0/16 | 65,536 | 整个云环境 |
| **节点子网** | 10.0.1.0/24 | 256 | K3s节点 |
| **Pod网络** | 10.42.0.0/16 | 65,536 | Pod IP分配 |
| **Service网络** | 10.43.0.0/16 | 65,536 | Service ClusterIP |

### 2.2 节点IP分配

```yaml
K3s Master节点:
  私有IP: 10.0.1.10
  公网IP: 通过NAT网关或弹性公网IP
  用途: 
    - K3s控制平面
    - etcd数据存储
    - API Server入口

K3s Worker节点1:
  私有IP: 10.0.1.11
  公网IP: 无（通过NAT访问外网）
  用途:
    - Harbor镜像仓库
    - ArgoCD控制器
    - GitLab Runner

K3s Worker节点2:
  私有IP: 10.0.1.12
  公网IP: 无（通过NAT访问外网）
  用途:
    - Prometheus监控
    - Grafana可视化
    - 应用Pod

预留IP:
  10.0.1.13-20: 未来扩展Worker节点
  10.0.1.21-30: 其他基础设施（如跳板机、堡垒机）
```

### 2.3 Service端口分配

| 服务 | 类型 | ClusterIP | 端口 | 外部访问 |
|------|------|-----------|------|---------|
| **Harbor** | ClusterIP | 10.43.x.x | 80 | Ingress (harbor.example.com) |
| **ArgoCD Server** | ClusterIP | 10.43.x.x | 80 | Ingress (argocd.example.com) |
| **Grafana** | ClusterIP | 10.43.x.x | 3000 | Ingress (grafana.example.com) |
| **Prometheus** | ClusterIP | 10.43.x.x | 9090 | Ingress (prometheus.example.com) |
| **K3s API Server** | NodePort | 10.43.0.1 | 6443 | Master节点:6443 |

## 3. 网络通信流程

### 3.1 外部访问应用流程

```
用户浏览器 (https://app.example.com)
    ↓ DNS解析
    ↓ (返回负载均衡器公网IP)
    ↓
云厂商负载均衡器 (443端口)
    ↓ SSL终止，转发到后端
    ↓
K3s Ingress Controller (Traefik)
    ↓ 根据Host头路由
    ↓
Service (ClusterIP: 10.43.x.x:80)
    ↓ kube-proxy负载均衡
    ↓
Pod (10.42.x.x:8000)
    ↓
应用容器响应
```

### 3.2 Pod间通信流程

```
Pod A (10.42.1.5) → Pod B (10.42.2.10)
    ↓
查询Service DNS (myapp.default.svc.cluster.local)
    ↓
CoreDNS返回Service ClusterIP (10.43.x.x)
    ↓
kube-proxy IPVS规则转发
    ↓
Flannel VXLAN封装
    ↓
跨节点传输
    ↓
目标节点Flannel解封装
    ↓
Pod B接收流量
```

### 3.3 Pod访问外网流程

```
Pod (10.42.x.x)
    ↓
通过宿主机路由
    ↓
宿主机网卡 (10.0.1.x)
    ↓
云厂商NAT网关
    ↓
公网
    ↓
外部服务 (如Docker Hub, GitHub)
```

### 3.4 外部访问K3s API Server

```
kubectl客户端
    ↓
Master节点公网IP:6443
    ↓ (或通过负载均衡器)
    ↓
K3s API Server (10.0.1.10:6443)
    ↓ TLS认证
    ↓
etcd数据库
```

## 4. CNI网络插件

### 4.1 Flannel配置

```yaml
CNI插件: Flannel (K3s默认)
网络模式: VXLAN
Pod CIDR: 10.42.0.0/16

特性:
  ✅ 简单易用，K3s默认集成
  ✅ 跨主机Pod通信
  ✅ 低延迟（相比其他隧道模式）
  ❌ 不支持NetworkPolicy（需额外配置）

配置文件: /etc/cni/net.d/10-flannel.conflist
```

### 4.2 网络性能

```yaml
延迟:
  - 同节点Pod通信: <1ms
  - 跨节点Pod通信: 2-5ms (VXLAN封装开销)
  - 通过Service访问: +0.5ms (kube-proxy转发)

带宽:
  - 理论上限: 节点网卡带宽 (1Gbps或更高)
  - VXLAN封装损耗: ~5-10%
  - 实际可用: 900Mbps+ (单节点)

并发连接:
  - Service连接池: 默认128K (可调整)
  - Pod端口范围: 32768-60999
```

### 4.3 未来升级路径

```yaml
阶段1 (当前): Flannel VXLAN
  - 满足初期需求
  - 简单可靠

阶段2 (6-12个月): Cilium
  - 条件: 微服务>30, 需要NetworkPolicy
  - 优势:
    ✅ 基于eBPF, 更高性能
    ✅ 内置NetworkPolicy
    ✅ 可观测性增强
    ✅ Service Mesh能力

阶段3 (12个月+): Cilium + Service Mesh
  - 条件: 复杂微服务架构
  - 优势:
    ✅ mTLS加密
    ✅ 流量管理
    ✅ 细粒度访问控制
```

## 5. 负载均衡

### 5.1 四层负载均衡

```yaml
云厂商SLB/CLB:
  类型: Layer 4 (TCP)
  协议: TCP:443 → NodePort:xxxxx
  健康检查: TCP端口探测
  会话保持: 基于源IP (可选)
  
用途:
  - HTTPS流量入口
  - 高可用性（跨AZ）
  - DDoS防护
  
配置示例:
  监听端口: 443
  后端端口: K3s NodePort (动态分配)
  健康检查间隔: 5秒
  健康检查阈值: 3次成功/2次失败
```

### 5.2 七层负载均衡

```yaml
Traefik Ingress Controller:
  类型: Layer 7 (HTTP/HTTPS)
  功能:
    - 基于域名路由
    - 基于路径路由
    - TLS证书管理
    - 中间件（限流、重试、熔断）
  
路由规则:
  - harbor.example.com → harbor-service:80
  - argocd.example.com → argocd-server:80
  - grafana.example.com → grafana:3000
  - *.example.com → default-backend

配置方式:
  - Kubernetes Ingress资源
  - Traefik IngressRoute CRD (可选)
```

### 5.3 Service类型选择

```yaml
ClusterIP (默认):
  用途: 集群内部服务
  示例: PostgreSQL, Redis, 内部API
  
NodePort:
  用途: 需要从集群外访问的服务
  示例: Ingress Controller后端
  端口范围: 30000-32767
  
LoadBalancer:
  用途: 云环境自动分配公网IP
  示例: 生产环境主入口 (可选)
  注意: 会产生额外费用
```

## 6. DNS配置

### 6.1 外部DNS

```yaml
云厂商DNS服务:
  域名: example.com
  
A记录:
  - harbor.example.com → SLB公网IP
  - argocd.example.com → SLB公网IP
  - grafana.example.com → SLB公网IP
  - *.example.com → SLB公网IP (泛域名)
  
TTL: 600秒 (10分钟)
```

### 6.2 集群内部DNS

```yaml
CoreDNS:
  版本: K3s内置
  配置文件: /etc/coredns/Corefile
  
解析规则:
  1. <service>.<namespace>.svc.cluster.local
     示例: harbor.harbor.svc.cluster.local
  
  2. <service>.<namespace>
     示例: harbor.harbor
  
  3. <service> (同namespace内)
     示例: harbor
  
  4. 外部域名 (转发到上游DNS)
     上游DNS: 云厂商DNS或8.8.8.8

DNS缓存: 30秒
```

### 6.3 DNS调试

```bash
# 在Pod内测试DNS解析
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
nslookup harbor.harbor.svc.cluster.local

# 查看CoreDNS日志
kubectl logs -n kube-system -l k8s-app=kube-dns

# 测试外部DNS
nslookup harbor.example.com
```

## 7. 防火墙与安全组

### 7.1 云厂商安全组规则

```yaml
入站规则 (Inbound):
  规则1:
    协议: TCP
    端口: 22
    源: 运维IP段 (例如: 公司办公网)
    说明: SSH管理访问
  
  规则2:
    协议: TCP
    端口: 80, 443
    源: 0.0.0.0/0
    说明: HTTP/HTTPS流量
  
  规则3:
    协议: TCP
    端口: 6443
    源: 运维IP段
    说明: K8s API Server访问
  
  规则4:
    协议: ALL
    源: 10.0.1.0/24
    说明: K3s节点间通信

出站规则 (Outbound):
  规则1:
    协议: ALL
    目标: 0.0.0.0/0
    说明: 允许所有出站流量（拉取镜像、依赖包）
```

### 7.2 NetworkPolicy (未来扩展)

```yaml
# 当前阶段: 不启用NetworkPolicy
# 原因: Flannel默认不支持，初期复杂度低

# 未来启用时的规则示例:

生产环境隔离:
  - production namespace的Pod只能:
    ✅ 访问同namespace内的服务
    ✅ 访问platform namespace的Harbor
    ❌ 不能访问dev/staging namespace

平台服务保护:
  - Harbor只允许:
    ✅ GitLab Runner推送镜像
    ✅ kubelet拉取镜像
    ❌ 应用Pod直接访问

数据库隔离:
  - PostgreSQL/Redis只允许:
    ✅ 特定应用Pod访问
    ❌ 其他Pod访问
```

### 7.3 端口开放策略

```yaml
最小权限原则:
  - 只开放必要的端口
  - 使用白名单模式
  - 定期审计开放端口

端口分类:
  公开端口 (0.0.0.0/0):
    - 80/443 (HTTP/HTTPS)
  
  受限端口 (运维IP):
    - 22 (SSH)
    - 6443 (K8s API)
  
  内部端口 (仅集群内):
    - 所有Service端口
    - 10250 (kubelet API)
    - 2379-2380 (etcd)
```

## 8. TLS/SSL配置

### 8.1 证书管理架构

```yaml
证书管理器: Cert-Manager
证书颁发机构: Let's Encrypt
验证方式: HTTP-01 或 DNS-01

证书自动化:
  1. Ingress注解触发证书申请
  2. Cert-Manager向Let's Encrypt请求证书
  3. 通过HTTP-01验证域名所有权
  4. 证书签发并存储到Secret
  5. Ingress自动引用证书
  6. 证书过期前30天自动续期
```

### 8.2 证书类型

```yaml
外部访问证书:
  域名: *.example.com (泛域名)
  类型: Let's Encrypt (免费)
  有效期: 90天 (自动续期)
  用途: 
    - harbor.example.com
    - argocd.example.com
    - grafana.example.com
  
集群内部证书:
  类型: 自签名 (K3s自动生成)
  用途:
    - K8s API Server
    - etcd集群通信
    - kubelet通信
  有效期: 1年 (K3s自动轮转)
```

### 8.3 TLS终止点

```yaml
方案1 (当前): 负载均衡器终止SSL
  流程:
    用户 --HTTPS--> SLB --HTTP--> Ingress --HTTP--> Pod
  优点:
    ✅ 减轻集群负载
    ✅ 利用云厂商SSL优化
  缺点:
    ❌ 内网流量未加密

方案2 (未来): 端到端加密
  流程:
    用户 --HTTPS--> SLB --HTTPS--> Ingress --HTTP--> Pod
  优点:
    ✅ 全链路加密
  缺点:
    ❌ 增加计算开销

推荐: 方案1 (初期) → 方案2 (合规要求高时)
```

## 9. 网络监控

### 9.1 监控指标

```yaml
节点网络:
  - 网卡流量 (bytes_in/bytes_out)
  - 丢包率 (packet_loss)
  - 错误数 (errors)
  - 延迟 (latency)

Pod网络:
  - Pod网络流量
  - 连接数 (TCP/UDP)
  - DNS查询延迟

Service:
  - 请求速率 (QPS)
  - 响应时间 (P50/P95/P99)
  - 错误率 (4xx/5xx)

采集方式:
  - Prometheus + node_exporter
  - Prometheus + kube-state-metrics
  - Traefik metrics
```

### 9.2 网络诊断工具

```bash
# 测试Pod间连通性
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash
ping <pod-ip>
curl <service-name>

# 查看Pod网络配置
kubectl exec -it <pod-name> -- ip addr
kubectl exec -it <pod-name> -- ip route

# 抓包分析
kubectl exec -it <pod-name> -- tcpdump -i eth0 -w /tmp/capture.pcap

# 查看Service端点
kubectl get endpoints <service-name>

# 查看kube-proxy规则
kubectl logs -n kube-system -l k8s-app=kube-proxy
```

### 9.3 告警规则

```yaml
高优先级告警:
  - 节点网络不可达 (持续1分钟)
  - DNS解析失败率 >10%
  - Service端点全部下线
  
中优先级告警:
  - 网络延迟 >100ms (P95)
  - 丢包率 >1%
  - 连接数 >10000
  
低优先级告警:
  - 网络流量异常 (超过基线2倍)
  - DNS查询缓慢 (>1秒)
```

## 10. 网络性能优化

### 10.1 当前优化措施

```yaml
1. 使用VXLAN模式 (低延迟):
   - 相比其他隧道模式延迟更低
   
2. 亲和性调度:
   - 相关服务Pod部署到同节点
   - 减少跨节点通信

3. Service负载均衡:
   - kube-proxy IPVS模式 (默认)
   - 比iptables性能更好

4. 连接复用:
   - HTTP Keep-Alive
   - gRPC连接池
```

### 10.2 未来优化方向

```yaml
短期 (3-6个月):
  - 启用Pod反亲和性（避免单点故障）
  - 配置Service拓扑感知路由
  - 优化DNS缓存时间

中期 (6-12个月):
  - 升级到Cilium CNI
  - 启用eBPF加速
  - 配置Service Mesh

长期 (12个月+):
  - 专用网络节点池
  - 多集群跨地域部署
  - CDN加速静态资源
```

### 10.3 网络瓶颈排查

```yaml
症状: Pod响应慢
排查步骤:
  1. 检查Pod资源限制 (CPU/内存是否到上限)
  2. 检查节点网络负载 (是否接近带宽上限)
  3. 检查跨节点延迟 (ping测试)
  4. 检查DNS解析时间 (nslookup)
  5. 检查Service端点健康状态
  
常见原因:
  - Pod CPU限流 → 增加CPU limits
  - DNS查询慢 → 增加CoreDNS副本
  - 跨节点通信 → 调整Pod亲和性
  - Service端点不健康 → 修复应用健康检查
```

## 11. 多环境网络隔离

### 11.1 命名空间网络隔离

```yaml
dev namespace:
  网络策略: 宽松（允许所有通信）
  目的: 快速开发调试
  
staging namespace:
  网络策略: 中等（允许同namespace + platform服务）
  目的: 模拟生产环境
  
production namespace:
  网络策略: 严格（白名单模式）
  目的: 最大化安全性
  
platform namespace:
  网络策略: 受保护（仅允许特定入站）
  目的: 保护基础设施
```

### 11.2 跨环境通信

```yaml
允许的通信:
  ✅ dev → platform (拉取镜像、访问Harbor)
  ✅ staging → platform
  ✅ production → platform
  ✅ 所有环境 → kube-dns (DNS解析)
  ✅ 所有环境 → 外网 (拉取依赖)

禁止的通信:
  ❌ dev → production
  ❌ staging → production
  ❌ production → dev/staging
  ❌ 应用Pod → etcd (直接访问)
```

## 12. 灾难恢复

### 12.1 网络故障场景

```yaml
场景1: 单节点网络故障
  影响: 该节点上的Pod不可用
  恢复: K8s自动重调度Pod到健康节点
  RTO: <5分钟
  
场景2: Master节点网络故障
  影响: API Server不可用，无法管理集群
  恢复: 故障转移到备用Master (未来HA配置)
  RTO: <15分钟
  
场景3: 云厂商网络故障
  影响: 整个集群不可用
  恢复: 切换到备用区域/集群
  RTO: <1小时 (需要人工干预)
```

### 12.2 网络配置备份

```yaml
备份对象:
  - K3s网络配置 (/etc/cni/net.d/)
  - CoreDNS配置 (ConfigMap)
  - Ingress规则 (kubectl导出)
  - 云厂商安全组规则 (自动化脚本)

备份频率: 每日
恢复测试: 每月
```

## 13. 参考资源

### 13.1 相关文档

- [Kubernetes网络模型](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- [Flannel文档](https://github.com/flannel-io/flannel)
- [K3s网络配置](https://docs.k3s.io/networking)
- [Traefik Ingress](https://doc.traefik.io/traefik/providers/kubernetes-ingress/)

### 13.2 网络CIDR计算器

- [CIDR计算器](https://www.subnet-calculator.com/)
- [IP地址规划工具](https://www.ipaddressguide.com/)

### 13.3 相关架构文档

- [架构概览](./overview.md)
- [安全设计](./security.md)
- [ADR-004: 网络插件选型](../adr/004-network-plugin-selection.md)

---

**文档版本**: v1.0  
**最后更新**: 2025-01-17  
**维护者**: DevOps Team  
**审阅周期**: 每季度
