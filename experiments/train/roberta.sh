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

# SCRIPT=${0##*/}
echo "[roberta/${0##*/}] iface=$IFACE ip=$IP rank=$RANK world_size=$WORLD_SIZE master=${MASTER_ADDR}:${MASTER_PORT} backend=$BACKEND"

export DPA_PREEMPTIVE=0
export DPA_TORCH_MODE=worksteal

# echo "====== RoBERTa training ======"
# sudo -E DPA_LOG=INFO DPA_SCHEDULER=OFF $(which python) experiments/train/roberta-train.py \
#   --rank "$RANK" \
#   --world_size "$WORLD" \
#   --iface "$IFACE" \
#   --master_addr "$MASTER_ADDR" \
#   --master_port "$MASTER_PORT" \
#   --backend $BACKEND \
#   --dpa_conf $CONF \
#   --dpa_repin \
#   --data ~/datasets/squad_v2 \
#   --squad_version v2 \
#   --n_best_size 100 \
#   --epochs 8 \
#   --batch_size 32 \
#   --learning_rate 3e-5 \
#   --warmup_ratio 0.2 \
#   --deterministic \
#   --workers 4 \
#   --prefetch_factor 4 \
#   --log_every_opt_steps 100 \
#   --mini_val_every_opt_steps 150 \
#   --json experiments/train/roberta.json \
#   --dpa_k 6
  # --straggle_points 1 \
  # --straggle_prob 15 \
  # --straggle_ranks 1 \
  # --straggle_amount 1.3 \
  # --straggle_multiply 0.5 2.0
# --bucket_cap_mb 200 \

echo "====== RoBERTa step timing ======"
sudo -E DPA_LOG=INFO DPA_SCHEDULER=OFF $(which python) experiments/train/roberta-step.py \
  --rank "$RANK" \
  --world_size "$WORLD_SIZE" \
  --iface "$IFACE" \
  --master_addr "$MASTER_ADDR" \
  --master_port "$MASTER_PORT" \
  --backend nccl \
  --dpa_conf $CONF \
  --dpa_repin \
  --data ~/datasets/squad_v2 \
  --squad_version v2 \
  --n_best_size 100 \
  --epochs 8 \
  --batch_size 32 \
  --learning_rate 3e-5 \
  --warmup_ratio 0.2 \
  --deterministic \
  --workers 4 \
  --prefetch_factor 4 \
  --log_every_opt_steps 10 \
  --mini_val_every_opt_steps 150 \
  --json experiments/train/roberta-step.json \
  --dpa_k 6