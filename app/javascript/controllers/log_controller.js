// The log window, built from the job's log as a stream of server-sent
// events, the framing the master's `archci web sse` writes: "job" with the
// job's fields, one message per journal entry (data: time, priority, pid,
// message, phase; id: the entry's journal cursor) and "end" once the job has
// finished (state, error_at, rc). A finished job's log is the exported file
// on R2 (r2-url), the same bytes stored once and decoded by the browser
// itself (Content-Encoding: zstd); when that fails (not exported yet, no
// CORS, a browser without zstd) the sse action serves it from the master.
// A running job's log comes from the sse action as it grows; a dropped
// connection resumes from the last id, which EventSource sends as
// Last-Event-ID. On a static file EventSource would reconnect after the end
// of the stream, so it is closed on the end event, or on the first error.
// Every line is coloured by the slice it ran in: a slice marker (phase
// online, offline or loopback) opens it, and the lines after it carry
// in-<slice> until the next marker; stderr and error colours still win.
// A running job's log is followed like tail -f: while the page is scrolled
// to its bottom, each line that arrives keeps it there; scrolled up, the
// page stays where it is (scrolling back down resumes the following).
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

const SLICES = ["online", "offline", "loopback"]

export default class extends Controller {
  static targets = ["pre", "status", "empty"]
  static values = { url: String, r2Url: String, after: String, count: Number, state: String }

  connect() {
    // A page Turbo restores from its cache (back, or a revisit) brings the
    // section with the lines already appended and the count and cursor it
    // reached: a finished job's log is complete, so it is not fetched (and
    // appended) again; a running job's resumes from its cursor. Anything
    // else with a stale count starts over.
    const rendered = this.preTarget.childElementCount
    if (rendered !== this.countValue) {
      this.preTarget.replaceChildren()
      this.countValue = 0
      this.afterValue = ""
    }
    const err = this.preTarget.querySelector(".line.err")
    this.errorLine = err ? Number(err.id.slice(1)) : null   // 1-based line of the first error, once one is seen
    // the slice the restored lines ended in, for the lines still to come
    const markers = this.preTarget.querySelectorAll(".line.phase-online, .line.phase-offline, .line.phase-loopback")
    const last = markers[markers.length - 1]
    this.slice = last ? SLICES.find((s) => last.classList.contains("phase-" + s)) : null
    if (this.countValue > 0 && this.stateValue !== "running") {
      this.render()
      return
    }
    this.open()
  }

  disconnect() {
    this.close()
  }

  // the source: the exported file for a finished job (once, from the
  // start), else the sse action, from the cursor reached
  open() {
    this.close()
    const fresh = this.countValue === 0 && !this.afterValue
    this.fromR2 = Boolean(this.r2UrlValue) && this.stateValue !== "running" && fresh
    let url
    if (this.fromR2) {
      url = this.r2UrlValue
    } else {
      url = new URL(this.urlValue, window.location.origin)
      if (this.afterValue) url.searchParams.set("after", this.afterValue)
      url = url.toString()
    }
    this.received = 0
    this.es = new EventSource(url)
    this.es.addEventListener("job", (e) => { this.job = JSON.parse(e.data) })
    this.es.onmessage = (e) => this.entry(JSON.parse(e.data), e.lastEventId)
    this.es.addEventListener("end", (e) => this.end(JSON.parse(e.data)))
    this.es.addEventListener("error", (e) => {
      // the master unreachable behind the sse action: said, and tried again by EventSource
      if (e.data) { this.statusTarget.textContent = "unavailable"; return }
      this.error()
    })
    this.es.onerror = () => this.error()
    this.statusTarget.textContent = "loading…"
  }

  close() {
    if (this.es) { this.es.close(); this.es = null }
  }

  // a connection error, or the end of a static file: from R2 with nothing
  // received, the file is not there (not exported yet, no CORS, or a browser
  // that cannot decode it), so the master serves it instead; a finished
  // job's stream is done; a running job's reconnects by itself
  error() {
    if (this.fromR2 && this.received === 0) {
      this.close()
      this.r2UrlValue = ""
      this.open()
      return
    }
    if (this.stateValue !== "running") {
      this.close()
      this.render()
    }
  }

  // one line per entry: its number (an anchor, with the time it was written
  // as its title and the journal cursor on the line), its journal priority
  // (a unit's stderr is 3, its stdout 6) and the phase a marker opens
  entry(e, cursor) {
    this.received += 1
    const n = this.countValue + 1
    const follow = this.stateValue === "running" && (this.following || this.atBottom())   // decided before the page grows
    const span = document.createElement("span")
    span.className = "line"
    span.id = "L" + n
    if (cursor) { span.dataset.cursor = cursor; this.afterValue = cursor }
    if (e.priority != null) span.classList.add("pri-" + e.priority)   // stderr lines (3) stand out from stdout (6)
    if (e.phase) span.classList.add("phase", "phase-" + e.phase)
    if (SLICES.includes(e.phase)) this.slice = e.phase                 // a slice marker opens its slice
    else if (this.slice) span.classList.add("in-" + this.slice)        // the lines in it wear its colour
    const num = document.createElement("a")
    num.className = "n"
    num.href = "#L" + n
    num.textContent = n
    if (e.time) num.title = e.time
    span.append(num, document.createTextNode(e.message ?? ""))
    this.preTarget.append(span)
    this.countValue = n
    this.render()
    if (n === 1 && this.jump()) return   // a line the URL names wins over the following
    if (follow) this.follow()
  }

  // the page is at its bottom (within a line's height)
  atBottom() {
    return window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 20
  }

  // keep the bottom in view: once per frame, however many lines arrived
  follow() {
    if (this.following) return
    this.following = true
    requestAnimationFrame(() => {
      this.following = false
      window.scrollTo({ top: document.documentElement.scrollHeight })
    })
  }

  // the end of the log: the first error marked, and, for a job that was
  // running when the page opened, the page's facts are stale: reload
  end(d) {
    this.close()
    if (d.error_at != null && this.errorLine == null) {
      const line = this.preTarget.children[d.error_at]
      if (line) { line.classList.add("err"); this.errorLine = d.error_at + 1 }
    }
    if (this.stateValue === "running" && d.state && d.state !== "running") {
      Turbo.visit(window.location.href, { action: "replace" })
      return
    }
    this.render()
    if (this.errorLine) this.jump()
  }

  // the line the URL's #L<n> names, once the log is there (the browser could
  // not scroll to it before), else the first error; whether there was one
  jump() {
    const m = window.location.hash.match(/^#L(\d+)$/)
    const target = m ? document.getElementById("L" + m[1]) : (this.errorLine && document.getElementById("L" + this.errorLine))
    if (target) target.scrollIntoView({ block: "center" })
    return Boolean(target)
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
    if (this.fromR2) html += ` <span class="muted">· from the release</span>`
    this.statusTarget.innerHTML = html
  }
}
