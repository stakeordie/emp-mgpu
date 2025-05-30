#!/bin/bash
# Only enable debug mode if DEBUG is set
if [ "${DEBUG:-}" = "true" ]; then
    set -x
fi

ROOT="${ROOT:-/workspace}"
LOG_DIR="${ROOT}/logs"
START_LOG="${LOG_DIR}/start.log"


echo "BEFORE PATH: $PATH"

PATH=/usr/local/bin:$PATH

echo "AFTER PATH: $PATH"

locale-gen en_US.UTF-8

# Add at the top of the file with other env vars
COMFY_AUTH=""
update-locale LANG=en_US.UTF-8

# Ensure base directories exist
mkdir -p "$LOG_DIR" "${ROOT}/shared"
chmod 755 "$LOG_DIR" "${ROOT}/shared"
touch "$START_LOG"
chmod 644 "$START_LOG"

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # Only write to log file, don't duplicate to stdout unless DEBUG is set
    echo "[$timestamp] $*" | tee -a "$START_LOG"
    # For non-debug mode, only show important messages on screen
    case "$*" in
        *ERROR*|*FAIL*|*SUCCESS*|*READY*)
            echo "[$timestamp] $*" 
            ;;
    esac
}

main() {
    log ""
    log "====================================="
    log "      Starting ComfyUI Setup         "
    log "====================================="
    log ""
    log "=============== Steps ================"
    log "1. Check environment variables"
    log "2. Setup SSH access"
    log "3. Setup pre-installed nodes"
    log "4. Install nodes from config"
    log "5. Download models"
    log "6. Setup NGINX"
    log "7. Setup shared directories"
    log "8. Setup ComfyUI instances"
    log "9. Setup service scripts"
    log "10. Start NGINX"
    log "11. Start ComfyUI services"
    log "12. Verify all services"
    log "====================================="
    log ""
    
    # Phase 1: Check environment variables
    log_phase "1" "Checking environment variables"
    if ! setup_env_vars; then
        log "ERROR: Environment check failed"
        return 1
    fi
    
    # Phase 2: Setup SSH access
    log_phase "2" "Setting up SSH access"
    if ! setup_ssh_access; then
        log "ERROR: SSH setup failed"
        return 1
    fi
    
    # Phase 3: Setup pre-installed nodes
    log_phase "3" "Setting up custom nodes"
    setup_preinstalled_nodes

    log_phase "4&5" "aws sync"
    if ! s3_sync; then
        log "ERROR: AWS sync failed"
        return 1
    fi
    
    # Phase 6: Setup NGINX
    log_phase "6" "Setting up NGINX"
    if ! setup_nginx; then
        log "ERROR: NGINX setup failed"
        return 1
    fi
    
    # Phase 8: Setup ComfyUI instances
    log_phase "8" "Setting up ComfyUI instances"
    setup_comfyui
    
    # Phase 9: Setup service scripts
    log_phase "9" "Setting up service scripts"
    setup_service_scripts
    
    # Phase 10: Start NGINX
    log_phase "10" "Starting NGINX"
    start_nginx
    
    # Phase 11: Start ComfyUI services
    log_phase "11" "Starting ComfyUI services"
    start_comfyui

    # Start Langflow
    log_phase "12" "Starting Langflow"
    setup_langflow

    # Setup Redis Workers
    log_phase "13" "Starting Redis Workers"
    setup_redis_workers
    # Start Redis Workers
    start_redis_workers
    
    # Phase 14: Verify all services
    log_phase "14" "Verifying all services"
    if ! verify_and_report; then
        log "ERROR: Service verification failed"
        # Don't exit - keep container running for debugging
    fi


}

