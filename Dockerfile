# Builder stage for SSH key
FROM pytorch/pytorch:latest AS start

# Updated: 2025-04-14T10:30:00-04:00 - Added Azure CLI installation
RUN apt update && apt-get install -y \
    git git-lfs rsync nginx wget curl jq tar nano net-tools lsof nvtop multitail ffmpeg libsm6 libxext6\
    cron sudo ssh zstd build-essential libgoogle-perftools-dev cmake ninja-build \
    gcc g++ openssh-client libx11-dev libxrandr-dev libxinerama-dev \
    libxcursor-dev libxi-dev libgl1-mesa-dev libglfw3-dev software-properties-common \
    apt-transport-https ca-certificates gnupg lsb-release \
    && curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && add-apt-repository ppa:ubuntu-toolchain-r/test -y \
    && apt install -y gcc-11 g++-11 libstdc++6 \
    && apt-get install -y locales \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*



# Install newer libstdc++ for both system and conda
RUN cd /tmp && \
    wget http://security.ubuntu.com/ubuntu/pool/main/g/gcc-12/libstdc++6_12.3.0-1ubuntu1~22.04_amd64.deb && \
    dpkg -x libstdc++6_12.3.0-1ubuntu1~22.04_amd64.deb . && \
    cp -v usr/lib/x86_64-linux-gnu/libstdc++.so.6.0.30 /usr/lib/x86_64-linux-gnu/ && \
    cp -v usr/lib/x86_64-linux-gnu/libstdc++.so.6.0.30 /opt/conda/lib/ && \
    cd /usr/lib/x86_64-linux-gnu && \
    ln -sf libstdc++.so.6.0.30 libstdc++.so.6 && \
    cd /opt/conda/lib && \
    ln -sf libstdc++.so.6.0.30 libstdc++.so.6

FROM start AS middle

ENV ROOT=/workspace
ENV PATH="${ROOT}/.local/bin:${PATH}"
ENV CONFIG_DIR=${ROOT}/config
ENV COMFY_DIR=${ROOT}/ComfyUI

WORKDIR ${ROOT}

ENV CFLAGS="-O2"
ENV CXXFLAGS="-O2"

RUN pip install --upgrade pip && \
    pip install --upgrade torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1

RUN git clone https://github.com/comfyanonymous/ComfyUI.git ${COMFY_DIR} && \
    cd ${COMFY_DIR} && \
    pip uninstall onnxruntime && \
    pip install --upgrade pip && \
    pip install --upgrade mmengine opencv-python imgui-bundle pyav boto3 awscli librosa azure-storage-blob && \
    pip install -r requirements.txt && \
    pip uninstall -y onnxruntime-gpu && \
    pip install onnxruntime-gpu==1.20.1


FROM middle AS shared

RUN cd ${ROOT} && rm -rf ${COMFY_DIR}

FROM shared AS langflow

# Install uv through pip
RUN pip install uv

# Install Langflow with uv
RUN uv pip install --system langflow

# Add Langflow startup to init.d
COPY scripts/langflow /etc/init.d/langflow
RUN chmod +x /etc/init.d/langflow && \
    update-rc.d langflow defaults

COPY config/shared ${ROOT}/shared_custom_nodes

RUN find ${ROOT}/shared_custom_nodes -name "requirements.txt" -execdir pip install -r {} \;

FROM langflow AS end

ARG COMFY_REPO_URL=https://github.com/comfyanonymous/ComfyUI.git
ENV COMFY_REPO_URL=${COMFY_REPO_URL}

# Copy init.d scripts
COPY scripts/comfyui /etc/init.d/comfyui
# 2025-04-12 18:38: Added a1111 init.d script
COPY scripts/a1111 /etc/init.d/a1111

RUN chmod +x /etc/init.d/comfyui /etc/init.d/a1111 && \
    update-rc.d comfyui defaults && \
    update-rc.d a1111 defaults

# 2025-04-12 18:37: Added a1111 script to /usr/local/bin
COPY ./scripts/mgpu /usr/local/bin/mgpu
COPY ./scripts/a1111 /usr/local/bin/a1111
RUN chmod +x /usr/local/bin/mgpu /usr/local/bin/a1111

# >>> ADDED FOR EMP-REDIS-WORKER
COPY scripts/worker /etc/init.d/worker
RUN chmod +x /etc/init.d/worker
RUN update-rc.d worker defaults

# Added: 2025-04-07T16:24:00-04:00 - Worker watchdog for automatic restart
COPY scripts/worker_watchdog.sh /usr/local/bin/worker_watchdog.sh
RUN chmod +x /usr/local/bin/worker_watchdog.sh

COPY scripts/worker-watchdog /etc/init.d/worker-watchdog
RUN chmod +x /etc/init.d/worker-watchdog
RUN update-rc.d worker-watchdog defaults

COPY scripts/wgpu /usr/local/bin/wgpu
RUN chmod +x /usr/local/bin/wgpu
# <<< END ADDED FOR EMP-REDIS-WORKER

RUN mkdir -p /usr/local/lib/mcomfy
COPY ./scripts/mcomfy /usr/local/bin/mcomfy
RUN chmod +x /usr/local/bin/mcomfy

