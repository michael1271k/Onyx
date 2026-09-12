#!/usr/bin/env node
/**
 * native/schema/supabase.json  →  the GRDB mirror, in Swift.
 *
 * ── WHY THIS IS GENERATED ────────────────────────────────────────────────────
 * The retired web app's generated Supabase types declared 17 tables while it
 * queried 29, and fourteen of those call sites were silently `any`. The file
 * drifted because nothing made it fail when it did. Twenty-nine hand-written Swift structs
 * would drift the same way, for the same reason, and the symptom would be a
 * column that silently stops syncing.
 *
 * So the mirror is generated from one introspected fixture, and `--check` fails
 * the build when the checked-in Swift no longer matches it — the same contract
 * `gen-atlas-swift.mjs` already enforces on the body atlas, and for the same
 * reason: two copies of one fact, and only one of them is looked at.
 *
 * `since: N` on a table puts its CREATE TABLE in `migrateMirrorV<N>`; a column
 * added to an older table goes in `cols` (fresh installs) AND in a guarded
 * `alter` migration in AppDatabase (existing stores) — see `v21.genericModel`.
 *
 *   node scripts/gen-mirror-swift.mjs           # write
 *   node scripts/gen-mirror-swift.mjs --check   # fail if the output would differ
 *
 * Re-introspecting is a separate, manual step (the `schema-truth-checker` agent
 * or the Supabase MCP): this script never touches the network, so it runs in CI
 * and on a plane.
 */

import { readFileSync, writeFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SCHEMA = join(ROOT, 'native/schema/supabase.json')
const OUT = join(ROOT, 'native/Packages/OnyxData/Sources/OnyxData/Mirror/MirrorModels.swift')

/**
 * Postgres → Swift.
 *
 * `date` is a STRING, not a Date, and deliberately: SQLite has no date type,
 * every other date in this store is `yyyy-MM-dd` text, and a string that sorts
 * correctly is worth more in a query than an epoch nobody can read. `timestamptz`
 * IS a Date — those are instants, not days.
 *
 * `numeric` is Double. Postgres numeric is arbitrary precision and Double is
 * not, but every numeric column here holds a body weight, a load or a macro —
 * quantities that were measured to one decimal place by a scale or typed by a
 * human. None of them is money.
 */
const TYPES = {
  uuid: 'String',
  text: 'String',
  date: 'String',
  timestamptz: 'Date',
  timestamp: 'Date',
  numeric: 'Double',
  float8: 'Double',
  float4: 'Double',
  int2: 'Int',
  int4: 'Int',
  int8: 'Int',
  bool: 'Bool',
  jsonb: 'JSONText',
  json: 'JSONText',
  _text: 'JSONText',
}

/** GRDB column types, for the CREATE TABLE. */
const SQLITE = {
  String: '.text', Date: '.datetime', Double: '.double', Int: '.integer',
  Bool: '.boolean', JSONText: '.text',
}

const RESERVED = new Set(['default', 'case', 'class', 'return', 'where', 'in', 'is', 'as', 'operator', 'protocol', 'extension', 'repeat', 'self', 'static', 'switch', 'true', 'false', 'nil'])

const camel = (s) => s.replace(/_([a-z0-9])/g, (_, c) => c.toUpperCase())
const pascal = (s) => {
  const c = camel(s)
  return c.charAt(0).toUpperCase() + c.slice(1)
}
/**
 * `workout_sessions` → `WorkoutSession`.
 *
 * `ies` → `y` FIRST: without it `nutrition_entries` singularises to
 * `NutritionEntrie`, which compiles and reads like a typo forever. `ss` is
 * left alone so nothing turns `..._progress` into `..._progres`.
 */
const typeName = (table) => {
  const p = pascal(table)
  if (p.endsWith('ies')) return `${p.slice(0, -3)}y`
  return p.endsWith('ss') ? p : p.replace(/s$/, '')
}
const swiftName = (col) => {
  const c = camel(col)
  return RESERVED.has(c) ? `\`${c}\`` : c
}

function parseCols(spec) {
  return spec.split(',').map((raw) => {
    const [name, rawType] = raw.trim().split(':')
    const nullable = rawType.endsWith('?')
    const pg = nullable ? rawType.slice(0, -1) : rawType
    const swift = TYPES[pg]
    if (!swift) throw new Error(`no Swift type for Postgres \`${pg}\` (column ${name})`)
    return { name, pg, nullable, swift }
  })
}

function structFor(table, def) {
  const cols = parseCols(def.cols)
  const type = typeName(table)
  const lines = []

  lines.push(`// MARK: - ${table}`)
  lines.push('')
  lines.push(`/// Mirrors \`public.${table}\` (${def.group}). ${
    def.cursor ? `Delta by \`${def.cursor}\`.`
    : def.window ? `Windowed on \`${def.window}\`.`
    : def.children_of ? `Pulled with its parent \`${def.children_of}\`.`
    : 'Pulled whole.'}`)
  lines.push(`public struct ${type}Row: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {`)
  lines.push(`    public static let databaseTableName = "${table}"`)
  lines.push('')
  for (const c of cols) {
    lines.push(`    public var ${swiftName(c.name)}: ${c.swift}${c.nullable ? '?' : ''}`)
  }
  lines.push('')
  lines.push('    public enum CodingKeys: String, CodingKey {')
  for (const c of cols) {
    const s = swiftName(c.name).replace(/`/g, '')
    lines.push(s === c.name ? `        case ${swiftName(c.name)}` : `        case ${swiftName(c.name)} = "${c.name}"`)
  }
  lines.push('    }')
  lines.push('')
  // Every nullable column defaults to nil, so a writer names only the columns
  // Postgres actually requires. The synthesised memberwise init cannot do this
  // — it has no defaults and is internal — and a forty-field call site written
  // by hand is where a column silently ends up in the wrong argument.
  lines.push('    public init(')
  lines.push(cols.map((c) => `        ${swiftName(c.name)}: ${c.swift}${c.nullable ? '? = nil' : ''}`).join(',\n'))
  lines.push('    ) {')
  for (const c of cols) lines.push(`        self.${swiftName(c.name)} = ${swiftName(c.name)}`)
  lines.push('    }')
  lines.push('}')
  lines.push('')
  return lines.join('\n')
}

