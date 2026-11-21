import { numericId, RemoteError } from './types'

// Space opens a regular video for a season, and a /list/ player for a series.
export function collectionRoute(value: string) {
  const url = new URL(value)
  const match = url.pathname.match(
    /^\/(\d+)\/(?:lists\/(\d+)|(?:channel\/)?(collectiondetail|seriesdetail))\/?$/,
  )
  const id = match?.[2] ?? url.searchParams.get('sid')
  if (url.origin !== 'https://space.bilibili.com' || !match || !id || !/^\d+$/.test(id))
    throw new RemoteError('invalid_url', '无法识别这个合集地址')
  return {
    mid: match[1],
    id,
    series: match[3] === 'seriesdetail' || url.searchParams.get('type') === 'series',
  }
}
export function playlistUrl(mid: unknown, series?: string, order: unknown = 'newest', bvid?: string) {
  const url = new URL('https://www.bilibili.com/list/' + numericId(mid) + '/')
  if (series) url.searchParams.set('sid', numericId(series))
  else {
    url.searchParams.set('sort_field', order === 'popular' ? 'play' : 'pubtime')
    url.searchParams.set('desc', order === 'oldest' ? '0' : '1')
  }
  if (bvid) url.searchParams.set('bvid', bvid)
  return url.href
}

const listRow = '.action-list-item-wrap[data-key],.video-pod__item[data-key]'
const name = (el: Element | null) => el?.getAttribute('title') || el?.textContent?.trim() || ''
function container() {
  return (
    document.querySelector('.action-list-container') ??
    [...document.querySelectorAll('.video-pod')].find((el) =>
      el.querySelector('.video-pod__item[data-key^="BV"]'),
    )
  )
}
export function currentBvid() {
  return (
    location.pathname.match(/\/video\/(BV[\da-z]+)/i)?.[1] ??
    document
      .querySelector<HTMLAnchorElement>('h1 .video-title-href')
      ?.href.match(/\/video\/(BV[\da-z]+)/i)?.[1] ??
    new URL(location.href).searchParams.get('bvid') ??
    ''
  )
}
function listId(root: Element) {
  return (
    root.querySelector<HTMLAnchorElement>('.video-pod__header a.title')?.href ??
    location.pathname + '?sid=' + (new URL(location.href).searchParams.get('sid') ?? '')
  )
}
function autoNext() {
  return document.querySelector<HTMLElement>(
    '.video-pod__auto-play input[type="checkbox"],.next-play .continuous-btn,.next-play input[type="checkbox"]',
  )
}
const pageSize = 50
let windowStart: number | undefined
let lastList = '',
  lastVideo = ''
