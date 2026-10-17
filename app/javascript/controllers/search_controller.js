import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  connect() {
    this.timeout = null
  }

  disconnect() {
    this.cancel()
  }

  schedule(event) {
    this.cancel()
    const input = event.target
    const value = input.value.trim()
    if (value.length > 0 && value.length < 2) return

    this.timeout = setTimeout(() => {
      this.timeout = null
      input.form?.requestSubmit()
    }, this.delayValue)
  }

  cancel() {
    if (this.timeout) clearTimeout(this.timeout)
    this.timeout = null
  }
}
