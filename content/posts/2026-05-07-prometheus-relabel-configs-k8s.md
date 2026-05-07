---
title: "详解使用 relabel_configs 进行 K8s 资源动态服务发现"
date: 2026-05-07T19:00:00+08:00
lastmod: 2026-05-07T19:00:00+08:00
draft: false
categories: ["云原生", "运维", "可观测性"]
tags: ["Prometheus", "Kubernetes", "relabel_configs", "监控"]
author: "diyal9"
toc: true
description: "系统阐述 Prometheus 在 Kubernetes 中的监控配置，核心聚焦于如何通过 relabel_configs 实现对 Node、Pod、Endpoint 等资源的动态服务发现。"
---

在 Kubernetes 这样高度动态的环境中，Pod 的 IP 瞬息万变，Service 和 Node 的状态也随时可能切换。对于 Prometheus 而言，如何“找到”这些监控目标并正确抓取指标，是构建可观测性的第一道门槛。

静态配置（`static_configs`）在 K8s 面前显得捉襟见肘，而基于 Kubernetes API 的服务发现（`kubernetes_sd_configs`）结合强大的 **`relabel_configs`**，才是自动化监控的核心引擎。

本文将详细拆解 `relabel_configs` 的工作原理，并给出各类 K8s 资源的最佳配置实践。

## 一、Prometheus 服务发现：静态 vs 动态

在深入 `relabel` 之前，我们需要理解 Prometheus 在 K8s 中发现目标的几种方式：

1.  **静态配置 (Static Configs)**：
    适用于那些 IP 固定、数量极少的基础设施，例如集群外部的数据库、或者通过 Service 暴露的固定端点。
2.  **Kubernetes 服务发现 (kubernetes_sd_configs)**：
    这是 K8s 环境的主力。Prometheus 通过 API Server 监听 K8s 资源对象的变化。支持发现的角色包括：
    *   `Node`：集群节点。
    *   `Service`：服务。
    *   `Pod`：最细粒度的工作负载。
    *   `Endpoints` / `EndpointSlice`：服务背后的真实 IP 列表。
    *   `Ingress`：路由规则。

然而，服务发现只是“发现”了目标，默认情况下，Prometheus 会试图从 K8s 对象中提取大量元数据（Metadata），这往往不是我们想要的。**`relabel_configs` 的作用，就是在 Prometheus 决定“抓哪里”和“怎么抓”之前，对这些元数据进行清洗、过滤和转换。**

## 二、relabel_configs 核心概念

`relabel_configs` 本质上是一组**重写规则**。当服务发现产生了一个 Target 时，Prometheus 会按顺序执行这些规则。

### 核心动作 (Action)
| 动作 | 描述 | 典型应用场景 |
| :--- | :--- | :--- |
| **replace** | 将正则匹配到的源标签值替换到目标标签中 | 端口转换、构造 URL、提取信息 |
| **keep** | 保留匹配正则的目标，丢弃其余的 | 仅监控带有特定 Label 的 Pod |
| **drop** | 丢弃匹配正则的目标 | 排除系统组件、排除特定 Namespace |
| **labelmap** | 将匹配到的标签名提取并映射为新标签 | 将 K8s Labels 批量转为 Prometheus Labels |
| **hashmod** | 用于分片，通过哈希取模分配 Target | 联邦集群架构 |

### 关键参数
*   `source_labels`: 输入标签，通常是 `__meta_kubernetes_*` 系列。
*   `regex`: 正则表达式，用于匹配源标签的值。
*   `target_label`: 输出标签，如 `__address__`（决定抓取地址）或自定义标签。
*   `replacement`: 替换后的值，可以使用 `$1`, `$2` 引用正则捕获组。

## 三、K8s 资源监控配置实战

### 1. Node 节点监控
Node Exporter 通常运行在每个节点上。我们需要从 API 获取 Node 的 IP，并将其默认端口（10250）替换为 NodeExporter 暴露的端口（9100）。

```yaml
- job_name: 'kubernetes-nodes'
  kubernetes_sd_configs:
  - role: node
  relabel_configs:
  # 提取节点 IP (InternalIP) 作为 target address
  - action: replace
    source_labels: [__meta_kubernetes_node_address_type]
    regex: InternalIP
    target_label: __address__
    replacement: $1:9100 # 替换端口为 9100
```

### 2. API Server 监控
API Server 是集群的入口，通常作为 Endpoints 存在。我们需要使用 HTTPS 并配置认证。

```yaml
- job_name: 'kubernetes-apiservers'
  kubernetes_sd_configs:
  - role: endpoints
  scheme: https
  tls_config:
    ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
  relabel_configs:
  # 仅保留名为 kubernetes 的 Service
  - action: keep
    source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name]
    regex: default;kubernetes
```

### 3. 基于注解的 Pod/Service 监控
这是最灵活的通用模式。我们不监控所有 Pod，只监控那些在 Annotation 中明确声明了 `prometheus.io/scrape: "true"` 的目标。

```yaml
- job_name: 'kubernetes-pods'
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  # 1. 过滤：必须有 prometheus.io/scrape=true 注解
  - action: keep
    source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    regex: "true"

  # 2. 路径替换：如果指定了 prometheus.io/path，则使用它
  - action: replace
    source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
    regex: (.+)
    target_label: __metrics_path__

  # 3. 端口替换：如果指定了 prometheus.io/port，则使用它
  - action: replace
    source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
    regex: ([^:]+)(?::\d+)?;(\d+)
    replacement: $1:$2
    target_label: __address__

  # 4. 附加 K8s Labels 作为 Prometheus 标签，方便查询
  - action: labelmap
    regex: __meta_kubernetes_pod_label_(.+)
```

## 四、常见坑点与排查

在配置 `relabel_configs` 时，有几个常见问题容易导致配置失效：

1.  **kube-proxy 监听地址问题**：
    默认的 kube-proxy 可能只监听 `127.0.0.1`，导致 Prometheus 无法抓取 `/metrics` 接口。需要在 Kube-proxy 配置中将 `metricsBindAddress` 修改为 `0.0.0.0:10249`。
2.  **etcd 证书问题**：
    如果是 kubeadm 部署的集群，etcd 通常使用自签名证书。如果 Prometheus 没有挂载正确的 Secret 证书，`relabel` 即使成功，抓取也会因 TLS 握手失败而报错。
3.  **调试技巧**：
    在 Prometheus UI 的 **Service Discovery** 页面，可以查看每个 Job 发现的 Target 以及应用 `relabel` **之前 (Discovered Labels)** 和 **之后 (Target Labels)** 的标签对比。这是调试 `regex` 是否匹配错误的最高效手段。

## 五、总结

`relabel_configs` 是 Prometheus 适应复杂 K8s 环境的“变形金刚”。通过合理的配置，我们可以实现：
*   **按需监控**：通过 Label 或 Annotation 控制监控范围。
*   **动态感知**：无需重启 Prometheus 即可自动适应 Pod 扩缩容。
*   **标签丰富**：将 K8s 的业务属性（如 `app`, `env`）带入监控指标中。

掌握这套配置模式，是构建高可用、自动化云原生监控体系的基础。
