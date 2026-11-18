import { atom, read, update } from 'claude-code'
import type { Hook, Register } from 'claude-code'

import type { View } from '../types'

import { EMOJI, ERRORS, FAMOUS, PHRASES, SUFFIXES, WORDS } from './data'
import { UI } from './strings'

// One failed Bash call, kept whole (cut at the limits below) so the report can show it.
type Incident = {
  at: string
  category: string
  command: string
  error: string
}

const KEEP_INCIDENTS = 100
const MAX_COMMAND = 500
const MAX_ERROR = 1500

const cut = (text: string, max: number): string =>
  text.length > max ? `${text.slice(0, max)}… [+${text.length - max} chars]` : text

type Yokai = {
  incidents?: Incident[]
  birth: string
  date: string
  life: number
  hunger: number
  streak: number
  categories: Record<string, number>
  emoji: string
  name: string
}

const PANE = 'yokai'
// Change the tag when the view's fields change: it declines what an earlier
// version stored, which outlives a reload.
const view = atom({ plugin: 'yokai', key: 'view' } as const, null, { shape: 'view-2' })
const phrase = atom({ plugin: 'yokai', key: 'phrase' } as const, null)
const isHidden = atom({ plugin: 'yokai', key: 'isHidden' } as const, false)

const QUIET_BELOW = 20
const LEAVE_AFTER = 7

// ---- Language: texts come from locales/<code>.json; English is the default --
// The texts in use: English, or the cached translation of the `lang` option.
let T: Record<string, string> = UI
let PH: readonly string[] = PHRASES
let LANG = 'en'

const t = (key: string, vars: Record<string, string | number> = {}): string =>
  (T[key] ?? UI[key] ?? key).replace(/\{(\w+)\}/g, (m, k: string) =>
    k in vars ? String(vars[k]) : m,
  )

const placeholders = (text: string): string =>
  (text.match(/\{\w+\}/g) ?? []).sort().join(',')

const isEnglish = (lang: string): boolean => lang === '' || lang === 'en' || lang.startsWith('en-')

const catName = (c: string): string => T[`cat.${c}`] ?? c

type Catalog = { strings: Record<string, string>; phrases: string[] }

// Keeps a translated entry only if it is a string with the same {placeholders}
// as the English one; anything else falls back to English.
function accept(raw: unknown): Catalog | undefined {
  if (typeof raw !== 'object' || raw === null) return undefined
  const got = raw as { strings?: Record<string, unknown>; phrases?: unknown }
  const strings: Record<string, string> = {}
  for (const [key, en] of Object.entries(UI)) {
    const value = got.strings?.[key]
    strings[key] =
      typeof value === 'string' && value.trim() !== '' && placeholders(value) === placeholders(en)
        ? value
        : en
  }
  const list = Array.isArray(got.phrases) ? got.phrases : []
  const phrases = PHRASES.map((en, i) => {
    const value = list[i]
    return typeof value === 'string' && value.trim() !== '' ? value : en
  })
  return { strings, phrases }
}

const pick = <T,>(list: readonly T[]): T => list[Math.floor(Math.random() * list.length)]!

const today = (): string => new Date().toISOString().slice(0, 10)

const dayNumber = (date: string): number => Math.floor(Date.parse(date + 'T00:00:00Z') / 86_400_000)

const format = (n: number): string => {
  if (n < 1000) return String(n)
  const tenths = Math.floor((n + 50) / 100)
  return tenths % 10 === 0 ? `${tenths / 10}K` : `${Math.floor(tenths / 10)}.${tenths % 10}K`
}

const makeName = (): string => {
  const roll = Math.random() * 100
  if (roll < 15) return pick(FAMOUS)
  if (roll < 50) {
    const a = pick(WORDS)
    let b = pick(WORDS)
    while (b === a) b = pick(WORDS)
    return `${a} no ${b}`
  }
  return `${pick(WORDS)}-${pick(SUFFIXES)}`
}

const categorize = (output: string, command: string): string => {
  for (const text of [output, command]) {
    const lower = text.toLowerCase()
    for (const [category, keyword] of ERRORS) {
      if (keyword !== '' && lower.includes(keyword.toLowerCase())) return category
    }
  }
  return 'other'
}

