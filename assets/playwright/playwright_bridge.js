/**
 * Playwright Bridge — stdin/stdout JSON-RPC process for browser automation.
 *
 * Protocol: newline-delimited JSON.
 *   Request:  {"id": "1", "command": "launch", "params": {...}}
 *   Response: {"id": "1", "status": "ok", "data": {...}}
 *              or {"id": "1", "status": "error", "error": "message"}
 */

const readline = require("readline");
const { chromium } = require("playwright");

let browser = null;
const pages = new Map();
let nextPageId = 1;

/**
 * Sends a JSON response to stdout.
 * @param {string} id - Request correlation ID.
 * @param {"ok"|"error"} status - Response status.
 * @param {object} [payload] - Response data or error message.
 */
function respond(id, status, payload) {
  const response =
    status === "ok"
      ? { id, status: "ok", data: payload || {} }
      : { id, status: "error", error: String(payload) };
  process.stdout.write(JSON.stringify(response) + "\n");
}

/**
 * Launches a Chromium browser instance.
 * @param {object} params - Launch parameters.
 * @param {boolean} [params.headless=true] - Run in headless mode.
 * @param {string[]} [params.args=[]] - Additional Chromium arguments.
 * @returns {Promise<{browser_version: string}>}
 */
async function handleLaunch(params) {
  if (browser) {
    await browser.close().catch(() => {});
  }

  const defaultArgs = [
    "--disable-blink-features=AutomationControlled",
    "--disable-dev-shm-usage",
    "--no-first-run",
    "--no-default-browser-check",
  ];

  const args = [...defaultArgs, ...(params.args || [])];

  browser = await chromium.launch({
    headless: params.headless !== false,
    args,
  });

  return { browser_version: browser.version() };
}

/**
 * Creates a new browser page.
 * @param {object} params - Page parameters.
 * @param {string} [params.user_agent] - Custom user agent string.
 * @param {object} [params.viewport] - Viewport dimensions {width, height}.
 * @returns {Promise<{page_id: string}>}
 */
async function handleNewPage(params) {
  if (!browser) {
    throw new Error("Browser not launched. Call launch first.");
  }

  const contextOptions = {};
  if (params.user_agent) {
    contextOptions.userAgent = params.user_agent;
  }
  if (params.viewport) {
    contextOptions.viewport = params.viewport;
  }

  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();
  page.__instabotJsonResponses = [];
  page.on("response", async (response) => {
    const url = response.url();
    const contentType = response.headers()["content-type"] || "";
    if (!contentType.includes("application/json") && !url.includes("graphql") && !url.includes("reels_media")) {
      return;
    }

    try {
      const body = await response.json();
      page.__instabotJsonResponses.push({ url, body });
      if (page.__instabotJsonResponses.length > 50) {
        page.__instabotJsonResponses.shift();
      }
    } catch (_) {}
  });
  const pageId = String(nextPageId++);
  pages.set(pageId, page);

  return { page_id: pageId };
}

/**
 * Gets the full storage state (cookies + localStorage) from the page's browser context.
 * @param {object} params
 * @param {string} params.page_id - Target page ID.
 * @returns {Promise<{storage_state: object}>}
 */
async function handleGetStorageState(params) {
  const page = getPage(params.page_id);
  const storageState = await page.context().storageState();
  return { storage_state: storageState };
}

/**
 * Restores full storage state (cookies + localStorage) into a page's browser context.
 * @param {object} params
 * @param {string} params.page_id - Target page ID.
 * @param {object} params.storage_state - Storage state with cookies array and origins array.
 * @returns {Promise<{}>}
 */
