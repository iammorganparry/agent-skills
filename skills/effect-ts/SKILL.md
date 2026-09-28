---
name: effect-ts
description: Expert guidance on Effect-TS patterns, error handling, services, layers, and dependency injection. Use when writing backend services, working with Effect code, or needing help with typed effects, error handling, or service patterns.
allowed-tools: Read, Glob, Grep, Write, Edit
---

# Effect-TS Master

Comprehensive, current (Effect **v3.x**) guide to Effect-TS. Backend services in this
codebase MUST use Effect-TS.

**Import everything from the single `"effect"` barrel.** The pre-3.0 per-package
imports (`@effect/io`, `@effect/data`, `@effect/schema`) are gone — `Schema`,
`Config`, `Match`, `Ref`, `Schedule` etc. all live in `"effect"`. Platform bindings
(`runMain`, HTTP, FS) come from `@effect/platform` / `@effect/platform-node`.

## The Effect Type

```typescript
Effect<Success, Error, Requirements>
```

- **Success** (`A`): value returned on success.
- **Error** (`E`): the typed error channel — a union of *expected*, recoverable errors.
- **Requirements** (`R`): dependencies (services) that must be provided before running.

Two kinds of failure: **typed errors** live in `E` (tracked, recoverable — like checked
exceptions); **defects** are unexpected bugs that live in the `Cause`, *not* in the type
(`Effect.die`, thrown exceptions). Model domain failures as typed errors; reserve defects
for "this should never happen".

## Creating Effects

### Success and Failure

```typescript
import { Effect } from "effect"

Effect.succeed(42)                       // Effect<number, never, never>
Effect.fail(new NotFoundError({ id }))   // Effect<never, NotFoundError, never>
```

### Sync / Promise constructors

```typescript
Effect.sync(() => Date.now())        // sync that CANNOT throw
Effect.try(() => JSON.parse(raw))    // sync that MIGHT throw -> E = UnknownException
Effect.promise(() => alwaysResolves())    // promise that CANNOT reject
Effect.tryPromise(() => fetch(url))       // promise that MIGHT reject -> E = UnknownException

// Object form maps the thrown value into a TYPED error (prefer this):
const fetchUser = (id: string) =>
  Effect.tryPromise({
    try: () => fetch(`/api/users/${id}`).then((r) => r.json()),
    catch: (cause) => new FetchError({ message: "Failed to fetch user", cause }),
  })

Effect.suspend(() => build())        // lazily defer creation (circular refs, unify returns)
```

## Generator Syntax (Effect.gen)

The default idiom. `yield*` "awaits" an effect; plain JS runs between yields; it
short-circuits on the first error.

```typescript
const program = Effect.gen(function* () {
  const user = yield* fetchUser("123")
  const posts = yield* fetchPosts(user.id)
  const published = posts.filter((p) => p.published)   // regular JS
  yield* Effect.log(`Found ${published.length} posts`)
  return published
})
```

> The old adapter form `Effect.gen(function* ($) { yield* $(eff) })` is **deprecated**
> (TS ≥ 5.5). Always use bare `yield*`.

`if/else`, `for`, `while` all work inside `Effect.gen`.

### Effect.fn — named, traceable functions (prefer for service methods)

`Effect.fn("name")(function* (...) {...})` wraps a generator into a **real callable** that
opens an OpenTelemetry span per call **and** captures the definition site in stack traces
(plain `Effect.gen` captures only the call site). Prefer it over `const f = (x) => Effect.gen(…)`
for any named helper or service method you want observable.

```typescript
import { Effect } from "effect"

const findById = Effect.fn("UserService.findById")(function* (id: string) {
  yield* Effect.annotateCurrentSpan("userId", id)
  const rows = yield* db.query(id)
  return rows[0]
})
// optional trailing pipeline: Effect.fn("name")(function*(){…}, Effect.retry(policy), Effect.withSpan("x"))
```

`Effect.fnUntraced` has the identical authoring shape but **skips span creation** — the
perf escape hatch for hot paths, or where an outer `Effect.withSpan` already provides one.