type Dollar = Parameters<Hook<'session.start'>>[0]

async function keyOf($: Dollar): Promise<string> {
  return `yokai:${await $.session.root()}`
}

// The yokai of this project, or undefined; closes every day since its last
// one (quiet days count toward leaving). Returns the farewell when it leaves.
async function load($: Dollar): Promise<{ yokai?: Yokai; farewell?: string }> {
  const k = await keyOf($)
  const yokai = (await $.store.get(k)) as Yokai | undefined
  if (yokai === undefined) return {}
  const now = today()
  if (yokai.date === now) return { yokai }
  const gap = dayNumber(now) - dayNumber(yokai.date)
  if (!(gap > 0)) return { yokai }
  yokai.streak = yokai.hunger < QUIET_BELOW ? yokai.streak + gap : gap - 1
  if (yokai.streak >= LEAVE_AFTER) {
    await $.store.delete(k)
    return { farewell: t('farewell') }
  }
  yokai.date = now
  yokai.hunger = 0
  await $.store.set(k, yokai)
  return { yokai }
}

async function draw($: Dollar, yokai?: Yokai): Promise<void> {
  const next: View | null =
    yokai === undefined
      ? null
      : {
          name: yokai.name,
          emoji: yokai.emoji,
          birth: yokai.birth,
          life: yokai.life,
          hunger: yokai.hunger,
          streak: yokai.streak,
          categories: { ...yokai.categories },
          recent: (yokai.incidents ?? []).slice(-5).map(i => ({
            at: i.at,
            category: i.category,
            command: cut(i.command, 80),
            error: cut(i.error, 160),
          })),
        }
  await update($, view, () => next)
}

// Reads locales/<code>.json shipped with the plugin ("pt-br" tries pt-br, then pt).
// Returns whether a translation was found; otherwise the texts stay in English.
async function useLocale($: Dollar, lang: string): Promise<boolean> {
  const codes = [lang, lang.split('-')[0]!].filter((c, i, all) => all.indexOf(c) === i)
  for (const code of codes) {
    if (!/^[a-z]{2,3}(-[a-z0-9]+)?$/.test(code)) continue
    try {
      const raw = await $.fs.read(`${$.plugin.root}/locales/${code}.json`)
      const catalog = accept(JSON.parse(String(raw)))
      if (catalog === undefined) continue
      T = catalog.strings
      PH = catalog.phrases
      LANG = code
      return true
    } catch {
      // No such file, or not valid JSON: try the next code.
    }
  }
  return false
}

async function available($: Dollar): Promise<string[]> {
  try {
    const entries = await $.fs.list(`${$.plugin.root}/locales`)
    const codes = entries
      .map(f => f.name)
      .filter(n => n.endsWith('.json'))
      .map(n => n.slice(0, -5))
    return ['en', ...codes].sort()
  } catch {
    return ['en']
  }
}

// Counting is serialized: one failure is written before the next is read.
let queue: Promise<void> = Promise.resolve()

