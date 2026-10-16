#!/bin/bash
# docker-entrypoint.sh
# GreatDB 容器入口
#   1) 处理 License(挂载 / env 注入)
#   2) 生成 my.cnf(模板沿用 installgreatdb.sh 的 addConf,参数化)
#   3) 数据目录为空 → --initialize-insecure
#   4) exec 启动 greatdbd(前台运行,容器主进程)
#
# 与 installgreatdb.sh 的差异:
#   - 跳过 systemd / selinux / 内核参数(容器层不适用)
#   - 跳过交互 passwd(--initialize-insecure 模式 root 无密码)
#   - 跳过 portcheck(Docker 端口映射由 -p 控制,容器内独占网络命名空间)
#   - 跳过 profile PATH(source /etc/profile 在容器内是 no-op;Dockerfile 已 ENV)

set -e

# ---------- 1) 读取环境变量(默认值与 Dockerfile 一致) ----------
DATA_DIR=${GREATDB_DATA_DIR:-/data/dev/GreatDB/greatdb}
PORT=${GREATDB_PORT:-63306}
ADMIN_PORT=${GREATDB_ADMIN_PORT:-$((PORT+500))}
MYSQLX_PORT=${GREATDB_MYSQLX_PORT:-$((PORT+550))}
DB_USER=${GREATDB_USER:-greatdb}
DB_CMD=greatdb
MY_HOST=${MY_HOST:-}
SERVER_ID=${SERVER_ID:-$PORT}
FREE_MEM=${GREATDB_BUFFER_POOL:-1G}
LICENSE_SRC=${LICENSE_FILE_PATH:-}
ROOT_PWD=${ROOT_PASSWORD:-}

MYSQL_BASE=${DATA_DIR}/svr/${DB_CMD}
MYSQL_CONF=${DATA_DIR}/conf/${DB_CMD}${PORT}.cnf
MYSQL_SOCKET=${DATA_DIR}/dbdata/data${PORT}/data/${DB_CMD}.sock
DATA_PATH=${DATA_DIR}/dbdata/data${PORT}/data
LOG_PATH=${DATA_DIR}/dbdata/data${PORT}/log
TMP_PATH=${DATA_DIR}/dbdata/data${PORT}/tmp
LICENSE_DST=${DATA_DIR}/tool/license.key

# MY_HOST(report_host):复制拓扑上报的 IP,installgreatdb.sh 注释说"禁止写 127.0.0.1"
#   - 没设 → 自动探测容器 IP(优先取第一张非回环网卡的 IP)
#   - 设了 → 用用户指定的
if [ -z "$MY_HOST" ]; then
    # 优先 hostname -i,失败再试 ip -4 addr
    MY_HOST=$(hostname -i 2>/dev/null | awk '{print $1}')
    if [ -z "$MY_HOST" ] || [ "$MY_HOST" = "127.0.0.1" ]; then
        MY_HOST=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
    fi
    # 还探测不到 → 兜底
    if [ -z "$MY_HOST" ] || [ "$MY_HOST" = "127.0.0.1" ]; then
        MY_HOST="0.0.0.0"
        AUTO_HOST=1  # 标记是兜底,启动 banner 提示一下
    else
        AUTO_HOST=1
    fi
else
    AUTO_HOST=0
fi

echo "=================================================================="
echo "  GreatDB 容器启动"
echo "  - DATA_DIR    = ${DATA_DIR}"
echo "  - PORT        = ${PORT} (MySQL)"
echo "  - ADMIN_PORT  = ${ADMIN_PORT}"
echo "  - MYSQLX_PORT = ${MYSQLX_PORT}"
echo "  - USER        = ${DB_USER}"
echo "  - BIN         = ${MYSQL_BASE}/bin/${DB_CMD}d"
if [ -n "$ROOT_PWD" ]; then
    echo "  - ROOT_PASSWORD = 已设置(长度 ${#ROOT_PWD})"
else
    echo "  - ROOT_PASSWORD = (空,root 无密码 — 仅限内网/开发)"
fi
if [ "$AUTO_HOST" = "1" ]; then
    echo "  - MY_HOST      = ${MY_HOST} (自动探测,主从复制建议显式 -e MY_HOST=<真实IP>)"
else
    echo "  - MY_HOST      = ${MY_HOST}"
fi
echo "=================================================================="

# ---------- 2) License 处理 ----------
# 优先级:env 指定的源路径 > 已挂载在目标路径 > 都没有(警告)
if [ -n "$LICENSE_SRC" ] && [ -f "$LICENSE_SRC" ]; then
    echo "[entrypoint] 从 ${LICENSE_SRC} 复制 License 到 ${LICENSE_DST}"
    cp -f "$LICENSE_SRC" "$LICENSE_DST"
    chmod 644 "$LICENSE_DST"
