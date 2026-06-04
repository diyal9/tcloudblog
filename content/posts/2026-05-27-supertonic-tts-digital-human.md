---
title: "Supertonic：99M 参数的本地 TTS，让数字人说话更自然"
date: 2026-05-27T10:25:04+08:00
lastmod: 2026-05-27T10:25:04+08:00
tags: ["TTS", "语音合成", "ONNX", "数字人", "开源工具", "Supertonic"]
categories: ["AI"]
summary: "Supertonic 是 Supertone 开源的轻量 TTS 系统，99M 参数、31 语言支持、ONNX 本地推理。本文分析其技术特点，并展示如何集成到数字人项目中替代 Web Speech API。"
---

## 问题背景

在开发 [VRM 数字人助手](https://github.com/diyal9/aibot-me) 时，语音合成（TTS）是关键一环。之前我一直用浏览器内置的 `speechSynthesis` API——零成本、零部署，但问题也很明显：

- **音质机械**：浏览器默认音色，听起来像导航软件
- **无情感控制**：无法加入呼吸、笑声、叹息等自然停顿
- **语言质量不可控**：不同操作系统/浏览器的 TTS 引擎差异巨大
- **无法定制音色**：不能给数字人设定专属声音

直到我发现了 [**Supertonic**](https://github.com/supertone-inc/supertonic)——一个完全本地运行、99M 参数、31 语言支持、由 ONNX Runtime 驱动的 TTS 系统。

## Supertonic 是什么？

Supertonic 由韩国公司 **Supertone** 开源，最新 v3 版本支持 **31 种语言**（含中、日、韩、英、法、德等），模型仅 99M 参数，完全本地推理，不需要 GPU，连树莓派都能跑。

### 核心指标对比

| 维度 | speechSynthesis | Supertonic 3 |
|------|:--------------:|:-----------:|
| 输出质量 | 浏览器默认 | 44.1kHz 16-bit WAV |
| 参数量 | N/A（系统级） | 99M |
| 情感控制 | ❌ | ✅ 10 种表情标签 |
| 声音定制 | ❌ | ✅ Voice Builder 克隆 |
| 部署 | 浏览器端 | 服务端 / 本地 |
| 语言一致性 | 系统/浏览器差异大 | 统一 31 语言 |
| 推理速度 | 即时 | RTF ~0.3x（比实时快 3 倍） |

## 技术架构

Supertonic 的核心技术来自三篇论文：

1. **SupertonicTTS**：flow matching 架构的 text-to-latent 模块
2. **LARoPE**：Length-Aware Rotary Position Embedding，改进文本-语音对齐
3. **Self-Purifying Flow Matching**：带噪声标签的鲁棒训练

```
文本 → Tokenizer → LARoPE 位置编码 → Flow Matching 模型 → 语音 Latent → Vocoder → 44.1kHz WAV
```

整个模型通过 ONNX Runtime 运行，支持 CPU、GPU、WebGPU 多种推理后端。

## 开箱即用体验

安装 Python SDK 后，4 行代码就能生成语音：

```python
from supertonic import TTS

tts = TTS(auto_download=True)  # 自动从 HuggingFace 下载模型
style = tts.get_voice_style(voice_name="M1")

wav, duration = tts.synthesize(
    text="你好，我是你的 AI 助手。",
    lang="na",           # 语言自适应
    voice_style=style,
    total_steps=8,       # 质量档位 5-12
)
tts.save_audio(wav, "output.wav")
```

首次运行会自动下载模型（~200MB ONNX 文件），之后完全离线运行。

## 本地 HTTP 服务

对于 Go/Node.js/其他语言的后端，Supertonic 提供了内置 HTTP Server：

```bash
pip install 'supertonic[serve]'
supertonic serve --host 0.0.0.0 --port 7788
```

启动后直接提供两个 API：
- `POST /v1/tts` — Supertonic 原生接口
- `POST /v1/audio/speech` — **OpenAI 兼容接口**（直接替换 OpenAI TTS 调用）

```bash
curl -X POST http://localhost:7788/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"input": "你好世界", "voice": "M1", "response_format": "wav"}' \
  --output speech.wav
```

这对现有项目的迁移极其友好——如果你的系统已经接了 OpenAI TTS API，改个 URL 就能切换。

## 表情标签：让数字人"活"起来

这是我最看重的功能。Supertonic 支持 10 种内联表情标签：

```
今天天气真<laugh>好呀，我们一起出去玩吧！<breath>
```

- `<laugh>` — 笑声
- `<breath>` — 呼吸/换气
- `<sigh>` — 叹息
- 以及其他 7 种

对于 VRM 数字人来说，这些标签不仅影响语音输出，还可以**同步驱动口型和表情**——检测到 `<laugh>` 时让数字人微笑，`<breath>` 时暂停口型动画。这是 `speechSynthesis` 完全做不到的。

## 集成到数字人项目的方案

### 方案对比

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|---------|
| **A. HTTP 代理** | 零改动后端，快速验证 | 多一次网络请求 | 快速原型 |
| **B. Go 原生** | 零网络开销，低延迟 | 需集成 ONNX Runtime Go | 生产环境 |
| **C. 混合模式** | speechSynthesis 保底，Supertonic 高质量 | 逻辑稍复杂 | 渐进迁移 |

### 推荐路径

```
阶段 1：HTTP 模式验证中文质量
  ↓
阶段 2：确认效果 → Go 原生集成（消除网络延迟）
  ↓
阶段 3：表情标签 + 口型同步联动
```

## 声音克隆

如果你想要数字人有专属音色，Supertone 提供了 [Voice Builder](https://supertonic.supertone.ai/voice-builder) 服务：

1. 录制 1-2 分钟参考音频
2. Voice Builder 生成版本特定的 JSON 音色文件
3. 下载到本地，Supertonic 加载后即可使用

**注意**：本地克隆管线未开源，声音克隆需要通过官方 Web 服务或 API。

## 性能实测

根据官方基准测试（Minimax-MLS-test），Supertonic 3 在多项语言上接近或超越更大的模型：

| 语言 | Supertonic 3 | VoxCPM2 (700M+) |
|------|:-----------:|:--------------:|
| 英语 (WER) | **2.06** | 2.11 |
| 日语 (CER) | **4.61** | 3.35 |
| 韩语 (CER) | **3.26** | 4.70 |
| 德语 (WER) | 0.86 | **0.85** |
| 法语 (WER) | 4.89 | **4.41** |

> 越低越好。WER = 词错误率，CER = 字符错误率。

99M 参数在 CPU 上的推理速度，甚至超过 0.7B-2B 模型在 A100 GPU 上的表现。

## 潜在问题

1. **中文质量未在表格中列出**：官方 WER 表没有中文数据，需要实际测试
2. **模型大小**：~200MB ONNX 文件，首次下载需要时间
3. **ONNX Runtime 依赖**：服务器需安装 `libonnxruntime`
4. **本地克隆未开源**：想用 Voice Builder 必须经过官方服务

## 总结

Supertonic 是目前最适合本地部署的开源 TTS 之一：

- ✅ **极小模型**（99M vs 行业 700M-2B）
- ✅ **CPU 实时推理**（树莓派都能跑）
- ✅ **31 语言**（含中日韩）
- ✅ **情感标签**（数字人必备）
- ✅ **OpenAI 兼容 API**（迁移成本极低）
- ✅ **声音克隆**（专属音色）

对于正在做数字人、语音助手、或任何需要本地 TTS 的项目，Supertonic 值得一试。我的下一步是把它集成到 [aibot-me](https://github.com/diyal9/aibot-me) 数字人项目中，替换掉现在的 `speechSynthesis`。

## 相关链接

- [GitHub: supertone-inc/supertonic](https://github.com/supertone-inc/supertonic)
- [Hugging Face 模型](https://huggingface.co/Supertone/supertonic-3)
- [在线 Demo](https://huggingface.co/spaces/Supertone/supertonic-3)
- [音频样例](https://supertonic3.github.io/)
- [Voice Builder](https://supertonic.supertone.ai/voice-builder)
- [Python SDK 文档](https://supertone-inc.github.io/supertonic-py/)
