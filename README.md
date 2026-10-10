# OpenCode Container

A self-contained Docker image for running [OpenCode](https://github.com/anomalyco/opencode)
and [OpenCode Studio](https://github.com/Microck/opencode-studio) together as a
persistent, centrally managed service.

This project is intended for NAS and homelab deployments such as Synology
Container Manager. It deliberately keeps application configuration and data
outside the image so the container can be upgraded or replaced without losing
configuration.

> **Not affiliated with OpenCode or OpenCode Studio.**
>
> This is an independent packaging/integration project. The OpenCode project
> explicitly asks projects using "opencode" in their name to state that they
> are not built by or affiliated with the OpenCode team.

## Features

- OpenCode HTTP server on port `4096`
- OpenCode Studio web UI on port `1080`
- Persistent OpenCode configuration
- Persistent Studio data
- Persistent OpenCode profiles
- Persistent application data
- Persistent `/workspace`
- No provider or MCP configuration baked into the image
- Multi-architecture Docker images: `linux/amd64` and `linux/arm64`
- GitHub Actions build and publish workflow
- Suitable for Synology Container Manager

## Philosophy

The image contains the software, not your environment.

After the first start, OpenCode has only a minimal configuration:

```json
{
  "$schema": "https://opencode.ai/config.json"
}
```

Configure providers, models, MCP servers, skills, plugins, agents and profiles
through OpenCode Studio or OpenCode itself.

This is intentional: upgrading the image should not require rebuilding or
editing the container to change your AI provider or MCP configuration.

## Ports

| Port | Service |
|---:|---|
| 4096 | OpenCode server/web UI |
| 1080 | OpenCode Studio |

For a first deployment, keep both ports LAN-only. If you later expose either
service outside the LAN, put it behind an authenticated HTTPS reverse proxy or
VPN/Tailscale.

## Persistent storage

Recommended Synology layout:

```text
/volume1/docker/opencode/
├── config/
├── data/
├── studio/
├── profiles/
└── workspace/
```

Mount them as:

```text
Synology path                         Container path
--------------------------------------------------------------
/volume1/docker/opencode/config      /data/.config/opencode
/volume1/docker/opencode/studio      /data/.config/opencode-studio
/volume1/docker/opencode/profiles    /data/.config/opencode-profiles
/volume1/docker/opencode/data        /data/.local/share
/volume1/docker/opencode/workspace   /data/workspace
```

## Synology Container Manager

1. Create `/volume1/docker/opencode/`.
2. Create the five subdirectories shown above.
3. Make the directories writable by the container user. The image runs as `opencode`, which is UID/GID `1000` in the image. Over SSH on the NAS, run:

   ```text
   sudo chown -R 1000:1000 /volume1/docker/opencode
   ```

   Without this, the container fails at startup with `mkdir: cannot create directory '/data/.local': Permission denied`.
4. Pull the image from Docker Hub:

   ```text
   <your-dockerhub-user>/opencode-container:latest
   ```

5. Create a container from the image.
6. Map ports `4096` and `1080`.
7. Add the five bind mounts.
8. Set the container to restart automatically.
9. Start the container.

Open:

```text
http://<synology-ip>:1080
```

for Studio.

Open:

```text
http://<synology-ip>:4096
```

for OpenCode.

## Configuration

OpenCode Studio manages the configuration files under:

```text
/home/opencode/.config/opencode/
```

Studio's own data is stored under:

```text
/home/opencode/.config/opencode-studio/
```

and profiles under:

```text
/home/opencode/.config/opencode-profiles/
```

These locations are persistent in the recommended Synology setup.

Configure your preferred AI provider and MCP servers after deployment.

For example, this project intentionally does **not** contain GreenPT,
GitHub MCP or Homey MCP configuration. Those belong to the deployment's
persistent configuration.

## Updating

The image uses pinned upstream versions at build time. To upgrade:

1. Update `OPENCODE_VERSION` and/or `STUDIO_REF` (a commit in `knippers/opencode-studio`) in the Dockerfile.
2. Commit and push.
3. GitHub Actions builds and publishes the image.
4. Pull the new image in Synology Container Manager.
5. Recreate the container using the same persistent mounts.

Your configuration and workspace remain outside the image.

## GitHub Actions / Docker Hub

Create the following GitHub repository variable/secret:

```text
DOCKERHUB_USERNAME
DOCKERHUB_TOKEN
```

`DOCKERHUB_TOKEN` should be a Docker Hub access token rather than your
Docker Hub password.

The workflow publishes:

- `latest` from the default branch
- an incrementing build number (the GitHub Actions run number), such as `42`

The workflow builds:

```text
linux/amd64
linux/arm64
```

## Security

This image is intended to run on a trusted network.

Do not expose OpenCode or Studio directly to the public Internet.

OpenCode can execute commands and modify files in its workspace, and MCP
servers can provide access to external systems. Treat the container and its
configuration as a privileged automation service.

Use least-privilege credentials for GitHub, Homey and other MCP servers.

## Upstream projects and licenses

This repository packages and runs software from two independent upstream
projects:

- [OpenCode](https://github.com/anomalyco/opencode) — MIT licensed
- [OpenCode Studio](https://github.com/Microck/opencode-studio) — MIT licensed

Their respective copyrights and licenses remain applicable to the upstream
software. This repository's packaging/configuration code is also released
under the MIT License.

See `LICENSE` for the license of this packaging project and
`THIRD-PARTY-NOTICES.md` for the upstream projects included in the image.

## Disclaimer

This project is provided "as is", without warranty.

It is an independent community packaging project and is not affiliated with,
endorsed by, or maintained by OpenCode or OpenCode Studio.
