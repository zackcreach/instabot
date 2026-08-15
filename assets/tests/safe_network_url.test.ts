import {describe, expect, test} from "vitest"
import {safeNetworkUrl} from "../playwright/playwright_bridge"

const publicLookup = async () => [{address: "93.184.216.34"}, {address: "2606:2800:220:1::1"}]

describe("safeNetworkUrl", () => {
  test("allows public web destinations", async () => {
    await expect(safeNetworkUrl("https://shop.example/products", publicLookup)).resolves.toBe(true)
    await expect(safeNetworkUrl("http://shop.example:80", publicLookup)).resolves.toBe(true)
  })

  test("rejects credentials and non-web ports", async () => {
    await expect(safeNetworkUrl("https://user:password@shop.example", publicLookup)).resolves.toBe(false)
    await expect(safeNetworkUrl("https://shop.example:444", publicLookup)).resolves.toBe(false)
  })

  test("rejects private and metadata destinations", async () => {
    for (const address of ["127.0.0.1", "10.0.0.1", "169.254.169.254", "::1", "fc00::1", "fe80::1"]) {
      await expect(safeNetworkUrl("https://shop.example", async () => [{address}])).resolves.toBe(false)
    }
  })

  test("rejects mapped IPv4 and mixed DNS answers", async () => {
    await expect(safeNetworkUrl("https://shop.example", async () => [{address: "::ffff:127.0.0.1"}])).resolves.toBe(
      false
    )
    await expect(
      safeNetworkUrl("https://shop.example", async () => [{address: "93.184.216.34"}, {address: "10.0.0.1"}])
    ).resolves.toBe(false)
  })

  test("fails closed when DNS resolution fails", async () => {
    await expect(
      safeNetworkUrl("https://shop.example", async () => {
        throw new Error("DNS failed")
      })
    ).resolves.toBe(false)
  })
})
