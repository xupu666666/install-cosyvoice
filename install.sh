#!/bin/bash

# 设置日志文件
LOG_FILE="install_log.txt"
exec 1> >(tee -a "$LOG_FILE") 2>&1

echo "安装开始时间: $(date)" >> "$LOG_FILE"

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 如果安装失败，添加恢复提示
trap 'echo -e "${RED}安装失败。要清理环境，请运行：${NC}"; echo "conda deactivate && conda env remove -n cosyvoice -y"' ERR

# 显示安装进度的函数
show_step() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] 步骤 $1: $2${NC}"
}

echo -e "${GREEN}开始安装 CosyVoice...${NC}"

# 清理空间
show_step "1/7" "清理系统空间"
apt-get clean
apt-get autoremove -y
conda clean -a -y
rm -rf /tmp/*

# 显示可用空间
FREE_SPACE=$(df -h . | awk 'NR==2 {print $4}' | sed 's/G//')
echo -e "${GREEN}当前可用空间: ${FREE_SPACE}GB${NC}"

# 询问是否继续
read -p "是否继续安装？(y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# 检查 CUDA
if ! command -v nvidia-smi &> /dev/null; then
    echo -e "${RED}错误: 未检测到 NVIDIA GPU${NC}"
    exit 1
fi

# 检查 CUDA 版本
CUDA_VERSION=$(nvidia-smi | grep "CUDA Version" | awk '{print $9}' | cut -d'.' -f1)
if [ "${CUDA_VERSION}" -lt "12" ]; then
    echo -e "${RED}错误: CUDA 版本必须 >= 12.0${NC}"
    echo -e "${YELLOW}当前版本: ${CUDA_VERSION}${NC}"
    exit 1
fi

# 检查 conda
if ! command -v conda &> /dev/null; then
    echo -e "${RED}错误: 请先安装 conda${NC}"
    echo -e "${YELLOW}可以从这里下载: https://docs.conda.io/en/latest/miniconda.html${NC}"
    exit 1
fi

# 克隆仓库
show_step "2/7" "克隆仓库"
if [ ! -d "CosyVoice" ]; then
    git clone --recursive https://github.com/FunAudioLLM/CosyVoice.git
    cd CosyVoice
    git submodule update --init --recursive
else
    echo -e "${YELLOW}CosyVoice 目录已存在，跳过克隆${NC}"
    cd CosyVoice
fi

# 安装系统依赖
show_step "3/7" "安装系统依赖"
apt-get update
if ! apt-get install -y sox libsox-dev; then
    echo -e "${RED}系统依赖安装失败${NC}"
    exit 1
fi

# 创建并激活 conda 环境
show_step "4/7" "创建 conda 环境"
if conda env list | grep -q "cosyvoice"; then
    echo -e "${YELLOW}conda 环境已存在，正在重新创建...${NC}"
    conda deactivate
    conda env remove -n cosyvoice -y
fi

# 尝试多个可能的 conda 路径
if [ -f ~/miniconda3/etc/profile.d/conda.sh ]; then
    source ~/miniconda3/etc/profile.d/conda.sh
elif [ -f ~/anaconda3/etc/profile.d/conda.sh ]; then
    source ~/anaconda3/etc/profile.d/conda.sh
else
    echo -e "${RED}找不到 conda.sh，请确保 conda 安装正确${NC}"
    exit 1
fi

# 初始化 conda
conda init bash
source ~/.bashrc
# 确保 conda 命令生效
hash -r

conda create -n cosyvoice python=3.10 -y
conda activate cosyvoice

# 安装依赖
show_step "5/7" "安装依赖"

# 先安装基础依赖
conda install -y numpy scipy pandas scikit-learn matplotlib -c conda-forge

# 再安装 PyTorch
conda install -y pytorch torchvision torchaudio pytorch-cuda=12.1 -c pytorch -c nvidia

# 安装 pynini (WeTextProcessing 需要)
conda install -y -c conda-forge pynini==2.1.5

# 安装 modelscope
pip install modelscope -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com

# 分步安装关键依赖
if ! pip install -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com \
    gradio==4.32.2 \
    librosa==0.10.2 \
    transformers \
    soundfile==0.12.1 \
    tensorboard==2.14.0 \
    omegaconf==2.3.0 \
    hydra-core==1.3.2; then
    echo -e "${RED}关键依赖安装失败${NC}"
    exit 1
fi

# 确保所有依赖都被正确安装
if ! pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com; then
    echo -e "${RED}依赖完整性检查失败${NC}"
    exit 1
fi

# 下载模型
show_step "6/7" "下载模型"
mkdir -p pretrained_models
python3 -c "
from modelscope import snapshot_download
import time
MAX_RETRIES = 3
try:
    for attempt in range(MAX_RETRIES):
        try:
            snapshot_download('iic/CosyVoice-300M', local_dir='pretrained_models/CosyVoice-300M')
            print('模型下载完成')
            break
        except Exception as e:
            if attempt < MAX_RETRIES - 1:
                print(f'下载失败，{attempt + 1}/{MAX_RETRIES}次尝试')
                time.sleep(10)
            else:
                raise e
except Exception as e:
    print('模型下载失败:', str(e))
    exit(1)
"

# 验证安装
show_step "7/7" "验证安装"
python3 -c "
try:
    import torch
    import gradio
    import librosa
    import modelscope
    import pynini
    import transformers
    import numpy
    import scipy
    import pandas
    import soundfile
    import tensorboard
    import omegaconf
    import hydra
    # 验证 CUDA
    if not torch.cuda.is_available():
        raise RuntimeError('CUDA 不可用')
    # 验证 GPU 显存
    gpu_mem = torch.cuda.get_device_properties(0).total_memory / 1024**3
    if gpu_mem < 8:  # 需要至少 8GB 显存
        raise RuntimeError(f'GPU 显存不足: {gpu_mem:.1f}GB < 8GB')
    print('PyTorch CUDA 可用:', torch.cuda.is_available())
    print('PyTorch 版本:', torch.__version__)
    print('CUDA 版本:', torch.version.cuda)
    print('GPU 数量:', torch.cuda.device_count())
    if torch.cuda.is_available():
        print('GPU 型号:', torch.cuda.get_device_name(0))
        print('GPU 显存:', torch.cuda.get_device_properties(0).total_memory / 1024**3, 'GB')
    print('验证通过')
except ImportError as e:
    print('验证失败:', str(e))
    exit(1)
except Exception as e:
    print('其他错误:', str(e))
    exit(1)
"

echo -e "${GREEN}安装完成！${NC}"
echo -e "${GREEN}使用以下命令启动Web界面：${NC}"
echo -e "${GREEN}conda activate cosyvoice${NC}"
echo -e "${GREEN}python3 webui.py --port 50000 --model_dir pretrained_models/CosyVoice-300M${NC}"

echo "安装结束时间: $(date)" >> "$LOG_FILE"
