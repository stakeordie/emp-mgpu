# Updated: 2025-05-14T18:41:11-04:00 - Added CUDA version selection via build arg
# Builder stage for SSH key
ARG BASE_IMAGE=pytorch/pytorch:latest

# Select base image based on CUDA version
FROM ${BASE_IMAGE} AS start

# Updated: 2025-04-24T15:56:14-04:00 - Added Google Cloud SDK and Azure CLI installation
RUN apt update && apt-get install -y \
    git git-lfs rsync nginx wget curl jq tar nano net-tools lsof nvtop multitail ffmpeg libsm6 libxext6\
    cron sudo ssh zstd build-essential libgoogle-perftools-dev cmake ninja-build \
    gcc g++ openssh-client libx11-dev libxrandr-dev libxinerama-dev \
    libxcursor-dev libxi-dev libgl1-mesa-dev libglfw3-dev software-properties-common \
    apt-transport-https ca-certificates gnupg lsb-release \
    && curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - \
    && apt-get update && apt-get install -y google-cloud-cli \
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

RUN pip install --upgrade pip

RUN if [ "$BASE_IMAGE" = "pytorch/pytorch:latest" ]; then \
    echo "LOLLYPOP"; \
else \
    echo "ICECREAM"; \
fi

RUN if [ "$BASE_IMAGE" = "pytorch/pytorch:latest" ]; then \
    pip install --upgrade torch==2.5.1 torchvision==0.20.0 torchaudio==2.5.1; \
else \
    pip install --upgrade torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0; \
fi

RUN git clone https://github.com/comfyanonymous/ComfyUI.git ${COMFY_DIR} && \
    cd ${COMFY_DIR} && \
    pip uninstall onnxruntime && \
    pip install --upgrade pip && \
    pip install --upgrade mmengine opencv-python imgui-bundle boto3 awscli librosa azure-storage-blob && \
    pip install -r requirements.txt && \
    pip uninstall -y onnxruntime-gpu && \
    pip install onnxruntime-gpu==1.20.1

RUN if [ "$BASE_IMAGE" = "pytorch/pytorch:latest" ]; then \
    pip install --upgrade pyav; \
fi


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

FROM langflow AS a1111

ARG COMFY_REPO_URL=https://github.com/stakeordie/ComfyUI.git
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

COPY ./scripts/update_models.sh /usr/local/lib/mcomfy/update_models.sh
RUN chmod +x /usr/local/lib/mcomfy/update_models.sh

# Copy startup script
COPY scripts/start.sh /scripts/start.sh
RUN chmod +x /scripts/start.sh

# [2025-05-16T18:10:00-04:00] Updated credential handling to be more secure
# Create empty credential files that will be populated at runtime
RUN mkdir -p /credentials && \
    echo '{"type": "service_account", "universe_domain": "googleapis.com"}' > /credentials/stake-or-die.json && \
    echo '{"type": "service_account", "universe_domain": "googleapis.com"}' > /credentials/emprops.json

# Credentials will be mounted or populated from environment variables at runtime

# Add build argument for fresh clone
ARG FORCE_FRESH_CLONE=false

# 2025-05-16T17:38:00-04:00: Optimized emprops_shared cloning for better caching
# Create shared directory first (this rarely changes)
RUN mkdir -p ${ROOT}/shared

# Conditionally clone based on FORCE_FRESH_CLONE
# Only use cache buster when FORCE_FRESH_CLONE is true
RUN if [ "${FORCE_FRESH_CLONE}" = "true" ]; then \
        # Use build date as cache buster instead of external URL
        echo "Forcing fresh clone at $(date)" && \
        rm -rf "${ROOT}/shared/*" && \
        git clone https://github.com/stakeordie/emprops_shared.git ${ROOT}/shared; \
    else \
        echo "Using cached clone if available..." && \
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

# Create a wrapper script to run A1111 with the correct environment
RUN echo '#!/bin/bash\n\
source /opt/conda/bin/activate a1111\n\
cd "$(dirname "$0")"\n\
exec python launch.py "$@"' > /usr/local/bin/run_a1111.sh && \
    chmod +x /usr/local/bin/run_a1111.sh

# 2025-05-16T17:40:00-04:00: Optimized A1111 setup for better caching
# Make clone script executable (this rarely changes)
RUN chmod +x /scripts/a1111_scripts/a1111_clone.sh

# Create base directories (this rarely changes)
RUN mkdir -p /tmp/a1111_template && mkdir -p /repositories

# Clone A1111 main repository
RUN cd /tmp/a1111_template && \
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git .

# Clone each repository separately for better caching
# Clone stable-diffusion-stability-ai
RUN cd /workspace && \
    /scripts/a1111_scripts/a1111_clone.sh stable-diffusion-stability-ai https://github.com/Stability-AI/stablediffusion.git cf1d67a6fd5ea1aa600c4df58e5b47da45f6bdbf

# Clone CodeFormer
RUN cd /workspace && \
    /scripts/a1111_scripts/a1111_clone.sh CodeFormer https://github.com/sczhou/CodeFormer.git c5b4593074ba6214284d6acd5f1719b6c5d739af

