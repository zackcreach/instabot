import readline from "node:readline"
import {chromium, type Browser, type BrowserContextOptions, type Page} from "playwright"

type JsonObject = Record<string, unknown>

type BridgeRequest = {
  command?: string
  id?: string
  params?: JsonObject
}

type JsonResponse = {
  body: unknown
  url: string
}

type BridgeState = {
  browser: Browser | null
  jsonResponsesByPage: WeakMap<Page, JsonResponse[]>
  nextPageId: number
  pages: Map<string, Page>
}

type BridgeHandler = (state: BridgeState, params: JsonObject) => Promise<JsonObject>

export function createBridgeState(): BridgeState {
  return {
    browser: null,
    jsonResponsesByPage: new WeakMap(),
    nextPageId: 1,
    pages: new Map()
  }
}

function respond(output: NodeJS.WritableStream, id: string | undefined, status: "error" | "ok", payload: unknown): void {
  const response =
    status === "ok"
      ? {data: payload || {}, id, status: "ok"}
      : {error: String(payload), id, status: "error"}

  output.write(`${JSON.stringify(response)}\n`)
}

async function handleLaunch(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  if (state.browser) {
    await state.browser.close().catch(() => undefined)
  }

  const defaultArgs = [
    "--disable-blink-features=AutomationControlled",
    "--disable-dev-shm-usage",
    "--no-first-run",
    "--no-default-browser-check"
  ]
  const paramsArgs = Array.isArray(params.args) ? params.args.filter((arg): arg is string => typeof arg === "string") : []

  state.browser = await chromium.launch({
    args: [...defaultArgs, ...paramsArgs],
    headless: params.headless !== false
  })

  return {browser_version: state.browser.version()}
}

async function handleNewPage(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  if (!state.browser) {
    throw new Error("Browser not launched. Call launch first.")
  }

  const contextOptions: BrowserContextOptions = {}

  if (typeof params.user_agent === "string") {
    contextOptions.userAgent = params.user_agent
  }

  if (isViewport(params.viewport)) {
    contextOptions.viewport = params.viewport
  }

  const context = await state.browser.newContext(contextOptions)
  const page = await context.newPage()
  const responses: JsonResponse[] = []

  state.jsonResponsesByPage.set(page, responses)

  page.on("response", async response => {
    const url = response.url()
    const contentType = response.headers()["content-type"] || ""

    if (!contentType.includes("application/json") && !url.includes("graphql") && !url.includes("reels_media")) {
      return
    }

    try {
      responses.push({body: await response.json(), url})

      if (responses.length > 50) {
        responses.shift()
      }
    } catch {
      return
    }
  })

  const pageId = String(state.nextPageId)
  state.nextPageId += 1
  state.pages.set(pageId, page)

  return {page_id: pageId}
}

async function handleGetStorageState(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  const page = getPage(state, params.page_id)
  const storageState = await page.context().storageState()

  return {storage_state: storageState}
}

async function handleRestoreStorageState(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  const page = getPage(state, params.page_id)
  const storageState = params.storage_state

  if (!isStorageState(storageState)) {
    return {}
  }

  if (storageState.cookies.length > 0) {
    await page.context().addCookies(storageState.cookies)
  }

  if (storageState.origins.length > 0) {
    await page.goto("https://www.instagram.com/", {
      timeout: 15000,
      waitUntil: "domcontentloaded"
    })

    for (const origin of storageState.origins) {
      if (Array.isArray(origin.localStorage) && origin.localStorage.length > 0) {
        await page.evaluate(items => {
          for (const {name, value} of items) {
            localStorage.setItem(name, value)
          }
        }, origin.localStorage)
      }
    }
  }

  return {}
}

async function handleNavigate(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  const page = getPage(state, params.page_id)

  await page.goto(requiredString(params.url, "url"), {
    timeout: numberParam(params.timeout, 30000),
    waitUntil: waitUntilParam(params.wait_until)
  })

  return {title: await page.title(), url: page.url()}
}

async function handleScreenshot(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  const page = getPage(state, params.page_id)
  const buffer = await page.screenshot({
    fullPage: params.full_page === true,
    path: typeof params.path === "string" ? params.path : undefined
  })

  return {base64: buffer.toString("base64")}
}

async function handleSetCookies(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  const page = getPage(state, params.page_id)

  if (Array.isArray(params.cookies)) {
    await page.context().addCookies(params.cookies)
  }

  return {}
}

async function handleGetCookies(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  const page = getPage(state, params.page_id)
  const cookies = await page.context().cookies()

  return {cookies}
}

async function handleEvaluate(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  const page = getPage(state, params.page_id)
  const result = await page.evaluate(requiredString(params.expression, "expression"))

  return {result}
}

async function handleGetPageContent(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  const page = getPage(state, params.page_id)
  const content = await page.content()

  return {content}
}

async function handleGetJsonResponses(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  const page = getPage(state, params.page_id)
  const responses = state.jsonResponsesByPage.get(page) || []

  if (typeof params.url_contains === "string") {
    return {responses: responses.filter(response => response.url.includes(params.url_contains as string))}
  }

  return {responses}
}

