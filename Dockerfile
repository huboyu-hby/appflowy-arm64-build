# AppFlowy多架构构建Dockerfile（Ubuntu 22.04）
# 支持x86_64/arm64架构，国内镜像加速，适配UID/GID权限
# 构建方式：
# 1. ARM64: docker build --target app-arm64 -t appflowy:arm64 .
# 2. x86_64: docker build --target app-x86_64 -t appflowy:x86_64 .
# 3. 多架构: docker buildx build --platform linux/amd64,linux/arm64 -t appflowy:latest --push .

# ======================== 全局参数定义 ========================
ARG BASE_IMAGE=ubuntu:22.04
ARG TARGETARCH  # Docker buildx自动注入：x86_64/arm64
ARG USER=appflowy
ARG UID=1000     # 可通过--build-arg传递，匹配主机UID
ARG GID=1000     # 可通过--build-arg传递，匹配主机GID

# ======================== 通用构建阶段（复用依赖安装逻辑） ========================
FROM ${BASE_IMAGE} as builder-common

# 基础配置：国内镜像源 + 错误终止 + 非交互模式
ENV DEBIAN_FRONTEND=noninteractive
RUN set -e && \
    # 替换Ubuntu阿里云源（加速国内构建）
    sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    # 安装系统构建依赖
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    wget \
    git \
    cmake \
    ninja-build \
    pkg-config \
    libssl-dev \
    libgl1-mesa-dev \
    libx11-xcb-dev \
    libxcb-icccm4-dev \
    libxcb-image0-dev \
    libxcb-keysyms1-dev \
    libxcb-randr0-dev \
    libxcb-render-util0-dev \
    libxcb-xinerama0-dev \
    libxcb-xfixes0-dev \
    libxcb-cursor-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libharfbuzz-dev \
    libicu-dev \
    libinput-dev \
    libxkbcommon-dev \
    libxkbcommon-x11-dev \
    libxi-dev \
    libxrandr-dev \
    libxrender-dev \
    libxtst-dev \
    libkeybinder-3-0-dev \
    libnotify-dev \
    libsqlite3-dev \
    libjemalloc-dev \
    libzstd-dev \
    librocksdb-dev \
    clang \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*  # 清理缓存，减小镜像体积

# 创建构建用户（免密sudo，避免root构建）
ARG USER
RUN useradd --system --create-home ${USER} && \
    echo "${USER} ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers

# 配置Flutter国内镜像（提前配置，确保安装时生效）
ENV PUB_HOSTED_URL=https://pub.flutter-io.cn
ENV FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# 切换到构建用户，设置工作目录
USER ${USER}
WORKDIR /home/${USER}

# 安装Rust（指定版本，确保环境变量全局生效）
RUN set -e && \
    # 安装Rustup
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    # 将cargo环境写入bashrc，确保后续指令生效
    echo "source ~/.cargo/env" >> ~/.bashrc && \
    # 激活环境并安装指定版本Rust
    . ~/.cargo/env && \
    rustup toolchain install 1.81 && \
    rustup default 1.81

# 安装Flutter（国内清华镜像，加速下载）
RUN set -e && \
    # 下载Flutter稳定版
    curl -sSfL \
    --output flutter.tar.xz \
    https://mirrors.tuna.tsinghua.edu.cn/flutter/flutter_infra_release/releases/stable/linux/flutter_linux_3.27.4-stable.tar.xz && \
    # 解压并清理压缩包
    tar -xf flutter.tar.xz && rm flutter.tar.xz && \
    # 配置Flutter路径到bashrc
    echo "export PATH=\$PATH:/home/${USER}/flutter/bin:/home/${USER}/flutter/bin/cache/dart-sdk/bin:/home/${USER}/.pub-cache/bin" >> ~/.bashrc && \
    # 激活环境并配置Flutter
    . ~/.bashrc && \
    flutter config --enable-linux-desktop && \
    flutter doctor && \
    dart pub global activate protoc_plugin 21.1.2

# 安装Cargo构建工具（缓存优化：依赖安装与代码解耦）
RUN set -e && \
    . ~/.cargo/env && \
    cargo install cargo-make --version 0.37.18 --locked && \
    cargo install cargo-binstall --version 1.10.17 --locked && \
    cargo binstall duckscript_cli --locked -y

# ======================== x86_64架构构建阶段 ========================
FROM builder-common as builder-x86_64

