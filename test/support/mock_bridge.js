/**
 * Mock Playwright bridge for Browser GenServer tests.
 * Reads JSON commands from stdin, returns canned JSON responses to stdout.
 * No Playwright dependency needed.
 */

const readline = require("readline");

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false,
});

const handlers = {
  launch: () => ({ browser_version: "mock-1.0" }),
  new_page: () => ({ page_id: "mock_page_1" }),
  navigate: (params) => ({ url: params.url, title: "Mock Page" }),
  get_page_content: () => ({ content: "<html><body>Mock content</body></html>" }),
  screenshot: () => ({ base64: Buffer.from("fake_png_data").toString("base64") }),
  set_cookies: () => ({}),
  get_cookies: () => ({ cookies: [{ name: "test", value: "cookie" }] }),
  get_json_responses: () => ({ responses: [] }),
  evaluate: () => ({ result: null }),
  click: () => ({}),
  type: () => ({}),
  wait_for_selector: () => ({}),
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
    const data = handler(params || {});
    process.stdout.write(JSON.stringify({ id, status: "ok", data }) + "\n");
  } else {
    process.stdout.write(
      JSON.stringify({ id, status: "error", error: `Unknown command: ${command}` }) + "\n"
    );
  }
});

rl.on("close", () => process.exit(0));
