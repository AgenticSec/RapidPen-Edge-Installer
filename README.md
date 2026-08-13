# AgenticSec Edge Installer

Official installer for AgenticSec Supervisor.

## Installation

Please follow the instructions in [AgenticSec Web UI](https://app.agenticsec.tech).

### Non-interactive installation

When the installer cannot be driven interactively (configuration management tools,
or a terminal whose settings prevent input from reaching the installer), pass the
API key and base URL as environment variables:

```bash
curl -fsSL https://raw.githubusercontent.com/AgenticSec/AgenticSec-Edge-Installer/main/install.sh -o agenticsec-install.sh
sudo AGENTICSEC_API_KEY='<your-api-key>' \
     AGENTICSEC_BASEURL='https://api.agenticsec.tech/api/edge/supervisor' \
     sh agenticsec-install.sh
```

Both variables must be set together. Setting only `AGENTICSEC_API_KEY` leaves the
installer waiting for the Base URL prompt.

### Optional environment variables

| Variable | Default | Purpose |
|---|---|---|
| `AGENTICSEC_API_KEY` | (prompted) | API key. Set it to skip the interactive prompt. |
| `AGENTICSEC_BASEURL` | `https://api.agenticsec.tech/api/edge/supervisor` | Cloud endpoint. Set it to skip the interactive prompt. |
| `AGENTICSEC_INPUT_TIMEOUT_SEC` | `120` | How long to wait for interactive input before giving up with recovery instructions. |
| `AGENTICSEC_PULL_TIMEOUT_SEC` | `900` | How long to wait for each container image pull. |

### Required network access

The installer needs HTTPS outbound access to:

- `api.agenticsec.tech` — AgenticSec Cloud
- `github.com`, `objects.githubusercontent.com` — installer and version info
- `ghcr.io`, `pkg-containers.githubusercontent.com` — supervisor image
- `registry-1.docker.io`, `auth.docker.io` — Fluent Bit image

In a proxy environment the Docker daemon needs its own proxy configuration;
shell-level proxy variables do not apply to image pulls.

## Uninstallation

```bash
sudo agenticsec-uninstall
```

## License

See the [LICENSE file](./LICENSE).