async function handleRestoreStorageState(params) {
  const ss = params.storage_state;
  process.stderr.write(
    `[bridge] restore_storage_state ss_type=${typeof ss} cookies_is_array=${Array.isArray(ss?.cookies)} cookies_len=${ss?.cookies?.length} origins_is_array=${Array.isArray(ss?.origins)} origins_len=${ss?.origins?.length} ss_keys=${ss ? Object.keys(ss).join(",") : "null"}\n`
  );
  if (ss?.cookies && !Array.isArray(ss.cookies)) {
    process.stderr.write(`[bridge] restore_storage_state cookies_sample=${JSON.stringify(ss.cookies).slice(0, 200)}\n`);
  }
  const page = getPage(params.page_id);
  const { cookies, origins } = params.storage_state;

  if (Array.isArray(cookies) && cookies.length > 0) {
    await page.context().addCookies(cookies);
  }

  if (Array.isArray(origins) && origins.length > 0) {
    await page.goto("https://www.instagram.com/", {
      waitUntil: "domcontentloaded",
      timeout: 15000,
    });

    for (const origin of origins) {
      if (Array.isArray(origin.localStorage) && origin.localStorage.length > 0) {
        await page.evaluate((items) => {
          for (const { name, value } of items) {
            localStorage.setItem(name, value);
          }
        }, origin.localStorage);
      }
    }
  }

  return {};
}

/**
 * Navigates a page to the given URL.
 * @param {object} params
 * @param {string} params.page_id - Target page ID.
 * @param {string} params.url - URL to navigate to.
 * @param {string} [params.wait_until="domcontentloaded"] - Navigation wait condition.
 * @returns {Promise<{url: string, title: string}>}
 */
async function handleNavigate(params) {
  const page = getPage(params.page_id);
  await page.goto(params.url, {
    waitUntil: params.wait_until || "domcontentloaded",
    timeout: params.timeout || 30000,
  });
  return { url: page.url(), title: await page.title() };
}

/**
 * Takes a screenshot of the page.
 * @param {object} params
 * @param {string} params.page_id - Target page ID.
 * @param {string} [params.path] - File path to save screenshot.
 * @param {boolean} [params.full_page=false] - Capture full scrollable page.
 * @returns {Promise<{base64: string}>}
 */
async function handleScreenshot(params) {
  const page = getPage(params.page_id);
  const buffer = await page.screenshot({
    path: params.path || undefined,
    fullPage: params.full_page || false,
  });
  return { base64: buffer.toString("base64") };
}

/**
 * Sets cookies on the page's browser context.
 * @param {object} params
 * @param {string} params.page_id - Target page ID.
 * @param {object[]} params.cookies - Array of cookie objects.
 * @returns {Promise<{}>}
 */
async function handleSetCookies(params) {
  const page = getPage(params.page_id);
  await page.context().addCookies(params.cookies);
  return {};
}

/**
 * Gets all cookies from the page's browser context.
 * @param {object} params
 * @param {string} params.page_id - Target page ID.
 * @returns {Promise<{cookies: object[]}>}
 */
async function handleGetCookies(params) {
  const page = getPage(params.page_id);
  const cookies = await page.context().cookies();
  return { cookies };
}

/**
 * Evaluates a JavaScript expression in the page context.
 * @param {object} params
 * @param {string} params.page_id - Target page ID.
 * @param {string} params.expression - JavaScript expression to evaluate.
 * @returns {Promise<{result: *}>}
 */
async function handleEvaluate(params) {
  const page = getPage(params.page_id);
  const result = await page.evaluate(params.expression);
  return { result };
}

/**
 * Gets the full HTML content of the page.
 * @param {object} params
 * @param {string} params.page_id - Target page ID.
 * @returns {Promise<{content: string}>}
 */
async function handleGetPageContent(params) {
  const page = getPage(params.page_id);
  const content = await page.content();
  return { content };
}

async function handleGetJsonResponses(params) {
  const page = getPage(params.page_id);
  const urlContains = params.url_contains;
  const responses = page.__instabotJsonResponses || [];
  const filtered = urlContains
    ? responses.filter((response) => response.url.includes(urlContains))
    : responses;
  return { responses: filtered };
}

/**
 * Clicks an element matching the selector.
 * @param {object} params
 * @param {string} params.page_id - Target page ID.
 * @param {string} params.selector - CSS selector to click.
 * @returns {Promise<{}>}
 */
