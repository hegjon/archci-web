// The log window, built from the job's journal entries (the log action:
// archci web entries on the master): each line with the time it was written
// and its journal cursor. A finished job's log is fetched once; a running
// job's is fetched and then, every interval, only the entries that follow
// the cursor last seen are asked for and appended, so the whole log is not
// re-sent on every poll (journalctl -f cannot follow a journald-remote
// journal, so the master polls it; the cursor makes each poll a delta).
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["pre", "status", "empty"]
  static values = { url: String, after: String, count: Number, interval: Number, state: String }

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
      if (!res.ok) { this.statusTarget.textContent = "unavailable"; return }
      const data = await res.json()
      if (this.stateValue === "running" && data.state && data.state !== "running") {
        // the job finished while we watched: the page's facts are stale, reload
        clearInterval(this.timer)
        Turbo.visit(window.location.href, { action: "replace" })
        return
      }
      this.append(data.entries || [], data.error_at)
      if (data.cursor) this.afterValue = data.cursor
    } catch {
      // transient (the master briefly unreachable); the next tick retries
    } finally {
      this.busy = false
    }
  }

  // one line per entry: its number (an anchor, with the time it was written
  // as its title and the journal cursor on the line), its journal priority
  // (a unit's stderr is 3, its stdout 6), the slice marker's phase and the
  // first error as the master flagged them
  append(entries, errorAt) {
    if (entries.length) {
      const frag = document.createDocumentFragment()
      entries.forEach((e, i) => {
        const n = this.countValue + i + 1
        const span = document.createElement("span")
        span.className = "line"
        span.id = "L" + n
        if (e.__CURSOR) span.dataset.cursor = e.__CURSOR
        if (e.PRIORITY != null) span.classList.add("pri-" + e.PRIORITY)   // stderr lines (3) stand out from stdout (6)
        if (e.phase) span.classList.add("phase", "phase-" + e.phase)
        if (errorAt != null && this.errorLine == null && i === errorAt) {
          span.classList.add("err")
          this.errorLine = n
        }
        const num = document.createElement("a")
        num.className = "n"
        num.href = "#L" + n
        num.textContent = n
        if (e.__REALTIME_TIMESTAMP) num.title = this.when(e.__REALTIME_TIMESTAMP)
        span.append(num, document.createTextNode(e.MESSAGE ?? ""))
        frag.append(span)
      })
      this.preTarget.append(frag)
      const first = this.countValue === 0
      this.countValue += entries.length
      this.render()
      if (first) this.jump()
    } else {
      this.render()
    }
  }

  // the journal's microseconds since the epoch, as an ISO time to the millisecond
  when(us) {
    const ms = Number(us.slice(0, -3))
    return Number.isFinite(ms) ? new Date(ms).toISOString() : ""
  }

  // the line the URL's #L<n> names, once the log is there (the browser could
  // not scroll to it before), else the first error
  jump() {
    const m = window.location.hash.match(/^#L(\d+)$/)
    const target = m ? document.getElementById("L" + m[1]) : (this.errorLine && document.getElementById("L" + this.errorLine))
    if (target) target.scrollIntoView({ block: "center" })
  }

  render() {
    if (this.countValue === 0) {
      this.emptyTarget.hidden = false
      this.statusTarget.textContent = ""
      return
    }
    this.emptyTarget.hidden = true
    this.preTarget.hidden = false
    let html = `${this.countValue} lines${this.stateValue === "running" ? " so far" : ""}`
    if (this.errorLine) html += ` · <a href="#L${this.errorLine}">first error at ${this.errorLine}</a>`
    this.statusTarget.innerHTML = html
  }
}