## Error Handling

### Defining errors: Data.TaggedError vs Schema.TaggedError

```typescript
import { Data } from "effect"

export class NotFoundError extends Data.TaggedError("NotFoundError")<{
  readonly message: string
  readonly entityId: string
}> {}
```

```typescript
import { Schema } from "effect"

export class ValidationError extends Schema.TaggedError<ValidationError>()("ValidationError", {
  message: Schema.String,
  field: Schema.String,
}) {}
```

- **`Data.TaggedError`** — lightweight, in-process. Use for local errors.
- **`Schema.TaggedError`** — same `_tag`, **plus** it's a `Schema`, so the error
  encodes/decodes across a serialization boundary (`@effect/rpc`, workers, HTTP). Use
  when the error crosses a wire. (This is why `packages/core` uses the Schema variant —
  errors must survive the RPC main↔renderer boundary.)

Both produce a `_tag` discriminant that `catchTag` keys off.

### Catching / recovering

```typescript
program.pipe(
  Effect.catchTag("NotFoundError", (e) => Effect.succeed({ fallback: true })),

  Effect.catchTags({                                  // several at once
    NotFoundError: () => Effect.succeed(null),
    ValidationError: (e) => Effect.fail(new UserFacingError(e.message)),
    DatabaseError: (e) => Effect.die(e),              // escalate to defect
  }),

  Effect.catchAll((e) => Effect.succeed({ error: e.message })),  // any TYPED error
)
```

- `catchTag` / `catchTags` — recover by `_tag`; removes that error from `E`.
- `catchAll` — recover from any typed error (defects still propagate).
- `catchAllCause` — recover from typed errors **and** defects/interrupts (gets the `Cause`).
- `catchSome` / `catchIf` — conditional recovery without changing `E`.
- `Effect.mapError((e) => new Wrapped({ cause: e }))` — transform the error value/type.
- `Effect.orElse(() => other)` — fall back to another effect on any failure.
- `Effect.tapError` / `Effect.tapErrorTag("Tag", fn)` — side-effect on failure without consuming it.
- `Effect.orDie` / `Effect.die(v)` — turn a typed error into an unrecoverable defect.
- `Effect.sandbox` — surface the full `Cause` into `E` so you can `catchTag`/match it;
  `Effect.unsandbox` collapses back.

### Matching outcomes

```typescript
Effect.match(program, {
  onFailure: (e) => `fail: ${e._tag}`,
  onSuccess: (a) => `ok: ${a}`,
})
Effect.matchEffect(program, {
  onFailure: (e) => Effect.logError(e),
  onSuccess: (a) => Effect.succeed(a),
})
// matchCauseEffect when you need the Cause (defects/interrupts) in the handlers.
```

### Exit and Cause

- `Exit<A, E>` = `Success{value}` | `Failure{cause}`. Returned by `runPromiseExit` /
  `runSyncExit` / `Effect.exit`. Test with `Exit.isSuccess`.
- `Cause<E>` = structured failure tree: `Fail` (typed), `Die` (defect), `Interrupt`, plus
  `Sequential`/`Parallel` composites. Query with `Cause.isFailType`, `Cause.failureOption`,
  `Cause.pretty`.

## Services, Layers & Dependency Injection

### Effect.Service — the modern idiom (preferred)

Fuses the **Tag** and a default **Layer** into one class. The class *is* the Tag
(`yield* UserService`), and `UserService.Default` is the layer you provide. Declare
**exactly one** constructor: `effect`, `scoped`, `sync`, or `succeed`.

```typescript
import { Effect } from "effect"

export class UserService extends Effect.Service<UserService>()("app/UserService", {
  effect: Effect.gen(function* () {          // effectful/async init that reads deps
    const db = yield* Database

    return {
      findById: Effect.fn("UserService.findById")(function* (id: string) {
        const rows = yield* db.query(id)
        return rows[0] as User | undefined
      }),
      create: (data: CreateUserInput) =>
        Effect.gen(function* () {
          yield* Effect.log(`Creating user: ${data.email}`)
          // ...
        }),
    }
  }),
  dependencies: [Database.Default],   // layers needed to build THIS service, folded into .Default
  accessors: true,                    // generate static method accessors
}) {}
```

