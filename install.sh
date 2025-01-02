
#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 错误处理
handle_error() {
    echo -e "${RED}错误: $1${NC}"
    exit 1
}

# 安装基础依赖
install_base_deps() {
    echo -e "${GREEN}安装基础依赖...${NC}"
    apt-get update
    apt-get install -y build-essential python3-dev python3-pip git
}

# 安装 PyTorch
install_pytorch() {
    echo -e "${GREEN}安装 PyTorch...${NC}"
    pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu121
    pip install flash-attn --no-build-isolation
}

# 安装 WeTextProcessing
install_wetext() {
    echo -e "${GREEN}安装 WeTextProcessing...${NC}"
    if [ -d "WeTextProcessing" ]; then
        rm -rf WeTextProcessing
    fi
    git clone https://github.com/wenet-e2e/WeTextProcessing.git
    cd WeTextProcessing
    # 修改 setup.py
    echo 'version = "1.0.3"' > version.txt
    sed -i 's/version = sys.argv\[-1\].split("="\)\[1\]/with open("version.txt") as f:\n    version = f.read().strip()/' setup.py
    pip install -e . || handle_error "安装 WeTextProcessing 失败"
    cd ..
}

# 设置环境
setup_environment() {
    echo -e "${GREEN}设置环境变量...${NC}"
    export PYTHONPATH=$PYTHONPATH:/workspace/CosyVoice/third_party/Matcha-TTS
    echo 'export PYTHONPATH=$PYTHONPATH:/workspace/CosyVoice/third_party/Matcha-TTS' >> ~/.bashrc
}

# 主函数
main() {
    echo -e "${GREEN}开始安装 CosyVoice...${NC}"
    
    # 检查是否为 root
    if [ "$EUID" -ne 0 ]; then 
        handle_error "请使用 root 权限运行此脚本"
    fi
    
    # 安装依赖
    install_base_deps
    install_pytorch
    install_wetext
    setup_environment
    
    echo -e "${GREEN}安装完成!${NC}"
    echo -e "${GREEN}现在你可以运行:${NC}"
    echo -e "${GREEN}python3 webui.py --port 50000 --model_dir pretrained_models/CosyVoice-300M-SFT${NC}"
}

# 运行主函数
main
EOL

# 添加执行权限
chmod +x install_cosyvoice.sh
