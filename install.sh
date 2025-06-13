#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
DEFAULT_INSTALL_DIR="/opt/am40-led-control"
DEFAULT_PORT="5000"
CONFIRMED_LED=""

# 系统检测函数
function detect_system() {
    if [ -f /etc/os-release ]; then
        OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
        OS_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    elif [ -f /etc/issue ]; then
        OS_INFO=$(head -n 1 /etc/issue | sed 's/\\[a-z]//g')
        OS_NAME=$(echo $OS_INFO | awk '{print $1}')
        OS_VERSION=$(echo $OS_INFO | awk '{print $2}')
    else
        OS_NAME="未知Linux"
        OS_VERSION=""
    fi

    echo "$OS_NAME $OS_VERSION" | tr -d '\n'
}

# 兼容性检查
function check_compatibility() {
    SYSTEM_INFO=$(detect_system)
    echo -e "\n检测到系统: ${BLUE}$SYSTEM_INFO${NC}"

    TESTED_SYSTEM="Armbian 23.02.2"

    if [[ "$SYSTEM_INFO" == *"$TESTED_SYSTEM"* ]]; then
        echo -e "${GREEN}✓ 当前系统已通过兼容性测试${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ 当前系统未做过兼容性测试${NC}"
        echo -e "已测试系统: ${BLUE}${TESTED_SYSTEM}${NC}"
        echo -e "可能存在的问题:"
        echo -e "1. LED控制路径不同"
        echo -e "2. 缺少必要的依赖包"
        echo -e "3. 系统服务管理方式不同"
        
        read -p "是否继续安装? [y/N] " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo -e "${RED}安装已取消${NC}"
            exit 0
        fi
        return 1
    fi
}

# 显示标题
function show_title() {
    clear
    echo -e "${GREEN}"
    echo "========================================"
    echo " SMART AM40 (RK3399) LED 控制服务安装程序"
    echo "========================================"
    echo -e "${NC}"
}