- **`sync:` / `succeed:`** — synchronous / already-built implementations (e.g. pure config).
- **`scoped:`** — construction needs resource lifecycle (`Effect.acquireRelease`); `.Default`
  does **not** leak `Scope` as a requirement.
- **`dependencies:`** — composed **into** `.Default`, so downstream code provides just
  `UserService.Default` and gets the whole subgraph.
- **`accessors: true`** — call `yield* UserService.findById(id)` directly instead of
  `const s = yield* UserService; yield* s.findById(id)`.

```typescript
// sync config service
export class ConfigService extends Effect.Service<ConfigService>()("app/ConfigService", {
  sync: () => ({ apiUrl: process.env.API_URL ?? "http://localhost:3000" }),
}) {}
```

Provide it:

```typescript
const runnable = program.pipe(Effect.provide(UserService.Default))
```

### Lower-level: Context.Tag / Context.GenericTag

What `Effect.Service` compiles down to. Reach for it when you want Tag and Layer defined
separately, or the implementation is chosen entirely at provide-time.

```typescript
import { Context, Effect, Layer } from "effect"

class Random extends Context.Tag("MyRandomService")<
  Random,
  { readonly next: Effect.Effect<number> }
>() {}

const RandomLive = Layer.succeed(Random, { next: Effect.sync(() => Math.random()) })
```

`Context.GenericTag<Id, Service>("key")` is the function-style variant when you can't use a class.

### Layers (`Layer<ROut, E, RIn>`)

- `Layer.succeed(Tag, impl)` — no-dependency, pure implementation.
- `Layer.effect(Tag, Effect.gen(…))` — effectful construction that can read other services.
- `Layer.scoped(Tag, Effect.acquireRelease(acquire, release))` — lifecycle-managed resource
  (DB pool, file handle); finalizer runs when the layer's scope closes.
- `Layer.mergeAll(a, b, c)` — combine siblings; the result **provides all** outputs and
  **requires all** inputs (no wiring between them).
- `outer.pipe(Layer.provide(inner))` — feed `inner`'s outputs to satisfy `outer`'s inputs;
  outer's requirements shrink, inner's outputs are hidden.
- `Layer.provideMerge(inner)` — same wiring but **keeps both** outputs (when downstream also
  needs the inner service).

**Memoization:** layers are memoized by reference within a single build — the same layer
*instance* is constructed once and shared. Two distinct layer values for the "same" service
build twice; reuse the same `.Default` reference to share.

### Layer.mock — fail-fast test doubles

```typescript
import { Effect, Layer } from "effect"

const UserServiceTest = Layer.mock(UserService, {
  findById: () => Effect.succeed({ id: "1", name: "Test" }),
  // methods you omit throw an UnimplementedError defect on access — surfaces unstubbed deps
})
```

`Layer.succeed(Tag, fullImpl)` still works when you want a complete stub with no fail-fast.

## Schema (effect/Schema)

Runtime validation + typed encode/decode. **Now in core `effect`** — the standalone
`@effect/schema` package is deprecated/merged (since Effect 3.10).

```typescript
import { Schema } from "effect"

const Person = Schema.Struct({
  name: Schema.String,
  age: Schema.Number,
  role: Schema.Literal("admin", "user"),
  email: Schema.optional(Schema.String),      // ?: string | undefined
  tags: Schema.Array(Schema.String),
})

Schema.decodeUnknown(Person)(input)     // Effect<Person, ParseError>  (prefer in Effect code)
Schema.decodeUnknownSync(Person)(input) // sync, throws ParseError
Schema.encode(Person)(person)           // Effect back to the Encoded form

type Decoded = typeof Person.Type        // or Schema.Schema.Type<typeof Person>
type Encoded = typeof Person.Encoded     // or Schema.Schema.Encoded<typeof Person>
```

### Filters, brands, transforms