elif [ -f "$LICENSE_DST" ]; then
    echo "[entrypoint] 使用已存在的 ${LICENSE_DST}"
else
    echo "[entrypoint] ====================================================="
    echo "[entrypoint] WARNING: 未发现 License 文件,GreatDB 大概率拒绝启动"
    echo "[entrypoint]   解决方法 1: -v /host/license.key:${LICENSE_DST}:ro"
    echo "[entrypoint]   解决方法 2: -e LICENSE_FILE_PATH=/path/in/container"
    echo "[entrypoint] ====================================================="
fi
# 同样过滤掉只读挂载的 license.key
find "${DATA_DIR}/tool" -writable -exec chown ${DB_USER}:${DB_USER} {} + 2>/dev/null || true

# ---------- 3) 生成 my.cnf(仅首次;挂卷后再次启动会复用) ----------
if [ ! -f "$MYSQL_CONF" ]; then
    echo "[entrypoint] 生成配置文件 ${MYSQL_CONF}"
    cat > "${MYSQL_CONF}" <<EOF
[mysqld]
#**********************Server**************************
#******user&port
user=${DB_USER}
port=${PORT}
server_id=${SERVER_ID}
admin_address='127.0.0.1'
admin_port=${ADMIN_PORT}
# mysqlx_port=${MYSQLX_PORT}
report_host=${MY_HOST}

#******character set&time zone
character_set_server=utf8mb4
collation_server=utf8mb4_0900_ai_ci
character_set_client_handshake=OFF
lower_case_table_names=1
local_infile=ON
secure_file_priv=''
skip_name_resolve=ON
default_time_zone='+8:00'
default_authentication_plugin=mysql_native_password
auto_increment_increment=1
auto_increment_offset=1
explicit_defaults_for_timestamp=ON
sql_mode=STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION

#******location
basedir=${MYSQL_BASE}
pid-file=${DATA_PATH}/${DB_CMD}.pid
socket=${DATA_PATH}/${DB_CMD}.sock
datadir=${DATA_PATH}
tmpdir=${TMP_PATH}


#**********************Performance*********************
#******connect
max_connections=10000
max_connect_errors=1000000
open_files_limit=65535
back_log=1500
table_open_cache=10000
table_definition_cache=10000
thread_cache_size=1000

#******session
sort_buffer_size=4M
join_buffer_size=4M
read_buffer_size=4M
read_rnd_buffer_size=4M
bulk_insert_buffer_size=64M
tmp_table_size=64M
max_heap_table_size=64M
thread_stack=512K
net_buffer_length=16K
max_allowed_packet=1G

#******timeout
lock_wait_timeout=600
interactive_timeout=3600
wait_timeout=3600


#**********************Logs****************************
log_timestamps=SYSTEM

#******error log
log_error=${DATA_DIR}/logs/error${PORT}.log
log_error_verbosity=3

#******slow log
slow_query_log=ON
slow_query_log_file=${DATA_DIR}/logs/slow${PORT}.log
log_slow_extra=ON
log_slow_verbosity=FULL
long_query_time=0.3

#******binlog
log_bin=${LOG_PATH}/binlog
binlog_format=ROW
sync_binlog=1
binlog_cache_size=4M
max_binlog_cache_size=4G
max_binlog_size=1G
binlog_expire_logs_seconds=2592000
binlog_rows_query_log_events=ON
gtid_mode=ON
enforce_gtid_consistency=ON

#******relaylog
relay_log=${LOG_PATH}/relaylog


#**********************Replication*********************
relay_log_recovery=ON
replica_parallel_type=LOGICAL_CLOCK
replica_parallel_workers=16
binlog_transaction_dependency_tracking=WRITESET
replica_preserve_commit_order=ON
replica_pending_jobs_size_max=2G
replica_max_allowed_packet=1G


#**********************InnoDB**************************
loose-plugin_load_add = 'mysql_clone.so'
transaction_isolation=READ-COMMITTED
innodb_buffer_pool_size=${FREE_MEM}
innodb_buffer_pool_instances=8
innodb_max_dirty_pages_pct=50
#******system tablespace
innodb_data_file_path=ibdata1:12M:autoextend
#******temporary tablespace
innodb_temp_data_file_path=ibtmp1:12M:autoextend:max:50G

#******redolog
innodb_log_group_home_dir=${LOG_PATH}
innodb_flush_log_at_trx_commit=1
innodb_log_buffer_size=32M
innodb_redo_log_capacity=4G

#******undolog
innodb_undo_directory=${LOG_PATH}
innodb_max_undo_log_size=4G

