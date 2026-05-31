#!/bin/bash
# test-llama-inference.sh
# 使用编译好的 llama-cli 验证 Qwen3 模型推理

LLAMA_CLI="/Users/ambrose/WorkBuddy/2026-05-31-task-4/llama.cpp/build/bin/llama-cli"
MODEL="/Users/ambrose/WorkBuddy/2026-05-31-task-4/llamachat/models/tinyllama-1.1b.Q4_K_M.gguf"

echo "===== Llama.cpp 推理测试 ====="
echo "模型: $MODEL"
echo "Prompt: 你好，请介绍一下自己"
echo ""

$LLAMA_CLI \
  -m "$MODEL" \
  -ngl 0 \
  -n 128 \
  --temp 0.7 \
  --top-p 0.9 \
  --no-display-prompt \
  -p "<|im_start|>user\n你好，请简单介绍一下自己<|im_end|>\n<|im_start|>assistant\n"

echo ""
echo "===== 测试完成 ====="
