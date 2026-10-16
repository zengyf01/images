# GreatDB 1.0 Docker 镜像
# 基于 installgreatdb.sh 的安装流程,改造为 Docker 容器场景:
#   - 跳过 systemd / selinux / 内核参数 / sudo / 交互输入
#   - 由 entrypoint 直接调用 greatdbd
#   - 数据运行时初始化,数据目录需挂卷持久化
#   - License 不内置,运行时通过 -v 挂载或环境变量注入

FROM rockylinux:8

# ============================================================
# 系统层:运行时依赖
#   - libaio: MySQL/MariaDB/GreatDB 系列的硬依赖(I/O 异步)
#   - numactl-libs: 多 CPU socket 场景优化
#   - procps-ng / which / hostname / iproute: 排障
#   - tar / xz: 已自带,显式列出避免最小镜像裁掉
# ============================================================
RUN dnf install -y \
        libaio numactl-libs which hostname procps-ng tar xz iproute \
        findutils \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# ============================================================
# 创建运行用户 greatdb(uid/gid 不固定,容器内一致即可)
# 与 installgreatdb.sh 的 addUser 保持同名,便于和官方文档对照
# ============================================================
RUN groupadd -r greatdb && \
    useradd  -r -g greatdb -s /bin/bash -m -d /home/greatdb greatdb

# ============================================================
# 环境变量(docker run -e 可覆盖)
# 路径/用户/端口命名风格参考 installgreatdb.sh 的常量
# ============================================================
ENV GREATDB_DATA_DIR=/data/dev/GreatDB/greatdb \
    GREATDB_PORT=63306 \
    GREATDB_ADMIN_PORT=63806 \
    GREATDB_MYSQLX_PORT=63856 \
    GREATDB_USER=greatdb \
    MY_HOST= \
    SERVER_ID=63306 \
    GREATDB_BUFFER_POOL=1G \
    LICENSE_FILE_PATH= \
    ROOT_PASSWORD=

# ============================================================
# 标准目录结构(沿用 installgreatdb.sh 的 addDir 布局)
# svr/   - 安装包解压目录
# conf/  - my.cnf
# logs/  - 错误/慢日志
# tool/  - License 等附属文件
# dbdata/data${PORT}/{data,log,tmp} - 实际数据/事务日志/临时
# ============================================================
RUN mkdir -p ${GREATDB_DATA_DIR}/conf \
             ${GREATDB_DATA_DIR}/svr \
             ${GREATDB_DATA_DIR}/logs \
             ${GREATDB_DATA_DIR}/tool \
             ${GREATDB_DATA_DIR}/dbdata/data${GREATDB_PORT}/data \
             ${GREATDB_DATA_DIR}/dbdata/data${GREATDB_PORT}/log \
             ${GREATDB_DATA_DIR}/dbdata/data${GREATDB_PORT}/tmp

# ============================================================
# 复制并解压安装包
#   - COPY 到 /tmp 而非 ${DATA_DIR}/svr,避免 tar 解压到一个临时
#     中间名目录,影响后面的 ls 推断
#   - 解压后用 `ls -1 | head -1` 推断顶层目录名(沿用 install 脚本的 D_PKG 模式)
#   - 创建 greatdb 软链,方便用相对路径访问
#   - `ls -la greatdb/bin/greatdbd` 强校验:解压结构不对直接 fail,
#     避免产出一个看似成功实际跑不起来的镜像
# ============================================================
COPY GreatDB-1.0.0.6208032-GA-1-64e8cba6-Linux-glibc2.28-x86_64.tar.xz /tmp/greatdb.tar.xz
RUN cd ${GREATDB_DATA_DIR}/svr && \
    tar -xJf /tmp/greatdb.tar.xz && \
    rm -f /tmp/greatdb.tar.xz && \
    D_PKG=$(ls -1 | head -1) && \
    test -n "$D_PKG" && \
    ln -sfn "$D_PKG" greatdb && \
    ls -la greatdb/bin/greatdbd && \
    chown -R ${GREATDB_USER}:${GREATDB_USER} ${GREATDB_DATA_DIR}

# ============================================================
# greatdb 二进制需要 LD_LIBRARY_PATH 找到私有 lib
# (宿主的 /etc/profile 在 docker run 时不会被 source,必须 ENV)
# ============================================================
ENV PATH=${PATH}:${GREATDB_DATA_DIR}/svr/greatdb/bin
ENV LD_LIBRARY_PATH=${GREATDB_DATA_DIR}/svr/greatdb/lib

# ============================================================
# 入口脚本:处理 license → 生成 my.cnf → 首次初始化 → exec 启动 greatdbd
# ============================================================
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# 三个端口(对照 installgreatdb.sh 的 portcheck 派生)
# GREATDB_PORT          = 63306 (MySQL)
# GREATDB_ADMIN_PORT    = GREATDB_PORT + 500
# GREATDB_MYSQLX_PORT   = GREATDB_PORT + 550
EXPOSE 63306 63806 63856

WORKDIR ${GREATDB_DATA_DIR}

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]