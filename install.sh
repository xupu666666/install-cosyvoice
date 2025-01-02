#!/bin/bash

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}开始安装 CosyVoice...${NC}"

# 检查NVIDIA显卡和CUDA
echo -e "${GREEN}检查NVIDIA显卡和CUDA环境...${NC}"
if ! command -v nvidia-smi &> /dev/null; then
    echo -e "${RED}未检测到NVIDIA显卡或驱动${NC}"
    exit 1
fi

CUDA_VERSION=$(nvidia-smi --query-gpu=cuda_version --format=csv,noheader | head -n 1)
echo -e "${GREEN}检测到CUDA版本: ${CUDA_VERSION}${NC}"

# 检查是否安装了conda
if ! command -v conda &> /dev/null; then
    echo -e "${RED}未检测到conda，请先安装Anaconda或Miniconda${NC}"
    exit 1
fi

# 克隆仓库
echo -e "${GREEN}克隆CosyVoice仓库...${NC}"
git clone --recursive https://github.com/FunAudioLLM/CosyVoice.git
cd CosyVoice
git submodule update --init --recursive

# 创建conda环境
echo -e "${GREEN}创建conda环境...${NC}"
conda create -n cosyvoice python=3.10 -y
eval "$(conda shell.bash hook)"
conda activate cosyvoice

# 安装CUDA相关包
echo -e "${GREEN}安装CUDA相关包...${NC}"
conda install -y pytorch torchvision torchaudio pytorch-cuda=11.8 -c pytorch -c nvidia

# 安装pynini
echo -e "${GREEN}安装pynini...${NC}"
conda install -y -c conda-forge pynini==2.1.5

# 安装依赖
echo -e "${GREEN}安装Python依赖...${NC}"
pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com

# 检测系统类型并安装系统依赖
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case $ID in
        ubuntu|debian)
            echo -e "${GREEN}安装Ubuntu/Debian系统依赖...${NC}"
            sudo apt-get update
            sudo apt-get install -y sox libsox-dev
            ;;
        centos|rhel|fedora)
            echo -e "${GREEN}安装CentOS/RHEL系统依赖...${NC}"
            sudo yum install -y sox sox-devel
            ;;
        *)
            echo -e "${RED}未识别的操作系统，请手动安装sox和sox-devel${NC}"
            ;;
    esac
fi

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
cd pretrained_models/CosyVoice-ttsfrd/
unzip resource.zip -d .
pip install ttsfrd_dependency-0.1-py3-none-any.whl
pip install ttsfrd-0.4.2-cp310-cp310-linux_x86_64.whl

cd ../../

# 验证GPU是否可用
echo -e "${GREEN}验证PyTorch GPU支持...${NC}"
python3 -c "import torch; print('GPU可用：', torch.cuda.is_available()); print('GPU数量：', torch.cuda.device_count()); print('GPU名称：', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'None')"

echo -e "${GREEN}安装完成！${NC}"
echo -e "${GREEN}使用以下命令启动Web界面：${NC}"
echo -e "${GREEN}conda activate cosyvoice${NC}"
echo -e "${GREEN}python3 webui.py --port 50000 --model_dir pretrained_models/CosyVoice-300M${NC}"
