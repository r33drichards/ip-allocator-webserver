{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.ip-allocator-webserver;

  # Generate TOML configuration from Nix attrset
  subscriberToToml = name: subscriber: ''
    [${name}]
    ${optionalString (subscriber.subscribers != {}) (
      concatStringsSep "\n" (mapAttrsToList (subName: sub: ''
        [${name}.subscribers.${subName}]
        post = "${sub.post}"
        mustSuceed = ${boolToString sub.mustSucceed}
        async = ${boolToString sub.async}
      '') subscriber.subscribers)
    )}
  '';

  configFile = pkgs.writeText "ip-allocator-config.toml" ''
    # Auto-generated configuration for ip-allocator-webserver
    ${subscriberToToml "borrow" cfg.subscribers.borrow}
    ${subscriberToToml "return" cfg.subscribers.return}
    ${subscriberToToml "submit" cfg.subscribers.submit}
  '';

  subscriberOptions = {
    options = {
      post = mkOption {
        type = types.str;
        description = "The URL to POST to when this event occurs.";
        example = "http://localhost:8080/webhook";
      };

      mustSucceed = mkOption {
        type = types.bool;
        default = false;
        description = ''
          If true, the operation will fail if this subscriber webhook fails.
          If false, the webhook failure is logged but the operation continues.
        '';
      };

      async = mkOption {
        type = types.bool;
        default = false;
        description = ''
          If true, this is an async subscriber that supports long-running operations.
          The webhook should return an operation ID that can be polled for completion.
        '';
      };
    };
  };

  operationSubscribersOptions = {
    options = {
      subscribers = mkOption {
        type = types.attrsOf (types.submodule subscriberOptions);
        default = {};
        description = "Named subscribers for this operation type.";
        example = literalExpression ''
          {
            myWebhook = {
              post = "http://localhost:8080/on-borrow";
              mustSucceed = true;
              async = false;
            };
          }
        '';
      };
    };
  };

in {
  options.services.ip-allocator-webserver = {
    enable = mkEnableOption "IP Allocator Webserver service";

    package = mkOption {
      type = types.package;
      description = "The ip-allocator-webserver package to use.";
    };

    port = mkOption {
      type = types.port;
      default = 8000;
      description = "Port on which the webserver listens.";
    };

    address = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address on which the webserver binds.";
    };

    redisUrl = mkOption {
      type = types.str;
      default = "redis://127.0.0.1:6379/";
      description = "Redis connection URL for the backing store.";
      example = "redis://localhost:6379/0";
    };

    user = mkOption {
      type = types.str;
      default = "ip-allocator";
      description = "User account under which the service runs.";
    };

    group = mkOption {
      type = types.str;
      default = "ip-allocator";
      description = "Group under which the service runs.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall port for the webserver.";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a custom TOML configuration file.
        If set, this takes precedence over the subscribers option.
      '';
      example = "/etc/ip-allocator/config.toml";
    };

    subscribers = {
      borrow = mkOption {
        type = types.submodule operationSubscribersOptions;
        default = {};
        description = "Subscribers to notify when an item is borrowed.";
      };

      return = mkOption {
        type = types.submodule operationSubscribersOptions;
        default = {};
        description = "Subscribers to notify when an item is returned.";
      };

      submit = mkOption {
        type = types.submodule operationSubscribersOptions;
        default = {};
        description = "Subscribers to notify when an item is submitted.";
      };
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Extra environment variables to pass to the service.";
      example = literalExpression ''
        {
          RUST_LOG = "debug";
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "IP Allocator Webserver service user";
    };

    users.groups.${cfg.group} = {};

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.ip-allocator-webserver = {
      description = "IP Allocator Webserver";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "redis.service" ];
      wants = [ "redis.service" ];

      environment = {
        REDIS_URL = cfg.redisUrl;
        ROCKET_ADDRESS = cfg.address;
        ROCKET_PORT = toString cfg.port;
      } // cfg.extraEnvironment;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = let
          configArg = if cfg.configFile != null
            then "--config ${cfg.configFile}"
            else if (cfg.subscribers.borrow.subscribers != {} ||
                     cfg.subscribers.return.subscribers != {} ||
                     cfg.subscribers.submit.subscribers != {})
            then "--config ${configFile}"
            else "";
        in "${cfg.package}/bin/ip-allocator-webserver ${configArg}";
        Restart = "on-failure";
        RestartSec = 5;

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
      };
    };
  };
}
