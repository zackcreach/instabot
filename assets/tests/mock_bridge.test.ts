import {describe, expect, test} from "vitest"
import {createLoginMockBridgeHandlers, handleLoginMockRequest} from "../../test/support/login_mock_bridge"
import {createMockBridgeHandlers, handleMockRequest} from "../../test/support/mock_bridge"

describe("mock bridge protocol", () => {
  test("returns launch data for successful launch", () => {
    const response = handleMockRequest(
      JSON.stringify({command: "launch", id: "1", params: {}}),
      createMockBridgeHandlers({})
    )

    expect(response).toEqual({
      data: {browser_version: "mock-1.0"},
      id: "1",
      status: "ok"
    })
  })

  test("returns configured launch failure", () => {
    const response = handleMockRequest(
      JSON.stringify({command: "launch", id: "1", params: {}}),
      createMockBridgeHandlers({INSTABOT_MOCK_BRIDGE_FAIL_LAUNCH: "true"})
    )

    expect(response).toEqual({
      error: "mock launch failed",
      id: "1",
      status: "error"
    })
  })

  test("ignores invalid json lines", () => {
    expect(handleMockRequest("{")).toBeNull()
  })
})

describe("login mock bridge protocol", () => {
  test("moves from credentials to successful home page", () => {
    const handlers = createLoginMockBridgeHandlers({LOGIN_MOCK_MODE: "success"})

    expect(
      handleLoginMockRequest(JSON.stringify({command: "get_page_content", id: "1", params: {}}), handlers)
    ).toMatchObject({
      data: {content: expect.stringContaining("loginForm")},
      status: "ok"
    })

    handleLoginMockRequest(JSON.stringify({command: "type", id: "2", params: {}}), handlers)
    handleLoginMockRequest(JSON.stringify({command: "type", id: "3", params: {}}), handlers)
    handleLoginMockRequest(JSON.stringify({command: "keyboard_press", id: "4", params: {}}), handlers)

    expect(
      handleLoginMockRequest(JSON.stringify({command: "get_page_content", id: "5", params: {}}), handlers)
    ).toMatchObject({
      data: {content: expect.stringContaining("Welcome to Instagram feed")},
      status: "ok"
    })
  })

  test("returns two-factor selector wait only after credentials submit", () => {
    const handlers = createLoginMockBridgeHandlers({LOGIN_MOCK_MODE: "two_factor"})

    expect(
      handleLoginMockRequest(
        JSON.stringify({command: "wait_for_selector", id: "1", params: {selector: "input[name='verificationCode']"}}),
        handlers
      )
    ).toEqual({
      error: "Timeout waiting for selector",
      id: "1",
      status: "error"
    })

    handleLoginMockRequest(JSON.stringify({command: "type", id: "2", params: {}}), handlers)
    handleLoginMockRequest(JSON.stringify({command: "type", id: "3", params: {}}), handlers)
    handleLoginMockRequest(JSON.stringify({command: "keyboard_press", id: "4", params: {}}), handlers)

    expect(
      handleLoginMockRequest(
        JSON.stringify({command: "wait_for_selector", id: "5", params: {selector: "input[name='verificationCode']"}}),
        handlers
      )
    ).toEqual({
      data: {},
      id: "5",
      status: "ok"
    })
  })
})
