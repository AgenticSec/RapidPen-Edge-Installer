# AgenticSec Edge Installer

Official installer for AgenticSec Supervisor.

## Installation

Please follow the instructions in [AgenticSec Web UI](https://app.agenticsec.tech).

### Configuration

This installer never prompts for input. Settings are taken from environment
variables. The Web UI hands out an installer with your API key already embedded,
so there is normally nothing to type in.

To set the variables yourself:

```bash
curl -fsSL https://raw.githubusercontent.com/AgenticSec/AgenticSec-Edge-Installer/main/install.sh -o agenticsec-install.sh
sudo AGENTICSEC_API_KEY='<your-api-key>' \
     AGENTICSEC_BASEURL='https://api.agenticsec.tech/api/edge/supervisor' \
     sh agenticsec-install.sh
```

`AGENTICSEC_API_KEY` is required. `AGENTICSEC_BASEURL` falls back to the default
shown above when unset.

### Optional environment variables

| Variable | Default | Purpose |
|---|---|---|
| `AGENTICSEC_API_KEY` | (required) | API key. The installer exits with instructions if unset. |
| `AGENTICSEC_BASEURL` | `https://api.agenticsec.tech/api/edge/supervisor` | Cloud endpoint. |
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