async function handleClick(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  const page = getPage(state, params.page_id)
  await page.click(requiredString(params.selector, "selector"))

  return {}
}

async function handleType(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  const page = getPage(state, params.page_id)
  const selector = requiredString(params.selector, "selector")
  const text = requiredString(params.text, "text")

  if (typeof params.delay === "number" && params.delay > 0) {
    await page.type(selector, text, {delay: params.delay})
  } else {
    await page.fill(selector, text)
  }

  return {}
}

async function handleWaitForSelector(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  const page = getPage(state, params.page_id)

  await page.waitForSelector(requiredString(params.selector, "selector"), {
    timeout: numberParam(params.timeout, 30000)
  })

  return {}
}

async function handleClose(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  if (typeof params.page_id === "string") {
    const page = getPage(state, params.page_id)
    await page.context().close()
    state.pages.delete(params.page_id)
  } else if (state.browser) {
    await state.browser.close()
    state.browser = null
    state.pages.clear()
  }

  return {}
}

async function handleKeyboardPress(state: BridgeState, params: JsonObject): Promise<JsonObject> {
  const page = getPage(state, params.page_id)
  await page.keyboard.press(requiredString(params.key, "key"))

  return {}
}

function getPage(state: BridgeState, pageId: unknown): Page {
  if (typeof pageId !== "string") {
    throw new Error("Missing page_id")
  }

  const page = state.pages.get(pageId)

  if (!page) {
    throw new Error(`Page ${pageId} not found`)
  }

  return page
}

function requiredString(value: unknown, name: string): string {
  if (typeof value !== "string") {
    throw new Error(`Missing ${name}`)
  }

  return value
}

function numberParam(value: unknown, defaultValue: number): number {
  return typeof value === "number" ? value : defaultValue
}

function waitUntilParam(value: unknown): "commit" | "domcontentloaded" | "load" | "networkidle" {
  if (value === "commit" || value === "load" || value === "networkidle") {
    return value
  }

  return "domcontentloaded"
}

function isViewport(value: unknown): value is {height: number; width: number} {
  return (
    typeof value === "object" &&
    value !== null &&
    "height" in value &&
    "width" in value &&
    typeof value.height === "number" &&
    typeof value.width === "number"
  )
}

function isStorageState(value: unknown): value is {
  cookies: Parameters<ReturnType<Page["context"]>["addCookies"]>[0]
  origins: Array<{localStorage?: Array<{name: string; value: string}>}>
} {
  return (
    typeof value === "object" &&
    value !== null &&
    "cookies" in value &&
    "origins" in value &&
    Array.isArray(value.cookies) &&
    Array.isArray(value.origins)
  )
}

const commands: Record<string, BridgeHandler> = {
  click: handleClick,
  close: handleClose,
  evaluate: handleEvaluate,
  get_cookies: handleGetCookies,
  get_json_responses: handleGetJsonResponses,
  get_page_content: handleGetPageContent,
  get_storage_state: handleGetStorageState,
  keyboard_press: handleKeyboardPress,
  launch: handleLaunch,
  navigate: handleNavigate,
  new_page: handleNewPage,
  restore_storage_state: handleRestoreStorageState,
  screenshot: handleScreenshot,
  set_cookies: handleSetCookies,
  type: handleType,
  wait_for_selector: handleWaitForSelector
}

export function startBridge(input: NodeJS.ReadableStream = process.stdin, output: NodeJS.WritableStream = process.stdout): void {
  const state = createBridgeState()
  const rl = readline.createInterface({
    input,
    output,
    terminal: false
  })

  rl.on("line", line => {
    void handleLine(state, output, line)
  })

  rl.on("close", () => {
    void closeBrowser(state).finally(() => process.exit(0))
  })

  process.on("SIGTERM", () => {
    void closeBrowser(state).finally(() => process.exit(0))
  })
}

async function handleLine(state: BridgeState, output: NodeJS.WritableStream, line: string): Promise<void> {
  let request: BridgeRequest

  try {
    request = JSON.parse(line) as BridgeRequest
  } catch {
    process.stderr.write(`Invalid JSON: ${line}\n`)
    return
  }

  const handler = request.command ? commands[request.command] : undefined
  process.stderr.write(`[bridge] command=${request.command} id=${request.id}\n`)

  if (!handler) {
    respond(output, request.id, "error", `Unknown command: ${request.command}`)
    return
  }

  try {
    const data = await handler(state, request.params || {})
    process.stderr.write(`[bridge] command=${request.command} id=${request.id} ok\n`)
    respond(output, request.id, "ok", data)
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    process.stderr.write(`[bridge] command=${request.command} id=${request.id} error: ${message}\n`)
    respond(output, request.id, "error", message)
  }
}

async function closeBrowser(state: BridgeState): Promise<void> {
  if (state.browser) {
    await state.browser.close().catch(() => undefined)
  }
}

if (require.main === module) {
  startBridge()
}
