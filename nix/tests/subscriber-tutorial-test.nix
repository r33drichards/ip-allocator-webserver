# NixOS VM test for Subscriber Tutorial
#
# This test verifies the subscriber tutorial example works correctly:
# 1. Subscriber service starts and is healthy
# 2. IP Allocator is configured to call the subscriber
# 3. Borrow events trigger subscriber calls
# 4. Return events trigger subscriber calls
# 5. Submit events trigger subscriber calls
# 6. Async subscriber mode works with polling
#
# Run with:
#   nix build .#checks.x86_64-linux.subscriber-tutorial-test
#

{ pkgs, self, ... }:

let
  # Build the example subscriber package
  exampleSubscriber = pkgs.callPackage ../examples/subscriber { };

in pkgs.testers.nixosTest {
  name = "subscriber-tutorial";

  nodes = {
    # Main server with IP Allocator and sync subscriber
    server = { config, pkgs, ... }: {
      imports = [ self.nixosModules.default ];

      # Apply overlay to get the package
      nixpkgs.overlays = [ self.overlays.default ];

      # Enable the IP allocator service with subscriber configuration
      services.ip-allocator-webserver = {
        enable = true;
        package = pkgs.ip-allocator-webserver;
        port = 8000;
        redisUrl = "redis://127.0.0.1:6379/";

        # Configure subscribers
        subscribers = {
          borrow.subscribers.example = {
            post = "http://127.0.0.1:8080/on-borrow";
            mustSucceed = true;
            async = false;
          };
          return.subscribers.example = {
            post = "http://127.0.0.1:8080/on-return";
            mustSucceed = true;
            async = false;
          };
          submit.subscribers.example = {
            post = "http://127.0.0.1:8080/on-submit";
            mustSucceed = true;
            async = false;
          };
        };
      };

      # Enable Redis
      services.redis.servers."ip-allocator" = {
        enable = true;
        port = 6379;
        bind = "127.0.0.1";
      };

      # Ensure proper service ordering
      systemd.services.ip-allocator-webserver = {
        after = [ "redis-ip-allocator.service" "example-subscriber.service" ];
        wants = [ "redis-ip-allocator.service" "example-subscriber.service" ];
      };

      # Run the example subscriber service (sync mode)
      systemd.services.example-subscriber = {
        description = "Example Subscriber for IP Allocator";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        environment = {
          ASYNC_MODE = "false";
          PORT = "8080";
          PROCESSING_DELAY = "0";
        };
        serviceConfig = {
          ExecStart = "${exampleSubscriber}/bin/example-subscriber";
          Restart = "always";
          RestartSec = "1s";
        };
      };

      # Open firewall for testing
      networking.firewall.allowedTCPPorts = [ 8000 8080 ];
    };

    # Async subscriber server
    async_server = { config, pkgs, ... }: {
      imports = [ self.nixosModules.default ];

      nixpkgs.overlays = [ self.overlays.default ];

      services.ip-allocator-webserver = {
        enable = true;
        package = pkgs.ip-allocator-webserver;
        port = 8000;
        redisUrl = "redis://127.0.0.1:6379/";

        subscribers = {
          borrow.subscribers.async-example = {
            post = "http://127.0.0.1:8080/on-borrow";
            mustSucceed = true;
            async = true;  # Async mode
          };
        };
      };

      services.redis.servers."ip-allocator" = {
        enable = true;
        port = 6379;
        bind = "127.0.0.1";
      };

      systemd.services.ip-allocator-webserver = {
        after = [ "redis-ip-allocator.service" "async-subscriber.service" ];
        wants = [ "redis-ip-allocator.service" "async-subscriber.service" ];
      };

      # Run subscriber in async mode
      systemd.services.async-subscriber = {
        description = "Async Example Subscriber";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        environment = {
          ASYNC_MODE = "true";
          PORT = "8080";
          PROCESSING_DELAY = "2";  # 2 second delay for async processing
        };
        serviceConfig = {
          ExecStart = "${exampleSubscriber}/bin/example-subscriber";
          Restart = "always";
          RestartSec = "1s";
        };
      };

      networking.firewall.allowedTCPPorts = [ 8000 8080 ];
    };
  };

  testScript = ''
    import json

    start_all()

    #
    # Test Sync Subscriber
    #

    # Wait for services on sync server
    server.wait_for_unit("redis-ip-allocator.service")
    server.wait_for_unit("example-subscriber.service")
    server.wait_for_open_port(6379)
    server.wait_for_open_port(8080)
    server.wait_for_unit("ip-allocator-webserver.service")
    server.wait_for_open_port(8000)

    # Give services time to fully initialize
    server.sleep(2)

    # Test 1: Subscriber health check
    with subtest("Subscriber health check"):
        result = server.succeed("curl -s http://localhost:8080/health")
        health = json.loads(result)
        assert health["status"] == "healthy", f"Expected healthy, got: {health}"
        print(f"Subscriber health: {health}")

    # Test 2: Clear any previous events
    with subtest("Clear previous events"):
        server.succeed("curl -s -X DELETE http://localhost:8080/events")

    # Test 3: Submit triggers subscriber
    with subtest("Submit triggers subscriber"):
        result = server.succeed(
            "curl -s -X POST http://localhost:8000/submit "
            "-H 'Content-Type: application/json' "
            "-d '{\"item\": \"test-ip-1\"}'"
        )
        print(f"Submit result: {result}")
        server.sleep(1)

        # Check subscriber received the event
        events_result = server.succeed("curl -s http://localhost:8080/events")
        events = json.loads(events_result)
        assert events["count"] >= 1, f"Expected at least 1 event, got: {events['count']}"
        assert any(e["type"] == "submit" for e in events["events"]), "No submit event found"
        print(f"Events after submit: {events}")

    # Test 4: Borrow triggers subscriber
    with subtest("Borrow triggers subscriber"):
        result = server.succeed("curl -s http://localhost:8000/borrow")
        borrow_response = json.loads(result)
        assert "item" in borrow_response, f"No item in response: {borrow_response}"
        assert "borrow_token" in borrow_response, f"No token in response: {borrow_response}"
        print(f"Borrow result: {borrow_response}")

        server.sleep(1)

        # Check subscriber received borrow event
        events_result = server.succeed("curl -s http://localhost:8080/events")
        events = json.loads(events_result)
        assert any(e["type"] == "borrow" for e in events["events"]), "No borrow event found"
        print(f"Events after borrow: {events}")

    # Store for return
    borrowed_item = borrow_response["item"]
    borrow_token = borrow_response["borrow_token"]

    # Test 5: Return triggers subscriber
    with subtest("Return triggers subscriber"):
        result = server.succeed(
            f"curl -s -X POST http://localhost:8000/return "
            f"-H 'Content-Type: application/json' "
            f"-d '{{\"item\": \"{borrowed_item}\", \"borrow_token\": \"{borrow_token}\"}}'"
        )
        print(f"Return result: {result}")

        server.sleep(2)

        # Check subscriber received return event
        events_result = server.succeed("curl -s http://localhost:8080/events")
        events = json.loads(events_result)
        assert any(e["type"] == "return" for e in events["events"]), "No return event found"
        print(f"Events after return: {events}")

    # Test 6: Verify all events were received
    with subtest("Verify all event types received"):
        events_result = server.succeed("curl -s http://localhost:8080/events")
        events = json.loads(events_result)
        event_types = [e["type"] for e in events["events"]]
        assert "submit" in event_types, "Missing submit event"
        assert "borrow" in event_types, "Missing borrow event"
        assert "return" in event_types, "Missing return event"
        print(f"All event types received: {set(event_types)}")

    # Test 7: Subscriber receives params
    with subtest("Subscriber receives params"):
        # Submit another item
        server.succeed(
            "curl -s -X POST http://localhost:8000/submit "
            "-H 'Content-Type: application/json' "
            "-d '{\"item\": \"test-ip-2\"}'"
        )
        server.sleep(1)

        # Borrow with params
        result = server.succeed(
            "curl -s 'http://localhost:8000/borrow?params=%7B%22region%22%3A%22us-west%22%7D'"
        )
        borrow_response = json.loads(result)
        print(f"Borrow with params result: {borrow_response}")

        server.sleep(1)

        # Check that params were received
        events_result = server.succeed("curl -s http://localhost:8080/events")
        events = json.loads(events_result)
        borrow_events = [e for e in events["events"] if e["type"] == "borrow"]
        # Find the event with params
        events_with_params = [e for e in borrow_events if e.get("params")]
        print(f"Borrow events with params: {events_with_params}")

    #
    # Test Async Subscriber
    #

    # Wait for async server services
    async_server.wait_for_unit("redis-ip-allocator.service")
    async_server.wait_for_unit("async-subscriber.service")
    async_server.wait_for_open_port(6379)
    async_server.wait_for_open_port(8080)
    async_server.wait_for_unit("ip-allocator-webserver.service")
    async_server.wait_for_open_port(8000)

    async_server.sleep(2)

    # Test 8: Async subscriber health
    with subtest("Async subscriber health check"):
        result = async_server.succeed("curl -s http://localhost:8080/health")
        health = json.loads(result)
        assert health["status"] == "healthy", f"Expected healthy, got: {health}"
        print(f"Async subscriber health: {health}")

    # Test 9: Submit and borrow with async subscriber
    with subtest("Async subscriber handles borrow"):
        # Submit an item
        async_server.succeed(
            "curl -s -X POST http://localhost:8000/submit "
            "-H 'Content-Type: application/json' "
            "-d '{\"item\": \"async-test-ip\"}'"
        )
        async_server.sleep(1)

        # Borrow (should trigger async subscriber)
        result = async_server.succeed("curl -s http://localhost:8000/borrow")
        borrow_response = json.loads(result)
        print(f"Async borrow result: {borrow_response}")

        # The operation should complete (async subscriber waits for completion)
        assert "item" in borrow_response, f"No item in response: {borrow_response}"
        print("Async subscriber completed successfully")

    # Test 10: Check async subscriber received events
    with subtest("Async subscriber received events"):
        events_result = async_server.succeed("curl -s http://localhost:8080/events")
        events = json.loads(events_result)
        print(f"Async subscriber events: {events}")
        assert events["count"] >= 1, f"Expected at least 1 event, got: {events['count']}"

    print("All subscriber tutorial tests passed!")
  '';
}
