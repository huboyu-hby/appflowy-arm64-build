FROM ubuntu:22.04

# 安装依赖
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    wget \
    git \
    cmake \
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
    pkg-config \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# 安装Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# 安装Flutter
RUN wget -O flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.16.0-stable.tar.xz && \
    tar -xf flutter.tar.xz -C /opt && \
    rm flutter.tar.xz
ENV PATH="/opt/flutter/bin:${PATH}"

# 克隆AppFlowy仓库
RUN git clone https://github.com/AppFlowy-IO/appflowy.git /appflowy
WORKDIR /appflowy

# 构建AppFlowy
RUN flutter pub get && \
    flutter build linux

# 运行AppFlowy
CMD ["/appflowy/build/linux/x64/release/bundle/appflowy"]