# 架构专属配置
ARG ROCKSDB_LIB_DIR="/usr/lib/x86_64-linux-gnu/"
ARG BUILD_PROFILE="production-linux-x86_64"

# 复制源码（最后复制，利用Docker缓存：代码变更不重新安装依赖）
COPY . /appflowy
RUN sudo chown -R ${USER}: /appflowy
WORKDIR /appflowy/frontend

# 构建AppFlowy（x86_64）
RUN set -e && \
    . ~/.bashrc && \
    cargo make appflowy-flutter-deps-tools && \
    cargo make flutter_clean && \
    # 构建参数：静态链接OpenSSL，指定ROCKSDB路径
    OPENSSL_STATIC=1 \
    ZSTD_SYS_USE_PKG_CONFIG=1 \
    ROCKSDB_LIB_DIR=${ROCKSDB_LIB_DIR} \
    cargo make -p ${BUILD_PROFILE} appflowy-linux

# ======================== ARM64架构构建阶段 ========================
FROM builder-common as builder-arm64

# 架构专属配置
ARG ROCKSDB_LIB_DIR="/usr/lib/aarch64-linux-gnu/"
ARG BUILD_PROFILE="production-linux-aarch64"

# 复制源码（最后复制，利用Docker缓存）
COPY . /appflowy
RUN sudo chown -R ${USER}: /appflowy
WORKDIR /appflowy/frontend

# 构建AppFlowy（ARM64，额外指定Flutter特性）
RUN set -e && \
    . ~/.bashrc && \
    cargo make appflowy-flutter-deps-tools && \
    cargo make flutter_clean && \
    # 构建参数：适配ARM64架构
    OPENSSL_STATIC=1 \
    ZSTD_SYS_USE_PKG_CONFIG=1 \
    ROCKSDB_LIB_DIR=${ROCKSDB_LIB_DIR} \
    FLUTTER_DESKTOP_FEATURES="dart,openssl_vendored" \
    cargo make -p ${BUILD_PROFILE} appflowy-linux

# ======================== 通用运行阶段（仅包含运行时依赖） ========================
FROM ${BASE_IMAGE} as app-common

# 基础配置：国内镜像源 + 非交互模式
ENV DEBIAN_FRONTEND=noninteractive
RUN set -e && \
    sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    # 安装运行时依赖（仅保留必要库，减小镜像体积）
    apt-get update && apt-get install -y --no-install-recommends \
    libgl1-mesa-glx \
    libx11-xcb1 \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-randr0 \
    libxcb-render-util0 \
    libxcb-xinerama0 \
    libxcb-xfixes0 \
    libxcb-cursor0 \
    libfontconfig1 \
    libfreetype6 \
    libharfbuzz0b \
    libicu70 \
    libinput10 \
    libxkbcommon0 \
    libxkbcommon-x11-0 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxtst6 \
    libkeybinder-3-0 \
    libnotify4 \
    libsqlite3-0 \
    libjemalloc2 \
    libzstd1 \
    librocksdb6.15 \
    && rm -rf /var/lib/apt/lists/*

# 创建运行用户（适配主机UID/GID，避免权限问题）
ARG USER
ARG UID
ARG GID
RUN groupadd --gid ${GID} ${USER} && \
    useradd --create-home --uid ${UID} --gid ${GID} ${USER} && \
    # 创建X运行时目录，解决GUI权限问题
    mkdir -p /tmp/runtime-${USER} && \
    chown -R ${UID}:${GID} /tmp/runtime-${USER}

# 切换到非root用户，设置工作目录
USER ${USER}
WORKDIR /home/${USER}

# 配置X运行时环境变量（解决GUI显示问题）
ENV XDG_RUNTIME_DIR=/tmp/runtime-${USER}

# ======================== x86_64运行镜像 ========================
FROM app-common as app-x86_64

# 从构建阶段复制编译产物
COPY --from=builder-x86_64 /appflowy/frontend/appflowy_flutter/build/linux/x64/release/bundle .

# 启动命令
CMD ["./AppFlowy"]

# ======================== ARM64运行镜像 ========================
FROM app-common as app-arm64

# 从构建阶段复制编译产物
COPY --from=builder-arm64 /appflowy/frontend/appflowy_flutter/build/linux/arm64/release/bundle .

# 启动命令
CMD ["./AppFlowy"]
