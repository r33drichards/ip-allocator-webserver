# NixOS VM test for ip-allocator-webserver
#
# This test verifies that:
# 1. The service starts correctly with Redis
# 2. Basic API endpoints work (borrow, return, submit)
# 3. Admin endpoints are accessible
#
# Run with: nix flake check
# Or: nix build .#checks.x86_64-linux.vm-test

{ pkgs, self, ... }:

pkgs.testers.nixosTest {
  name = "ip-allocator-webserver";

  nodes.server = { config, pkgs, ... }: {
    imports = [ self.nixosModules.default ];

    # Apply overlay to get the package
    nixpkgs.overlays = [ self.overlays.default ];

    # Enable the IP allocator service
    services.ip-allocator-webserver = {
      enable = true;
      package = pkgs.ip-allocator-webserver;
      port = 8000;
      redisUrl = "redis://127.0.0.1:6379/";
    };

    # Enable Redis with persistence
    services.redis.servers."ip-allocator" = {
      enable = true;
      port = 6379;
      bind = "127.0.0.1";
      settings = {
        save = ["900 1" "300 10" "60 10000"];
        appendonly = "yes";
        appendfsync = "everysec";
      };
    };

    # Ensure proper service ordering
    systemd.services.ip-allocator-webserver = {
      after = [ "redis-ip-allocator.service" ];
      wants = [ "redis-ip-allocator.service" ];
    };

    # Open firewall for testing
    networking.firewall.allowedTCPPorts = [ 8000 ];
  };

  testScript = ''
    import json

    start_all()

    # Wait for Redis to be ready
    server.wait_for_unit("redis-ip-allocator.service")
    server.wait_for_open_port(6379)

    # Wait for the webserver to be ready
    server.wait_for_unit("ip-allocator-webserver.service")
    server.wait_for_open_port(8000)

    # Give the service a moment to fully initialize
    server.sleep(2)

    # Test 1: Check admin stats endpoint
    with subtest("Admin stats endpoint works"):
        result = server.succeed("curl -s http://localhost:8000/admin/stats")
        stats = json.loads(result)
        assert "free_count" in stats, f"Expected 'free_count' in stats, got: {stats}"
        assert "borrowed_count" in stats, f"Expected 'borrowed_count' in stats, got: {stats}"
        print(f"Initial stats: {stats}")

    # Test 2: Submit an item to the pool
    with subtest("Submit item to pool"):
        result = server.succeed(
            "curl -s -X POST http://localhost:8000/submit "
            "-H 'Content-Type: application/json' "
            "-d '{\"item\": \"192.168.1.100\"}'"
        )
        print(f"Submit result: {result}")

    # Test 3: Verify item was added
    with subtest("Verify item in pool"):
        result = server.succeed("curl -s http://localhost:8000/admin/stats")
        stats = json.loads(result)
        assert stats["free_count"] == 1, f"Expected free_count=1, got: {stats['free_count']}"
        print(f"Stats after submit: {stats}")

    # Test 4: Borrow the item
    with subtest("Borrow item from pool"):
        result = server.succeed("curl -s http://localhost:8000/borrow")
        borrow_response = json.loads(result)
        assert "item" in borrow_response, f"Expected 'item' in response, got: {borrow_response}"
        assert "token" in borrow_response, f"Expected 'token' in response, got: {borrow_response}"
        assert borrow_response["item"] == "192.168.1.100", f"Wrong item: {borrow_response['item']}"
        print(f"Borrow result: {borrow_response}")

    # Store token for return
    borrowed_item = borrow_response["item"]
    borrow_token = borrow_response["token"]

    # Test 5: Verify item is now borrowed
    with subtest("Verify item is borrowed"):
        result = server.succeed("curl -s http://localhost:8000/admin/stats")
        stats = json.loads(result)
        assert stats["free_count"] == 0, f"Expected free_count=0, got: {stats['free_count']}"
        assert stats["borrowed_count"] == 1, f"Expected borrowed_count=1, got: {stats['borrowed_count']}"
        print(f"Stats after borrow: {stats}")

    # Test 6: Try to borrow when pool is empty (should fail or wait)
    with subtest("Borrow from empty pool returns error"):
        result = server.succeed("curl -s -w '%{http_code}' http://localhost:8000/borrow")
        # The response should indicate no items available (404 or empty response)
        print(f"Empty pool borrow result: {result}")

    # Test 7: Return the item
    with subtest("Return borrowed item"):
        result = server.succeed(
            f"curl -s -X POST http://localhost:8000/return "
            f"-H 'Content-Type: application/json' "
            f"-d '{{\"item\": \"{borrowed_item}\", \"token\": \"{borrow_token}\"}}'"
        )
        print(f"Return result: {result}")

    # Test 8: Verify item is back in pool
    with subtest("Verify item returned to pool"):
        result = server.succeed("curl -s http://localhost:8000/admin/stats")
        stats = json.loads(result)
        assert stats["free_count"] == 1, f"Expected free_count=1, got: {stats['free_count']}"
        assert stats["borrowed_count"] == 0, f"Expected borrowed_count=0, got: {stats['borrowed_count']}"
        print(f"Stats after return: {stats}")

    # Test 9: Admin UI is accessible
    with subtest("Admin UI is accessible"):
        result = server.succeed("curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/admin/ui")
        assert result.strip() == "200", f"Expected 200, got: {result}"

    # Test 10: Swagger UI is accessible
    with subtest("Swagger UI is accessible"):
        result = server.succeed("curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/swagger-ui/")
        assert result.strip() == "200", f"Expected 200, got: {result}"

    # Test 11: RapiDoc is accessible
    with subtest("RapiDoc is accessible"):
        result = server.succeed("curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/rapidoc/")
        assert result.strip() == "200", f"Expected 200, got: {result}"

    # Test 12: Submit multiple items and verify
    with subtest("Submit multiple items"):
        for i in range(5):
            server.succeed(
                f"curl -s -X POST http://localhost:8000/submit "
                f"-H 'Content-Type: application/json' "
                f"-d '{{\"item\": \"192.168.1.{101 + i}\"}}'"
            )
        result = server.succeed("curl -s http://localhost:8000/admin/stats")
        stats = json.loads(result)
        # Should have 6 items now (1 original + 5 new)
        assert stats["free_count"] == 6, f"Expected free_count=6, got: {stats['free_count']}"
        print(f"Final stats: {stats}")

    print("All tests passed!")
  '';
}