```typescript
const Username = Schema.String.pipe(Schema.minLength(3), Schema.maxLength(50))
const PositiveInt = Schema.Number.pipe(Schema.int(), Schema.greaterThan(0))

// Custom filter: return true/undefined = ok, string = error message
const Long = Schema.String.pipe(
  Schema.filter((s) => s.length >= 10 || "must be at least 10 characters"),
)

// Branded nominal type
const AuthToken = Schema.String.pipe(Schema.brand("AuthToken"))
type AuthToken = typeof AuthToken.Type   // string & Brand<"AuthToken">

// Transformation (always succeeds)
const BooleanFromString = Schema.transform(
  Schema.Literal("on", "off"), Schema.Boolean,
  { strict: true, decode: (l) => l === "on", encode: (b) => (b ? "on" : "off") },
)
// Fallible transform: Schema.transformOrFail + ParseResult.succeed/fail
```

### Classes / tagged errors / requests

```typescript
class Person extends Schema.Class<Person>("Person")({
  id: Schema.Number,
  name: Schema.NonEmptyString,
}) {}
new Person({ id: 1, name: "John" })

class HttpError extends Schema.TaggedError<HttpError>()("HttpError", {
  status: Schema.Number,
}) {}

// Schema.TaggedRequest — request/response with typed success + failure (RPC-friendly)
class GetUser extends Schema.TaggedRequest<GetUser>()("GetUser", {
  failure: Schema.String,
  success: Person,
  payload: { id: Schema.String },
}) {}
```

## Config

Typed, provider-backed configuration read inside effects. Secrets use `Redacted` so they
never leak into logs.

```typescript
import { Config, ConfigProvider, Effect, Redacted } from "effect"

const program = Effect.gen(function* () {
  const host = yield* Config.string("HOST")
  const port = yield* Config.number("PORT").pipe(Config.withDefault(8080))
  const secret = yield* Config.redacted("API_KEY")     // Config<Redacted<string>>
  useKey(Redacted.value(secret))                        // unwrap only when needed
})

Config.nested(Config.number("PORT"), "SERVER")   // reads SERVER_PORT
Config.all([Config.string("HOST"), Config.number("PORT")])
// also: Config.integer, Config.boolean, Config.date, Config.duration, Config.url, Config.array, Config.map

// Swap the provider for tests:
Effect.withConfigProvider(program, ConfigProvider.fromMap(new Map([["HOST", "localhost"]])))
```

## Concurrency & Fibers

### Effect.all / Effect.forEach with concurrency

```typescript
Effect.all([t1, t2, t3])                              // SEQUENTIAL (default!)
Effect.all([t1, t2, t3], { concurrency: 2 })          // max 2 in flight
Effect.all([t1, t2, t3], { concurrency: "unbounded" })
Effect.all(tasks, { mode: "validate" })               // accumulate ALL errors, not first

Effect.forEach(items, (x) => handle(x), { concurrency: 5 })
Effect.forEach(items, (x) => handle(x), { concurrency: "unbounded", discard: true }) // -> Effect<void>
```

Options: `{ concurrency?: number | "unbounded" | "inherit"; discard?: boolean; batching?: boolean; mode?: "default" | "validate" }`.
`"inherit"` reads from `Effect.withConcurrency(n)`; `discard: true` drops results (memory win).

`Effect.zip` / `zipWith` run **sequentially** unless you pass `{ concurrent: true }`.

### Fibers, racing

```typescript
import { Effect, Fiber } from "effect"

const program = Effect.gen(function* () {
  const fiber = yield* Effect.fork(longTask)   // -> Fiber<A, E>
  const result = yield* Fiber.join(fiber)      // rejoin; propagates failure
  const exit = yield* Fiber.await(fiber)       // -> Exit<A, E> (never fails)
})

Effect.race(t1, t2)        // first SUCCESS wins; loser interrupted
Effect.raceAll([t1, t2, t3])
Effect.raceFirst(t1, t2)   // first to SETTLE (success OR failure) wins
```

## Interruption & Structured Concurrency