# Clone BLIP
RUN cd /workspace && \
    /scripts/a1111_scripts/a1111_clone.sh BLIP https://github.com/salesforce/BLIP.git 48211a1594f1321b00f14c9f7a5b4813144b2fb9

# Clone k-diffusion
RUN cd /workspace && \
    /scripts/a1111_scripts/a1111_clone.sh k-diffusion https://github.com/crowsonkb/k-diffusion.git ab527a9a6d347f364e3d185ba6d714e22d80cb3c

# Clone clip-interrogator
RUN cd /workspace && \
    /scripts/a1111_scripts/a1111_clone.sh clip-interrogator https://github.com/pharmapsychotic/clip-interrogator 2cf03aaf6e704197fd0dae7c7f96aa59cf1b11c9

# Clone generative-models
RUN cd /workspace && \
    /scripts/a1111_scripts/a1111_clone.sh generative-models https://github.com/Stability-AI/generative-models 45c443b316737a4ab6e40413d7794a7f5657c19f

# [2025-05-19T13:37:00-04:00] Disable tcmalloc to avoid errors
# Previous attempts to fix the tcmalloc library loading issue were unsuccessful
# Since tcmalloc is optional for performance and not critical for functionality,
# we're removing the LD_PRELOAD setting completely to avoid the error messages

# No ENV LD_PRELOAD setting - this removes the tcmalloc dependency

# 2025-05-16T17:36:00-04:00: Optimized conda and pip steps for better caching
# Create conda environment for A1111 with Python 3.10
RUN conda create -n a1111 python=3.10 -y

# Install PyTorch and related packages
RUN --mount=type=cache,target=/root/.cache/pip \
    /opt/conda/envs/a1111/bin/pip install \
    torch==2.0.1+cu118 \
    torchvision==0.15.2+cu118 \
    torchaudio==2.0.2+cu118 \
    --index-url https://download.pytorch.org/whl/cu118

# Install A1111 requirements in its conda environment
RUN --mount=type=cache,target=/root/.cache/pip \
    /opt/conda/envs/a1111/bin/pip install -r /scripts/a1111_scripts/a1111_requirements.txt

# Install additional dependencies from reference Dockerfile
RUN --mount=type=cache,target=/root/.cache/pip \
    /opt/conda/envs/a1111/bin/pip install \
    git+https://github.com/TencentARC/GFPGAN.git@8d2447a2d918f8eba5a4a01463fd48e45126a379 \
    git+https://github.com/openai/CLIP.git@d50d76daa670286dd6cacf3bcd80b5e4823fc8e1 \
    git+https://github.com/mlfoundations/open_clip.git@v2.20.0

# 2025-05-16T16:46:30-04:00: Added Gradio fix from reference Dockerfile
# 2025-05-16T16:59:00-04:00: Fixed source command for Docker compatibility
RUN sed -i 's/in_app_dir = .*/in_app_dir = True/g' /opt/conda/envs/a1111/lib/python3.10/site-packages/gradio/routes.py && \
    git config --global --add safe.directory '*'

# 2025-05-16T17:35:00-04:00: Clone repositories needed by A1111 - Split into separate RUN commands for better caching
# Create base directories first (this rarely changes)
RUN mkdir -p /tmp/a1111_template/repositories

# Clone CodeFormer
RUN cd /tmp/a1111_template && \
    git clone https://github.com/sczhou/CodeFormer.git repositories/CodeFormer && \
    cd repositories/CodeFormer && git reset --hard c5b4593074ba6214284d6acd5f1719b6c5d739af

# Clone BLIP
RUN cd /tmp/a1111_template && \
    git clone https://github.com/salesforce/BLIP.git repositories/BLIP && \
    cd repositories/BLIP && git reset --hard 48211a1594f1321b00f14c9f7a5b4813144b2fb9

# Clone k-diffusion
RUN cd /tmp/a1111_template && \
    git clone https://github.com/crowsonkb/k-diffusion.git repositories/k-diffusion && \
    cd repositories/k-diffusion && git reset --hard ab527a9a6d347f364e3d185ba6d714e22d80cb3c

# Clone clip-interrogator
RUN cd /tmp/a1111_template && \
    git clone https://github.com/pharmapsychotic/clip-interrogator repositories/clip-interrogator && \
    cd repositories/clip-interrogator && git reset --hard 2cf03aaf6e704197fd0dae7c7f96aa59cf1b11c9

# Clone generative-models
RUN cd /tmp/a1111_template && \
    git clone https://github.com/Stability-AI/generative-models repositories/generative-models && \
    cd repositories/generative-models && git reset --hard 45c443b316737a4ab6e40413d7794a7f5657c19f

# 2025-05-16T16:49:00-04:00: Install CodeFormer requirements
# 2025-05-16T17:00:00-04:00: Fixed source command for Docker compatibility
RUN /opt/conda/envs/a1111/bin/pip install -r /tmp/a1111_template/repositories/CodeFormer/requirements.txt

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


FROM a1111 AS end

RUN if [ "$BASE_IMAGE" = "pytorch/pytorch:latest" ]; then \
    echo "LOLLYPOP"; \
else \
    echo "ICECREAM"; \
fi

# Start services and application
CMD ["/scripts/start.sh"]