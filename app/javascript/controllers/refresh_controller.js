// Reloads the page every interval-value milliseconds (0: never) by a Turbo
// visit that morphs the DOM, so scroll position and the filter box survive.
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { interval: Number }

  connect() {
    if (this.intervalValue > 0) {
      this.timer = setInterval(() => {
        if (document.hidden) return
        Turbo.visit(window.location.href, { action: "replace" })
      }, this.intervalValue)
    }
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