A child fiber's lifespan is bound to its parent: when the parent completes, forked children
are **automatically interrupted** — no leaks. Interruption is a first-class `Exit`/`Cause`
outcome; finalizers and `onInterrupt` handlers always run.

```typescript
task.pipe(
  Effect.onInterrupt(() => Console.log("cleanup")),
)

Effect.uninterruptible(critical)          // region cannot be interrupted
Effect.interruptible(region)              // mark interruptible again
Effect.uninterruptibleMask((restore) => acquire.pipe(restore(...)))  // acquire/release safety

yield* Effect.fork(child)        // supervised: dies with parent
yield* Effect.forkDaemon(child)  // survives parent (global scope)
yield* Effect.forkScoped(child)  // tied to enclosing Effect.scoped
```

Resource acquisition in `acquireRelease` runs **uninterruptibly** — you never leak a
half-acquired resource.

## Resource Management (Scope)

A `Scope` collects finalizers and runs them in **reverse order** when it closes — on success,
failure, or interruption.

```typescript
import { Effect } from "effect"

// release runs when the enclosing scope closes:
const resource = Effect.acquireRelease(
  openConnection,                       // Effect<Conn, E, R>
  (conn, exit) => closeConnection(conn) // (a, exit) => Effect<void>
)   // -> Effect<Conn, E, R | Scope>

// self-contained acquire -> use -> release (no Scope in result):
Effect.acquireUseRelease(open, (c) => use(c), (c) => close(c))

Effect.addFinalizer((exit) => Console.log(`closing, exit=${exit._tag}`))
myEffect.pipe(Effect.ensuring(cleanup))    // run finalizer regardless of outcome

const runnable = Effect.scoped(program)    // creates + closes a Scope, discharges the requirement
```

For long-lived resources (DB pools, watchers), build them with `Layer.scoped(Tag, acquireRelease)`
so cleanup runs when the app runtime shuts down.

## Scheduling / Retry / Repeat

`Schedule<Out, In, R>` drives both `retry` (keyed off errors) and `repeat` (keyed off values).

```typescript
import { Effect, Schedule } from "effect"

Schedule.recurs(5)                       // up to 5 times
Schedule.spaced("200 millis")            // fixed gap after each run
Schedule.fixed("1 second")               // fixed interval regardless of run time
Schedule.exponential("10 millis", 2.0)   // exponential backoff (base, factor)
Schedule.jittered(schedule)              // randomize delays (anti thundering-herd)
Schedule.intersect(a, b)                 // recur while BOTH continue; delay = max
Schedule.union(a, b)                     // recur while EITHER continues; delay = min

// Classic capped backoff:
const policy = Schedule.exponential("10 millis").pipe(
  Schedule.jittered,
  Schedule.intersect(Schedule.recurs(5)),
)
Effect.retry(task, policy)
Effect.repeat(task, Schedule.spaced("1 second"))

// Options-object form:
Effect.retry(task, { times: 5 })
Effect.retry(task, { while: (e) => e._tag === "Transient" })
Effect.retryOrElse(task, policy, (err) => Effect.succeed("default"))
```

### Timeouts

```typescript
task.pipe(Effect.timeout("3 seconds"))         // fails with TimeoutException
task.pipe(Effect.timeoutOption("1 second"))    // -> Option<A>, None on timeout (no failure)
Effect.timeoutFail(task, { duration: "1 second", onTimeout: () => new MyError() })
```

## State & Communication Primitives

- **`Ref`** — synchronous mutable reference, safe across fibers.
- **`SynchronizedRef`** — `Ref` with **effectful** atomic updates (`updateEffect`), serialized.
- **`SubscriptionRef`** — `Ref` whose changes are observable as a `Stream` (`.changes`).
- **`Queue`** — async, back-pressured queue (work distribution between fibers).
- **`PubSub`** — broadcast: every subscriber receives every message.
- **`Deferred`** — one-shot promise-like cell; set once, awaited by many.

```typescript
import { Effect, Ref, Queue } from "effect"

Effect.gen(function* () {
  const ref = yield* Ref.make(0)
  yield* Ref.update(ref, (n) => n + 1)
  const count = yield* Ref.get(ref)             // 1

  const queue = yield* Queue.bounded<number>(100)
  yield* Queue.offer(queue, 1)
  const item = yield* Queue.take(queue)         // 1
})
```

