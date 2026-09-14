// A running job's log, live: an EventSource on the job's stream (server-sent
// events from the master's journalctl -f) fills <pre id="log"> line by line.
// On "reset" the rendered lines go (the stream starts with the last ones), on
// "end" the page reloads to show the finished job and its archived log. Sits
// on <body>, which a Turbo morph keeps, so the stream survives the refreshes.
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.count = 0
    this.source = new EventSource(this.urlValue)
    this.source.addEventListener("reset", () => this.reset())
    this.source.addEventListener("line", (e) => this.append(JSON.parse(e.data).line))
    this.source.addEventListener("end", () => this.end())
    this.source.onerror = () => { /* the browser reconnects by itself; a finished job answers "end" */ }
  }

  disconnect() {
    this.source?.close()
  }

  get pre() {
    return document.getElementById("log")
  }

  reset() {
    const pre = this.pre
    if (pre) pre.textContent = ""
    this.count = 0
  }

  append(text) {
    const pre = this.pre
    if (!pre) return
    const atBottom = window.innerHeight + window.scrollY >= document.body.scrollHeight - 60
    const line = document.createElement("span")
    line.className = "line"
    line.id = `L${++this.count}`
    const n = document.createElement("span")
    n.className = "n"
    n.textContent = this.count
    line.append(n, text)
    pre.append(line)
    const count = document.getElementById("log-count")
    if (count) count.textContent = `live · ${this.count} lines`
    if (atBottom) window.scrollTo(0, document.body.scrollHeight)
  }

  end() {
    this.source.close()
    Turbo.visit(window.location.href, { action: "replace" })
  }
}