function migrationFor(table, def) {
  const cols = parseCols(def.cols)
  const pk = def.pk ?? []
  const lines = []
  lines.push(`            try db.create(table: "${table}") { t in`)
  if (pk.length === 1) {
    const c = cols.find((x) => x.name === pk[0])
    lines.push(`                t.primaryKey("${pk[0]}", ${SQLITE[c.swift]})`)
  }
  for (const c of cols) {
    if (pk.length === 1 && c.name === pk[0]) continue
    // NOT NULL follows Postgres exactly. A column that is NOT NULL there and
    // nullable here would let a decode failure land as a silent gap.
    lines.push(`                t.column("${c.name}", ${SQLITE[c.swift]})${c.nullable ? '' : '.notNull()'}`)
  }
  if (pk.length > 1) {
    lines.push(`                t.primaryKey([${pk.map((p) => `"${p}"`).join(', ')}])`)
  }
  lines.push('            }')
  return lines.join('\n')
}

function registryFor(tables) {
  const lines = []
  lines.push('/// Every mirrored table, with the strategy that keeps it current.')
  lines.push('///')
  lines.push('/// Generated, so the list cannot fall behind the schema fixture the way a')
  lines.push('/// hand-maintained one would. `bespoke` tables are absent on purpose: they')
  lines.push('/// land in tables the logger already owns, through `SyncTranslation`.')
  lines.push('///')
  lines.push('/// `conflict` is the PostgREST upsert target for a LOCAL write of the table,')
  lines.push('/// and it is the NATURAL key wherever one exists — introspected, not guessed.')
  lines.push('/// Upserting `daily_logs` on `id` would insert a second row for a day the')
  lines.push('/// server already holds under a different uuid, and then fail on')
  lines.push('/// `daily_logs_user_id_date_key` forever.')
  lines.push('public enum MirrorCatalogue {')
  lines.push('    public static let tables: [MirrorTable] = [')
  for (const [table, def] of tables) {
    if (def.bespoke) continue
    const strategy = def.cursor ? `.delta(column: "${def.cursor}")`
      : def.window ? `.window(column: "${def.window}")`
      : '.full'
    const conflict = def.conflict ?? (def.pk ?? ['id']).join(',')
    const type = `${typeName(table)}Row`
    lines.push(`        MirrorTable(name: "${table}", group: .${def.group}, strategy: ${strategy},`)
    const order = (def.pk ?? ['id']).map((c) => `"${c}"`).join(', ')
    lines.push(`                    conflict: "${conflict}", order: [${order}],`)
    lines.push(`                    pull: { try await $0.pull(${type}.self, from: $1) },`)
    lines.push(`                    push: { try await $1.pushRow(${type}.self, from: $0, table: "${table}", conflict: "${conflict}", ref: $2) }),`)
  }
  lines.push('    ]')
  lines.push('')
  lines.push('    /// By name. Every lookup the pusher and the realtime wiring do is by name,')
  lines.push('    /// and rebuilding the dictionary per call would be a linear scan of')
  lines.push('    /// twenty-six entries on the drain path.')
  lines.push('    public static let byName: [String: MirrorTable] = Dictionary(')
  lines.push('        tables.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }')
  lines.push('    )')
  lines.push('}')
  return lines.join('\n')
}

