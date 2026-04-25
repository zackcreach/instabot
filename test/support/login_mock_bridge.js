/**
 * Stateful mock Playwright bridge for LoginOrchestrator tests.
 * Simulates a login flow by tracking state transitions:
 * - First get_page_content after navigate returns login page HTML
 * - After type + click sequence, get_page_content returns home page HTML
 *
 * Set LOGIN_MOCK_MODE env to control behavior:
 *   "success" (default) — login succeeds after credentials
 *   "two_factor"        — returns 2FA page after credentials, then succeeds after code
 *   "error"             — returns incorrect password error
 */

const readline = require("readline");

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false,
});

const mode = process.env.LOGIN_MOCK_MODE || "success";
let state = "initial";
let typeCount = 0;
let clickCount = 0;

const LOGIN_PAGE_HTML =
  '<html><head><title>Login</title></head><body><form id="loginForm" action="/accounts/login/"><input name="username"><input name="password"><button type="submit">Log in to Instagram</button></form></body></html>';

const HOME_PAGE_HTML =
  "<html><head><title>Instagram</title></head><body><div>Welcome to Instagram feed</div></body></html>";

const TWO_FACTOR_HTML =
  '<html><head><title>Instagram</title></head><body><h1>Two-Factor Authentication Required</h1><p>Enter the security code</p><form id="twoFactorForm"><input name="verificationCode"><button type="submit">Confirm</button></form></body></html>';

const ERROR_PASSWORD_HTML =
  '<html><head><title>Login</title></head><body><form id="loginForm" action="/accounts/login/"><div role="alert">Sorry, your password was incorrect. Please double-check your password.</div></form></body></html>';

function getPageContent() {
  if (mode === "error") {
    if (state === "credentials_submitted") {
      return ERROR_PASSWORD_HTML;
    }
    return LOGIN_PAGE_HTML;
  }

  if (mode === "two_factor") {
    if (state === "credentials_submitted") {
      state = "two_factor";
      return TWO_FACTOR_HTML;
    }
    if (state === "two_factor_submitted") {
      return HOME_PAGE_HTML;
    }
    return LOGIN_PAGE_HTML;
  }

  if (state === "credentials_submitted") {
    return HOME_PAGE_HTML;
  }
  return LOGIN_PAGE_HTML;
}

const handlers = {
  launch: () => ({ browser_version: "mock-1.0" }),
  new_page: () => ({ page_id: "mock_page_1" }),
  navigate: (params) => ({ url: params.url, title: "Mock Page" }),
  get_page_content: () => ({ content: getPageContent() }),
  screenshot: () => ({
    base64: Buffer.from("fake_screenshot_data").toString("base64"),
  }),
  set_cookies: () => ({}),
  get_cookies: () => ({
    cookies: [
      { name: "sessionid", value: "mock_session_123", domain: ".instagram.com" },
      { name: "csrftoken", value: "mock_csrf_456", domain: ".instagram.com" },
    ],
  }),
  get_storage_state: () => ({
    cookies: [
      { name: "sessionid", value: "mock_session_123", domain: ".instagram.com" },
      { name: "csrftoken", value: "mock_csrf_456", domain: ".instagram.com" },
    ],
    origins: [],
  }),
  get_json_responses: () => ({ responses: [] }),
  restore_storage_state: () => ({}),
  evaluate: () => ({ result: null }),
  click: () => {
    clickCount++;
    if (state === "two_factor_typed") {
      state = "two_factor_submitted";
    }
    return {};
  },
  type: () => {
    typeCount++;
    if (typeCount >= 2 && state === "initial") {
      state = "credentials_typed";
    }
    if (state === "two_factor") {
      state = "two_factor_typed";
    }
    return {};
  },
  keyboard_press: () => {
    if (state === "credentials_typed") {
      state = "credentials_submitted";
    }
    return {};
  },
  wait_for_selector: (params) => {
    if (params.selector && params.selector.includes("verificationCode")) {
      if (state === "two_factor" || state === "credentials_submitted" && mode === "two_factor") {
        return {};
      }
      throw new Error("Timeout waiting for selector");
    }
    return {};
  },
  close: () => ({}),
};

rl.on("line", (line) => {
  let request;
  try {
    request = JSON.parse(line);
  } catch {
    return;
  }

  const { id, command, params } = request;
  const handler = handlers[command];

  if (handler) {
    try {
      const data = handler(params || {});
      process.stdout.write(JSON.stringify({ id, status: "ok", data }) + "\n");
    } catch (error) {
      process.stdout.write(
        JSON.stringify({ id, status: "error", error: error.message }) + "\n"
      );
    }
  } else {
    process.stdout.write(
      JSON.stringify({
        id,
        status: "error",
        error: `Unknown command: ${command}`,
      }) + "\n"
    );
  }
});

rl.on("close", () => process.exit(0));