setup_env_vars() {
    log "Setting up environment variables..."
    
    # Install uv if not already installed
    if ! command -v uv >/dev/null 2>&1; then
        log "Installing uv package installer..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
    
    check_env_vars
    set_gpu_env
    
    # Clean up PATH to avoid duplicates
    clean_path="/opt/conda/bin:/workspace/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"   
    AWS_SECRET_ACCESS_KEY=$(echo "${AWS_SECRET_ACCESS_KEY_ENCODED}" | sed 's/_SLASH_/\//g')
    export AWS_SECRET_ACCESS_KEY
    
    # Persist environment variables for SSH sessions
    log "Persisting environment variables..."
    {
        echo "ROOT=${ROOT}"
        echo "NUM_GPUS=${NUM_GPUS}"
        echo "MOCK_GPU=${MOCK_GPU}"
        echo "TEST_GPUS=${TEST_GPUS:-}"
        echo "SERVER_CREDS=${SERVER_CREDS}"
        echo "COMFY_AUTH=${COMFY_AUTH}"
        echo "PATH=${clean_path}"
        echo "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
        echo "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}"
        echo "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"
        echo "OPENAI_API_KEY=${OPENAI_API_KEY}"
        echo "LANGFLOW_AUTO_LOGIN=${LANGFLOW_AUTO_LOGIN}"
        echo "LANGFLOW_SUPERUSER=${LANGFLOW_SUPERUSER}"
        echo "LANGFLOW_SUPERUSER_PASSWORD=${LANGFLOW_SUPERUSER_PASSWORD}"
        echo "LANGFLOW_SECRET_KEY=${LANGFLOW_SECRET_KEY}"
        echo "LANGFLOW_NEW_USER_IS_ACTIVE=${LANGFLOW_NEW_USER_IS_ACTIVE}"
        echo "LANGFLOW_VARIABLES_TO_GET_FROM_ENVIRONMENT=${LANGFLOW_VARIABLES_TO_GET_FROM_ENVIRONMENT}"
        echo "COMFY_REPO_URL=${COMFY_REPO_URL}"
        echo "WORKER_REDIS_API_HOST=${WORKER_REDIS_API_HOST}"
        echo "WORKER_REDIS_API_PORT=${WORKER_REDIS_API_PORT}"
        echo "WORKER_USE_SSL=${WORKER_USE_SSL}"
        echo "WORKER_CONNECTORS=${WORKER_CONNECTORS}"
        echo "WORKER_WEBSOCKET_AUTH_TOKEN=${WORKER_WEBSOCKET_AUTH_TOKEN}"
        echo "WORKER_HEARTBEAT_INTERVAL=${WORKER_HEARTBEAT_INTERVAL:-20}"
        echo "WORKER_LOG_LEVEL=${WORKER_LOG_LEVEL:-INFO}"
        echo "WORKER_SIMULATION_JOB_TYPE=${WORKER_SIMULATION_JOB_TYPE:-simulation}"
        echo "WORKER_SIMULATION_PROCESSING_TIME=${WORKER_SIMULATION_PROCESSING_TIME:-10}"
        echo "WORKER_SIMULATION_STEPS=${WORKER_SIMULATION_STEPS:-5}"
    } >> /etc/environment
    

        log "WORKER_REDIS_API_HOST: ${WORKER_REDIS_API_HOST}"
        log "WORKER_REDIS_API_PORT: ${WORKER_REDIS_API_PORT}"
        log "WORKER_USE_SSL: ${WORKER_USE_SSL}"
        log "WORKER_WEBSOCKET_AUTH_TOKEN: ${WORKER_WEBSOCKET_AUTH_TOKEN}"
        log "WORKER_CONNECTORS: ${WORKER_CONNECTORS}"
        log "WORKER_HEARTBEAT_INTERVAL: ${WORKER_HEARTBEAT_INTERVAL}"
        log "WORKER_LOG_LEVEL: ${WORKER_LOG_LEVEL}"
        log "WORKER_SIMULATION_JOB_TYPE: ${WORKER_SIMULATION_JOB_TYPE}"
        log "WORKER_SIMULATION_PROCESSING_TIME: ${WORKER_SIMULATION_PROCESSING_TIME}"
        log "WORKER_SIMULATION_STEPS: ${WORKER_SIMULATION_STEPS}"

    # Also add to profile for interactive sessions
    {
        echo "ROOT=${ROOT}"
        echo "NUM_GPUS=${NUM_GPUS}"
        echo "MOCK_GPU=${MOCK_GPU}"
        echo "TEST_GPUS=${TEST_GPUS:-}"
        echo "SERVER_CREDS=${SERVER_CREDS}"
        echo "COMFY_AUTH=${COMFY_AUTH}"
        echo "PATH=${clean_path}"
        echo "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
        echo "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}"
        echo "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"
        echo "OPENAI_API_KEY=${OPENAI_API_KEY}"
        echo "LANGFLOW_AUTO_LOGIN=${LANGFLOW_AUTO_LOGIN}"
        echo "LANGFLOW_SUPERUSER=${LANGFLOW_SUPERUSER}"
        echo "LANGFLOW_SUPERUSER_PASSWORD=${LANGFLOW_SUPERUSER_PASSWORD}"
        echo "LANGFLOW_SECRET_KEY=${LANGFLOW_SECRET_KEY}"
        echo "LANGFLOW_NEW_USER_IS_ACTIVE=${LANGFLOW_NEW_USER_IS_ACTIVE}"
        echo "LANGFLOW_VARIABLES_TO_GET_FROM_ENVIRONMENT=${LANGFLOW_VARIABLES_TO_GET_FROM_ENVIRONMENT}"
        echo "COMFY_REPO_URL=${COMFY_REPO_URL}"
        echo "WORKER_REDIS_API_HOST=${WORKER_REDIS_API_HOST}"
        echo "WORKER_REDIS_API_PORT=${WORKER_REDIS_API_PORT}"
        echo "WORKER_USE_SSL=${WORKER_USE_SSL}"
        echo "WORKER_CONNECTORS=${WORKER_CONNECTORS}"
        echo "WORKER_WEBSOCKET_AUTH_TOKEN=${WORKER_WEBSOCKET_AUTH_TOKEN}"
        echo "WORKER_HEARTBEAT_INTERVAL=${WORKER_HEARTBEAT_INTERVAL:-20}"
        echo "WORKER_LOG_LEVEL=${WORKER_LOG_LEVEL:-INFO}"
        echo "WORKER_SIMULATION_JOB_TYPE=${WORKER_SIMULATION_JOB_TYPE:-simulation}"
        echo "WORKER_SIMULATION_PROCESSING_TIME=${WORKER_SIMULATION_PROCESSING_TIME:-10}"
        echo "WORKER_SIMULATION_STEPS=${WORKER_SIMULATION_STEPS:-5}"
    } > /etc/profile.d/comfyui-env.sh
    
    # Set for current session
    export PATH="${clean_path}"
    
    log "Environment variables persisted"
}

