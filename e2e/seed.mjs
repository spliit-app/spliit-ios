#!/usr/bin/env node
// Seeds a Spliit instance with deterministic data for the end-to-end suite.
//
// Everything goes in through the public tRPC API rather than SQL, so the harness stays
// decoupled from Prisma migrations and works against any instance — including a self-hosted
// one you want to smoke-test against.
//
//   node seed.mjs                                   # seeds http://localhost:3009/
//   node seed.mjs --base-url https://example.com/   # somewhere else
//   node seed.mjs --dump ../Packages/…/Fixtures     # also save raw responses as fixtures
//
// Prints a JSON map of fixture keys to the IDs the server assigned, which the UI tests read
// to know what to look for.

const args = process.argv.slice(2)
const option = (name, fallback) => {
  const index = args.indexOf(`--${name}`)
  return index === -1 ? fallback : args[index + 1]
}

const baseUrl = (option('base-url', 'http://localhost:3009/') ?? '').replace(/\/?$/, '/')
const dumpDir = option('dump', null)

const endpoint = (path) => `${baseUrl}api/trpc/${path}`

async function query(path, input) {
  const url =
    input === undefined
      ? endpoint(path)
      : `${endpoint(path)}?input=${encodeURIComponent(JSON.stringify({ json: input }))}`
  const response = await fetch(url, { headers: { accept: 'application/json' } })
  return unwrap(path, response)
}

async function mutate(path, input) {
  const response = await fetch(endpoint(path), {
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ json: input }),
  })
  return unwrap(path, response)
}

async function unwrap(path, response) {
  const text = await response.text()
  let body
  try {
    body = JSON.parse(text)
  } catch {
    throw new Error(`${path}: response was not JSON (${response.status})\n${text.slice(0, 400)}`)
  }
  if (body.error) {
    throw new Error(`${path}: ${body.error.json?.message ?? 'unknown error'}`)
  }
  if (!response.ok) {
    throw new Error(`${path}: HTTP ${response.status}\n${text.slice(0, 400)}`)
  }
  return { data: body.result.data.json, raw: text }
}

// A fixed date so date-bucketing assertions ("This week", "Last month") stay stable: every
// expense is placed relative to the day the seed runs.
const today = new Date()
const daysAgo = (days) => {
  const date = new Date(today)
  date.setUTCDate(date.getUTCDate() - days)
  return date.toISOString().slice(0, 10)
}

const FIXTURES = [
  {
    key: 'lisbon',
    name: 'Weekend in Lisbon',
    currency: '€',
    currencyCode: 'EUR',
    information: 'Shared costs for the Lisbon trip. Settle up before we fly home.',
    participants: ['Ana', 'Bruno', 'Chloé'],
    expenses: [
      {
        title: 'Airport taxi',
        amount: 4250,
        date: daysAgo(1),
        paidBy: 'Ana',
        paidFor: ['Ana', 'Bruno', 'Chloé'],
        splitMode: 'EVENLY',
      },
      {
        title: 'Dinner at Time Out Market',
        amount: 9630,
        date: daysAgo(2),
        paidBy: 'Bruno',
        paidFor: ['Ana', 'Bruno', 'Chloé'],
        splitMode: 'EVENLY',
        notes: 'Bruno covered the wine too.',
      },
      {
        title: 'Apartment',
        amount: 48000,
        date: daysAgo(40),
        paidBy: 'Chloé',
        // Chloé took the double room, so she carries two of the four shares.
        paidFor: ['Ana', 'Bruno', 'Chloé'],
        shares: { Ana: 100, Bruno: 100, 'Chloé': 200 },
        splitMode: 'BY_SHARES',
      },
      {
        title: 'Tram tickets',
        amount: 1800,
        date: daysAgo(400),
        paidBy: 'Ana',
        paidFor: ['Ana', 'Bruno'],
        splitMode: 'BY_AMOUNT',
        shares: { Ana: 1000, Bruno: 800 },
      },
    ],
  },
  {
    key: 'flat',
    name: 'Flat 3B',
    currency: '$',
    currencyCode: 'USD',
    information: null,
    participants: ['Dana', 'Eli'],
    expenses: [
      {
        title: 'Internet',
        amount: 6000,
        date: daysAgo(3),
        paidBy: 'Dana',
        paidFor: ['Dana', 'Eli'],
        splitMode: 'BY_PERCENTAGE',
        shares: { Dana: 6000, Eli: 4000 },
      },
    ],
  },
  {
    key: 'empty',
    name: 'Book club',
    currency: '£',
    currencyCode: 'GBP',
    information: null,
    participants: ['Fen', 'Gil'],
    expenses: [],
  },
]

