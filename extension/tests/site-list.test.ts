// @vitest-environment jsdom
import { expect, it, vi } from 'vitest'
import { collectionRoute, currentBvid, playlistUrl, siteAction, siteList } from '../src/site-list'

it('preserves the space route type, creator sort and selected episode', () => {
  expect(collectionRoute('https://space.bilibili.com/123/channel/seriesdetail?sid=42')).toEqual({
    mid: '123',
    id: '42',
    series: true,
  })
  expect(collectionRoute('https://space.bilibili.com/123/lists/42?type=season').series).toBe(false)
  expect(playlistUrl('123', '42', undefined, 'BVabc')).toBe(
    'https://www.bilibili.com/list/123/?sid=42&bvid=BVabc',
  )
  expect(playlistUrl('123', undefined, 'popular')).toContain('sort_field=play&desc=1')
  expect(playlistUrl('123', undefined, 'oldest')).toContain('sort_field=pubtime&desc=0')
  expect(() => collectionRoute('https://example.org/123/lists/42')).toThrow()
})

it('uses the live series heading and clicks the native list row and playback controls', async () => {
  history.replaceState({}, '', '/list/123/?sid=42&bvid=BVold')
  document.body.innerHTML =
    '<h1><a class="video-title-href" href="/video/BVtwo">second</a></h1><div class="action-list-container"><div class="list-title">Series</div><div class="list-count">2/210</div><button class="list-playorder-btn" title="顺序播放"></button><div class="action-list-item-wrap" data-key="BVone"><div class="singlep-list-item-inner"><div class="title">first</div></div></div><div class="action-list-item-wrap" data-key="BVtwo"><div class="multip-list-item" title="one"></div><div class="multip-list-item multip-list-item-active" title="two"></div></div></div>'
  expect(currentBvid()).toBe('BVtwo')
  const list = siteList()!
  expect(list).toMatchObject({
    position: 2,
    total: 210,
    part: 2,
    previous: true,
    parts: ['one', 'two'],
    order: '顺序播放',
  })
  for (const [action, value, selector] of [
    ['listPrevious', null, '.singlep-list-item-inner'],
    ['listOrder', null, '.list-playorder-btn'],
    ['listPart', 1, '.multip-list-item'],
  ] as const) {
    const handle = vi.fn()
    document.querySelector(selector)!.addEventListener('click', handle)
    await siteAction(action, value, list.id)
    expect(handle).toHaveBeenCalledOnce()
  }
  await expect(siteAction('listOrder', null, 'stale')).rejects.toThrow()
})

it('pages through long season lists and selects the actual clickable episode', async () => {
  history.replaceState({}, '', '/video/BV1/')
  const rows = Array.from(
    { length: 105 },
    (_, i) =>
      '<div class="video-pod__item" data-key="BV' +
      (i + 1) +
      '"><div class="single-p"><div class="simple-base-item"><div class="title">Episode ' +
      (i + 1) +
      '</div></div></div></div>',
  )
  document.body.innerHTML =
    '<div class="video-pod"><div class="video-pod__header"><a class="title" href="/series">Season</a></div>' +
    rows.join('') +
    '</div>'
  const list = siteList()!
  expect(list.items).toHaveLength(50)
  await siteAction('listAfter', null, list.id)
  expect(siteList()?.items[0].bvid).toBe('BV51')
  await siteAction('listAfter', null, list.id)
  expect(siteList()?.items).toHaveLength(5)
  const handle = vi.fn()
  document.querySelector('[data-key="BV102"] .simple-base-item')!.addEventListener('click', handle)
  await siteAction('listSelect', 'BV102', list.id)
  expect(handle).toHaveBeenCalledOnce()
  await siteAction('listBefore', null, list.id)
  expect(siteList()?.items[0].bvid).toBe('BV51')
})