check_env_vars() {
    if [ -z "$HF_TOKEN" ]; then
        log "WARNING: HF_TOKEN environment variable not set"
    else
        log "HF_TOKEN environment variable set"
    fi

    if [ -z "$OPENAI_API_KEY" ]; then
        log "WARNING: OPENAI_API_KEY environment variable not set"
    else
        log "OPENAI_API_KEY environment variable set"
    fi
    
    if [ -z "$CUT_PK_1" ] || [ -z "$CUT_PK_2" ] || [ -z "$CUT_PK_3" ]; then
        log "WARNING: CUT_PK_1, CUT_PK_2, or CUT_PK_3 environment variables are not set"
    else
        log "CUT_PK_1, CUT_PK_2, and CUT_PK_3 environment variables set"
    fi

    if [ ! -d "$COMFY_DIR" ]; then
        log "ERROR: Working directory does not exist: $COMFY_DIR"
        return 1
    fi

    if [ -z "$TEST_GPUS" ]; then
        log "TEST_GPUS is not set"
    else
        log "TEST_GPUS is set"
    fi   
}

set_gpu_env() {
    log "=== GPU Environment Debug ==="
    
    # Check for test mode
    if [ -n "$TEST_GPUS" ] && [[ "$TEST_GPUS" =~ ^[1-9]+$ ]]; then
        log "Test mode: Mocking $TEST_GPUS GPUs"
        NUM_GPUS=$TEST_GPUS
        export NUM_GPUS
        export MOCK_GPU=1  # Flag to indicate we're in test mode
        return 0
    fi
    
    if command -v nvidia-smi &> /dev/null; then
        log "nvidia-smi is available"
        nvidia-smi 2>&1 | while read -r line; do log "  $line"; done
        
        # Get number of GPUs
        NUM_GPUS=$(nvidia-smi --list-gpus | wc -l)
        log "Found $NUM_GPUS GPUs"
        export NUM_GPUS
        export MOCK_GPU=0
    else
        # Treat CPU mode as mock mode with 1 GPU
        log "nvidia-smi not found, running in CPU mode (mocking 1 GPU)"
        NUM_GPUS=1
        export NUM_GPUS
        export MOCK_GPU=1
    fi
    
    log "GPU Environment: NUM_GPUS=$NUM_GPUS MOCK_GPU=$MOCK_GPU"
}

setup_ssh_access() {
    log "Starting SSH agent"
    eval "$(ssh-agent -s)"

    log "Setting up SSH access..."
    
    # Verify SSH directory exists and has correct permissions
    if [ ! -d "/root/.ssh" ]; then
        log "Creating /root/.ssh directory"
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
    fi
    
    # Verify directory permissions
    if [ "$(stat -c %a /root/.ssh)" != "700" ]; then
        log "Fixing /root/.ssh directory permissions"
        chmod 700 /root/.ssh
    fi

    # Check if all key parts are present
    if [ -n "$CUT_PK_1" ] && [ -n "$CUT_PK_2" ] && [ -n "$CUT_PK_3" ]; then
        # Combine the key parts
        full_base64_key="${CUT_PK_1}${CUT_PK_2}${CUT_PK_3}"
        
        # Decode the base64 key
        if ! full_key=$(echo "$full_base64_key" | base64 -d); then
            log "ERROR: Failed to decode base64 key"
            return 1
        fi
        
        # Write the key to file
        if ! echo "$full_key" > /root/.ssh/id_ed25519; then
            log "ERROR: Failed to write SSH key to file"
            return 1
        fi
        
        # Set correct permissions
        chmod 400 /root/.ssh/id_ed25519
        
        # Verify key file exists and has correct permissions
        if [ ! -f "/root/.ssh/id_ed25519" ]; then
            log "ERROR: SSH key file not found after creation"
            return 1
        fi
        
        if [ "$(stat -c %a /root/.ssh/id_ed25519)" != "400" ]; then
            log "ERROR: SSH key file has incorrect permissions"
            chmod 400 /root/.ssh/id_ed25519
        fi
        
        # Try to add the key
        if ! ssh-add /root/.ssh/id_ed25519; then
            log "ERROR: Failed to add SSH key to agent"
            return 1
        fi
        
        # Verbose key validation
        log "Validating SSH key..."
        if ! ssh-keygen -y -f /root/.ssh/id_ed25519; then
            log "ERROR: SSH key validation failed"
            return 1
        fi
        
        # Test SSH connection to GitHub with retries
        log "Testing GitHub SSH connection..."
        local max_attempts=3
        local attempt=1
        local success=false
        
        while [ $attempt -le $max_attempts ]; do
            log "SSH connection attempt $attempt of $max_attempts"
            if ssh -T git@github.com -o StrictHostKeyChecking=no 2>&1 | grep -q "successfully authenticated"; then
                success=true
                break
            else
                log "SSH attempt $attempt failed with exit code $?"
            fi
            attempt=$((attempt + 1))
            if [ $attempt -le $max_attempts ]; then
                log "Waiting 10 seconds before next attempt..."
                sleep 10
                log "Resuming after wait"
            fi
        done
        
        if [ "$success" != "true" ]; then
            log "ERROR: Failed to connect to GitHub after $max_attempts attempts"
            return 1
        fi
        
        log "SSH key successfully set up and verified"
    else
        # Detailed logging if key parts are missing
        [ -z "$CUT_PK_1" ] && log "Missing CUT_PK_1"
        [ -z "$CUT_PK_2" ] && log "Missing CUT_PK_2"
        [ -z "$CUT_PK_3" ] && log "Missing CUT_PK_3"

        log "ERROR: SSH key parts are missing"
        return 1
    fi

    # Add GitHub to known hosts if not present
    touch /root/.ssh/known_hosts
    chmod 644 /root/.ssh/known_hosts
    if ! grep -q "github.com" /root/.ssh/known_hosts; then
        ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null
    fi
    
    # Final verification
    log "Final SSH setup verification:"
    log "- SSH directory: $(ls -ld /root/.ssh)"
    log "- SSH key file: $(ls -l /root/.ssh/id_ed25519)"
    log "- Known hosts: $(ls -l /root/.ssh/known_hosts)"
}