export const register: Register = (on, options) => {
  const lang = String(options.lang ?? 'en').trim().toLowerCase()

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'yokai',
      description: 'Yokai: sarcastic error counter (summon, forget, report, help)',
    })
    // Versions before 0.1.0 drew in the status line; clear what they left there.
    $.ui.status(undefined)

    T = UI
    PH = PHRASES
    LANG = 'en'
    if (!isEnglish(lang) && !(await useLocale($, lang))) {
      $.ui.toast(t('lang_missing', { lang, list: (await available($)).join(', ') }))
    }

    const { yokai, farewell } = await load($)
    if (farewell !== undefined) $.ui.toast(`${t('farewell_label')}: ${farewell}`)
    await draw($, yokai)

    return next(e)
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const ran = await next(e)
    if (ran.deny !== undefined || ran.isError !== true) return ran

    // Counting is a side effect: whatever goes wrong here, the tool's result
    // goes back to the model untouched. Several failures can land at once (Bash
    // calls run in parallel), so each one waits for the previous to finish writing.
    const mine = queue.then(async () => {
      try {
        const { yokai, farewell } = await load($)
        if (farewell !== undefined) {
          $.ui.toast(`${t('farewell_label')}: ${farewell}`)
          await draw($, undefined)
          return
        }
        if (yokai === undefined) return

        const error = ran.text ?? ''
        const category = categorize(error, e.command)
        yokai.life += 1
        yokai.hunger += 1
        yokai.categories[category] = (yokai.categories[category] ?? 0) + 1
        yokai.incidents = [
          ...(yokai.incidents ?? []),
          {
            at: new Date().toISOString(),
            category,
            command: cut(e.command, MAX_COMMAND),
            error: cut(error, MAX_ERROR),
          },
        ].slice(-KEEP_INCIDENTS)
        await $.store.set(await keyOf($), yokai)

        await draw($, yokai)
        if (yokai.life % 10 === 0) {
          const line = pick(PH)
          await update($, phrase, () => line)
          $.clock.after(15_000, () => update($, phrase, () => null))
        }
      } catch {
        // The yokai missed this one.
      }
    })
    queue = mine
    await mine

    return ran
  }).catch(($, e, next) => next(e))

  on('command.run', { command: 'yokai' }, async ($, e) => {
    const sub = e.args.trim().split(/\s+/)[0]?.toLowerCase() ?? ''
    const say = (text: string) => ({
      text: `${t('label')}: ${text}`,
      isTextDisplayOnly: true as const,
    })

    if (sub === 'help' || sub === '') return say(t('help'))
    if (sub === 'show') {
      await update($, isHidden, () => false)
      return say(t('show_ok'))
    }
    if (sub === 'lang') {
      const code = e.args.trim().slice(4).trim().toLowerCase()
      const list = (await available($)).join(', ')
      if (code === '') return say(t('lang_current', { lang: lang === '' ? 'en' : lang, list }))
      const base = code.split('-')[0] ?? code
      if (!/^[a-z]{2,3}(-[a-z0-9]+)?$/.test(code) || !(await available($)).includes(base)) {
        return say(t('lang_unknown', { lang: code, list }))
      }
      const set = await $.config.set({ key: 'yokai.lang', value: code })
      if (set.deny !== undefined) return say(t('lang_denied', { reason: set.deny }))
      return say(t('lang_set', { lang: code }))
    }
    if (!['summon', 'forget', 'report', 'export', 'rename'].includes(sub)) return say(t('help'))

    const k = await keyOf($)
    const { yokai, farewell } = await load($)
    if (farewell !== undefined) {
      await draw($, undefined)
      return say(farewell)
    }

    if (sub === 'summon') {
      if (yokai !== undefined) return say(t('exists'))
      const fresh: Yokai = {
        birth: today(),
        date: today(),
        life: 0,
        hunger: 0,
        streak: 0,
        categories: Object.fromEntries([...new Set(ERRORS.map(([c]) => c))].map(c => [c, 0])),
        emoji: pick(EMOJI),
        name: makeName(),
      }
      await $.store.set(k, fresh)
      await draw($, fresh)
      return say(t('summoned', { name: fresh.name }))
    }

    if (yokai === undefined) return say(t('no_yokai'))

    if (sub === 'forget') {
      await $.store.delete(k)
      await draw($, undefined)
      return say(t('forgotten'))
    }

    if (sub === 'rename') {
      const name = e.args.trim().slice(6).trim().replace(/\s+/g, ' ')
      if (name === '') return say(t('rename_what'))
      if (name.length > 40) return say(t('rename_long'))
      const old = yokai.name
      yokai.name = name
      await $.store.set(k, yokai)
      await draw($, yokai)
      return say(t('rename_done', { old, name }))
    }

    if (sub === 'export') {
      const root = await $.session.root()
      const arg = e.args.trim().slice(6).trim()
      // One new file per export, stamped with the date and time, so exports pile up.
      const stamp = new Date().toISOString().slice(0, 19).replace(/:/g, '-')
      const target =
        arg === ''
          ? `${root}/.claude/yokai/report-${stamp}.json`
          : /^([a-zA-Z]:|[\\/])/.test(arg)
            ? arg
            : `${root}/${arg}`
      const categories = Object.entries(yokai.categories)
        .map(([c, n], i) => ({ category: c, count: n, i }))
        .sort((a, b) => b.count - a.count || a.i - b.i)
        .map(({ category, count }) => ({ category, count }))
      const report = {
        project: root,
        name: yokai.name,
        emoji: yokai.emoji,
        birth: yokai.birth,
        date: yokai.date,
        totalFailures: yokai.life,
        failuresToday: yokai.hunger,
        quietStreak: yokai.streak,
        quietDaysUntilLeaving: LEAVE_AFTER - yokai.streak,
        topCategory: yokai.life > 0 && categories[0] ? categories[0].category : null,
        categories,
        // Every failure kept (the last 100), oldest first, with the command and the error text.
        incidents: yokai.incidents ?? [],
        exportedAt: new Date().toISOString(),
      }
      await $.fs.write(target, `${JSON.stringify(report, null, 2)}\n`)
      return say(t('exported', { path: target }))
    }

    // report: categories by count, descending; ties keep catalog order.
    const ordered = Object.entries(yokai.categories)
      .map(([c, n], i) => ({ c, n, i }))
      .sort((a, b) => b.n - a.n || a.i - b.i)
    const top = yokai.life > 0 && ordered[0] ? `${catName(ordered[0].c)} (${ordered[0].n})` : t('none_yet')
    const detail = ordered.map(({ c, n }) => `${catName(c)}: ${n}`).join(' · ')
    const status =
      yokai.streak === 0 ? t('status_today') : t('status_left', { n: LEAVE_AFTER - yokai.streak })

    await update($, isHidden, () => false)
    await $.ui.open({ id: PANE, title: `${yokai.emoji} ${yokai.name}` })

    const last = (yokai.incidents ?? [])
      .slice(-3)
      .reverse()
      .map(i => `[${catName(i.category)}] ${cut(i.command, 60)} → ${cut(i.error.replace(/\s+/g, ' ').trim(), 100)}`)
      .join(' | ')

    return say(
      `${t('report_head', { name: yokai.name, life: yokai.life, top })} · ${detail} · ${status}${last === '' ? '' : ` · ${t('latest')}: ${last}`} — ${pick(PH)}`,
    )
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const v = await read($, view)
    if (e.props.hasSurvey || v === null || (await read($, isHidden))) return next(e)

    const line = await read($, phrase)
    const { Box, Button, Text } = $.ui.resolve(e)

    return (
      <Box>
        <Text>
          {v.emoji} {v.name}{'  '}
        </Text>
        <Text dimColor>
          {line ?? t('band', { hunger: format(v.hunger), life: format(v.life) })}{' '}
        </Text>
        <Button key="hide" label={t('hide')} onPress={() => update($, isHidden, () => true)} />
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const v = await read($, view)
    if (v === null) return <Text dimColor>{t('pane_empty')}</Text>

    const rows = Object.entries(v.categories)
      .filter(([, n]) => n > 0)
      .sort((a, b) => b[1] - a[1])
    const left = LEAVE_AFTER - v.streak

    return (
      <Box flexDirection="column">
        <Text>
          {v.emoji} {v.name}
        </Text>
        <Text dimColor>{t('born', { date: v.birth })}</Text>
        <Text>{t('totals', { hunger: format(v.hunger), life: format(v.life) })}</Text>
        <Text dimColor>{v.streak === 0 ? t('status_today') : t('status_left', { n: left })}</Text>
        {rows.length === 0 && <Text dimColor>{t('no_failures')}</Text>}
        {rows.map(([c, n]) => (
          <Text key={c}>
            {catName(c)}: {n}
          </Text>
        ))}
        {v.recent.length > 0 && <Text>{t('latest_failures')}</Text>}
        {[...v.recent].reverse().map(i => (
          <Box key={i.at} flexDirection="column">
            <Text>
              [{catName(i.category)}] {i.command}
            </Text>
            <Text dimColor>{i.error.replace(/\s+/g, ' ').trim()}</Text>
          </Box>
        ))}
      </Box>
    )
  })
}