function rowsOf(root: Element) {
  return [...root.querySelectorAll<HTMLElement>(listRow)].filter((row) =>
    /^BV[0-9A-Za-z]+$/.test(row.dataset.key ?? ''),
  )
}
function available(el: HTMLElement | null) {
  return !!el && !el.hidden && el.style.display !== 'none'
}
export function siteList() {
  const root = container()
  if (!root) return
  const rows = rowsOf(root),
    bvid = currentBvid(),
    active = rows.findIndex((row) => row.dataset.key === bvid)
  const id = listId(root)
  if (lastList !== id || lastVideo !== bvid) {
    windowStart = undefined
    lastList = id
    lastVideo = bvid
  }
  const start = Math.max(
    0,
    Math.min(
      windowStart ?? Math.floor(Math.max(0, active) / pageSize) * pageSize,
      Math.max(0, rows.length - 1),
    ),
  )
  const count = name(root.querySelector('.list-count,.video-pod__header .amt')).match(/(\d+)\s*\/\s*(\d+)/)
  const current = rows[active]
  const sections = [...root.querySelectorAll<HTMLElement>('.slide-inner .slide-item[data-slide-value]')]
  const parts = current ? [...current.querySelectorAll('.multip-list-item,.multi-p .page-item')] : []
  const toggle = autoNext()
  return {
    id,
    autoNext:
      toggle instanceof HTMLInputElement
        ? toggle.checked
        : toggle
          ? !!toggle.querySelector('.switch-btn.on')
          : undefined,
    title: name(root.querySelector('.list-title,.video-pod__header .title')) || '播放列表',
    position: count ? Number(count[1]) : active + 1,
    total: count ? Number(count[2]) : rows.length,
    sections: sections.map((el) => ({ id: el.dataset.slideValue!, title: name(el) })),
    section: name(root.querySelector('.slide-item.active')),
    description: name(root.querySelector('.pod-description-dropdown')),
    subscribe: name(root.querySelector('.subscribe-btn')),
    order: name(root.querySelector('.list-playorder-btn')),
    mode: name(root.querySelector('.list-playway-btn')),
    before: start > 0 || available(root.querySelector('#actionListAheadAnchor')),
    after: start + pageSize < rows.length || available(root.querySelector('#actionListBehindAnchor')),
    previous: active > 0,
    next:
      active >= 0 &&
      (active + 1 < rows.length ||
        !!document.querySelector('.bpx-player-ctrl-next:not(.bpx-state-disabled)')),
    parts: parts.map((el) => name(el.querySelector('.title')) || name(el)),
    part: parts.findIndex((el) => el.matches('.multip-list-item-active,.active')) + 1,
    items: rows
      .slice(start, start + pageSize)
      .map((row) => ({
        bvid: row.dataset.key!,
        title: name(row.querySelector('.main .title,.title')) || row.dataset.key!,
        duration: name(row.querySelector('.stats .duration')),
      })),
  }
}
export async function siteAction(action: string, value: unknown, expected: unknown) {
  const root = container(),
    list = siteList()
  if (!root || !list || list.id !== expected)
    throw new RemoteError('target_changed', '播放列表已变化，请重新选择')
  const rows = rowsOf(root)
  const active = rows.findIndex((row) => row.dataset.key === currentBvid())
  let control: HTMLElement | null | undefined
  if (action === 'listBefore' || action === 'listAfter') {
    const forward = action === 'listAfter'
    const start = rows.findIndex((row) => row.dataset.key === list.items[0]?.bvid)
    if (forward ? start + pageSize < rows.length : start > 0) {
      windowStart = Math.max(0, start + (forward ? pageSize : -pageSize))
      return
    }
    const anchor = root.querySelector<HTMLElement>(
      forward ? '#actionListBehindAnchor' : '#actionListAheadAnchor',
    )
    if (available(anchor)) {
      const boundary = forward ? rows[rows.length - 1] : rows[0]
      const pane = root.querySelector<HTMLElement>('.action-list-inner')
      if (pane && pane.offsetHeight === 0) root.querySelector<HTMLElement>('.list-expand-btn')?.click()
      anchor!.scrollIntoView({ block: 'nearest' })
      for (let i = 0; i < 40; i++) {
        await new Promise((r) => setTimeout(r, 200))
        const updated = rowsOf(root),
          idx = updated.findIndex((row) => row.dataset.key === boundary?.dataset.key)
        if (idx >= 0 && (forward ? idx + 1 < updated.length : idx > 0)) {
          windowStart = forward ? idx + 1 : Math.max(0, idx - pageSize)
          return
        }
        if (!available(anchor)) return
      }
      throw new RemoteError('catalog_timeout', '网页未载入更多选集，请重试')
    }
    return
  }
  switch (action) {
    case 'listSection':
      control = [...root.querySelectorAll<HTMLElement>('.slide-inner .slide-item')].find(
        (el) => el.dataset.slideValue === value,
      )
      windowStart = 0
      break
    case 'listAutoNext':
      control = autoNext()
      break
    case 'listSubscribe':
      control = root.querySelector<HTMLElement>('.subscribe-btn')
      break
    case 'listOrder':
      control = root.querySelector<HTMLElement>('.list-playorder-btn')
      break
    case 'listMode':
      control = root.querySelector<HTMLElement>('.list-playway-btn')
      break
    case 'listPart':
      control = rows[active]?.querySelectorAll<HTMLElement>('.multip-list-item,.multi-p .page-item')[
        Number(value) - 1
      ]
      break
    case 'listNext':
      control = document.querySelector<HTMLElement>('.bpx-player-ctrl-next:not(.bpx-state-disabled)')
      break
  }
  if (!control && ['listSelect', 'listPrevious', 'listNext'].includes(action)) {
    const row =
      action === 'listSelect'
        ? rows.find((row) => row.dataset.key === value)
        : rows[active + (action === 'listPrevious' ? -1 : 1)]
    control = row?.querySelector<HTMLElement>(
      '.singlep-list-item-inner,.multip-list-item-inner,.normal-base-item,.simple-base-item,.title',
    )
  }
  if (!control) throw new RemoteError('list_changed', '网页上的选集或播放控件已变化，请重试')
  control.click()
}
