> [!NOTE]
> GUI support was removed by design. This repository is now a CLI-only launcher for running Vivado on macOS via Docker.

# Vivado CLI on macOS via Docker

`yokeTH/vivado-mac` provides shell-first wrappers for running Vivado CLI from macOS while executing the tool inside a Linux `linux/amd64` Docker container.

The goal is simple:

```bash
vivado
vivado -mode batch -source scripts/build.tcl
vivado -mode tcl
```

You run those commands from your normal macOS terminal. The wrappers handle Docker image selection, project mounting, working directory preservation, and persistent Vivado state automatically.

## Supported Vivado installers

- 2025.2
- 2024.2
- 2023.2

## What Changed

- GUI support was removed.
- XQuartz is no longer required.
- `DISPLAY`, `xhost`, and X11 startup logic were removed.
- `start_container.sh` is now only a compatibility wrapper that forwards to the new CLI launcher.

## Prerequisites

1. Docker Desktop for macOS, or OrbStack.
2. At least 120 GB of free disk space for installer extraction and Vivado installation.
3. A Linux Vivado installer downloaded from AMD/Xilinx.

Optional:

- `git` on the host, for automatic git-root mounting when you run the wrappers inside a repository.

## One-Time Setup

Clone this repository somewhere on your Mac:

```bash
git clone https://github.com/aaaadev/vivado-mac.git
cd vivado-mac
```

Build the Docker image and install Vivado into `~/.vivado-mac/Xilinx`:

```bash
./scripts/setup.sh /path/to/FPGAs_AdaptiveSoCs_Unified_2025.2_*.bin
```

If you omit the installer path, `setup.sh` will prompt for it.

Install the host-side wrappers into your user `bin` directory:

```bash
./scripts/install_wrappers.sh
```

By default, wrappers are symlinked into `~/bin` if it exists, otherwise `~/.local/bin`. You can also pass a target directory explicitly:

```bash
./scripts/install_wrappers.sh "$HOME/bin"
```

If that directory is not already on your `PATH`, add it in your shell startup file.

## Persistent State

The repository does not bake Vivado or licenses into the image.

- Vivado installation is stored at `~/.vivado-mac/Xilinx`
- Vivado license/config state is stored at `~/.Xilinx`

Both are mounted into the container automatically by the wrappers.

The wrappers also request the host's logical CPU count with Docker `--cpus` and the host physical memory size with Docker `--memory`, so Vivado runs are not artificially pinned below the host values by the wrapper itself. If Docker Desktop or OrbStack is configured with lower CPU or memory limits, those platform limits still apply.

## CLI Usage

### Vivado

From any project directory:

```bash
vivado -mode batch -source scripts/build.tcl
```

Start an interactive Tcl session:

```bash
vivado
```

Explicit Tcl mode also works:

```bash
vivado -mode tcl
```

Note: plain `vivado` defaults to `vivado -mode tcl` in this repository's CLI-only workflow.

## Automatic Project Mounting

The wrappers mount your project automatically:

- If you run a wrapper inside a git repository, the git repo root is mounted at `/workspace`.
- If you run it outside a git repository, the current working directory is mounted at `/workspace`.
- Your current subdirectory is preserved as the container working directory.

Example:

```bash
cd ~/src/my-fpga-repo/subdir/ip
vivado -mode batch -source ../../scripts/build.tcl
```

In that case:

- `~/src/my-fpga-repo` is mounted into the container
- the container starts in `/workspace/subdir/ip`

This keeps relative paths working without manually typing `docker run` mounts.

## Wrapper Locations

After `./scripts/install_wrappers.sh`, these host-side commands become available:

- `vivado`

If you do not want to install symlinks, you can run the repo-local wrappers directly:

```bash
./bin/vivado -mode batch -source scripts/build.tcl
```

## Migration Note

Previous versions of this repository focused on launching the Vivado GUI through XQuartz with:

```bash
./scripts/start_container.sh
```

That flow was removed intentionally.

For old users:

- `./scripts/start_container.sh` now prints a deprecation warning and launches the CLI wrapper instead.
- Use `vivado` for interactive Tcl mode.
- Use `vivado -mode batch -source ...` for non-interactive builds.

## Troubleshooting

### `docker: command not found`

Install Docker Desktop or OrbStack and make sure `docker` is available in your shell.

### `Vivado installation not found`

Run:

```bash
./scripts/setup.sh /path/to/your-installer.bin
```

The wrappers expect Vivado to exist under `~/.vivado-mac/Xilinx`.

### Wrapper command not found

Install the symlinks:

```bash
./scripts/install_wrappers.sh
```

Then ensure the chosen install directory is on your `PATH`.

## License

This project is licensed under the BSD 3-Clause License.

Vivado itself is not included. You must download it separately and comply with AMD/Xilinx licensing terms.
