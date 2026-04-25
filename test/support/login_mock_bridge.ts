import readline from "node:readline"

type LoginMode = "error" | "success" | "two_factor"
type LoginState =
  | "credentials_submitted"
  | "credentials_typed"
  | "initial"
  | "two_factor"
  | "two_factor_submitted"
  | "two_factor_typed"

type LoginRequest = {
  command?: string
  id?: string
  params?: Record<string, unknown>
}

type LoginHandler = (params: Record<string, unknown>) => Record<string, unknown>

const loginPageHtml =
  '<html><head><title>Login</title></head><body><form id="loginForm" action="/accounts/login/"><input name="username"><input name="password"><button type="submit">Log in to Instagram</button></form></body></html>'

const homePageHtml =
  "<html><head><title>Instagram</title></head><body><div>Welcome to Instagram feed</div></body></html>"

const twoFactorHtml =
  '<html><head><title>Instagram</title></head><body><h1>Two-Factor Authentication Required</h1><p>Enter the security code</p><form id="twoFactorForm"><input name="verificationCode"><button type="submit">Confirm</button></form></body></html>'

const errorPasswordHtml =
  '<html><head><title>Login</title></head><body><form id="loginForm" action="/accounts/login/"><div role="alert">Sorry, your password was incorrect. Please double-check your password.</div></form></body></html>'

function modeFromEnvironment(environment: NodeJS.ProcessEnv): LoginMode {
  if (environment.LOGIN_MOCK_MODE === "error" || environment.LOGIN_MOCK_MODE === "two_factor") {
    return environment.LOGIN_MOCK_MODE
  }

  return "success"
}

export function createLoginMockBridgeHandlers(environment: NodeJS.ProcessEnv = process.env): Record<string, LoginHandler> {
  const mode = modeFromEnvironment(environment)
  let state: LoginState = "initial"
  let typeCount = 0

  const getPageContent = (): string => {
    if (mode === "error") {
      if (state === "credentials_submitted") {
        return errorPasswordHtml
      }

      return loginPageHtml
    }

    if (mode === "two_factor") {
      if (state === "credentials_submitted") {
        return twoFactorHtml
      }

      if (state === "two_factor" || state === "two_factor_typed") {
        return twoFactorHtml
      }

      if (state === "two_factor_submitted") {
        return homePageHtml
      }

      return loginPageHtml
    }

    if (state === "credentials_submitted") {
      return homePageHtml
    }

    return loginPageHtml
  }

  return {
    click: () => {
      if (state === "two_factor_typed") {
        state = "two_factor_submitted"
      }

      return {}
    },
    close: () => ({}),
    evaluate: () => ({result: null}),
    get_cookies: () => ({
      cookies: [
        {domain: ".instagram.com", name: "sessionid", value: "mock_session_123"},
        {domain: ".instagram.com", name: "csrftoken", value: "mock_csrf_456"}
      ]
    }),
    get_json_responses: () => ({responses: []}),
    get_page_content: () => ({content: getPageContent()}),
    get_storage_state: () => ({
      cookies: [
        {domain: ".instagram.com", name: "sessionid", value: "mock_session_123"},
        {domain: ".instagram.com", name: "csrftoken", value: "mock_csrf_456"}
      ],
      origins: []
    }),
    keyboard_press: () => {
      if (state === "credentials_typed") {
        state = mode === "two_factor" ? "two_factor" : "credentials_submitted"
      }

      return {}
    },
    launch: () => ({browser_version: "mock-1.0"}),
    navigate: params => ({title: "Mock Page", url: params.url}),
    new_page: () => ({page_id: "mock_page_1"}),
    restore_storage_state: () => ({}),
    screenshot: () => ({
      base64: Buffer.from("fake_screenshot_data").toString("base64")
    }),
    set_cookies: () => ({}),
    type: () => {
      typeCount += 1

      if (typeCount >= 2 && state === "initial") {
        state = "credentials_typed"
      }

      if (state === "two_factor") {
        state = "two_factor_typed"
      }

      return {}
    },
    wait_for_selector: params => {
      if (typeof params.selector === "string" && params.selector.includes("verificationCode")) {
        if (state === "two_factor" || state === "two_factor_typed") {
          return {}
        }

        throw new Error("Timeout waiting for selector")
      }

      return {}
    }
  }
}

export function handleLoginMockRequest(
  line: string,
  handlers: Record<string, LoginHandler> = createLoginMockBridgeHandlers()
): {data?: Record<string, unknown>; error?: string; id: string | undefined; status: "error" | "ok"} | null {
  let request: LoginRequest

  try {
    request = JSON.parse(line) as LoginRequest
  } catch {
    return null
  }

  const handler = request.command ? handlers[request.command] : undefined

  if (!handler) {
    return {
      error: `Unknown command: ${request.command}`,
      id: request.id,
      status: "error"
    }
  }

  try {
    return {
      data: handler(request.params || {}),
      id: request.id,
      status: "ok"
    }
  } catch (error) {
    return {
      error: error instanceof Error ? error.message : String(error),
      id: request.id,
      status: "error"
    }
  }
}

export function startLoginMockBridge(input: NodeJS.ReadableStream = process.stdin, output: NodeJS.WritableStream = process.stdout): void {
  const handlers = createLoginMockBridgeHandlers()
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
    const response = handleLoginMockRequest(line, handlers)

    if (response) {
      output.write(`${JSON.stringify(response)}\n`)
    }
  })

  rl.on("close", () => process.exit(0))
}

if (require.main === module) {
  startLoginMockBridge()
}
