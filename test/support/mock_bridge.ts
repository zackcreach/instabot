import readline from "node:readline"

export type MockRequest = {
  command?: string
  id?: string
  params?: Record<string, unknown>
}

export type MockResponse =
  | {data: Record<string, unknown>; id: string | undefined; status: "ok"}
  | {error: string; id: string | undefined; status: "error"}

type HandlerResult = Record<string, unknown> | {error: string; status: "error"}
type MockHandler = (params: Record<string, unknown>) => HandlerResult

function isErrorResult(data: HandlerResult): data is {error: string; status: "error"} {
  return "status" in data && data.status === "error"
}

export function createMockBridgeHandlers(environment: NodeJS.ProcessEnv = process.env): Record<string, MockHandler> {
  return {
    click: () => ({}),
    close: () => ({}),
    evaluate: () => ({result: null}),
    get_cookies: () => ({cookies: [{name: "test", value: "cookie"}]}),
    get_json_responses: () => ({responses: []}),
    get_page_content: () => ({content: "<html><body>Mock content</body></html>"}),
    launch: () => {
      if (environment.INSTABOT_MOCK_BRIDGE_FAIL_LAUNCH === "true") {
        return {error: "mock launch failed", status: "error"}
      }

      return {browser_version: "mock-1.0"}
    },
    navigate: params => ({title: "Mock Page", url: params.url}),
    new_page: () => ({page_id: "mock_page_1"}),
    screenshot: () => ({base64: Buffer.from("fake_png_data").toString("base64")}),
    set_cookies: () => ({}),
    type: () => ({}),
    wait_for_selector: () => ({})
  }
}

export function handleMockRequest(
  line: string,
  handlers: Record<string, MockHandler> = createMockBridgeHandlers()
): MockResponse | null {
  let request: MockRequest

  try {
    request = JSON.parse(line) as MockRequest
  } catch {
    return null
  }

  const handler = request.command ? handlers[request.command] : undefined

  if (!handler) {
    return {error: `Unknown command: ${request.command}`, id: request.id, status: "error"}
  }

  const data = handler(request.params || {})

  if (isErrorResult(data)) {
    return {error: data.error, id: request.id, status: "error"}
  }

  return {data, id: request.id, status: "ok"}
}

export function startMockBridge(input: NodeJS.ReadableStream = process.stdin, output: NodeJS.WritableStream = process.stdout): void {
  const rl = readline.createInterface({
    input,
    output,
    terminal: false
  })

  output.on("error", error => {
    if ("code" in error && error.code === "EPIPE") {
      process.exit(0)
    }

    throw error
  })

  rl.on("line", line => {
    const response = handleMockRequest(line)

    if (response) {
      output.write(`${JSON.stringify(response)}\n`)
    }
  })

  rl.on("close", () => process.exit(0))
}

if (require.main === module) {
  startMockBridge()
}
