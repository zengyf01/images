# greatdb:1.0

GreatDB 单节点 Docker 镜像(基于 `installgreatdb.sh` 的安装流程改造,跳过 systemd / selinux / 内核参数等主机层操作)。

---

## 目录

- [一、部署场景速查](#一部署场景速查)
- [二、单节点部署(默认,推荐)](#二单节点部署默认推荐)
- [三、主从复制部署](#三主从复制部署)
- [四、测试 / 临时启动](#四测试--临时启动)
- [五、参数参考](#五参数参考)
- [六、数据持久化](#六数据持久化)
- [七、License 配置](#七license-配置)
- [八、镜像构建](#八镜像构建)
- [九、推送到内网仓库](#九推送到内网仓库)
- [十、与 `installgreatdb.sh` 的差异](#十与-installgreatdbsh-的差异)
- [十一、踩坑经验](#十一踩坑经验)
- [十二、版本历史](#十二版本历史)

---

## 一、部署场景速查

| 场景 | 复杂度 | 端口 | 密码 | MY_HOST | 典型用途 |
|---|---|---|---|---|---|
| **A. 单节点**(默认) | ⭐ | 63306 | `ROOT_PASSWORD` | 自动探测 | 应用开发、测试、单机生产 |
| **B. 主从复制** | ⭐⭐⭐ | 63306 + 63806 | `ROOT_PASSWORD` | **显式指定** | 读写分离、HA |
| **C. 测试 / 临时** | ⭐ | 63306 | 空(不设 ROOT_PASSWORD) | 自动探测 | 排障、PoC |

---

## 二、单节点部署(默认,推荐)

### 2.1 启动命令

```bash
docker run -d --name greatdb \
  -p 63306:63306 \
  -e ROOT_PASSWORD='YourStrongPassword!!' \
  -e GREATDB_BUFFER_POOL=4G \
  -v D:\license\license.key:/data/dev/GreatDB/greatdb/tool/license.key:ro \
  -v greatdb-data:/data/dev/GreatDB/greatdb/dbdata \
  greatdb:1.0
```

### 2.2 各参数说明

| 参数 | 值 | 必要性 | 说明 |
|---|---|---|---|
| `--name greatdb` | 固定名 | 必备 | 后续命令引用 |
| `-p 63306:63306` | MySQL 主端口 | **必备** | 业务连接用 |
| `-e ROOT_PASSWORD` | 自定密码 | **强烈建议** | 不设则 root 空密码,只适合内网测试 |
| `-e GREATDB_BUFFER_POOL` | `4G`(按主机内存 50%) | 建议 | 默认 1G 偏保守,生产建议调整 |
| `-v .../license.key:...:ro` | License 文件 | **必备** | `GreatDB` 必须有 license 才能正常服务 |
| `-v greatdb-data:.../dbdata` | 数据卷 | **必备** | 数据持久化,容器重建不丢 |
| `-e MY_HOST` | 不设(自动探测) | 否 | 单节点 `report_host` 谁都看不到,自动即可 |

### 2.3 License 文件准备

```bash
mkdir -p D:\license
copy "C:\Users\Admin\Desktop\db\db\license-20261012-QY20261010377.key" D:\license\license.key
```

### 2.4 验证

```bash
# 1) 看日志(看到 "ready for connections" 即就绪)
docker logs -f greatdb

# 2) 测连通
MYSQL_PWD='YourStrongPassword!!' docker exec -i greatdb \
  greatdb -uroot -h127.0.0.1 -P63306 -e "SELECT VERSION(), CURRENT_USER();"
# 预期:8.0.32-23-GreatDB1.0.0.6208032-GA-1  root@%

# 3) 业务验证
MYSQL_PWD='YourStrongPassword!!' docker exec -i greatdb \
  greatdb -uroot -h127.0.0.1 -P63306 <<'SQL'
CREATE DATABASE test_db;
USE test_db;
CREATE TABLE t (id INT PRIMARY KEY, name VARCHAR(50));
INSERT INTO t VALUES (1, 'GreatDB Docker Test');
SELECT * FROM t;
SQL
```

### 2.5 单节点生产强化版

如果对安全 / 性能要求更高,可加这些参数(仍然单节点):

```bash
docker run -d --name greatdb \
  --restart=unless-stopped \                                  # 异常退出自动重启
  -p 63306:63306 \                                            # 只暴露 MySQL
  -e ROOT_PASSWORD='YourStrongPassword!!' \
  -e GREATDB_BUFFER_POOL=8G \                                  # 按内存调
  -e SERVER_ID=10063306 \                                     # 即使单节点,也建议唯一
  -v D:\license\license.key:/data/dev/GreatDB/greatdb/tool/license.key:ro \
  -v greatdb-data:/data/dev/GreatDB/greatdb/dbdata \           # 数据
  -v greatdb-logs:/data/dev/GreatDB/greatdb/logs \             # 日志独立卷(可选)
  greatdb:1.0
```

---

## 三、主从复制部署

主从模式多了一个关键要求:**MY_HOST 必须是其他节点能直达的稳定 IP**(`installgreatdb.sh` 注释:"禁止写 127.0.0.1")。

### 3.1 网络准备(Docker 自定义网络 + 固定 IP)

```yaml
# docker-compose.yml
networks:
  dbnet:
    driver: bridge
    ipam:
      config:
        - subnet: 172.18.0.0/24

services:
  greatdb-master:
    image: greatdb:1.0
    hostname: greatdb-master
    networks:
      dbnet:
        ipv4_address: 172.18.0.10
    ports:
      - "63306:63306"
    environment:
      ROOT_PASSWORD: 'YourStrongPassword!!'
      MY_HOST: 172.18.0.10
      SERVER_ID: 10063306
    volumes:
      - ./license.key:/data/dev/GreatDB/greatdb/tool/license.key:ro
      - greatdb-master-data:/data/dev/GreatDB/greatdb/dbdata

  greatdb-slave:
    image: greatdb:1.0
    hostname: greatdb-slave
    networks:
      dbnet:
        ipv4_address: 172.18.0.11
    ports:
      - "63307:63306"           # 主机端口不同,避免冲突
    environment:
      ROOT_PASSWORD: 'YourStrongPassword!!'
      MY_HOST: 172.18.0.11
      SERVER_ID: 10063307        # 必须与 Master 不同
    volumes:
      - ./license.key:/data/dev/GreatDB/greatdb/tool/license.key:ro
      - greatdb-slave-data:/data/dev/GreatDB/greatdb/dbdata

volumes:
  greatdb-master-data:
  greatdb-slave-data:
```

启动:`docker compose up -d`

### 3.2 配置主从复制(在 Master 上)

```bash
# 1) Master 上创建复制账号
MYSQL_PWD='YourStrongPassword!!' docker exec -i greatdb-master \
  greatdb -uroot -h172.18.0.10 -P63306 <<'SQL'
CREATE USER 'repl'@'%' IDENTIFIED BY 'ReplPassword!!';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;

-- 记录位点(GTID 模式不需要 binlog 位点,Slave 用 MASTER_AUTO_POSITION=1)
GET SHOW MASTER STATUS;
SQL
```

### 3.3 配置 Slave 同步

```bash
MYSQL_PWD='YourStrongPassword!!' docker exec -i greatdb-slave \
  greatdb -uroot -h172.18.0.11 -P63306 <<'SQL'
CHANGE MASTER TO
  MASTER_HOST='172.18.0.10',
  MASTER_PORT=63306,
  MASTER_USER='repl',
  MASTER_PASSWORD='ReplPassword!!',
  MASTER_AUTO_POSITION=1,
  GET_SOURCE_PUBLIC_KEY=1;

START SLAVE;
SHOW SLAVE STATUS\G
SQL
```

`SHOW SLAVE STATUS` 里 `Slave_IO_Running: Yes` + `Slave_SQL_Running: Yes` 即同步成功。

### 3.4 验证

```bash
# Master 写
mysql -h172.18.0.10 -uroot -p'YourStrongPassword!!' -e "
USE test_db; INSERT INTO t VALUES (2, 'from Master');"

# Slave 读
mysql -h172.18.0.11 -uroot -p'YourStrongPassword!!' -e "
SELECT * FROM test_db.t;"
# 应看到两行
```

### 3.5 MY_HOST 在主从下的关键作用

`report_host` 影响:
- Master `SHOW SLAVE HOSTS` 里 Slave 显示的 IP
- Master 回调 Slave 的目标 IP(部分复制操作需要)
- Group Replication / Orchestrator 等工具读取

**写错后果**:
- `127.0.0.1`:Master 以为是本机回调,操作超时
- `0.0.0.0`:GreatDB 直接拒绝这个值
- 容器动态 IP:Slave 重启后 Master 找不到它 → 复制中断

---

## 四、测试 / 临时启动

### 4.1 最小启动(60 秒跑起来)

```bash
docker run -d --name greatdb-test \
  -p 63306:63306 \
  -v greatdb-test-data:/data/dev/GreatDB/greatdb/dbdata \
  greatdb:1.0
```

⚠️ **没有 License 也没有密码** — 仅适合临时测试,数据库大概率拒绝服务。

### 4.2 启动后改密码

```bash
docker exec -i greatdb-test \
  greatdb -uroot -h127.0.0.1 -P63306 <<'SQL'
ALTER USER 'root'@'%' IDENTIFIED BY 'NewPassword';
ALTER USER 'root'@'localhost' IDENTIFIED BY 'NewPassword';
FLUSH PRIVILEGES;
SQL
```

### 4.3 完全清理(数据也不要了)

```bash
docker rm -f greatdb-test
docker volume rm greatdb-test-data
```

---

## 五、参数参考

### 5.1 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `GREATDB_DATA_DIR` | `/data/dev/GreatDB/greatdb` | 数据根目录,对照 `installgreatdb.sh` 的 `DATA_DIR` |
| `GREATDB_PORT` | `63306` | MySQL 端口 |
| `GREATDB_ADMIN_PORT` | `PORT+500` | Admin 端口,容器内 127.0.0.1 |
| `GREATDB_MYSQLX_PORT` | `PORT+550` | mysqlx 端口(本镜像 cnf 已注释掉) |
| `GREATDB_USER` | `greatdb` | 系统运行用户 |
| **`ROOT_PASSWORD`** | **空** | **root 密码(详见 § 二 / § 四)** |
| `LICENSE_FILE_PATH` | 空 | License 源路径,entrypoint 复制到 `tool/license.key` |
| `MY_HOST` | **自动探测** | `report_host`,主从场景需显式设真实 IP |
| `SERVER_ID` | `${PORT}` | `server_id`,主从部署时每个实例必须不同 |
| `GREATDB_BUFFER_POOL` | `1G` | `innodb_buffer_pool_size`,建议主机的 50% 可用内存 |

### 5.2 端口

| 容器内端口 | 用途 | bind 地址 |
|---|---|---|
| 63306 | MySQL 主端口 | `*:63306` (任意来源) |
| 63806 | Admin 端口 | `127.0.0.1:63806`(容器内,可 `-p` 暴露) |
| 63856 | mysqlx 端口 | 未启用(cnf 已注释) |

### 5.3 密码支持特殊字符

`-e ROOT_PASSWORD='sq"quote\''` 这种密码内部自动 SQL 转义,无需手动处理。`'` `\"` `\\` 都安全。

---

## 六、数据持久化

### 6.1 目录结构

```
${DATA_DIR}/                              # /data/dev/GreatDB/greatdb
├── svr/greatdb/                         # 安装包解压(只读,无需挂卷)
├── conf/greatdb63306.cnf                # 生成的 my.cnf(可挂卷做配置持久化)
├── logs/                                # error.log / slow.log(建议挂卷)
├── tool/license.key                     # License(挂卷或 LICENSE_FILE_PATH)
└── dbdata/data63306/
        ├── data/         # 表数据 / undo / 系统表空间 → 必须挂卷
        ├── log/         # binlog / relaylog / redolog → 建议挂卷
        └── tmp/         # 临时表 → 无需挂卷
```

### 6.2 推荐挂卷方式

| 挂载 | 推荐做法 |
|---|---|
| **License** | Bind mount(单文件):`-v /host/license.key:...:ro` |
| **dbdata/data** | Named volume(高 IO):`-v greatdb-data:.../dbdata` |
| **dbdata/log** | 同上,合到 greatdb-data 里即可,生产严格可独立 |
| **logs** | Bind mount 或 named volume:`-v greatdb-logs:.../logs` |
| **conf** | 一般不挂,容器内 entrypoint 生成;要定制才挂 |

### 6.3 首次 vs 后续启动

- 启动时 `${DATA_DIR}/dbdata/data${PORT}/data` 为空 → 自动 `--initialize-insecure`
- 非空 → 直接启动已用实例,**不会重新初始化**

---

## 七、License 配置

两种注入方式:

| 方式 | 操作 | 适用 |
|---|---|---|
| **A. 挂卷到默认路径** | `-v /host/license.key:/data/dev/GreatDB/greatdb/tool/license.key:ro` | 文件命名固定,直接挂 |
| **B. 环境变量指向任意路径** | `-e LICENSE_FILE_PATH=/path/in/container` | 容器内路径任意,entrypoint 复制到 tool/license.key |

License 缺失时启动 banner 大警告,GreatDB 大概率拒绝服务。

---

## 八、镜像构建

```bash
cd D:\project\images\docker-file\greatdb\1.0
docker build -t greatdb:1.0 .
```

构建过程:
1. 装 libaio / numactl-libs 等依赖
2. 创建系统用户 greatdb
3. 解压安装包(~805 MB)到 `${DATA_DIR}/svr/greatdb/`
4. 校验 `greatdb/bin/greatdbd` 存在(解压结构不对会**直接 build 失败**)
5. 复制并 chmod 入口脚本

> **镜像大小**:约 7.1 GB(Rocky 8 base ~250 MB + GreatDB ~1.8 GB + InnoDB 表空间镜像层)。

构建首次约 3-5 分钟,后续增量 < 1 秒。

---

## 九、推送到内网仓库

```bash
docker tag greatdb:1.0 r.mayishangshu.cn:82/dev/greatdb:1.0
docker push r.mayishangshu.cn:82/dev/greatdb:1.0

# k8s 中如果未读到最新的则删除下载的镜像
crictl images
crictl rmi r.mayishangshu.cn:82/dev/greatdb:1.0
```

---

## 十、与 `installgreatdb.sh` 的差异

| 项目 | `installgreatdb.sh`(主机) | 本镜像(entrypoint) |
|---|---|---|
| selinux / firewalld | 关闭 | 跳过(由 daemon 处理) |
| 内核参数(swappiness / hugepage / numa) | 优化 | 跳过(由 daemon / kubelet 处理) |
| systemd 服务 | `systemctl enable/start` | **不可用**,直接 `exec greatdbd` |
| `passwd` 设置 greatdb 用户密码 | 交互式 | 跳过(系统用户无需登录) |
| portcheck 自增 admin / mysqlx | 动态扫描 | 跳过(端口由 `-p` 控制) |
| `source /etc/profile` | 改 PATH | `ENV PATH=...`(Dockerfile 阶段) |
| `my.cnf` 生成 | 一次性 | **幂等**:已存在则复用(配合 volume) |
| 数据初始化 | 启动前一次性 | **首次启动自动**(data 空时) |
| root 密码 | 安装后手工设置 | **`-e ROOT_PASSWORD` 自动注入** |
| License | 人工拷贝到 `${DATA_DIR}/tool/` | `-v` 挂卷 / `LICENSE_FILE_PATH` env |
| `my_host`(report_host) | 写死 `192.168.1.15` | 自动探测 / `-e MY_HOST` 覆盖 |

---

## 十一、踩坑经验

| 坑 | 原因 | 解决 |
|---|---|---|
| `greatdbd` 启动报 libaio 找不到 | 基础镜像未装 `libaio` | Dockerfile 已 `dnf install libaio` |
| `greatdbd` 启动报 GLIBC_X.Y not found | 基础镜像 glibc 太低 | 选 `rockylinux:8`(glibc 2.28 精确匹配) |
| 数据丢失 | 没 `-v` 挂数据目录 | 强制要求 `-v greatdb-data:.../dbdata` |
| License 报错拒启 | 没挂 license 或路径错位 | 见 § 七两种方式 |
| 容器一启动就 exit 255 | 之前 chown -R 撞到 :ro license.key | 已用 `find -writable` 过滤 |
| TCP `Access denied`(root@127.0.0.1) | `--initialize-insecure` 只建 root@localhost | entrypoint 用 `--init-file` 注入 root@'%' |
| TCP 改了 ROOT_PASSWORD 但密码不变 | `CREATE USER IF NOT EXISTS` 对已存在用户是 no-op | entrypoint 改成 CREATE + ALTER 两条 |
| 主从复制 Slave 找不到 Master 回调 IP | Slave | 重启后 IP 变了报改用固定网络 / 显式 MY_HOST |
| my.cnf 端口变了 admin 端口没跟 | Admin 端口是 `PORT+500` 不是 env | 修改 `GREATDB_PORT` 时一并改 `-p` |
| `0.0.0.0` 报错 | 写成了 `report_host=0.0.0.0` | 用 `-e MY_HOST=<真实IP>` 或不设(自动探测) |

---

## 十二、版本历史

- **1.0** (2026-10-16): 初版,基于 `installgreatdb.sh` 改造。
  - 增:`ROOT_PASSWORD` env 自动注入
  - 增:`MY_HOST` 自动探测(主从场景支持 `-e` 覆盖)
  - 修:`chown -R` 在 `:ro` license 上的失败
  - 修:TCP root 远程访问通过 init-file 注入
  - 修:`CREATE USER IF NOT EXISTS` 不更新密码的 bug
  - 增:按部署方式组织的 README(单节点 / 主从 / 测试)