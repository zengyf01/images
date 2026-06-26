#!/bin/bash
set -e

# 读取环境变量，提供默认值
PORT=${CDM_PORT:-6379}
PASSWORD=${CDM_PASSWORD:-}
DATA_DIR=${CDM_DATA_DIR:-/data}
CONFIG_FILE=${CDM_CONFIG_FILE:-/etc/cdm/cdm_server.ini}

# 如果用户挂载了自定义配置文件，直接使用它
if [ -f "$CONFIG_FILE" ]; then
    echo "Using custom config: $CONFIG_FILE"
else
    # 从模板生成配置文件
    echo "Generating config from template..."
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cp /opt/dmncbd/cdm/conf/config_templates/cdm_server.ini "$CONFIG_FILE"
    
    # 修改监听端口
    sed -i "s/^port .*/port $PORT/" "$CONFIG_FILE"
    
    # 修改数据目录
    sed -i "s#^dir .*#dir $DATA_DIR#" "$CONFIG_FILE"
    
    # 如果设置了密码，添加 requirepass
    if [ -n "$PASSWORD" ]; then
        echo "requirepass $PASSWORD" >> "$CONFIG_FILE"
    fi
fi

# 确保数据目录存在
mkdir -p "$DATA_DIR"

echo "Starting CDM server on port $PORT with data dir $DATA_DIR"
exec /opt/dmncbd/cdm/bin/cdm_server "$CONFIG_FILE"
