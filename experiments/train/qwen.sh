#!/usr/bin/env bash
set -euo pipefail

sudo cpupower frequency-set -g performance 2>/dev/null && \
  echo "[cpufreq] Set governor to performance" || \
  echo "[cpufreq] Could not set governor, continuing"

# Disable C-states, restore on exit
if cpupower idle-info 2>/dev/null | grep -q "C[1-9]"; then
  sudo cpupower idle-set -D 0 2>/dev/null
  trap 'sudo cpupower idle-set -E 0 2>/dev/null' EXIT
  echo "[cpupower] C-states disabled (will restore on exit)"
fi


FLUX_HOME="$HOME/flux"
FLUX_REPO="https://github.com/gkrls/flux.git"
FLUX_BRANCH="wip"
TEST_HOME="$HOME/flux-experiments"
TEST_REPO="https://github.com/gkrls/flux-experiments.git"
TEST_BRANCH="wip"

NEED_BUILD=0
# Clone on the first run
[[ -d "$FLUX_HOME/.git" ]] || git clone -b "$FLUX_BRANCH" "$FLUX_REPO" "$FLUX_HOME"
[[ -d "$TEST_HOME/.git" ]] || git clone -b "$TEST_BRANCH" "$TEST_REPO" "$TEST_HOME"

# Create venv on first run, or just activate it otherwise
if [[ ! -d "$TEST_HOME/venv" ]]; then
    python3 -m venv "$TEST_HOME/venv"
    source "$TEST_HOME/venv/bin/activate"
    pip install -r "$FLUX_HOME/src/dpa_torch_plugin/requirements.txt"
    pip install -r "$TEST_HOME/requirements-remote.txt"
    NEED_BUILD=1
else
    source "$TEST_HOME/venv/bin/activate"
fi

# If needed and resync the repos recompile 
if [[ $# -eq 1 && "$1" == "sync" ]]; then
  git -C "$FLUX_HOME" fetch -q origin || true
  git -C "$FLUX_HOME" checkout "$FLUX_BRANCH" 2>/dev/null || true
  git -C "$FLUX_HOME" reset --hard origin/"$FLUX_BRANCH" 2>/dev/null || true #git -C "$DIR" reset --hard || true
  git -C "$FLUX_HOME" pull --ff-only origin "$FLUX_BRANCH" 2>/dev/null || true
  git -C "$FLUX_HOME" clean -ffd || true

  git -C "$TEST_HOME" reset --hard >/dev/null 2>&1 || true
  git -C "$TEST_HOME" pull --ff-only || true
  NEED_BUILD=1
fi

# Build if first run or sync
if [[ "$NEED_BUILD" -eq 1 ]]; then
    mkdir -p "$FLUX_HOME/build"
    cd "$FLUX_HOME/build"
    cmake -DCMAKE_INSTALL_MESSAGE=LAZY \
          -DCMAKE_BUILD_TYPE=Release \
          -DDPA_TRACE=OFF \
          -DDPA_DEVELOP=OFF \
          -DDPA_SWITCH=OFF \
          -DDPA_AVX=ON \
          -DDPA_PROFILE=OFF \
          -DDPA_DPDK_RX_REUSE=ON \
          -DDPA_DPDK_WIN_HUGE=ON \
          -DDPA_TORCH_PINNEDPOOL=ON ..
    make -j4 torch-plugin
fi

cd $TEST_HOME


IFACE="${IFACE:-ens4f1}" 
# Derive IP on IFACE, rank = last octet - 1
IP=$(ip -4 -o addr show dev "$IFACE" | awk '{print $4}' | cut -d/ -f1 || true)
if [[ -z "${IP}" ]]; then
  echo "ERROR: could not get IPv4 for IFACE=$IFACE" >&2
  exit 1
fi
RANK=$(( ${IP##*.} - 1 ))
WORLD="${WORLD:-6}"
MASTER_ADDR="${MASTER_ADDR:-"42.0.1.1"}"
MASTER_PORT="${MASTER_PORT:-"29500"}"
CONF=$TEST_HOME/configs/edgecore.json
BACKEND="${BACKEND:-dpa_dpdk}"
GDB='gdb -ex run --args'

QWEN_15=Qwen/Qwen1.5-0.5B #--learning_rate 0.00002
QWEN_25=Qwen/Qwen2.5-0.5B #--learning_rate 0.000002

# SCRIPT=${0##*/}
echo "[qwen/${0##*/}] iface=$IFACE ip=$IP rank=$RANK world_size=$WORLD_SIZE master=${MASTER_ADDR}:${MASTER_PORT} backend=$BACKEND"

export DPA_PREEMPTIVE=0
export DPA_TORCH_MODE=worksteal

# echo "====== Qwen training ======"
# sudo -E DPA_LOG=INFO DPA_SCHEDULER=OFF $(which python) experiments/train/qwen/train.py \
#   --rank "$RANK" \
#   --world_size "$WORLD" \
#   --iface "$IFACE" \
#   --master_addr "$MASTER_ADDR" \
#   --master_port "$MASTER_PORT" \
#   --backend $BACKEND \
#   --dpa_conf $CONF \
#   --dpa_repin \
#   --workers 0 \
#   --model_name $QWEN_25 \
#   --dataset meta-math/MetaMathQA-40K \
#   --data ~/datasets/qwen-metamath40k \
#   --epochs 3 \
#   --learning_rate 0.000005 \
#   --gradient_accumulation_steps 10 \
#   --no_mask_prompt \
#   --seq_len 512 \
#   --sched cosine \
#   --amp \
#   --deterministic \
#   --prefetch_factor 4 \
#   --log_every_opt_steps 20 \
#   --log_flush_on_minival \
#   --mini_val_every_opt_steps 60 \
#   --mini_val_early_every 5 \
#   --mini_val_early_until 20 \
#   --mini_val_max_batches 0 \
#   --mini_val_0 \
#   --json experiments/train/qwen.json \
#   --dpa_k 6
  # --straggle_points 3 \
  # --straggle_prob 15 \
  # --straggle_ranks 1 \
  # --straggle_amount 0.9 \
  # --straggle_multiply 0.5 2.0
  

# echo "====== Qwen step timing ======"
sudo -E DPA_LOG=INFO DPA_SCHEDULER=OFF $(which python) experiments/train/qwen/step.py \
  --rank "$RANK" \
  --world_size "$WORLD" \
  --iface "$IFACE" \
  --master_addr "$MASTER_ADDR" \
  --master_port "$MASTER_PORT" \
  --backend dpa_dpdk \
  --dpa_conf $CONF \
  --dpa_repin \
  --workers 0 \
  --model_name $QWEN_25 \
  --dataset meta-math/MetaMathQA-40K \
  --data ~/datasets/qwen-metamath40k \
  --epochs 3 \
  --learning_rate 0.000005 \
  --gradient_accumulation_steps 10 \
  --no_mask_prompt \
  --seq_len 512 \
  --sched cosine \
  --amp \
  --deterministic \
  --prefetch_factor 4 \
  --log_every_opt_steps 2 \
  --log_flush_on_minival \
  --mini_val_max_batches 0 \
  --mini_val_0 \
  --batch_size 1 \
  --json experiments/train/qwen-step.json \
  --save_model ~/saved_models/qwen25 \
  --dpa_k 6