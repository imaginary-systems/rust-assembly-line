# Flow Extractor

## When to Use
Run in parallel with the entity extractor after ADR validation. Extracts user flows, API endpoints, CLI commands, and async control flows to feed the story generator.

## Instructions

Parse the ADR and extract every flow that requires implementation work:

### Extraction Rules

**HTTP API Endpoints**
- Method (GET, POST, PUT, DELETE, PATCH)
- Path pattern (e.g., `/users/:id`)
- Request body type (if any)
- Response type
- Auth requirement
- Handler crate layer (`crate:api`)

**gRPC / tRPC Services**
- Service name and RPC method signatures
- Request/response message types
- Streaming patterns (unary, server-stream, client-stream, bidirectional)

**CLI Commands**
- Command and subcommand names
- Arguments and flags with types
- Expected output format (JSON, table, plain text)
- Crate layer (`crate:cli`)

**Async / Background Flows**
- Worker or job name
- Trigger mechanism (schedule, message queue, event)
- Input and output types
- Retry and error recovery strategy
- Crate layer (`crate:worker`)

**Internal Service Flows**
- Service method name
- Sequence of operations (repository calls, external calls, events emitted)
- Transactional boundaries
- Crate layer (`crate:service`)

**Channel / Event Flows**
- Channel type (`mpsc`, `broadcast`, `watch`, `oneshot`)
- Producer and consumer crates
- Message type
- Backpressure handling

### Output Format

```yaml
flows:
  - kind: http_endpoint
    method: POST
    path: /users
    request_type: CreateUserRequest
    response_type: UserResponse
    auth_required: true
    handler_crate: crate:api
    notes: "Returns 409 if email exists"

  - kind: service_flow
    name: UserService::create
    crate: crate:service
    steps:
      - "Validate input with CreateUserRequest::validate()"
      - "Check duplicate via UserRepository::find_by_email()"
      - "Hash password with argon2"
      - "Persist via UserRepository::insert()"
      - "Emit UserCreated event on broadcast channel"
    transactional: true
    notes: "Rolls back on any step failure"

  - kind: background_worker
    name: EmailNotificationWorker
    trigger: broadcast channel (UserCreated event)
    input_type: UserCreated
    crate: crate:worker
    retry: "3 attempts with exponential backoff"
    notes: "Non-blocking; failures logged but not surfaced to caller"

  - kind: cli_command
    name: "users create"
    args:
      - name: email
        type: String
        flag: "--email"
        required: true
    output_format: json
    crate: crate:cli
```

## Tools
- Read
- Grep

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:planning:flow-extractor",
  prompt="Extract all flows from this ADR: <path>"
)
```
