# First-time run on Ubuntu 22.04 or 24.04 LTS

This guide supports x86-64 Ubuntu with Bash. It uses the same staging source and
Neon database as Windows. Python environments, Flutter
builds, logs, and runtime files stay under the Ubuntu user's local data
directories, outside the Git clone.

## 1. Install the system prerequisites

The supported installation sources are the official
[Docker Engine Ubuntu guide](https://docs.docker.com/engine/install/ubuntu/),
[Flutter Linux guide](https://docs.flutter.dev/install/manual), and
[uv Python guide](https://docs.astral.sh/uv/guides/install-python/).

Install the base packages:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git unzip xz-utils zip \
  libglu1-mesa util-linux coreutils shellcheck
```

Install Docker Engine and its Compose plugin from Docker's official `apt`
repository by following the Docker guide above. The required packages are:

```text
docker-ce
docker-ce-cli
containerd.io
docker-buildx-plugin
docker-compose-plugin
```

Allow your account to use Docker, then sign out and back in so the new group is
applied:

```bash
sudo usermod -aG docker "$USER"
```

Install Flutter 3.32.8 from the official Flutter SDK archive, extract it to a
user-owned location such as `$HOME/develop/flutter`, and add its `bin` folder
to `PATH`. For example, after extracting the archive:

```bash
echo 'export PATH="$HOME/develop/flutter/bin:$PATH"' >> "$HOME/.bashrc"
source "$HOME/.bashrc"
flutter config --enable-web
```

Install `uv` for managed Python 3.14:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Close and reopen the terminal, then verify everything:

```bash
git --version
docker version
docker compose version
flutter --version
flutter doctor
uv --version
```

The project setup script asks `uv` for Python 3.14. You do not need to replace
Ubuntu's system Python.

### Lab computer without sudo

Ask lab IT to complete this checklist before you use the computer:

- Install Git, curl, unzip, xz-utils, zip, libglu1-mesa, util-linux,
  coreutils, and ShellCheck.
- Install Docker Engine and the Docker Compose plugin from Docker's official
  repository.
- Start and enable the Docker service.
- Add your lab account to the `docker` group, or provide an approved rootless
  Docker configuration.
- Install Flutter 3.32.8 with web support in a readable location and make
  `flutter` available on your `PATH`.
- Permit access to GitHub, Docker Hub, Flutter downloads, and Python package
  downloads.
- Provide a supported browser. Firefox is sufficient because the launcher uses
  Flutter's web-server device; Chrome is optional.

You can install `uv` in your own user account without sudo. If lab policy blocks
that installer or outbound downloads, IT must install `uv` and Python 3.14 or
prepare the computer for you.

## 2. Clone the staging repository

Use a normal local folder, not OneDrive or another synchronized folder:

```bash
mkdir -p "$HOME/Projects"
cd "$HOME/Projects"
git clone https://github.com/CS-Ponkoj/Robotics-Programming-Lab-Staging.git
cd Robotics-Programming-Lab-Staging
```

Before running a local backend, obtain an authorized private `.env` through the
project's approved secret-delivery method and place it in
`local_handoff_package`. Git intentionally does not distribute Neon or OpenAI
credentials.

## 3. Prepare this computer

Run once after cloning, and again after dependency changes:

```bash
./scripts/setup-local.sh
```

If normal setup reports a damaged or incomplete environment, repair it:

```bash
./scripts/setup-local.sh --repair
```

The managed Python 3.14 environment is stored below
`${XDG_DATA_HOME:-$HOME/.local/share}/RoboticsProgrammingLab`, not in the Git
clone.

## 4. Build and check the ROS 2 grader

Build the image once on each computer:

```bash
./scripts/check-ros2-local.sh --build
```

Later checks can omit `--build` unless the ROS Dockerfile or grading
dependencies changed:

```bash
./scripts/check-ros2-local.sh
```

## 5. Start the application

```bash
./scripts/run-local.sh --frontend-port 8180 --backend-port 5100 --sandbox-port 5101
```

Open `http://127.0.0.1:8180/app` in the browser. The launcher connects to Neon
and starts the Python sandbox, FastAPI, and Flutter web. AI is off by default.

To intentionally test optional AI feedback, place `OPENAI_API_KEY` in the
ignored `local_handoff_package/.env` and add `--enable-ai`. Never commit or
print that file.

## 6. Stop safely

```bash
./scripts/stop-local.sh
```

The stop command stops only processes recorded by this Ubuntu launcher.
Closing the browser is not enough. Neon keeps the shared data; no local database
handoff is required.

## 7. Verify the installation

With the application stopped, run the complete Ubuntu gate:

```bash
./scripts/verify-local.sh --api-base-url http://127.0.0.1:5100
```

When the application is running, the same command also checks the managed
backend and sandbox health endpoints.

## 8. Prepare another authorized computer

Clone the source and provision its private Neon configuration through the
approved secret-delivery method. Do not copy Python environments, Flutter
builds, Docker volumes, or log folders. Local database fallbacks are not
supported.

## 9. Update the project later

Stop the application before updating:

```bash
./scripts/stop-local.sh
git status --short
git pull --ff-only
./scripts/setup-local.sh
```

Rebuild the ROS image only when its Dockerfile or dependencies changed.

## Troubleshooting

| Message or symptom | Correct action |
| --- | --- |
| `Permission denied` when running a script | Run `chmod +x scripts/*.sh` once in the clone. |
| `docker: permission denied` | Sign out and back in after IT adds your account to the Docker group; do not run the application with `sudo`. |
| Docker daemon is unavailable | Run `sudo systemctl start docker`, or ask lab IT. |
| `uv`, `flutter`, or `docker compose` is not found | Complete prerequisite installation, reopen Bash, and verify the command. |
| A port is already used | Stop the old stack or choose different `--frontend-port`, `--backend-port`, or `--sandbox-port` values. |
| Neon cannot connect | Check internet access and the ignored `.env`; never paste the connection string into Git or support messages. |
| Python environment is incomplete | Stop the app and run `./scripts/setup-local.sh --repair`. |
| ROS image is missing | Run `./scripts/check-ros2-local.sh --build`. |
| Flutter cannot find a browser | Open the printed URL manually; the launcher uses the web-server device. |

The private configuration folder is ignored by Git and is not encrypted. It may contain API
keys, database credentials, and temporary account passwords. Do not commit,
email, publicly share, or leave it on an untrusted computer.
