---
title: "Langfuse 提升 LLM 和 Agents 的可观测性"
date: 2026-05-08T08:00:00+08:00
lastmod: 2026-05-08T08:00:00+08:00
tags: ["AI", "LLM", "Agent", "可观测性", "Langfuse", "OpenTelemetry"]
categories: ["AI"]
summary: "Langfuse 是一个开源 LLM 工程平台，提供强大的 Tracing 功能。本文介绍如何在 OpenAI、Anthropic 等 LLM 调用中集成 Langfuse，并结合 OpenAI Agents 框架实现单智能体、多智能体及工具调用的可观测性。"
---

## 概述

在日常使用大模型（LLM）和多智能体（Agents）时，我们常常需要追踪它们的响应情况和成本。**[Langfuse](https://langfuse.com/)** 作为一个开源 LLM 工程平台，提供了强大的 Tracing（追踪）功能，使开发者能够详细监控 LLM 的调用路径、输入输出、响应时间和成本等关键指标。

本文将介绍如何在 OpenAI 和 Anthropic 的 LLM 调用中集成 Langfuse，并通过 OpenAI Agents 框架展示单智能体、多智能体以及工具调用场景的可观测性实现。

## Langfuse 简介

Langfuse 是一个开源的大型语言模型（LLM）工程平台，专注于为开发者和研究人员提供灵活且高效的语言模型开发环境。它旨在解决 LLM 应用的工程化挑战，包括模型训练、部署、监控和优化等方面的问题。

### 主要特点

- **高度可定制化**：提供丰富的配置选项和灵活的 API 接口
- **高效资源管理**：轻松管理和调度各种计算资源
- **完善的监控运维体系**：内置强大的监控工具，实时掌握 LLM 运行状态
- **多功能支持**：包括 LLM 可观测性、提示管理、LLM 评估、数据集管理、指标分析等

## Langfuse 与 LLM

首先需要创建 Langfuse 账号，生成 `LANGFUSE_SECRET_KEY`、`LANGFUSE_PUBLIC_KEY` 和 `LANGFUSE_HOST` 环境变量。

### 1. 与 OpenAI 集成

Langfuse 已原生支持 OpenAI，调用方式非常简单：

```python
from dotenv import load_dotenv
from langfuse.decorators import observe
from langfuse.openai import openai

load_dotenv()

@observe()
def story():
    response = openai.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": "What is Langfuse?"}],
    )
    return response.choices[0].message.content

@observe()
def main():
    return story()

main()
```

Langfuse 的 **Tracing** 功能可以追踪 LLM 的响应情况与成本。通过 Tracing 面板，你可以看到：

- 调用路径（如 `main() -> story() -> OpenAI-generation`）
- 调用的模型与参数
- 响应时间
- 输入与输出 token 数量
- Token 成本

### 2. 与任意 LLM 集成

Langfuse 支持任意 LLM 的追踪。以 Anthropic Claude 为例：

```python
import os
from langfuse.decorators import observe, langfuse_context
import anthropic
from dotenv import load_dotenv

load_dotenv()

anthropic_client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

@observe(as_type="generation")
def anthropic_completion(**kwargs):
    kwargs_clone = kwargs.copy()
    _input = kwargs_clone.pop('messages', None)
    model = kwargs_clone.pop('model', None)
    langfuse_context.update_current_observation(
        input=_input, model=model, metadata=kwargs_clone
    )
    response = anthropic_client.messages.create(**kwargs)
    langfuse_context.update_current_observation(
        usage_details={
            "input": response.usage.input_tokens,
            "output": response.usage.output_tokens
        }
    )
    return response.content[0].text

@observe()
def main():
    return anthropic_completion(
        model="claude-3-opus-20240229",
        max_tokens=1024,
        messages=[{"role": "user", "content": "Hello, Claude"}]
    )
```

通过 `@observe` 装饰器和 `langfuse_context`，你可以追踪 message、model、输入输出 token 等参数。

### 3. 自定义配置

Langfuse 支持自定义任务名称、`trace_id`、`session_id` 等信息：

```python
from langfuse import Langfuse

def story(**kwargs):
    langfuse = Langfuse(environment="development")
    trace = langfuse.trace(
        id=kwargs.get("langfuse_observation_id"),
        name=kwargs.get("name"),
        tags=kwargs.get("tags"),
        session_id=kwargs.get("session_id")
    )
    generation = trace.generation(
        name="my-first-generation",
        model="gpt-4o",
        model_parameters={"maxTokens": 1000, "temperature": 0.5},
        input=[{"role": "user", "content": "What is Langfuse?"}]
    )
    # ... LLM call ...
    generation.end(output=response, usage_details=response.usage)
```

## Langfuse 与 Agents

OpenAI 开源的 [openai-agents-python](https://github.com/openai/openai-agents-python) 框架允许快速创建多智能体应用。安装命令：

```bash
pip install openai-agents
```

Langfuse 可以通过 **OpenTelemetry (OTLP)** 与 OpenAI Agents SDK 集成：

```python
import base64
import logfire
from agents import Agent, Runner

LANGFUSE_AUTH = base64.b64encode(
    f"{os.environ.get('LANGFUSE_PUBLIC_KEY')}:{os.environ.get('LANGFUSE_SECRET_KEY')}".encode()
).decode()

os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"] = os.environ.get("LANGFUSE_HOST") + "/api/public/otel"
os.environ["OTEL_EXPORTER_OTLP_HEADERS"] = f"Authorization=Basic {LANGFUSE_AUTH}"

logfire.configure(service_name='my_agent_service', send_to_logfire=False)
logfire.instrument_openai_agents()
```

### 单智能体（Single Agent）

```python
agent = Agent(name="Assistant", instructions="You are a helpful assistant.")
result = await Runner.run(agent, "What is the capital of France?")
```

### 多智能体（Multi Agents）

构建多个 Agent 并设置 Handoff：

```python
zh2en_agent = Agent(name="Chinese to English agent", instructions="Translate Chinese to English.")
en2zh_agent = Agent(name="English to Chinese agent", instructions="Translate English to Chinese.")

translation_agent = Agent(
    name="Translation agent",
    instructions="Translate between Chinese and English.",
    handoffs=[zh2en_agent, en2zh_agent],
)

result = await Runner.run(translation_agent, input="The Shawshank Redemption")
```

Langfuse 可以清晰追踪 Agent 之间的 Handoff 流程。

### 带工具调用的多智能体（Function Calling）

```python
from agents import function_tool

@function_tool
def get_weather(city: str) -> str:
    return f"The weather in {city} is sunny."

@function_tool
def get_now_time() -> str:
    return f"The current time is {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}."

weather_agent = Agent(name="Weather agent", tools=[get_weather])
time_agent = Agent(name="Time agent", tools=[get_now_time])

agent = Agent(
    name="Agent",
    instructions="You are a helpful agent.",
    handoffs=[weather_agent, time_agent],
)
```

Langfuse 可以记录工具调用的参数与输出，完整追踪智能体的决策路径。

## 总结

Langfuse 作为开源 LLM 工程平台，提供了强大的 Tracing 功能，可监控调用路径、输入输出、响应时间和成本。通过 `@observe` 装饰器和 OpenTelemetry 集成，开发者可以：

- **追踪 LLM 调用**：无论是 OpenAI 还是 Anthropic 模型
- **监控 Agent 行为**：单智能体、多智能体 Handoff、工具调用
- **成本管理**：实时掌握 token 用量与费用

对于需要生产级可观测性的 LLM 应用，Langfuse 是一个值得考虑的选择。
