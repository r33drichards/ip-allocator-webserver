# NixOS Module for IP Allocator Webserver

This directory contains a NixOS module for deploying the IP Allocator Webserver as a systemd service.

## Quick Start

### 1. Add the flake input

In your `flake.nix`, add the ip-allocator-webserver flake as an input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    ip-allocator-webserver = {
      url = "github:r33drichards/ip-allocator-webserver";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ip-allocator-webserver, ... }: {
    nixosConfigurations.myserver = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Import the module
        ip-allocator-webserver.nixosModules.default

        # Apply the overlay
        { nixpkgs.overlays = [ ip-allocator-webserver.overlays.default ]; }

        # Your configuration
        ./configuration.nix
      ];
    };
  };
}
```

### 2. Enable the service

In your NixOS configuration:

```nix
{ config, pkgs, ... }:

{
  services.ip-allocator-webserver = {
    enable = true;
    package = pkgs.ip-allocator-webserver;
  };

  # Required: Enable Redis as the backing store
  services.redis.servers."".enable = true;
}
```

### 3. Rebuild your system

```bash
sudo nixos-rebuild switch --flake .#myserver
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | boolean | `false` | Whether to enable the IP Allocator Webserver service |
| `package` | package | - | The ip-allocator-webserver package to use |
| `port` | integer | `8000` | Port on which the webserver listens |
| `address` | string | `"0.0.0.0"` | Address on which the webserver binds |
| `redisUrl` | string | `"redis://127.0.0.1:6379/"` | Redis connection URL |
| `user` | string | `"ip-allocator"` | User account under which the service runs |
| `group` | string | `"ip-allocator"` | Group under which the service runs |
| `openFirewall` | boolean | `false` | Whether to open the firewall port |
| `configFile` | path or null | `null` | Path to a custom TOML configuration file |
| `subscribers` | attrset | `{}` | Webhook subscribers configuration (see below) |
| `extraEnvironment` | attrset | `{}` | Extra environment variables |

## Configuring Webhook Subscribers

The service supports webhook notifications for three event types: `borrow`, `return`, and `submit`.

### Subscriber Options

Each subscriber has the following options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `post` | string | - | URL to POST to when the event occurs |
| `mustSucceed` | boolean | `false` | If true, operation fails when webhook fails |
| `async` | boolean | `false` | If true, supports long-running async operations |

### Example with Subscribers

```nix
{ config, pkgs, ... }:

{
  services.ip-allocator-webserver = {
    enable = true;
    package = pkgs.ip-allocator-webserver;
    port = 8080;
    openFirewall = true;

    subscribers = {
      borrow.subscribers = {
        # Synchronous webhook that must succeed
        provisioner = {
          post = "http://provisioner.local:8000/on-borrow";
          mustSucceed = true;
          async = false;
        };

        # Fire-and-forget notification
        logger = {
          post = "http://logger.local:8000/log";
          mustSucceed = false;
          async = false;
        };
      };

      return.subscribers = {
        # Async webhook for long-running cleanup
        cleanup = {
          post = "http://cleanup.local:8000/on-return";
          mustSucceed = true;
          async = true;
        };
      };
    };
  };

  services.redis.servers."".enable = true;
}
```

## Using a Custom Config File

If you prefer to use a TOML config file directly:

```nix
{ config, pkgs, ... }:

{
  services.ip-allocator-webserver = {
    enable = true;
    package = pkgs.ip-allocator-webserver;
    configFile = ./my-config.toml;
  };

  services.redis.servers."".enable = true;
}
```

The config file format is:

```toml
[borrow.subscribers.mySubscriber]
post = "http://example.com/webhook"
mustSuceed = true
async = false

[return.subscribers.anotherSubscriber]
post = "http://example.com/return-webhook"
mustSuceed = false
async = true
```

## Security

The systemd service runs with security hardening enabled:

- Runs as a dedicated system user (`ip-allocator`)
- `NoNewPrivileges=true`
- `ProtectSystem=strict`
- `ProtectHome=true`
- `PrivateTmp=true`
- `PrivateDevices=true`
- Restricted network address families
- Memory execution protection

## API Endpoints

Once running, the service exposes:

| Endpoint | Description |
|----------|-------------|
| `GET /borrow` | Borrow an item from the pool |
| `POST /return` | Return a borrowed item |
| `POST /submit` | Submit a new item to the pool |
| `GET /operations/<id>` | Check async operation status |
| `GET /admin/ui` | Admin web interface |
| `GET /swagger-ui/` | Swagger API documentation |
| `GET /rapidoc/` | RapiDoc API documentation |

## Checking Service Status

```bash
# Check if service is running
systemctl status ip-allocator-webserver

# View logs
journalctl -u ip-allocator-webserver -f

# Test the API
curl http://localhost:8000/admin/stats
```

## Examples

See the `examples/` directory for complete configuration examples:

- `basic.nix` - Minimal configuration
- `with-subscribers.nix` - Full configuration with webhook subscribers
- `flake-usage.nix` - Complete flake.nix example

## Troubleshooting

### Service fails to start

1. Check Redis is running: `systemctl status redis`
2. Verify Redis URL is correct
3. Check logs: `journalctl -u ip-allocator-webserver -e`

### Cannot connect to service

1. Verify the port is correct: `ss -tlnp | grep 8000`
2. Check firewall: `sudo iptables -L -n`
3. If `openFirewall = true`, ensure NixOS firewall is enabled

### Webhook subscribers not working

1. Verify subscriber URLs are reachable from the server
2. Check service logs for webhook errors
3. Test webhooks manually with curl