# 检测LED设备
function detect_leds() {
    echo -e "${GREEN}[1/7] 检测LED设备...${NC}"

    LEDS=($(ls /sys/class/leds/ 2>/dev/null))

    if [ ${#LEDS[@]} -eq 0 ]; then
        echo -e "${RED}错误: 未检测到任何LED设备${NC}"
        echo -e "请确认:"
        echo -e "1. 设备已正确连接"
        echo -e "2. 系统驱动已加载"
        exit 1
    fi

    echo -e "检测到以下LED设备:"
    for i in "${!LEDS[@]}"; do
        echo -e "  $((i + 1)). ${LEDS[$i]}"
    done
    echo
}

# 测试LED设备
function test_led() {
    local led=$1
    echo -e "${YELLOW}正在测试LED: ${BLUE}$led${NC}"

    # 保存当前状态
    original_trigger=$(cat /sys/class/leds/$led/trigger)
    original_brightness=$(cat /sys/class/leds/$led/brightness)

    # 测试闪烁
    for i in {1..3}; do
        echo 1 | tee /sys/class/leds/$led/brightness >/dev/null
        sleep 0.3
        echo 0 | tee /sys/class/leds/$led/brightness >/dev/null
        sleep 0.3
    done

    # 恢复原状态
    echo $original_brightness | tee /sys/class/leds/$led/brightness >/dev/null
    echo $original_trigger | tee /sys/class/leds/$led/trigger >/dev/null

    # 用户确认
    read -p "您看到LED闪烁了吗? [Y/n] " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" || "$confirm" == "" ]]; then
        CONFIRMED_LED=$led
        return 0
    fi
    return 1
}

# 选择LED设备
function select_led() {
    LEDS=($(ls /sys/class/leds/))

    while true; do
        echo -e "请选择要测试的LED设备:"
        for i in "${!LEDS[@]}"; do
            echo -e "  $((i + 1)). ${LEDS[$i]}"
        done
        echo -e "  q. 退出安装"

        read -p "请输入选择 [1-${#LEDS[@]}/q]: " choice

        if [ "$choice" == "q" ]; then
            echo -e "${RED}安装已取消${NC}"
            exit 0
        fi

        if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#LEDS[@]} ]; then
            selected_led=${LEDS[$((choice - 1))]}
            if test_led $selected_led; then
                echo -e "${GREEN}已确认LED设备: ${BLUE}$CONFIRMED_LED${NC}"
                break
            else
                echo -e "${YELLOW}继续测试其他设备...${NC}"
            fi
        else
            echo -e "${RED}无效选择，请重新输入${NC}"
        fi
    done
}

# 安装依赖
function install_dependencies() {
    echo -e "${GREEN}[3/7] 安装系统依赖...${NC}"
    apt update >/dev/null 2>&1
    apt install -y python3 python3-pip >/dev/null 2>&1
    pip3 install flask >/dev/null 2>&1
}

# 部署文件
function deploy_files() {
    echo -e "${GREEN}[4/7] 部署程序文件...${NC}"

    mkdir -p ${INSTALL_DIR}/templates

    # 生成带确认LED的app.py
    cat >${INSTALL_DIR}/app.py <<EOF
from flask import Flask, request, jsonify, render_template
import os

app = Flask(__name__)
LED_PATH = "/sys/class/leds/${CONFIRMED_LED}"

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/toggle', methods=['POST'])
def toggle():
    try:
        with open(f"{LED_PATH}/brightness", 'r+') as f:
            current = int(f.read())
            f.seek(0)
            f.write('0' if current else '1')
        return jsonify(success=True)
    except Exception as e:
        return jsonify(error=str(e)), 500

@app.route('/set_mode', methods=['POST'])
def set_mode():
    try:
        mode = request.json.get('mode')
        with open(f"{LED_PATH}/trigger", 'w') as f:
            f.write(mode)
        return jsonify(success=True)
    except Exception as e:
        return jsonify(error=str(e)), 500

@app.route('/status')
def status():
    try:
        with open(f"{LED_PATH}/brightness", 'r') as f:
            on = int(f.read()) == 1
        return jsonify(on=on)
    except Exception as e:
        return jsonify(error=str(e)), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=${SERVICE_PORT})
EOF

    # 部署前端文件
    cp templates/index.html ${INSTALL_DIR}/templates/

    # 创建管理命令
    cat >/usr/local/bin/led-control <<EOF
#!/bin/bash

INSTALL_DIR="${INSTALL_DIR}"
CONFIRMED_LED="${CONFIRMED_LED}"

function show_help() {
    echo -e "${GREEN}SMART AM40 LED 控制服务管理工具${NC}"
    echo "当前控制LED: ${CONFIRMED_LED}"
    echo "安装目录: ${INSTALL_DIR}"
    echo "用法: led-control [command]"
    echo
    echo "可用命令:"
    echo "  status       - 查看服务状态"
    echo "  start        - 启动服务"
    echo "  stop         - 停止服务"
    echo "  restart      - 重启服务"
    echo "  enable       - 启用开机自启"
    echo "  disable      - 禁用开机自启"
    echo "  set-port     - 修改服务端口"
    echo "  test-led     - 测试LED功能"
    echo "  uninstall    - 卸载服务"
    echo "  help         - 显示帮助信息"
}

function test_led() {
    original_trigger=\$(cat /sys/class/leds/${CONFIRMED_LED}/trigger)
    original_brightness=\$(cat /sys/class/leds/${CONFIRMED_LED}/brightness)
    
    echo -e "${YELLOW}正在测试LED: ${BLUE}${CONFIRMED_LED}${NC}"
    
    for i in {1..3}; do
        echo 1 | tee /sys/class/leds/${CONFIRMED_LED}/brightness >/dev/null
        sleep 0.3
        echo 0 | tee /sys/class/leds/${CONFIRMED_LED}/brightness >/dev/null
        sleep 0.3
    done
    
    echo \$original_brightness | tee /sys/class/leds/${CONFIRMED_LED}/brightness >/dev/null
    echo \$original_trigger | tee /sys/class/leds/${CONFIRMED_LED}/trigger >/dev/null
    
    echo -e "${GREEN}LED测试完成${NC}"
}

case "\$1" in
    status)
        systemctl status led-control
        ;;
    start)
        systemctl start led-control
        ;;
    stop)
        systemctl stop led-control
        ;;
    restart)
        systemctl restart led-control
        ;;
    enable)
        systemctl enable led-control
        ;;
    disable)
        systemctl disable led-control
        ;;
    set-port)
        read -p "请输入新端口号: " NEW_PORT
        sed -i "s/port=[0-9]\\+/port=\${NEW_PORT}/g" \${INSTALL_DIR}/app.py
        systemctl restart led-control
        echo "端口已修改为 \${NEW_PORT}"
        ;;
    test-led)
        test_led
        ;;
    uninstall)
        \${INSTALL_DIR}/uninstall.sh
        ;;
    help|*)
        show_help
        ;;
