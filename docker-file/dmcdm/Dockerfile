FROM centos:7

# 修复 CentOS 7 源（官方源已停用，改用 vault.centos.org）
RUN sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*.repo && \
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*.repo

# 安装基础依赖
RUN yum install -y \
    compat-openssl10 \
    iproute \
    libstdc++ \
    && yum clean all \
    && rm -rf /var/cache/yum/*

# 复制 RPM 包（确保文件名与下方一致）
COPY cdm_V1.1_20260427_9c25f06c_x86__64_ms.rpm /tmp/cdm.rpm

# 安装 CDM（使用 yum localinstall 自动解决依赖）
RUN yum localinstall -y /tmp/cdm.rpm && \
    rm -f /tmp/cdm.rpm

# 创建数据目录
RUN mkdir -p /data && chmod 755 /data

# 暴露端口
EXPOSE 6379

# 复制启动脚本
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# 数据卷
VOLUME ["/data"]

# 入口点
ENTRYPOINT ["docker-entrypoint.sh"]