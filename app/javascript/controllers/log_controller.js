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
  static targets = ["pre", "status", "empty", "live"]
  static values = { url: String, r2Url: String, after: String, count: Number, state: String, times: String }

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
    this.marks = {}
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
    // a running job's log comes from the worker's journal as it is written: live
    this.liveTarget.hidden = !(this.stateValue === "running" && !this.fromR2)
  }

  close() {
    if (this.es) { this.es.close(); this.es = null }
    this.liveTarget.hidden = true
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
    this.mark(e)
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

  // the build's times, from the entries as they pass: the start record (or
  // the first line), the deps-install marker (online), the build marker
  // (build, and its slice), the finish record (or the last line)
  mark(e) {
    if (!e.time) return
    const m = this.marks ||= {}
    const t = Date.parse(e.time.replace(/(\.\d{3})\d+Z$/, "$1Z"))
    if (Number.isNaN(t)) return
    const msg = e.message ?? ""
    if (m.start == null) m.start = t
    if (e.event === "start") m.start = t
    if (m.online == null && msg.startsWith("==> Installing the pacman dependencies")) m.online = t
    if (m.build == null && (msg.startsWith("==> Building in the archci-") || msg.startsWith("==> Building with "))) { m.build = t; m.slice = e.phase || "offline" }
    if (e.event === "finish" || msg.startsWith("==> archci-build finished with") || msg.startsWith("==> archci-sourcer finished with")) m.finish = t
    m.last = t
  }

  // "1h 12m", "4m 30s", "45s", as the page's helper writes them
  hms(ms) {
    const s = Math.max(0, Math.round(ms / 1000))
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60
    if (h > 0) return `${h}h ${m}m`
    return m > 0 ? `${m}m ${sec}s` : `${sec}s`
  }

  // the build time fact of a finished job: total, and the online (deps
  // install) and build (its slice) portions when the markers were seen;
  // kept in a value on the (permanent) section for a restored page
  times() {
    const m = this.marks || {}
    const stop = m.finish ?? m.last
    if (m.start == null || stop == null) return
    let html = this.hms(stop - m.start)
    if (m.online != null && m.build != null) {
      const slice = SLICES.includes(m.slice) ? m.slice : "offline"
      html += ` <span class="muted">·</span> <span class="net-online">online ${this.hms(m.build - m.online)}</span> <span class="muted">·</span> <span class="net-${slice}">${slice} ${this.hms(stop - m.build)}</span>`
    }
    this.timesValue = html
  }

  // the slot is in the page's facts list, outside this (permanent) section,
  // so it is found by id, not as a target
  showTimes() {
    const dd = document.getElementById("build-time"), dt = document.getElementById("build-time-label")
    if (!this.timesValue || !dd || !dt) return
    dd.innerHTML = this.timesValue
    dd.hidden = false
    dt.hidden = false
  }

  // the end of the log: the first error marked, and, for a job that was
  // running when the page opened, the page's facts are stale: reload
  end(d) {
    this.close()
    this.times()
    if (d.error_at != null && this.errorLine == null) {
      const line = this.preTarget.children[d.error_at]
      if (line) { line.classList.add("err"); this.errorLine = d.error_at + 1 }
    }
    if (this.stateValue === "running" && d.state && d.state !== "running") {
      // the section is permanent across the visit: its state must say the
      // job is finished, or connect() would open the stream (and the live
      // badge) again on the reloaded page
      this.stateValue = d.state
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
    if (this.stateValue !== "running") { this.liveTarget.hidden = true; this.showTimes() }   // a finished job's log is never live; its times are shown
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