#******feature
innodb_open_files=65535
innodb_flush_method=O_DIRECT
innodb_flush_neighbors=0
innodb_flush_sync=ON
innodb_io_capacity=1000
innodb_io_capacity_max=2000
innodb_lock_wait_timeout=30
innodb_print_all_deadlocks=ON
innodb_online_alter_log_max_size=4G
innodb_print_ddl_logs=ON
innodb_read_io_threads=8
innodb_write_io_threads=8
innodb_doublewrite_pages=128
innodb_adaptive_hash_index=OFF
innodb_status_file=OFF


#**********************PFS*****************************
performance_schema=ON
performance_schema_show_processlist=ON
performance_schema_events_statements_history_size=1024
performance_schema_consumer_events_statements_history_long=ON

[mysqldump]
quick
net_buffer_length=16K

[mysql]
no_auto_rehash
default_character_set=utf8mb4

EOF
    chmod 644 "${MYSQL_CONF}"
    chown ${DB_USER}:${DB_USER} "${MYSQL_CONF}"
else
    echo "[entrypoint] 复用已存在配置 ${MYSQL_CONF}"
fi

# ---------- 4) 数据目录首次初始化 ----------
if [ -z "$(ls -A ${DATA_PATH} 2>/dev/null)" ]; then
    echo "[entrypoint] 数据目录为空,首次初始化(--initialize-insecure)..."
    if [ -z "$ROOT_PWD" ]; then
        echo "[entrypoint] ============================================================"
        echo "[entrypoint] WARNING: ROOT_PASSWORD 未设置,root 将保持空密码!"
        echo "[entrypoint]   仅适合内网/开发测试。生产请设置 -e ROOT_PASSWORD=xxx"
        echo "[entrypoint]   或容器启动后立刻 ALTER USER 修改密码。"
        echo "[entrypoint] ============================================================"
    fi
    # 只 chown 可写项(:ro 挂载的 license.key 会让整条 chown -R 失败,挂卷场景下常踩)
    find "${DATA_DIR}" -writable -exec chown ${DB_USER}:${DB_USER} {} +
    ${MYSQL_BASE}/bin/${DB_CMD}d \
        --defaults-file=${MYSQL_CONF} \
        --initialize-insecure \
        --user=${DB_USER}
else
    echo "[entrypoint] 数据目录已有内容,跳过初始化"
fi

# ---------- 5) 信号处理 ----------
# 容器收到 SIGTERM 时,优雅关闭数据库(避免数据损坏)
shutdown_db() {
    echo "[entrypoint] 收到停止信号,关闭 ${DB_CMD} ..."
    if [ -S "${MYSQL_SOCKET}" ]; then
        ${MYSQL_BASE}/bin/${DB_CMD}admin \
            --defaults-file=${MYSQL_CONF} \
            -uroot \
            --socket=${MYSQL_SOCKET} \
            shutdown || true
    fi
    exit 0
}
trap shutdown_db SIGTERM SIGINT

# ---------- 6) 启动 greatdbd(前台,Docker 主进程) ----------
# 通过 --init-file 注入一份幂等 SQL:
#   - GreatDB --initialize-insecure 只建 root@localhost(密码为空)
#   - TCP 客户端通过 -p 映射连进来时会落到 root@127.0.0.1,但该账号不存在 → Access denied
#   - 用 init-file 同时设置 root@'%'(任意 TCP) 和 root@localhost 的密码:
#     * ROOT_PASSWORD 未设置 → 空密码(仅适合内网/开发)
#     * ROOT_PASSWORD 已设置 → 用该密码
#   - CREATE USER IF NOT EXISTS / ALTER USER 都是幂等的,多次启动无副作用
#   - 密码需做 SQL 转义:把 \ 替换为 \\,把 ' 替换为 ''(SQL 标准转义)
ROOT_PWD_SQL=${ROOT_PWD//\\/\\\\}    # backslash → double backslash
ROOT_PWD_SQL=${ROOT_PWD_SQL//\'/\'\'} # single quote → two single quotes

cat > /tmp/zz_docker_init.sql <<EOSQL
-- Docker 入口注入:设置 root 密码(由 ROOT_PASSWORD env 控制,默认空)
-- 幂等:每次启动都会执行;CREATE USER IF NOT EXISTS 对已存在用户是 no-op,
-- 所以后面必须再跟一个 ALTER USER 强制覆盖密码
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${ROOT_PWD_SQL}';
ALTER USER 'root'@'%' IDENTIFIED BY '${ROOT_PWD_SQL}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PWD_SQL}';
EOSQL

echo "[entrypoint] 启动 ${DB_CMD}d(port=${PORT}, admin=${ADMIN_PORT})..."
exec ${MYSQL_BASE}/bin/${DB_CMD}d \
    --defaults-file=${MYSQL_CONF} \
    --user=${DB_USER} \
    --init-file=/tmp/zz_docker_init.sql