export type RecentFailure = {
  at: string
  category: string
  command: string
  error: string
}

export type View = {
  name: string
  emoji: string
  birth: string
  life: number
  hunger: number
  streak: number
  categories: Record<string, number>
  recent: RecentFailure[]
}

declare module 'claude-code' {
  interface PluginState {
    // `view` is read with a shape tag in hooks/register.tsx, so it is declared Shaped.
    yokai: { view: Shaped<View | null>; phrase: string | null; isHidden: boolean }
  }
}
