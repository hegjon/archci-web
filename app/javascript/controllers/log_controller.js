// A running job's log, without re-sending the whole thing each poll. The page
// first renders nothing; this loads the journal so far, then every interval
// asks the master (the log action) only for the lines that follow the cursor
// it last saw and appends them. journalctl -f cannot follow a journald-remote
// journal, so the master polls the journal; the cursor makes each poll a delta.
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["pre", "status", "empty"]
  static values = { url: String, after: String, count: Number, interval: Number }

  connect() {
    this.errorLine = null   // 1-based line of the first error, once one is seen
    this.poll()
    if (this.intervalValue > 0) {
      this.timer = setInterval(() => { if (!document.hidden) this.poll() }, this.intervalValue)
    }
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async poll() {
    if (this.busy) return
    this.busy = true
    try {
      const url = new URL(this.urlValue, window.location.origin)
      if (this.afterValue) url.searchParams.set("after", this.afterValue)
      const res = await fetch(url, { headers: { Accept: "application/json" } })
      if (!res.ok) return
      const data = await res.json()
      if (data.state && data.state !== "running") {
        // the job finished: stop, and let the page render the archived log
        clearInterval(this.timer)
        Turbo.visit(window.location.href, { action: "replace" })
        return
      }
      this.append(data.lines || [], data.error_at)
      if (data.cursor) this.afterValue = data.cursor
    } catch {
      // transient (the master briefly unreachable); the next tick retries
    } finally {
      this.busy = false
    }
  }

  append(lines, errorAt) {
    if (lines.length) {
      const frag = document.createDocumentFragment()
      lines.forEach((line, i) => {
        const n = this.countValue + i + 1
        const span = document.createElement("span")
        span.className = "line"
        span.id = "L" + n
        if (errorAt != null && this.errorLine == null && i === errorAt) {
          span.classList.add("err")
          this.errorLine = n
        }
        const num = document.createElement("span")
        num.className = "n"
        num.textContent = n
        span.append(num, document.createTextNode(line))
        frag.append(span)
      })
      this.preTarget.append(frag)
      this.countValue += lines.length
    }
    this.render()
  }

  render() {
    if (this.countValue === 0) return   // still nothing streamed
    this.emptyTarget.hidden = true
    this.preTarget.hidden = false
    let html = `${this.countValue} lines so far`
    if (this.errorLine) html += ` · <a href="#L${this.errorLine}">first error at ${this.errorLine}</a>`
    this.statusTarget.innerHTML = html
  }
}