COPY ./scripts/update_nodes.sh /usr/local/lib/mcomfy/update_nodes.sh
RUN chmod +x /usr/local/lib/mcomfy/update_nodes.sh

# Copy startup script
COPY scripts/start.sh /scripts/start.sh
RUN chmod +x /scripts/start.sh

COPY config/stake-or-die-e419d53af34a.json /credentials/stake-or-die-e419d53af34a.json

# Add build argument for fresh clone
ARG FORCE_FRESH_CLONE=false
# Cache buster for fresh clone
ADD "https://www.random.org/cgi-bin/randbyte?nbytes=10&format=h" /tmp/random

RUN echo "Debug: FORCE_FRESH_CLONE value is '${FORCE_FRESH_CLONE}'" && \
    if [ "${FORCE_FRESH_CLONE}" = "true" ]; then \
        echo "Forcing fresh clone..." && \
        rm -rf "${ROOT}/shared" && \
        mkdir -p ${ROOT}/shared && \
        git clone https://github.com/stakeordie/emprops_shared.git ${ROOT}/shared; \
    else \
        echo "Using cached clone if available..." && \
        mkdir -p ${ROOT}/shared && \
        git clone https://github.com/stakeordie/emprops_shared.git ${ROOT}/shared || true; \
    fi


# RUN usermod -aG crontab ubuntu
# Create cron pid directory with correct permissions
RUN mkdir -p /var/run/cron \
    && touch /var/run/cron/crond.pid \
    && chmod 644 /var/run/cron/crond.pid
RUN sed -i 's/touch $PIDFILE/# touch $PIDFILE/g' /etc/init.d/cron

RUN cd ${ROOT} && git-lfs install 

# Copy cleanup script and setup cron
COPY scripts/cleanup_outputs.sh /usr/local/bin/cleanup_outputs.sh
RUN chmod +x /usr/local/bin/cleanup_outputs.sh && \
    echo "*/15 * * * * /usr/local/bin/cleanup_outputs.sh >> /var/log/cleanup.log 2>&1" > /etc/cron.d/cleanup && \
    chmod 0644 /etc/cron.d/cleanup && \
    mkdir -p /var/run/cron && \
    touch /var/run/cron/crond.pid && \
    chmod 644 /var/run/cron/crond.pid && \
    sed -i 's/touch $PIDFILE/# touch $PIDFILE/g' /etc/init.d/cron
    
# Added: 2025-04-14T18:41:00-04:00 - Automatic1111 setup
# Setup Automatic1111 template directory


# Copy Automatic1111 scripts
# Added: 2025-04-14T18:55:00-04:00 - Moved scripts to /scripts/ directory for consistency
RUN mkdir -p /scripts/a1111_scripts
COPY scripts/a1111_scripts/ /scripts/a1111_scripts/
RUN chmod +x /scripts/a1111_scripts/*

RUN mkdir -p /tmp/a1111_template && \
    cd /tmp && \
    chmod +x /scripts/a1111_scripts/a1111_clone.sh && \
    cd /tmp/a1111_template && \
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git . && \
    git reset --hard cf2772fab0af5573da775e7437e6acdca424f26e

# Clone required repositories for Automatic1111
# Added: 2025-04-14T18:55:00-04:00 - Updated path for clone script
RUN cd /workspace && \
    mkdir -p /repositories && \
    /scripts/a1111_scripts/a1111_clone.sh stable-diffusion-stability-ai https://github.com/Stability-AI/stablediffusion.git cf1d67a6fd5ea1aa600c4df58e5b47da45f6bdbf && \
    /scripts/a1111_scripts/a1111_clone.sh CodeFormer https://github.com/sczhou/CodeFormer.git c5b4593074ba6214284d6acd5f1719b6c5d739af && \
    /scripts/a1111_scripts/a1111_clone.sh BLIP https://github.com/salesforce/BLIP.git 48211a1594f1321b00f14c9f7a5b4813144b2fb9 && \
    /scripts/a1111_scripts/a1111_clone.sh k-diffusion https://github.com/crowsonkb/k-diffusion.git ab527a9a6d347f364e3d185ba6d714e22d80cb3c && \
    /scripts/a1111_scripts/a1111_clone.sh clip-interrogator https://github.com/pharmapsychotic/clip-interrogator 2cf03aaf6e704197fd0dae7c7f96aa59cf1b11c9 && \
    /scripts/a1111_scripts/a1111_clone.sh generative-models https://github.com/Stability-AI/generative-models 45c443b316737a4ab6e40413d7794a7f5657c19f

# Install tcmalloc to fix memory leaks
ENV LD_PRELOAD=libtcmalloc.so

# Create directories for models and outputs
# Added: 2025-04-14T18:42:00-04:00 - Using template directory approach for multi-GPU support
RUN mkdir -p /tmp/a1111_template/models/Stable-diffusion \
    /tmp/a1111_template/models/VAE-approx \
    /tmp/a1111_template/models/karlo \
    /data/models/Stable-diffusion \
    /data/models/VAE-approx \
    /data/models/karlo \
    /data/embeddings \
    /data/config/auto \
    /data/config/auto/scripts \
    /output/txt2img-images \
    /output/img2img-images \
    /output/extras-images \
    /output/txt2img-grids \
    /output/img2img-grids \
    /output/saved

# Start services and application
CMD ["/scripts/start.sh"]