esac
EOF

    chmod +x /usr/local/bin/led-control
}

# 配置服务
function configure_service() {
    echo -e "${GREEN}[5/7] 配置系统服务...${NC}"

    cat >/etc/systemd/system/led-control.service <<EOF
[Unit]
Description=SMART AM40 LED Control Service
After=network.target

[Service]
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # 设置LED权限
    echo 'SUBSYSTEM=="leds", ACTION=="add", RUN+="/bin/chmod 0666 /sys/class/leds/%k/brightness /sys/class/leds/%k/trigger"' >/etc/udev/rules.d/99-leds.rules
    udevadm control --reload
    udevadm trigger
}

# 创建卸载脚本
function create_uninstaller() {
    echo -e "${GREEN}[6/7] 创建卸载脚本...${NC}"

    cat >${INSTALL_DIR}/uninstall.sh <<EOF
#!/bin/bash

# 停止并禁用服务
systemctl stop led-control
systemctl disable led-control

# 删除服务文件
rm /etc/systemd/system/led-control.service

# 删除安装目录
rm -rf ${INSTALL_DIR}

# 删除udev规则
rm /etc/udev/rules.d/99-leds.rules

# 删除管理命令
rm /usr/local/bin/led-control

# 重新加载udev
udevadm control --reload
udevadm trigger

echo "AM40 LED控制服务已成功卸载"
EOF

    chmod +x ${INSTALL_DIR}/uninstall.sh
}

# 启动服务
function start_service() {
    echo -e "${GREEN}[7/7] 启动服务...${NC}"
    systemctl daemon-reload
    systemctl enable led-control
    systemctl start led-control
}

# 显示安装结果
function show_result() {
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      安装成功!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "控制LED设备: ${BLUE}${CONFIRMED_LED}${NC}"
    echo -e "访问控制界面: ${YELLOW}http://${IP_ADDRESS}:${SERVICE_PORT}${NC}"
    echo
    echo -e "服务管理命令: ${YELLOW}led-control [command]${NC}"
    echo
    echo -e "可用命令:"
    echo -e "  ${YELLOW}status${NC}     - 查看服务状态"
    echo -e "  ${YELLOW}start${NC}      - 启动服务"
    echo -e "  ${YELLOW}stop${NC}       - 停止服务"
    echo -e "  ${YELLOW}restart${NC}    - 重启服务"
    echo -e "  ${YELLOW}enable${NC}     - 启用开机自启"
    echo -e "  ${YELLOW}disable${NC}    - 禁用开机自启"
    echo -e "  ${YELLOW}set-port${NC}   - 修改服务端口"
    echo -e "  ${YELLOW}test-led${NC}   - 测试LED功能"
    echo -e "  ${YELLOW}uninstall${NC}  - 卸载服务"
    echo
}

# 主安装流程
function main() {
    show_title
    check_compatibility
    detect_leds
    select_led

    read -p "请输入安装路径 [默认: ${DEFAULT_INSTALL_DIR}]: " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}

    read -p "请输入服务端口 [默认: ${DEFAULT_PORT}]: " SERVICE_PORT
    SERVICE_PORT=${SERVICE_PORT:-$DEFAULT_PORT}

    read -p "是否继续安装? [Y/n] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" && "$confirm" != "" ]]; then
        echo -e "${RED}安装已取消${NC}"
        exit 0
    fi

    install_dependencies
    deploy_files
    configure_service
    create_uninstaller
    start_service
    show_result
}

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误: 请使用root用户运行此脚本${NC}" >&2
    echo -e "请执行: ${YELLOW}sudo $0${NC}"
    exit 1
fi

main