setup_preinstalled_nodes() {
    log "Setting up pre-installed custom nodes..."
    if [ -d "/workspace/shared_custom_nodes" ]; then
        log "Found pre-installed nodes, moving to shared directory"
        mv /workspace/shared_custom_nodes "${ROOT}/shared/custom_nodes"
        log "Contents of shared custom_nodes directory:"
        ls -la "${ROOT}/shared/custom_nodes" | while read -r line; do log "  $line"; done
    else
        log "No pre-installed nodes found at /workspace/shared_custom_nodes"
    fi
}

sync_models() {
    log "=== Starting model sync process ==="
    
    # Determine which bucket to use based on AWS_TEST_MODE
    local bucket="emprops-share"
    if [ "${AWS_TEST_MODE:-false}" = "true" ]; then
        log "Using test bucket: emprops-share-test"
        bucket="emprops-share-test"
    else
        log "Using production bucket: emprops-share"
    fi

    # Sync models and configs from S3
    log "Starting sync from s3://$bucket to /workspace/shared..."
    if [ "${SKIP_AWS_SYNC:-false}" = "true" ]; then
        log "Skipping AWS S3 sync (SKIP_AWS_SYNC=true)"
    else
        log "Running AWS S3 sync command..."
        aws s3 sync "s3://$bucket" /workspace/shared --size-only --exclude "custom_nodes/*" 2>&1 | tee -a "${START_LOG}"
        local sync_status=$?
        if [ $sync_status -eq 0 ]; then
            log "SUCCESS: AWS S3 sync completed successfully"
        else
            log "ERROR: AWS S3 sync failed with status $sync_status"
            return 1
        fi
    fi
    
    log "=== Model sync process complete ==="
}