async function seed() {
  const result = { baseUrl, groups: {} }

  for (const fixture of FIXTURES) {
    const { data: created } = await mutate('groups.create', {
      groupFormValues: {
        name: fixture.name,
        information: fixture.information ?? undefined,
        currency: fixture.currency,
        currencyCode: fixture.currencyCode,
        participants: fixture.participants.map((name) => ({ name })),
      },
    })

    const groupId = created.groupId
    const { data: fetched } = await query('groups.get', { groupId })
    const idFor = Object.fromEntries(
      fetched.group.participants.map((participant) => [participant.name, participant.id]),
    )

    for (const expense of fixture.expenses) {
      await mutate('groups.expenses.create', {
        groupId,
        // Who the activity log credits. Optional on every mutating procedure, and the payer is
        // the realistic answer: whoever paid for dinner is who typed it in.
        participantId: idFor[expense.paidBy],
        expenseFormValues: {
          title: expense.title,
          expenseDate: expense.date,
          amount: expense.amount,
          category: 0,
          paidBy: idFor[expense.paidBy],
          paidFor: expense.paidFor.map((name) => ({
            participant: idFor[name],
            shares: expense.shares ? expense.shares[name] : 100,
          })),
          splitMode: expense.splitMode,
          saveDefaultSplittingOptions: false,
          isReimbursement: false,
          documents: [],
          notes: expense.notes,
          recurrenceRule: 'NONE',
        },
      })
    }

    result.groups[fixture.key] = { id: groupId, name: fixture.name, participants: idFor }
    console.error(`seeded ${fixture.name} → ${groupId}`)
  }

  await recordActivityHistory(result)

  if (dumpDir) await dumpFixtures(result)

  process.stdout.write(JSON.stringify(result, null, 2) + '\n')
}

// Gives the Lisbon group a log worth recording a fixture from.
//
// Seeding alone writes nothing but CREATE_EXPENSE, and an `activities-list.json` of four
// identical rows would prove only that one branch of the decoder works. This adds the other
// three kinds, and — through an expense created and then deleted — the case that separates a
// row which can be opened from one which cannot: the server sends the whole expense alongside
// each activity, and `null` there is how a deleted expense reads.
//
// Everything here leaves the group exactly as it found it. The scratch expense is deleted, and
// the two updates re-send the values already stored, so every other fixture is unaffected.
async function recordActivityHistory(result) {
  const group = result.groups.lisbon
  const { Ana, Bruno, 'Chloé': Chloe } = group.participants

  const scratch = await mutate('groups.expenses.create', {
    groupId: group.id,
    participantId: Bruno,
    expenseFormValues: {
      title: 'Pastéis de Belém',
      expenseDate: daysAgo(1),
      amount: 760,
      category: 0,
      paidBy: Bruno,
      paidFor: [{ participant: Bruno, shares: 100 }],
      splitMode: 'EVENLY',
      saveDefaultSplittingOptions: false,
      isReimbursement: false,
      documents: [],
      recurrenceRule: 'NONE',
    },
  })

  await mutate('groups.expenses.delete', {
    groupId: group.id,
    expenseId: scratch.data.expenseId,
    participantId: Bruno,
  })

  const { data: listed } = await query('groups.expenses.list', {
    groupId: group.id,
    limit: 20,
    cursor: 0,
  })
  const taxi = listed.expenses.find((expense) => expense.title === 'Airport taxi')

  await mutate('groups.expenses.update', {
    groupId: group.id,
    expenseId: taxi.id,
    participantId: Ana,
    expenseFormValues: {
      title: taxi.title,
      expenseDate: taxi.expenseDate,
      amount: taxi.amount,
      category: 0,
      paidBy: taxi.paidBy.id,
      paidFor: taxi.paidFor.map((paidFor) => ({
        participant: paidFor.participant.id,
        shares: paidFor.shares,
      })),
      splitMode: taxi.splitMode,
      saveDefaultSplittingOptions: false,
      isReimbursement: taxi.isReimbursement,
      documents: [],
      recurrenceRule: 'NONE',
    },
  })

  const lisbon = FIXTURES.find((fixture) => fixture.key === 'lisbon')
  await mutate('groups.update', {
    groupId: group.id,
    participantId: Chloe,
    groupFormValues: {
      name: lisbon.name,
      information: lisbon.information,
      currency: lisbon.currency,
      currencyCode: lisbon.currencyCode,
      participants: Object.entries(group.participants).map(([name, id]) => ({ id, name })),
    },
  })

  console.error(`recorded activity history for ${lisbon.name}`)
}

