import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket, type LiveSocketInstanceInterface} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/instabot"
import topbar from "../vendor/topbar"

type LiveReloader = {
  enableServerLogs(): void
  openEditorAtCaller(target: EventTarget | null): void
  openEditorAtDef(target: EventTarget | null): void
}

declare global {
  interface Window {
    liveReloader?: LiveReloader
    liveSocket: LiveSocketInstanceInterface
  }
}

const csrfTokenElement = document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")

if (!csrfTokenElement) {
  throw new Error("Missing csrf-token meta tag")
}

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: {...colocatedHooks},
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfTokenElement.content}
})

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())

liveSocket.connect()

window.liveSocket = liveSocket

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", event => {
    const reloader = (event as CustomEvent<LiveReloader>).detail

    reloader.enableServerLogs()

    let keyDown: string | null = null

    window.addEventListener("keydown", event => {
      keyDown = event.key
    })

    window.addEventListener("keyup", () => {
      keyDown = null
    })

    window.addEventListener(
      "click",
      event => {
        if (keyDown === "c") {
          event.preventDefault()
          event.stopImmediatePropagation()
          reloader.openEditorAtCaller(event.target)
        } else if (keyDown === "d") {
          event.preventDefault()
          event.stopImmediatePropagation()
          reloader.openEditorAtDef(event.target)
        }
      },
      true
    )

    window.liveReloader = reloader
  })
}
