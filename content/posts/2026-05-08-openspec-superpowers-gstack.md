---
categories: ["技术文章"]
title: "增强开发三件套OpenSpec + Superpowers + gstack"
date: 2026-05-08T14:24:57+08:00
lastmod: 2026-05-08T14:24:57+08:00
summary: "介绍 OpenSpec（规范定义）、Superpowers（执行流程）与 gstack（验证交付）三件套如何协同工作，解决 AI 写代码中的需求偏差、过程黑盒和缺环境验证等问题。"
tags: ["AI", "开发工具", "OpenSpec", "Superpowers", "gstack"]
---

生产里用 AI 写代码常见三类问题：**需求理解偏差**导致返工多、**执行过程黑盒**难审查、**缺真实环境验证**。本文介绍 OpenSpec + Superpowers + gstack 三件套如何串联解决这些问题。

## 核心分工

| 组件 | 层级 | 作用 |
|------|------|------|
| **OpenSpec** | 需求 / 规范 | 人机先在文档层对齐，减少返工 |
| **Superpowers** | 执行 / 流程 | 编码过程标准化、可观测、可审查 |
| **gstack** | 验证 / 交付 | 浏览器、QA、发版、监控等一键能力 |

一句话总结：**OpenSpec 管需求文档，Superpowers 管写代码流程，gstack 管验证与交付。**

## 1. OpenSpec：规范先于代码

OpenSpec 采用 **双目录模型**：
- `specs/`：当前系统的事实规范（SSOT）
- `changes/`：每次变更的完整提案

单次变更建议三份文件（人机契约，编码前先对齐）：

| 文件 | 内容 |
|------|------|
| `proposal.md` | 为何做、目标、成功标准 |
| `design.md` | 技术方案、接口与数据流 |
| `tasks.md` | 可执行任务清单（常作为 Superpowers 输入） |

实测显示，相同需求下 Token 约降 30%–50%，返工率明显下降。
**边界**：OpenSpec 只产出规范，**不直接写业务代码**。

## 2. Superpowers：不可跳过的执行链

定位为 **7 步工作流**（强调步骤顺序与完整性）：

| 步骤 | 含义 |
|------|------|
| brainstorming | 澄清假设与范围 |
| git worktree | 隔离分支，保护主干 |
| writing-plans | 拆成短时可完成的小任务 |
| subagent 执行 | 子任务分代理，隔离上下文 |
| TDD | RED → GREEN → REFACTOR |
| 代码审查 | 规范合规 + 质量 |
| 分支收尾 | 测过再合并，减少遗留 |

**边界**：按 `tasks.md` 执行编码流程；**不**替代浏览器验证与部署动作。

## 3. gstack：验证与交付命令

gstack 不做架构决策，封装日常动作：

- `/browse`：截图、元素检查、用户路径
- `/qa`：端到端测试
- `/ship`：发版前检查（base、测试、diff、CHANGELOG）
- `/land-and-deploy`：合并 PR、等 CI、验生产
- `/canary`：上线后错误与性能监控
- `/careful`：危险操作拦截（如 `rm -rf`、`DROP TABLE`、force-push）

**边界**：只做验证与交付，**不参与**需求分析或方案定稿。

## 4. 三者如何串联

信息在 **文件与命令** 间传递，而非隐式共享状态：

```text
需求 → OpenSpec（proposal / design / tasks）
         ↓ tasks.md
       Superpowers（brainstorm → worktree → 小任务 → subagent → TDD → review → 收尾）
         ↓ 代码产出
       gstack（/browse、/qa、/ship、/land-and-deploy、/canary）
         ↓
       生产
```

**完成定义**：无测试 / 截图 / QA 报告等证据，不视为完成。

## 5. 任务分流（参考档位）

- **只读**：分析、解释、读代码 → 直接答；真 bug 未改可用 systematic-debugging。
- **轻量**：单文件、小范围、明确修复 → 可跳过完整 brainstorming / worktree / 长 review；实现 + 定向验证 + 必要时 `/browse`。
- **中等**：多文件但边界清晰 → OpenSpec 提案 → 短 brainstorm + 短 plan → 实现 → `/browse` 或 `/qa` + verification。
- **大型**：跨模块、公共 API、新架构 → 全文闭环：OpenSpec → brainstorm → plans → worktree + TDD → `/qa` → verification → code-review → 分支收尾 → `/ship` → `/land-and-deploy` → `/canary`。

---
*本文源自微信公众号“笨小葱”（2026-04-23）剪藏内容的重排与精简。*
