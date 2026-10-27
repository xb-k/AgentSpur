# DeepSeek Model Specifications & Pricing Guide

---

## 1. Model Overview & Specifications

| Feature / Parameter | DeepSeek-Flash | DeepSeek-V4-Pro |
| :--- | :--- | :--- |
| **Model ID** | `deepseek-flash` <sup>[1]</sup> | `deepseek-v4-pro` |
| **Base Model Version** | DeepSeek-V4.1-Flash-1017 | DeepSeek-V4-Pro-0813 |
| **Reasoning Mode** | Supported (Default ON; Switchable to Non-reasoning) | Supported (Default ON; Switchable to Non-reasoning) |
| **Context Window** | 1M Tokens | 1M Tokens |
| **Max Output Length** | 384K Tokens | 384K Tokens |
| **Vision Understanding** | **Supported** | Not Supported |
| **FIM Completion (Beta)** | Non-reasoning mode only | Non-reasoning mode only |
| **API Capabilities** | JSON Output, Tool Calls, Responses API, Anthropic API, Prompt Prefix Continuation (Beta) | JSON Output, Tool Calls, Responses API, Anthropic API, Prompt Prefix Continuation (Beta) |
| **Concurrency Limit** | 2,500 | 500 |

> **<sup>[1]</sup> Model Naming Note:** Please use `deepseek-flash` as the model name in requests. Legacy model names (`deepseek-v4-flash`, `deepseek-v4-flash-vision-exp`) remain callable, but the underlying legacy models have been retired. All requests using legacy names will be served by `DeepSeek-V4.1-Flash-1017` and billed at Flash rates.

---

## 2. API Endpoints (Base URLs)

- **OpenAI Compatible Format:** `https://api.deepseek.com`
- **Anthropic Compatible Format:** `https://api.deepseek.com/anthropic`

---

## 3. Tiered Pricing Table (RMB / Million Tokens)

### Time Window Definitions
- **Peak Hours:** Monday to Friday (excluding China statutory holidays), `09:00 - 12:00` and `14:00 - 18:00` (Beijing Time, UTC+8).
- **Off-Peak Hours:** All other times, including nights, weekends, and full days of China statutory holidays.
- **Off-Peak Discount:** Off-peak hours receive a **50% discount (half price)** compared to peak rates.

### Pricing Breakdown

| Category | Time Window | deepseek-flash | deepseek-v4-pro |
| :--- | :--- | :--- | :--- |
| **Input: Cache Read (Hit)** | Off-Peak | **¥0.02** / M tokens | **¥0.15** / M tokens |
| | Peak | **¥0.04** / M tokens | **¥0.30** / M tokens |
| **Input: Cache Miss** | Off-Peak | **¥1.00** / M tokens | **¥4.50** / M tokens |
| | Peak | **¥2.00** / M tokens | **¥9.00** / M tokens |
| **Output / Reasoning** | Off-Peak | **¥4.00** / M tokens | **¥13.50** / M tokens |
| | Peak | **¥8.00** / M tokens | **¥27.00** / M tokens |