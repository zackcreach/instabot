interface Topbar {
  config(options: {barColors: Record<number, string>; shadowColor: string}): void
  hide(): void
  show(delay?: number): void
}

declare const topbar: Topbar

export default topbar