## Pattern Matching & Do Notation

### Match module

```typescript
import { Match } from "effect"

const describe = Match.type<string | number>().pipe(
  Match.when(Match.string, (s) => `string: ${s}`),
  Match.when(Match.number, (n) => `number: ${n}`),
  Match.exhaustive,                    // compile error if a case is missing
)

const handle = Match.type<Event>().pipe(
  Match.tag("Success", (e) => e.value),      // discriminated union on _tag
  Match.tag("Failure", (e) => e.error),
  Match.exhaustive,
)

Match.value(user).pipe(
  Match.when({ role: "admin" }, (u) => `admin ${u.name}`),
  Match.orElse((u) => `user ${u.name}`),     // fallback
)
```

### Do notation (point-free alternative to Effect.gen)

```typescript
Effect.Do.pipe(
  Effect.bind("user", () => fetchUser(id)),        // bind an Effect result
  Effect.bind("posts", ({ user }) => fetchPosts(user.id)),
  Effect.let("count", ({ posts }) => posts.length), // bind a pure value
  Effect.tap(({ count }) => Effect.log(`count=${count}`)),
  Effect.map(({ user, posts }) => ({ user, posts })),
)
```

## Running Effects

```typescript
Effect.runPromise(program)       // -> Promise<A> (rejects on failure)
Effect.runPromiseExit(program)   // -> Promise<Exit<A, E>> (never rejects)
Effect.runSync(syncProgram)      // sync only; throws on failure
Effect.runSyncExit(syncProgram)  // sync -> Exit
Effect.runFork(program)          // -> RuntimeFiber (recommended default for background work)
```

### Recommended app entrypoint — runMain

Don't hand-roll `runPromise` at the top of a real app. `NodeRuntime.runMain` sets exit codes,
pretty-logs errors, handles SIGINT, and tears down resources:

```typescript
import { NodeRuntime } from "@effect/platform-node"

NodeRuntime.runMain(program)   // { disableErrorReporting?, disablePrettyLogger?, teardown? }
```

### In tRPC routes

```typescript
export const userRouter = createTRPCRouter({
  getById: protectedProcedure
    .input(z.object({ id: z.string() }))
    .query(({ input }) =>
      Effect.runPromise(
        Effect.gen(function* () {
          const users = yield* UserService
          return yield* users.findById(input.id)
        }).pipe(Effect.provide(UserService.Default)),
      ),
    ),
})
```

## Logging & Observability

```typescript
Effect.gen(function* () {
  yield* Effect.log("Info message")
  yield* Effect.logDebug("Debug"); yield* Effect.logWarning("Warn"); yield* Effect.logError("Error")

  // Structured annotations:
  yield* Effect.log("Processing user").pipe(
    Effect.annotateLogs({ userId: "123", action: "enrich" }),
  )
})

// Tracing spans:
myEffect.pipe(Effect.withSpan("enrich-prospect", { attributes: { prospectId } }))
yield* Effect.annotateCurrentSpan("key", value)   // inside the span
```

## Testing (@effect/vitest)

Import runners from `@effect/vitest`; test utilities (`TestClock`) from `effect`.

```typescript
import { expect, it, layer } from "@effect/vitest"
import { Effect, Exit, TestClock } from "effect"

it.effect("returns the quotient", () =>
  Effect.gen(function* () {
    const result = yield* divide(4, 2)
    expect(result).toBe(2)
  }))

it.effect("captures failure as Exit", () =>
  Effect.gen(function* () {
    const result = yield* Effect.exit(divide(4, 0))
    expect(result).toStrictEqual(Exit.fail("Cannot divide by zero"))
  }))

it.effect("advances virtual time (no real waiting)", () =>
  Effect.gen(function* () {
    const fiber = yield* Effect.sleep("1 minute").pipe(Effect.fork)
    yield* TestClock.adjust("1 minute")
    yield* fiber.await
  }))
```

