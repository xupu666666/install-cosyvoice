#!/bin/bash

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 设置日志文件
LOG_FILE="install_log.txt"
exec 1> >(tee -a "$LOG_FILE") 2>&1

echo -e "${GREEN}开始安装 CosyVoice...${NC}"
echo "安装开始时间: $(date)"

# 检查系统要求
echo -e "${GREEN}检查系统要求...${NC}"
if ! command -v git &> /dev/null; then
    echo -e "${RED}未安装git，正在安装...${NC}"
    sudo apt-get update && sudo apt-get install -y git
fi

# 检查NVIDIA显卡和CUDA
echo -e "${GREEN}检查NVIDIA显卡和CUDA环境...${NC}"
if ! command -v nvidia-smi &> /dev/null; then
    echo -e "${RED}未检测到NVIDIA显卡或驱动${NC}"
    echo -e "${YELLOW}请先安装NVIDIA驱动和CUDA 12.0或更高版本${NC}"
    exit 1
fi

CUDA_VERSION=$(nvidia-smi | grep "CUDA Version" | awk '{print $9}' | cut -d'.' -f1)
echo -e "${GREEN}检测到CUDA版本: ${CUDA_VERSION}${NC}"

# 检查CUDA版本是否满足要求
if [ "${CUDA_VERSION}" -lt "12" ]; then
    echo -e "${RED}CUDA版本过低，CosyVoice需要CUDA 12.0或更高版本${NC}"
    echo -e "${YELLOW}当前CUDA版本: ${CUDA_VERSION}${NC}"
    exit 1
fi

# 检查是否安装了conda
if ! command -v conda &> /dev/null; then
    echo -e "${RED}未检测到conda，请先安装Anaconda或Miniconda${NC}"
    echo -e "${YELLOW}可以从 https://docs.conda.io/en/latest/miniconda.html 下载安装${NC}"
    exit 1
fi

# 检查磁盘空间
FREE_SPACE=$(df -h . | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "${FREE_SPACE%.*}" -lt 50 ]; then
    echo -e "${RED}警告: 可用磁盘空间不足50GB${NC}"
    echo -e "${YELLOW}当前可用空间: ${FREE_SPACE}GB${NC}"
    echo -e "${YELLOW}继续安装...${NC}"
fi

# 克隆仓库
echo -e "${GREEN}克隆CosyVoice仓库...${NC}"
if [ -d "CosyVoice" ]; then
    echo -e "${YELLOW}CosyVoice目录已存在，正在更新...${NC}"
    cd CosyVoice
    git pull
    git submodule update --init --recursive
else
    git clone --recursive https://github.com/FunAudioLLM/CosyVoice.git
    cd CosyVoice
    git submodule update --init --recursive
fi

# 创建并激活conda环境
echo -e "${GREEN}创建conda环境...${NC}"
if conda env list | grep -q "cosyvoice"; then
    echo -e "${YELLOW}conda环境已存在，正在重新创建...${NC}"
    conda deactivate
    conda env remove -n cosyvoice -y
fi

conda create -n cosyvoice python=3.10 -y
eval "$(conda shell.bash hook)"
conda activate cosyvoice

# 安装所有依赖
echo -e "${GREEN}安装所有依赖...${NC}"

# 1. 系统依赖
apt-get update
apt-get install -y sudo sox libsox-dev

# 2. Conda 依赖
conda install -y -c conda-forge pynini==2.1.5

# 3. Python 依赖
pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com

# 创建模型目录
mkdir -p pretrained_models

# 安装modelscope
echo -e "${GREEN}安装modelscope...${NC}"
pip install modelscope -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com

# 创建下载模型的Python脚本
echo -e "${GREEN}创建模型下载脚本...${NC}"
cat > download_models.py << 'EOL'
from modelscope import snapshot_download

def download_model(model_id, local_dir):
    print(f"下载模型: {model_id}")
    try:
        snapshot_download(model_id, local_dir=local_dir)
        print(f"成功下载模型: {model_id}")
    except Exception as e:
        print(f"下载模型 {model_id} 时出错: {str(e)}")

models = [
    ('iic/CosyVoice2-0.5B', 'pretrained_models/CosyVoice2-0.5B'),
    ('iic/CosyVoice-300M', 'pretrained_models/CosyVoice-300M'),
    ('iic/CosyVoice-300M-25Hz', 'pretrained_models/CosyVoice-300M-25Hz'),
    ('iic/CosyVoice-300M-SFT', 'pretrained_models/CosyVoice-300M-SFT'),
    ('iic/CosyVoice-300M-Instruct', 'pretrained_models/CosyVoice-300M-Instruct'),
    ('iic/CosyVoice-ttsfrd', 'pretrained_models/CosyVoice-ttsfrd')
]

if __name__ == "__main__":
    for model_id, local_dir in models:
        download_model(model_id, local_dir)
EOL

# 下载预训练模型
echo -e "${GREEN}开始下载预训练模型...${NC}"
python download_models.py

# 安装ttsfrd
echo -e "${GREEN}安装ttsfrd...${NC}"
if [ ! -d "pretrained_models/CosyVoice-ttsfrd" ]; then
    echo -e "${RED}等待模型下载完成...${NC}"
    exit 1
fi
cd pretrained_models/CosyVoice-ttsfrd/
unzip resource.zip -d .
pip install ttsfrd_dependency-0.1-py3-none-any.whl
pip install ttsfrd-0.4.2-cp310-cp310-linux_x86_64.whl

cd ../../

# 验证GPU是否可用
echo -e "${GREEN}验证PyTorch GPU支持...${NC}"
python3 -c "import torch; print('GPU可用：', torch.cuda.is_available()); print('GPU数量：', torch.cuda.device_count()); print('GPU名称：', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'None')"

# 检查关键依赖是否安装成功
echo -e "${GREEN}检查关键依赖...${NC}"
python3 -c "
try:
    import torch
    import gradio
    import librosa
    import modelscope
    import transformers
    import numpy
    import scipy
    import pandas
    import nltk
    import pypinyin
    import zhconv
    import unidecode
    import tensorrt
    import pynini
    import deepspeed
    import onnxruntime
    import conformer
    import diffusers
    import hydra
    import omegaconf
    import lightning
    print('检查PyTorch CUDA是否可用:', torch.cuda.is_available())
    print('检查CUDA版本:', torch.version.cuda)
    print('${GREEN}所有关键依赖检查通过！${NC}')
except ImportError as e:
    print('${RED}依赖检查失败：', str(e), '${NC}')
    exit(1)
except Exception as e:
    print('${RED}其他错误：', str(e), '${NC}')
    exit(1)
"

echo -e "${GREEN}安装完成！${NC}"

# 切换到正确的目录
cd /workspace/CosyVoice

echo -e "${GREEN}使用以下命令启动Web界面：${NC}"
echo -e "${GREEN}conda activate cosyvoice${NC}"
echo -e "${GREEN}cd /workspace/CosyVoice  # 确保在正确的目录下${NC}"
echo -e "${GREEN}python3 webui.py --port 50000 --model_dir pretrained_models/CosyVoice-300M${NC}"

# 检查webui.py是否存在
if [ ! -f "webui.py" ]; then
    echo -e "${RED}错误: webui.py 文件不存在${NC}"
    echo -e "${YELLOW}请确保您在 CosyVoice 目录下：${NC}"
    echo -e "${YELLOW}cd /workspace/CosyVoice${NC}"
    exit 1
fi

echo "安装结束时间: $(date)" >> "$LOG_FILE" 