// Saves raw, unmodified API responses so the Swift decoders are tested against exactly what a
// real server sends rather than against JSON we hand-wrote to match our own assumptions.
async function dumpFixtures(result) {
  const { mkdir, writeFile } = await import('node:fs/promises')
  const { join } = await import('node:path')
  await mkdir(dumpDir, { recursive: true })

  const lisbon = result.groups.lisbon.id
  const { data: expenses } = await query('groups.expenses.list', {
    groupId: lisbon,
    limit: 20,
    cursor: 0,
  })

  const captures = [
    ['categories-list', () => query('categories.list', undefined)],
    ['groups-get', () => query('groups.get', { groupId: lisbon })],
    ['groups-get-details', () => query('groups.getDetails', { groupId: lisbon })],
    [
      'groups-list',
      () => query('groups.list', { groupIds: Object.values(result.groups).map((g) => g.id) }),
    ],
    ['expenses-list', () => query('groups.expenses.list', { groupId: lisbon, limit: 20, cursor: 0 })],
    [
      'expenses-get',
      () => query('groups.expenses.get', { groupId: lisbon, expenseId: expenses.expenses[0].id }),
    ],
    ['balances-list', () => query('groups.balances.list', { groupId: lisbon })],
    // Both shapes, because the participant fields are what changes between them: named, they
    // carry Ana's figures; unnamed, they come back `undefined` and superjson annotates them
    // rather than omitting the keys, which is the half the decoder has to survive.
    [
      'groups-stats-get',
      () =>
        query('groups.stats.get', {
          groupId: lisbon,
          participantId: result.groups.lisbon.participants['Ana'],
        }),
    ],
    ['groups-stats-get-anonymous', () => query('groups.stats.get', { groupId: lisbon })],
    [
      'activities-list',
      () => query('groups.activities.list', { groupId: lisbon, limit: 20, cursor: 0 }),
    ],
    ['error-not-found', () => query('groups.getDetails', { groupId: 'does-not-exist' }).catch((e) => e)],
  ]

  for (const [name, run] of captures) {
    try {
      const { raw } = await run()
      await writeFile(join(dumpDir, `${name}.json`), raw + '\n')
      console.error(`dumped ${name}.json`)
    } catch (error) {
      console.error(`could not dump ${name}: ${error.message}`)
    }
  }

  // The error envelope needs a raw fetch, since `query` throws on it.
  const errorResponse = await fetch(
    `${endpoint('groups.getDetails')}?input=${encodeURIComponent(
      JSON.stringify({ json: { groupId: 'does-not-exist' } }),
    )}`,
  )
  await writeFile(join(dumpDir, 'error-not-found.json'), (await errorResponse.text()) + '\n')
  console.error('dumped error-not-found.json')
}

seed().catch((error) => {
  console.error(error.message)
  process.exit(1)
})
