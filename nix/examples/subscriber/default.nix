# Example subscriber package for IP Allocator
#
# This creates a simple Python-based subscriber that can be used
# for testing and as a reference implementation.
#
# Usage in a NixOS configuration:
#   let
#     exampleSubscriber = pkgs.callPackage ./subscriber { };
#   in {
#     systemd.services.example-subscriber = {
#       wantedBy = [ "multi-user.target" ];
#       after = [ "network.target" ];
#       serviceConfig = {
#         ExecStart = "${exampleSubscriber}/bin/example-subscriber";
#         Restart = "always";
#       };
#     };
#   }

{ lib
, python3
, writeShellScriptBin
, makeWrapper
}:

let
  pythonEnv = python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    pydantic
  ]);

  subscriberScript = ''
    #!/usr/bin/env python3
    """
    Example Subscriber for IP Allocator Tutorial

    This subscriber demonstrates both sync and async operation modes.
    It handles borrow, return, and submit events with configurable behavior.
    """

    import os
    import uuid
    import asyncio
    from typing import Any, Optional
    from fastapi import FastAPI, BackgroundTasks
    from pydantic import BaseModel

    app = FastAPI(
        title="Example Subscriber",
        description="Tutorial subscriber for IP Allocator",
        version="1.0.0"
    )

    # Configuration from environment
    ASYNC_MODE = os.environ.get("ASYNC_MODE", "false").lower() == "true"
    PROCESSING_DELAY = int(os.environ.get("PROCESSING_DELAY", "2"))

    # In-memory operation tracking
    operations: dict[str, dict] = {}
    events_received: list[dict] = []


    class BorrowEvent(BaseModel):
        item: Any
        params: Optional[dict] = None


    class ReturnEvent(BaseModel):
        item: Any
        params: Optional[dict] = None


    class SubmitEvent(BaseModel):
        item: Any


    async def process_async(operation_id: str, event_type: str, item: Any):
        """Process event asynchronously with delay."""
        await asyncio.sleep(PROCESSING_DELAY)
        operations[operation_id]["status"] = "succeeded"
        print(f"Async {event_type} completed for item: {item}")


    @app.post("/on-borrow")
    async def on_borrow(event: BorrowEvent, background_tasks: BackgroundTasks):
        """Handle borrow event."""
        events_received.append({
            "type": "borrow",
            "item": event.item,
            "params": event.params
        })
        print(f"Borrow event: item={event.item}, params={event.params}")

        if ASYNC_MODE:
            op_id = str(uuid.uuid4())
            operations[op_id] = {"status": "pending"}
            background_tasks.add_task(process_async, op_id, "borrow", event.item)
            return {"operation_id": op_id}
        return {"status": "ok"}


    @app.post("/on-return")
    async def on_return(event: ReturnEvent, background_tasks: BackgroundTasks):
        """Handle return event."""
        events_received.append({
            "type": "return",
            "item": event.item,
            "params": event.params
        })
        print(f"Return event: item={event.item}, params={event.params}")

        if ASYNC_MODE:
            op_id = str(uuid.uuid4())
            operations[op_id] = {"status": "pending"}
            background_tasks.add_task(process_async, op_id, "return", event.item)
            return {"operation_id": op_id}
        return {"status": "ok"}


    @app.post("/on-submit")
    async def on_submit(event: SubmitEvent, background_tasks: BackgroundTasks):
        """Handle submit event."""
        events_received.append({
            "type": "submit",
            "item": event.item
        })
        print(f"Submit event: item={event.item}")

        if ASYNC_MODE:
            op_id = str(uuid.uuid4())
            operations[op_id] = {"status": "pending"}
            background_tasks.add_task(process_async, op_id, "submit", event.item)
            return {"operation_id": op_id}
        return {"status": "ok"}


    @app.get("/operations/status")
    async def get_status(id: str):
        """Get operation status for async mode."""
        if id not in operations:
            return {"status": "pending"}
        return operations[id]


    @app.get("/health")
    async def health():
        """Health check endpoint."""
        return {"status": "healthy"}


    @app.get("/events")
    async def get_events():
        """Get all received events (for testing)."""
        return {"events": events_received, "count": len(events_received)}


    @app.delete("/events")
    async def clear_events():
        """Clear all received events (for testing)."""
        events_received.clear()
        return {"status": "cleared"}


    if __name__ == "__main__":
        import uvicorn
        port = int(os.environ.get("PORT", "8080"))
        uvicorn.run(app, host="0.0.0.0", port=port)
  '';

in
python3.pkgs.buildPythonApplication {
  pname = "example-subscriber";
  version = "1.0.0";
  format = "other";

  propagatedBuildInputs = with python3.pkgs; [
    fastapi
    uvicorn
    pydantic
  ];

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin $out/lib
    cat > $out/lib/subscriber.py << 'SCRIPT'
${subscriberScript}
SCRIPT

    makeWrapper ${pythonEnv}/bin/python $out/bin/example-subscriber \
      --add-flags "$out/lib/subscriber.py"
  '';

  nativeBuildInputs = [ makeWrapper ];

  meta = with lib; {
    description = "Example subscriber for IP Allocator tutorial";
    license = licenses.mit;
    maintainers = [ ];
  };
}
