---
title: "Cursor + Infisical MCP：Agent 动态配置与密钥零信任实践"
date: 2026-05-11T08:30:00+08:00
lastmod: 2026-05-11T08:30:00+08:00
author: "diyal9"
categories: ["AI 工程化", "DevSecOps", "工具链"]
tags: ["Cursor", "Infisical", "MCP", "Secrets", "Go"]
---

## 痛点与方案

在 AI Agent 开发中，我们面临一个难题：**如何让 Agent 安全地获取敏感配置（如数据库密码、API Key）？**

传统的 `.env` 文件容易泄露，硬编码更是大忌。本文介绍如何利用 **Infisical**（开源 Secrets 管理）结合 **Cursor MCP**，打造一套“密钥不落地、环境秒切”的现代化开发流。

## 1. 为什么是 Infisical + MCP？

* **Infisical**：提供端到端加密的 Secrets 存储，支持多环境隔离（Dev/Test/Prod）和版本控制。
* **Cursor MCP**：让 AI 能够通过标准协议调用外部工具。

两者结合，Agent 不再是“盲猜”配置，而是**动态询问** Infisical 获取真实值，用完即焚，不落地磁盘。

## 2. 核心配置：接入 MCP

在项目根目录创建或修改 `.cursor/mcp.json`：

```json
{
  "mcpServers": {
    "infisical": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-infisical"],
      "env": {
        "INFISICAL_API_URL": "http://localhost:8080/api",
        "INFISICAL_TOKEN": "st.你的 Service Token",
        "INFISICAL_PROJECT_ID": "你的 Project ID",
        "INFISICAL_ENV_SLUG": "development"
      }
    }
  }
}
```
*注意：Token 务必使用只读权限，防止 Agent 误操作修改。*

## 3. 实战场景

### 场景 A：代码生成时注入真实值
你不需要手动复制密码。
* **Prompt**："帮我写 Go 的 MySQL 连接代码，请从 Infisical 获取 `DB_URL` 并初始化。"
* **Agent 行为**：自动调用 Infisical MCP -> 获取连接串 -> 生成代码 -> 完成。
* **优势**：代码直接可运行，无需人工干预配置，且本地磁盘不留明文。

### 场景 B：Cursor Skills 动态参数
在 `.cursor/rules/` 定义的 Skill 中，加入以下指令：
> "当编写涉及第三方服务的代码时，优先通过 `@Infisical` 工具拉取配置，严禁硬编码 Key。"

这样，每次 Skill 激活，Agent 都会自动拉取最新配置。

### 场景 C：一键切换环境
想测试 Staging 环境？
* **Prompt**："把环境切换到 Staging，帮我检查代码中的连接配置。"
* **Agent 行为**：修改 `mcp.json` 中的 `INFISICAL_ENV_SLUG` 为 `staging` -> 提示重启 -> 下次调用自动使用测试库。

## 4. 架构师建议

* **CI/CD 集成**：生产部署不要依赖 MCP，应使用 Infisical 的 **Service Token** 或 **Infisical Agent** 注入环境变量。
* **安全红线**：虽然 Agent 能拿到 Key，但必须配合 `.gitignore` 和 Code Review，确保生成的含密钥代码不被提交。

## 总结

Cursor + Infisical MCP 是 AI 时代的**配置管理最佳实践**。它让 Agent 从“工具”进化为“懂环境的协作者”，既安全又高效。