manage_custom_nodes() {
    log "=== Starting custom node management ==="

    # Determine which config file to use
    local config_file="/workspace/shared/config_nodes.json"
    if [ "${AWS_TEST_MODE:-false}" = "true" ]; then
        log "Using test config: config_nodes_test.json"
        config_file="/workspace/shared/config_nodes_test.json"
    fi

    log "Using config file: $config_file"
    
    if [ ! -f "$config_file" ]; then
        log "ERROR: Config file $config_file not found"
        return 1
    fi

    log "Validating config file format..."
    if ! jq empty "$config_file" 2>/dev/null; then
        log "ERROR: Invalid JSON in config file"
        return 1
    fi

    cd /workspace/shared/custom_nodes || {
        log "ERROR: Failed to change to custom_nodes directory"
        return 1
    }

    log "Processing custom nodes from config..."
    for node in $(jq -r '.custom_nodes[] | @base64' "$config_file"); do
        _jq() {
            echo "${node}" | base64 --decode | jq -r "${1}"
        }
        
        name=$(_jq '.name')
        url=$(_jq '.url')
        branch=$(_jq '.branch')
        commit=$(_jq '.commit // empty')
        install_reqs=$(_jq '.requirements')
        recursive=$(_jq '.recursive')
        env_vars=$(_jq '.env')
        
        if [ "$name" != "null" ] && [ "$url" != "null" ]; then
            log "Processing node: $name"
            log "  URL: $url"
            log "  Branch: ${branch:-default}"
            log "  Commit: ${commit:-latest}"
            
            # Clone if directory doesn't exist
            if [ ! -d "$name" ]; then
                log "  Cloning new node: $name"
                
                # Build git clone command
                clone_cmd="git clone"
                if [ "$recursive" = "true" ]; then
                    log "  Using recursive clone"
                    clone_cmd="$clone_cmd --recursive"
                fi
                
                if [ "$branch" != "null" ] && [ ! -z "$branch" ]; then
                    log "  Cloning specific branch: $branch"
                    $clone_cmd -b "$branch" "$url" "$name" || {
                        log "ERROR: Failed to clone branch $branch for $name"
                        continue
                    }
                else
                    log "  Cloning default branch"
                    $clone_cmd "$url" "$name" || {
                        log "ERROR: Failed to clone default branch for $name"
                        continue
                    }
                fi
            fi
            
            # Handle specific commit if specified
            if [ ! -z "$commit" ]; then
                log "  Resetting to specific commit: $commit"
                (cd "$name" && git reset --hard "$commit") || {
                    log "ERROR: Failed to reset to commit $commit for $name"
                    continue
                }
            fi
            
            # Handle environment variables
            if [ "$env_vars" != "null" ] && [ ! -z "$env_vars" ]; then
                log "  Setting up .env file"
                : > "$name/.env"
                
                while IFS="=" read -r key value; do
                    if [ ! -z "$key" ]; then
                        expanded_value=$(eval echo "$value")
                        echo "$key=$expanded_value" >> "$name/.env"
                        log "    Added env var: $key"
                    fi
                done < <(echo "$env_vars" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"')
            fi
            
            # Handle requirements installation
            if [ "$install_reqs" = "true" ]; then
                if [ -f "$name/requirements.txt" ]; then
                    log "  Installing requirements using uv..."
                    (cd "$name" && uv pip install --system -r requirements.txt) || {
                        log "WARNING: uv install failed, falling back to pip..."
                        (cd "$name" && pip install -r requirements.txt) || {
                            log "ERROR: Failed to install requirements for $name"
                            continue
                        }
                    }
                    log "  Requirements installed successfully"
                else
                    log "  No requirements.txt found"
                fi
            fi
            
            log "  Node $name processed successfully"
        fi
    done
    
    log "=== Custom node management complete ==="
}

s3_sync() {
    log "=== Starting combined sync process ==="
    
    # First sync models
    if ! sync_models; then
        log "ERROR: Model sync failed"
        return 1
    fi
    
    # Then manage custom nodes
    if ! manage_custom_nodes; then
        log "ERROR: Custom node management failed"
        return 1
    fi
    
    log "=== Combined sync process complete ==="
}

setup_nginx() {
    log "Setting up NGINX..."
    
    # Setup auth first
    if ! setup_nginx_auth; then
        log "ERROR: Failed to setup NGINX authentication"
        return 1
    fi
    
    ssh-agent bash << 'EOF'
        eval "$(ssh-agent -s)"
        ssh-add /root/.ssh/id_ed25519
        
        git clone git@github.com:stakeordie/emprops-nginx-conf.git /etc/nginx-repo
EOF

    if [ ! -d "/etc/nginx-repo" ]; then
        log "Failed to clone nginx repo"
        return 1
    fi

    rm -rf /etc/nginx

    ln -s /etc/nginx-repo/node /etc/nginx

    log "Nginx configuration set up"
}

setup_nginx_auth() {
    log "Setting up NGINX authentication..."
    
    # Create nginx directory if it doesn't exist
    if [ ! -d "/etc/nginx" ]; then
        log "Creating /etc/nginx directory"
        mkdir -p /etc/nginx
        chmod 755 /etc/nginx
    fi
    
    # Check if auth credentials are available
    if [ -n "$SERVER_CREDS" ]; then
        # Write credentials to .sd file
        if ! echo "$SERVER_CREDS" > /etc/nginx/.sd; then
            log "ERROR: Failed to write auth credentials to file"
            return 1
        fi
        
        # Set correct permissions
        chmod 600 /etc/nginx/.sd
        
        # Verify file exists and has correct permissions
        if [ ! -f "/etc/nginx/.sd" ]; then
            log "ERROR: Auth file not found after creation"
            return 1
        fi
        
        if [ "$(stat -c %a /etc/nginx/.sd)" != "600" ]; then
            log "ERROR: Auth file has incorrect permissions"
            chmod 600 /etc/nginx/.sd
        fi
        
        log "NGINX authentication setup complete"
    else
        log "ERROR: SERVER_CREDS not set"
        return 1
    fi
}

setup_comfyui() {
    log "Setting up ComfyUI..."

    pip uninstall -y opencv-python opencv-python-headless opencv-contrib-python-headless opencv-contrib-python && pip install opencv-python opencv-python-headless opencv-contrib-python-headless && pip install opencv-contrib-python
        
    # Add --cpu flag in test mode
    if [ "${MOCK_GPU:-0}" -eq 1 ]; then
        log "Test mode: Adding --cpu flag to all instances"
        export COMFY_ARGS="--cpu"
    else
        log "Setting up GPU mode with $NUM_GPUS GPUs"
    fi
    
    # Setup GPU instances
    log "Setting up GPU instances..."
    if ! mgpu setup all; then
        log "ERROR: Failed to set up GPU instances"
        return 1
    fi
    
    # Start services
    log "Starting GPU services..."
    if ! mgpu start all; then
        log "ERROR: Failed to start GPU services"
        return 1
    fi
    
    # Quick status check
    log "Verifying services..."
    mgpu status all >/dev/null || {
        log "ERROR: Service verification failed"
        return 1
    }
    
    log "ComfyUI setup complete"
    return 0
}

setup_service_scripts() {
    log "Setting up service scripts"
    
    # Verify mgpu script is available
    if ! command -v mgpu >/dev/null 2>&1; then
        log "ERROR: MGPU command not found in PATH"
        return 1
    fi
    
    # Update service defaults if needed
    if ! update-rc.d comfyui defaults; then
        log "WARNING: Failed to update ComfyUI service defaults"
    fi
    
    log "Service scripts initialized"
}

setup_services() {
    log "Setting up cron..."
    
    # Setup and start cron if cleanup is needed
    if [ -d "${COMFY_DIR}/output" ]; then
        log "Setting up cleanup cron job..."
        CRON_JOB="0 * * * * rm -f ${COMFY_DIR}/output/*"
        (crontab -l 2>/dev/null | grep -v "$COMFY_DIR/output"; echo "$CRON_JOB") | crontab -
        
        log "Starting cron service..."
        service cron start
    else
        log "Output directory not found, skipping cron setup"
    fi
}

start_nginx() {
    log "Starting NGINX..."
    
    # Stop nginx if it's already running
    if service nginx status >/dev/null 2>&1; then
        log "NGINX is already running, stopping it first..."
        service nginx stop
    fi
    
    # Start nginx
    log "Starting NGINX service..."
    if ! service nginx start; then
        log "ERROR: Failed to start NGINX"
        return 1
    fi
    
    # Verify it's running
    sleep 2
    if ! service nginx status >/dev/null 2>&1; then
        log "ERROR: NGINX failed to start"
        service nginx status | while read -r line; do log "  $line"; done
        return 1
    fi
    
    log "NGINX started successfully"
}

start_comfyui() {
    log "Starting ComfyUI services..."

    pip uninstall -y onnxruntime-gpu

    pip install onnxruntime-gpu
    
    if [ "${MOCK_GPU:-0}" -eq 1 ]; then
        log "Starting ComfyUI in mock mode with $NUM_GPUS instances"
        export COMFY_ARGS="--cpu"
    else
        log "Setting up GPU mode with $NUM_GPUS GPUs"
    fi
    
    if ! mgpu start all; then
        log "ERROR: Failed to start ComfyUI services"
        mgpu status all 2>&1 | tail -n 5 | while read -r line; do log "  $line"; done
        return 1
    fi
    
    # Check services
    if ! verify_services; then
        return 1
    fi
}

log_phase() {
    local phase_num=$1
    local phase_name=$2
    log ""
    log "===================================="
    log "Phase $phase_num: $phase_name"
    log "===================================="
}

verify_and_report() {
    log ""
    log "===================================="
    log "Starting Service Verification"
    log "===================================="
    
    # Give services a moment to start if they just started
    sleep 2
    
    # Run comprehensive verification
    verify_services
    
    # Final user instructions
    if [ "$all_services_ok" = true ]; then
        log ""
        log "===================================="
        log "All services are running correctly"
        log "Use 'mgpu logs-all' to monitor all services"
        log "===================================="
        return 0
    else
        log ""
        log "===================================="
        log "WARNING: Some services are not functioning correctly"
        log "Check the logs above for specific errors"
        log "Use 'mgpu logs-all' to monitor services for errors"
        log "===================================="
        return 1
    fi
}

verify_services() {
    local all_services_ok=true
    
    # 1. Check NGINX
    log "Checking NGINX..."
    if ! service nginx status >/dev/null 2>&1; then
        log "ERROR: NGINX is not running"
        service nginx status 2>&1 | while read -r line; do log "  $line"; done
        all_services_ok=false
    else
        log "NGINX is running"
    fi

    # Setup auth for testing requests
    setup_auth
    
    # 2. Check ComfyUI Services
    if [ "${MOCK_GPU:-0}" -eq 1 ]; then
        log "Checking ComfyUI services in mock mode ($NUM_GPUS instances)..."
    else
        log "Checking ComfyUI services in GPU mode ($NUM_GPUS GPUs)..."
    fi

    for instance in $(seq 0 $((NUM_GPUS-1))); do
        log "Checking instance $instance..."
        
        # Check service
        if ! mgpu status "$instance" | grep -q "running"; then
            log "ERROR: ComfyUI service for instance $instance is not running"
            mgpu status "$instance" 2>&1 | while read -r line; do log "  $line"; done
            all_services_ok=false
            continue
        fi
        
        # Check proxy port
        local proxy_port=$((3188 + instance))
        if ! netstat -tuln | grep -q ":$proxy_port "; then
            log "ERROR: NGINX proxy port $proxy_port is not listening"
            log "Current listening ports:"
            netstat -tuln | while read -r line; do log "  $line"; done
            all_services_ok=false
        fi
        
        # Check logs
        local log_dir="${ROOT}/comfyui_gpu${instance}/logs/output.log"
        
        if [ ! -f "$log_dir" ]; then
            log "ERROR: Missing log file: $log_dir"
            all_services_ok=false
        else
            log "=== Last 5 lines of $log_dir ==="
            tail -n 5 "$log_dir" | while read -r line; do log "  $line"; done
        fi
        
        # Try a test request
        if ! make_auth_request "http://localhost:$proxy_port/system_stats"; then
            log "ERROR: ComfyUI instance $instance is not responding to requests"
            log "Curl verbose output:"
            make_auth_request "http://localhost:$proxy_port/system_stats" "verbose" 2>&1 | while read -r line; do log "  $line"; done
            all_services_ok=false
        fi
    done
    
    # 3. Final Summary
    log "=== Service Status Summary ==="
    log "NGINX: $(service nginx status >/dev/null 2>&1 && echo "RUNNING" || echo "NOT RUNNING")"
    log "Langflow: $(service langflow status >/dev/null 2>&1 && echo "RUNNING" || echo "NOT RUNNING")"
    
    for instance in $(seq 0 $((NUM_GPUS-1))); do
        local service_status=$(mgpu status "$instance" | grep -q "running" && echo "RUNNING" || echo "NOT RUNNING")
        local proxy_port=$((3188 + instance))
        local proxy_status=$(netstat -tuln | grep -q ":$proxy_port " && echo "LISTENING" || echo "NOT LISTENING")
        local api_status=$(make_auth_request "http://localhost:$proxy_port/system_stats" && echo "RESPONDING" || echo "NOT RESPONDING")
        
        if [ "${MOCK_GPU:-0}" -eq 1 ]; then
            log "ComfyUI Mock Instance $instance: Service: $service_status, Proxy: $proxy_status, API: $api_status"
        else
            log "ComfyUI GPU $instance: Service: $service_status, Proxy: $proxy_status, API: $api_status"
        fi
        
        # Also report worker status
        local worker_status=$(wgpu status "$instance" | grep -q "running" && echo "RUNNING" || echo "NOT RUNNING")
        log "Redis Worker $instance: Service: $worker_status"
    done
    
    # Check Langflow
    log "Checking Langflow service..."
    if ! service langflow status >/dev/null 2>&1; then
        log "ERROR: Langflow service is not running"
        service langflow status 2>&1 | while read -r line; do log "  $line"; done
        all_services_ok=false
    else
        log "Langflow service is running"
        
        # Check Langflow port
        local langflow_port=7860
        if ! netstat -tuln | grep -q ":$langflow_port "; then
            log "ERROR: Langflow port $langflow_port is not listening"
            all_services_ok=false
        else
            log "Langflow port $langflow_port is listening"
            
            # Try a test request to Langflow
            if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:$langflow_port/ | grep -q "200\|302"; then
                log "ERROR: Langflow is not responding to requests"
                all_services_ok=false
            else
                log "Langflow is responding to requests"
            fi
        fi
    fi
    
    # Check Redis Workers
    log "Checking Redis Workers..."
    if ! empredis-mgr status all; then
        log "ERROR: One or more Redis Worker instances are not running"
        all_services_ok=false
    else
        log "Redis Workers: All instances reported running by empredis-mgr."
        
        # Check worker logs for connection status
        for instance in $(seq 0 $((NUM_GPUS-1))); do
            local worker_log_dir="${ROOT}/worker_gpu${instance}/logs/output.log"
            
            if [ ! -f "$worker_log_dir" ]; then
                log "ERROR: Missing worker log file: $worker_log_dir"
                all_services_ok=false
            else
                log "=== Last 10 lines of worker $instance log ==="
                tail -n 10 "$worker_log_dir" | while read -r line; do log "  $line"; done
                
                # Check for successful connection to Redis in logs
                if grep -q "Successfully connected to Redis" "$worker_log_dir"; then
                    log "Worker $instance has successfully connected to Redis"
                elif grep -q "Connecting to Redis" "$worker_log_dir"; then
                    log "Worker $instance is attempting to connect to Redis"
                else
                    log "WARNING: Worker $instance may not be connecting to Redis properly"
                    # Don't fail verification for this, just warn
                fi
                
                # Check connector status
                log "Checking connector status for worker $instance..."
                
                # Get list of connectors from environment or worker log
                local connectors=""
                if [ -n "$WORKER_CONNECTORS" ]; then
                    connectors="$WORKER_CONNECTORS"
                elif grep -q "WORKER_CONNECTORS" "$worker_log_dir"; then
                    connectors=$(grep "WORKER_CONNECTORS" "$worker_log_dir" | head -1 | sed 's/.*WORKER_CONNECTORS: \(.*\)/\1/')
                fi
                
                log "Worker $instance connectors: $connectors"
                
                # Check each connector
                if [[ "$connectors" == *"comfyui"* ]]; then
                    if grep -q "Successfully connected to ComfyUI" "$worker_log_dir"; then
                        log "Worker $instance has successfully connected to ComfyUI connector"
                    elif grep -q "Attempting to connect to ComfyUI" "$worker_log_dir"; then
                        log "Worker $instance is attempting to connect to ComfyUI connector"
                    else
                        log "WARNING: Worker $instance may not be connecting to ComfyUI connector properly"
                    fi
                fi
                
                if [[ "$connectors" == *"simulation"* ]]; then
                    if grep -q "Simulation connector initialized" "$worker_log_dir"; then
                        log "Worker $instance has initialized simulation connector"
                    else
                        log "WARNING: Worker $instance may not have initialized simulation connector"
                    fi
                fi
            fi
        done
    fi
    
    if [ "$all_services_ok" = true ]; then
        log "All services are running correctly"
        return 0
    else
        log "Some services have issues"
        return 1
    fi
}

setup_auth() {
    if [ -n "$SERVER_CREDS" ]; then
        # Add "sd:" prefix and base64 encode
        COMFY_AUTH=$(echo -n "sd:$SERVER_CREDS" | base64)
    else
        log "WARNING: SERVER_CREDS not set, authentication may fail"
    fi
}

make_auth_request() {
    local url=$1
    local auth_opts=""
    
    if [ -n "$COMFY_AUTH" ]; then
        # Decode base64 credentials for curl
        local decoded_creds=$(echo "$COMFY_AUTH" | base64 -d)
        auth_opts="-u '$decoded_creds'"
    fi
    
    if [ "$2" = "verbose" ]; then
        eval "curl -v $auth_opts '$url'"
    else
        eval "curl -s $auth_opts '$url'"
    fi
}

setup_langflow() {
    log "Setting up Langflow..."
    
    # Start Langflow service
    if ! service langflow start; then
        log "ERROR: Failed to start Langflow"
        return 1
    fi
    
    log "Langflow setup complete"
    return 0
}

setup_redis_workers() {
    log ""
    log "===================================="
    log "Starting Service Verification"
    log "===================================="
    
    
    local release_url="https://api.github.com/repos/stakeordie/emp-redis/releases/latest"
    local download_url
    local asset_name="emp-redis-worker.tar.gz"
    local setup_script_run_flag="${ROOT}/.worker_setup_done"

    # --- Get Download URL ---
    log "Fetching latest release information from $release_url"
    # Use curl and jq to find the download URL for the specific asset
    download_url=$(curl -sSL $release_url | jq -r --arg NAME "$asset_name" '.assets[] | select(.name == $NAME) | .browser_download_url')

    if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
        log "ERROR: Could not find asset '$asset_name' in the latest release. Please check the repository releases."
        return 1 # Indicate failure
    fi
    log "Found download URL: $download_url"

    # --- Download Once ---
    local tarball_path="/tmp/worker_package.tar.gz"
    log "Downloading $asset_name to $tarball_path..."
    if ! curl -sSL "$download_url" -o "$tarball_path"; then
        log "ERROR: Failed to download worker package from $download_url"
        rm -f "$tarball_path" # Clean up partial download
        return 1
    fi

    # --- Extract and Setup for each GPU ---
    for i in $(seq 0 $((NUM_GPUS-1))); do
        local WORKER_DIR="${ROOT}/worker_gpu${i}"
        log "Setting up worker in ${WORKER_DIR}"

        mkdir -p "${WORKER_DIR}/logs"
        if [ $? -ne 0 ]; then
            log "ERROR: Failed to create worker directory ${WORKER_DIR}"
            continue # Skip to next GPU
        fi

        # Extract worker files, stripping the top-level directory
        log "Extracting $tarball_path to ${WORKER_DIR}"
        if ! tar xzf "$tarball_path" -C "${WORKER_DIR}" --strip-components=1; then
            log "ERROR: Failed to extract worker package to ${WORKER_DIR}"
            rm -rf "${WORKER_DIR}" # Clean up failed extraction
            continue # Skip to next GPU
        fi

        # --- Setup Worker Environment ---
        # Determine the correct ComfyUI port for this worker
        # Restore original port calculation
        local comfyui_port=$((8188 + i))

        # Determine Worker ID
        host_identifier=$(echo "$HOSTNAME" | cut -d'-' -f1)
        worker_id="${host_identifier:-$HOSTNAME}-gpu${i}"


        
        log "WORKER_REDIS_API_HOST: ${WORKER_REDIS_API_HOST}"
        log "WORKER_REDIS_API_PORT: ${WORKER_REDIS_API_PORT}"
        log "WORKER_USE_SSL: ${WORKER_USE_SSL}"
        log "WORKER_WEBSOCKET_AUTH_TOKEN: ${WORKER_WEBSOCKET_AUTH_TOKEN}"
        log "WORKER_CONNECTORS: ${WORKER_CONNECTORS}"
        log "WORKER_HEARTBEAT_INTERVAL: ${WORKER_HEARTBEAT_INTERVAL}"
        log "WORKER_LOG_LEVEL: ${WORKER_LOG_LEVEL}"
        log "WORKER_SIMULATION_JOB_TYPE: ${WORKER_SIMULATION_JOB_TYPE}"
        log "WORKER_SIMULATION_PROCESSING_TIME: ${WORKER_SIMULATION_PROCESSING_TIME}"
        log "WORKER_SIMULATION_STEPS: ${WORKER_SIMULATION_STEPS}"

        

        # --- Run Worker Setup Script (if exists) ---
        local setup_script="${WORKER_DIR}/scripts/setup.sh"
        if [ -f "$setup_script" ]; then
            log "Running setup script for worker ${i}: $setup_script"
            # Run setup script from within the worker directory
            (cd "${WORKER_DIR}" && bash ./scripts/setup.sh)
            if [ $? -ne 0 ]; then
                log "ERROR: Worker setup script failed for worker ${i}"
                # Decide if this is fatal or just a warning
                # return 1 # Uncomment if failure should stop the whole process
            fi
        else
            log "Warning: Worker setup script ($setup_script) not found in extracted files."
        fi

        # Log Redis environment variables for debugging
        log "Redis environment variables for worker ${i}:"
        log "WORKER_REDIS_API_HOST: ${WORKER_REDIS_API_HOST}"
        log "WORKER_REDIS_API_PORT: ${WORKER_REDIS_API_PORT}"
        log "WORKER_USE_SSL: ${WORKER_USE_SSL}"
        log "WORKER_WEBSOCKET_AUTH_TOKEN: ${WORKER_WEBSOCKET_AUTH_TOKEN}"
        log "WORKER_CONNECTORS: ${WORKER_CONNECTORS}"
        log "WORKER_HEARTBEAT_INTERVAL: ${WORKER_HEARTBEAT_INTERVAL}"
        log "WORKER_LOG_LEVEL: ${WORKER_LOG_LEVEL}"
        log "WORKER_SIMULATION_JOB_TYPE: ${WORKER_SIMULATION_JOB_TYPE}"
        log "WORKER_SIMULATION_PROCESSING_TIME: ${WORKER_SIMULATION_PROCESSING_TIME}"
        log "WORKER_SIMULATION_STEPS: ${WORKER_SIMULATION_STEPS}"
        
        # Note: .env file is now created by the wgpu script during setup
        
        log "Worker setup complete for GPU ${i}"
    done

    # --- Clean up downloaded tarball ---
    log "Cleaning up downloaded tarball $tarball_path"
    rm -f "$tarball_path"

    log "All Redis Workers setup complete."
    touch "$setup_script_run_flag" # Mark setup as done
    return 0
}

start_redis_workers() {
    log "Starting Redis Workers..."
    
    log "Starting Redis Worker instances via wgpu..."
    # First make sure the worker directories are set up
    wgpu setup all
    # Then start the workers
    wgpu start all
    # Check status
    sleep 5 # Give them time to start
    wgpu status all
    log "Redis Worker start command issued."
    
    # Added: 2025-04-07T22:42:00-04:00 - Start worker watchdog service
    log "Starting Worker Watchdog service..."
    service worker-watchdog start
    sleep 2 # Give it time to start
    service worker-watchdog status
    log "Worker Watchdog service started."
}

all_services_ok=true
main

tail -f /dev/null