function generate() {
  const schema = JSON.parse(readFileSync(SCHEMA, 'utf8'))
  const entries = Object.entries(schema.tables)
  const generated = entries.filter(([, d]) => !d.bespoke)

  const out = []
  out.push('// GENERATED by scripts/gen-mirror-swift.mjs — DO NOT EDIT.')
  out.push('//')
  out.push(`// Source: native/schema/supabase.json (introspected ${schema.introspected}).`)
  out.push('// Edit the fixture and re-run `npm run mirror`; `npm run check:mirror`')
  out.push('// fails the build when this file and the fixture disagree.')
  out.push('')
  out.push('import Foundation')
  out.push('import GRDB')
  out.push('')
  for (const [table, def] of generated) out.push(structFor(table, def))

  out.push('// MARK: - Schema')
  out.push('')
  out.push('extension AppDatabase {')
  out.push('    /// The mirror\'s tables, as one migration.')
  out.push('    ///')
  out.push('    /// Registered by `AppDatabase.migrator`. Append-only like every other')
  out.push('    /// migration here: a regenerated schema is a NEW migration, never an edit')
  out.push('    /// to this one, because an edited migration runs on a fresh install and')
  out.push('    /// not on yours.')
  out.push('    static func migrateMirrorV1(_ db: Database) throws {')
  for (const [table, def] of generated.filter(([, d]) => (d.since ?? 1) === 1)) out.push(migrationFor(table, def))
  out.push('    }')
  out.push('')
  // Tables the fixture marks `since: 2` (W2, 2026-09-10). A store that already
  // ran v9 gets them from `v21.genericModel`; a fresh install runs V1 then V2.
  // Append-only like V1: the next schema change is a V3, never an edit here.
  out.push('    /// The tables added at `since: 2`, registered by `v21.genericModel`.')
  out.push('    static func migrateMirrorV2(_ db: Database) throws {')
  for (const [table, def] of generated.filter(([, d]) => (d.since ?? 1) === 2)) out.push(migrationFor(table, def))
  out.push('    }')
  out.push('}')
  out.push('')
  out.push(registryFor(entries))
  out.push('')

  return out.join('\n')
}

const text = generate()
if (process.argv.includes('--check')) {
  let current = ''
  try { current = readFileSync(OUT, 'utf8') } catch { /* missing counts as stale */ }
  if (current !== text) {
    console.error('MirrorModels.swift is stale. Run `npm run mirror`.')
    process.exit(1)
  }
  console.log('mirror: up to date')
} else {
  writeFileSync(OUT, text)
  console.log(`mirror: wrote ${OUT}`)
}
