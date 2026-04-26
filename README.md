# Data Plane AllReduce Experiments

## Local setup
```bash
sudo apt install pssh

# with (local) python
python -m venv env
source env/bin/activate
pip install matplotlib scipy

# without (local) python env
sudo apt install python3-matplotlib python3-scipy
```

## Worker setup

Run the following to check that workers are ready. If it returns any error, please set up workers according to the steps in the Flux repo

```bash
parallel-ssh -h hosts.txt -i 'source ~/.bashrc && curl -fsSL https://raw.githubusercontent.com/gkrls/flux/refs/heads/wip/scripts/dpa-worker-check.sh | bash'
```
## Training/Finetuning Info

| Model        | Dataset     | DPA |
|--------------|-------------|-----|
| Resnet50     | Imagenet1K  | RTO=1ms,STO=25ms  |
| GPT2-Small   | OpenWebtext | RTO=1ms,STO=100ms |
| RoBERTa-base | Squad v2.0  | RTO=1ms,STO=50ms  |
| Qwen2.5-0.5B | Metamath40k | RTO=1ms,STO=50ms  |

### Datasets
Datasets are downloaded and cached by the trainer scripts, exept the following two that require extra steps.

##### Imagenet
```bash
./scripts/datasets/imagenet-1k-download.sh <dir>
python scripts/datasets/imagenet-1k-prepare.py <dir> # Prepare in place. Second argument <out> for a different output dir
python scripts/datasets/imagenet-1k-prepare.py <dir> --verify # optional
```

##### OpenWebText

```bash
./scripts/datasets/openwebtext-download.sh <dir>
cd <dir> && tar xf openwebtext.tar.xz
./scripts/datasets/openwebtext-prepare.sh <dir>
# if needed, rerun with --force to regenerate, or --token-only to skip the Parquet step.
```


## Example

The following will perform the [allreaduce benchmark](./experiments/allreduce/) on the nodes specified in `hosts.txt`.
Note that password-less SSH access to all hosts in `hosts.txt` should be set up in advance.

##### Start/Reset switch session:
```bash
ssh switch
cd flux/build

# if the switch is not running, compile the P4 program and start and the switch
../scripts/dpa-switch-compile.sh ../configs/edgecore.json install $SDE_INSTALL p4build
../scripts/dpa-switch-start.sh ../configs/edgecore.json install $SDE_INSTALL p4build

# if the switch is running:
tmux attach -t switch  # top pane should be inside flux/build
../scripts/dpa-switch-controller.sh ../configs/edgecore.json install
```

##### Run the benchmark
```bash
./scripts/pexec.sh dpa -f hosts.txt -S experiments/allreduce/run.sh sync 
```
`pexec` will run a script (or command) in a `tmux` session (in this case `dpa`).
Adding the `--keep` flag will keep the session open after the commant finished (or errored). This is meant for long runnning tasks, for short commands you can just use `pssh`.

`pstop` stop will kill a `tmux` session on all hosts (or all sessions with `--all`)

##### Gather results
```bash
# allreduce-benchmark.json is the default filename, rerun bench with --json <file> to change it
./scripts/pfile.sh -f hosts.txt flux-experiments/allreduce-benchmark.json -o out --short
```
`pfile` will create a new directory `out` under the current directory and populate it with `rank0.json, rank1.json` etc., each one being each rank's  `flux-experiments/allreduce-benchmark.json` file.

## Other
```bash
parallel-ssh -h hosts.txt -i "echo 'export PKG_CONFIG_PATH=/opt/mellanox/dpdk/lib/x86_64-linux-gnu/pkgconfig:\$PKG_CONFIG_PATH' >> ~/.bashrc"
```