Runners: `it.effect` (auto-provides `TestContext` incl. `TestClock`, clock at 0),
`it.live` (real clock/logging), `it.scoped` (effects needing a `Scope`), `it.scopedLive`.
Modifiers: `.skip`, `.only`, `.fails`, `it.effect.each([...])`, `it.flakyTest(eff, "5 seconds")`.

Share a layer across a suite with `layer()` (built once, memoized):

```typescript
layer(UserService.Default)("UserService", (it) => {
  it.effect("finds a user", () =>
    Effect.gen(function* () {
      const users = yield* UserService
      expect(yield* users.findById("1")).toBeDefined()
    }))
})
```

Test doubles are plain layers — `Layer.mock(Tag, partial)` (fail-fast) or
`Layer.succeed(Tag, fullImpl)` — swapped in via `layer()` or `Effect.provide`.

## Pipe vs Generator

**Generators** for sequential logic, intermediate variables, readability.
**Pipe** for simple transforms, operator chains, one-liners.

```typescript
// Pipe — simple chain
fetchUser(id).pipe(
  Effect.map((u) => u.name),
  Effect.mapError((e) => new WrappedError({ cause: e })),
  Effect.tap((name) => Effect.log(`Found: ${name}`)),
)

// Generator — branching logic
Effect.gen(function* () {
  const user = yield* fetchUser(id)
  if (user.status === "inactive") return yield* Effect.fail(new InactiveUserError())
  return { user, posts: yield* fetchPosts(user.id) }
})
```

## Quick Reference

| Operation | Code |
|-----------|------|
| Create success / failure | `Effect.succeed(v)` / `Effect.fail(e)` |
| Wrap promise (typed) | `Effect.tryPromise({ try, catch })` |
| Wrap sync (typed) | `Effect.try({ try, catch })` |
| Named traceable fn | `Effect.fn("name")(function* (){…})` |
| Get service | `yield* MyService` |
| Provide service | `.pipe(Effect.provide(MyService.Default))` |
| Catch by tag / all | `Effect.catchTag("Tag", fn)` / `Effect.catchAll(fn)` |
| Transform error | `Effect.mapError(fn)` |
| Concurrent map | `Effect.forEach(xs, fn, { concurrency: "unbounded" })` |
| Retry w/ backoff | `Effect.retry(task, Schedule.exponential("10 millis"))` |
| Timeout | `Effect.timeout("3 seconds")` |
| Resource | `Effect.acquireRelease(acquire, release)` + `Effect.scoped` |
| Decode schema | `Schema.decodeUnknown(S)(input)` |
| Read config | `yield* Config.string("KEY")` |
| Log w/ context | `Effect.log(m).pipe(Effect.annotateLogs({…}))` |
| Add span | `.pipe(Effect.withSpan("name"))` |
| Run to promise | `Effect.runPromise(effect)` |
| App entrypoint | `NodeRuntime.runMain(program)` |

## Version notes (v3.x)

- Everything imports from `"effect"`. `@effect/schema` is **merged into core** — use
  `import { Schema } from "effect"`.
- `Effect.fn` / `Effect.fnUntraced` are the newer named-function helpers — prefer over
  anonymous `(x) => Effect.gen(…)` for service methods.
- The `Effect.gen` `$` adapter is deprecated — use bare `yield*`.
- `Effect.Service` (with `.Default`) is the current service idiom; `Context.Tag` + hand-written
  `Layer.effect` is the lower-level primitive it builds on.
- `Layer.mock` gives fail-fast partial test doubles.
- `{ concurrency }` options replaced the removed `Effect.allPar` / `forEachPar` variants.
- Effect v4 is in beta on `main` — a few APIs move (e.g. `Schema.TaggedRequest`). This guide
  targets **v3**, which is where this codebase lives.

## Resources

- Effect docs: https://effect.website/docs/
- API reference: https://effect-ts.github.io/effect/
- GitHub: https://github.com/Effect-TS/effect
- Effect examples in the current repo: `rg -l "Effect.Service|Context.Tag|Layer\." --type ts`