async function handleClick(params) {
  const page = getPage(params.page_id);
  await page.click(params.selector);
  return {};
}

/**
 * Types text into an element matching the selector.
 * @param {object} params
 * @param {string} params.page_id - Target page ID.
 * @param {string} params.selector - CSS selector of input element.
 * @param {string} params.text - Text to type.
 * @param {number} [params.delay=0] - Delay between keystrokes in ms.
 * @returns {Promise<{}>}
 */
async function handleType(params) {
  const page = getPage(params.page_id);
  if (params.delay) {
    await page.type(params.selector, params.text, { delay: params.delay });
  } else {
    await page.fill(params.selector, params.text);
  }
  return {};
}

/**
 * Waits for an element matching the selector to appear.
 * @param {object} params
 * @param {string} params.page_id - Target page ID.
 * @param {string} params.selector - CSS selector to wait for.
 * @param {number} [params.timeout=30000] - Timeout in milliseconds.
 * @returns {Promise<{}>}
 */
async function handleWaitForSelector(params) {
  const page = getPage(params.page_id);
  await page.waitForSelector(params.selector, {
    timeout: params.timeout || 30000,
  });
  return {};
}

/**
 * Closes a specific page or the entire browser.
 * @param {object} params
 * @param {string} [params.page_id] - Page to close. If omitted, closes the browser.
 * @returns {Promise<{}>}
 */
async function handleClose(params) {
  if (params.page_id) {
    const page = getPage(params.page_id);
    await page.context().close();
    pages.delete(params.page_id);
  } else if (browser) {
    await browser.close();
    browser = null;
    pages.clear();
  }
  return {};
}

/**
 * Retrieves a page by ID, throwing if not found.
 * @param {string} pageId - The page ID to look up.
 * @returns {import("playwright").Page}
 */
function getPage(pageId) {
  const page = pages.get(pageId);
  if (!page) {
    throw new Error(`Page ${pageId} not found`);
  }
  return page;
}

/**
 * Presses a keyboard key on a page.
 * @param {object} params
 * @param {string} params.page_id - Target page ID.
 * @param {string} params.key - Key to press (e.g. "Enter", "Tab", "Escape").
 * @returns {Promise<{}>}
 */
async function handleKeyboardPress(params) {
  const page = getPage(params.page_id);
  await page.keyboard.press(params.key);
  return {};
}

const COMMANDS = {
  launch: handleLaunch,
  new_page: handleNewPage,
  navigate: handleNavigate,
  screenshot: handleScreenshot,
  set_cookies: handleSetCookies,
  get_cookies: handleGetCookies,
  get_storage_state: handleGetStorageState,
  restore_storage_state: handleRestoreStorageState,
  evaluate: handleEvaluate,
  get_page_content: handleGetPageContent,
  get_json_responses: handleGetJsonResponses,
  click: handleClick,
  type: handleType,
  wait_for_selector: handleWaitForSelector,
  keyboard_press: handleKeyboardPress,
  close: handleClose,
};

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false,
});

rl.on("line", async (line) => {
  let request;
  try {
    request = JSON.parse(line);
  } catch (error) {
    process.stderr.write(`Invalid JSON: ${line}\n`);
    return;
  }

  const { id, command, params } = request;
  const handler = COMMANDS[command];
  process.stderr.write(`[bridge] command=${command} id=${id}\n`);

  if (!handler) {
    respond(id, "error", `Unknown command: ${command}`);
    return;
  }

  try {
    const data = await handler(params || {});
    process.stderr.write(`[bridge] command=${command} id=${id} ok\n`);
    respond(id, "ok", data);
  } catch (error) {
    process.stderr.write(`[bridge] command=${command} id=${id} error: ${error.message}\n`);
    respond(id, "error", error.message);
  }
});

rl.on("close", async () => {
  if (browser) {
    await browser.close().catch(() => {});
  }
  process.exit(0);
});

process.on("SIGTERM", async () => {
  if (browser) {
    await browser.close().catch(() => {});
  }
  process.exit(0);
});
