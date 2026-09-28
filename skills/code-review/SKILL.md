---
name: code-review
description: Code review a pull request
---

# Code Review

Review PRs and leave actionable comments with code suggestions for the author.

## Workflow

1. Fetch PR details and diff
2. Read CLAUDE.md for project conventions
3. Analyze changes against review criteria
4. Post comments with code suggestions

## Phase 1: Fetch PR

### Determine PR Number

**If PR number provided** (e.g., `/code-review 123`):
```bash
gh pr view 123 --json number,title,author,baseRefName,headRefName,url
```

**If no number** (use current branch):
```bash
gh pr view --json number,title,author,baseRefName,headRefName,url
```

If no PR found:
```
Error: No PR found. Create one first or specify PR number.
```

### Fetch the Diff

```bash
gh pr diff [PR_NUMBER]
```

### Get Changed Files List

```bash
gh pr view [PR_NUMBER] --json files --jq '.files[].path'
```

## Phase 2: Read Project Context

Read CLAUDE.md to understand project conventions:
```bash
Read file_path=[REPO_ROOT]/CLAUDE.md
```

Key patterns to extract:
- Effect-TS service patterns (required for backend)
- React guidelines (avoid useEffect)
- Testing requirements (Vitest, Playwright)
- Code style (Biome, DRY, KISS, YAGNI)

## Phase 3: Analyze Changes

Review each file against these criteria in order of priority.

### 3.1 Security Concerns

**Critical** - Block if found:
- SQL injection vulnerabilities
- Command injection (unescaped shell commands)
- XSS vulnerabilities (unescaped user input in JSX)
- Secrets/credentials in code
- Insecure authentication patterns
- Missing input validation at system boundaries

```typescript
// BAD: SQL injection
const query = `SELECT * FROM users WHERE id = ${userId}`;

// GOOD: Parameterized
const query = prisma.user.findUnique({ where: { id: userId } });
```

### 3.2 DRY Violations

**Major** - Flag repeated code:
- Same logic in 3+ places
- Copy-pasted functions with minor variations
- Repeated error handling patterns
- Duplicated API call structures

```typescript
// BAD: Repeated fetch logic
const getUsers = async () => {
  const res = await fetch('/api/users');
  if (!res.ok) throw new Error('Failed');
  return res.json();
};
const getPosts = async () => {
  const res = await fetch('/api/posts');
  if (!res.ok) throw new Error('Failed');
  return res.json();
};

// GOOD: Extracted utility
const fetchApi = async <T>(path: string): Promise<T> => {
  const res = await fetch(path);
  if (!res.ok) throw new Error(`Failed to fetch ${path}`);
  return res.json();
};
```

### 3.3 Over-Complications

**Major** - Simplify if found:
- Premature abstractions (helper for one-time use)
- Over-engineered solutions (5 files for simple feature)
- Unnecessary indirection
- Complex conditional logic that could be simplified
- Feature flags for code that should just change
- Backwards-compatibility shims when code can just change

```typescript
// BAD: Over-abstracted
class UserFetcherFactory {
  createFetcher(type: string) {
    return new UserFetcher(this.config[type]);
  }
}

// GOOD: Direct and simple
const fetchUser = (id: string) => prisma.user.findUnique({ where: { id } });
```

### 3.4 CLAUDE.md Violations

**Major** - Enforce project conventions:

**Effect-TS (backend services MUST use):**
```typescript
// BAD: Raw async/await in service
async function createUser(data: UserInput) {
  try {
    return await prisma.user.create({ data });
  } catch (e) {
    throw new Error('Failed');
  }
}

// GOOD: Effect-TS pattern
export class UserService extends Effect.Service<UserService>()("UserService", {
  effect: Effect.gen(function* () {
    const prisma = yield* PrismaClient;
    return {
      create: (data: UserInput) => Effect.tryPromise({
        try: () => prisma.user.create({ data }),
        catch: (e) => new UserCreateError({ cause: e }),
      }),
    };
  }),
}) {}
```

**React (avoid useEffect):**
```typescript
// BAD: useEffect for data fetching
useEffect(() => {
  fetchData().then(setData);
}, []);

// GOOD: tRPC query
const { data } = trpc.users.list.useQuery();
```

**Dates (use dayjs):**
```typescript
// BAD: Native Date manipulation
new Date(timestamp).toLocaleDateString();

// GOOD: dayjs
dayjs(timestamp).format('YYYY-MM-DD');
```

### 3.5 Missing Test Coverage

**Major** - Flag untested code:

**Business logic without tests:**
- Services in `packages/services` need unit tests
- Complex utility functions need tests
- Error handling paths need coverage

**Frontend without Playwright tests:**
- New pages/routes need E2E tests
- User flows need coverage
- Form submissions need testing

**Inngest functions without integration tests:**
- Core workflows need integration tests
- Event handlers need testing

```typescript
// If adding: packages/services/src/billing/calculate-usage.ts
// Require: packages/services/src/__tests__/billing/calculate-usage.spec.ts
```

### 3.6 Test Integrity

**Major** - Flag tests that don't verify real behavior:

**Testing implementation details instead of behavior:**
- Asserting on internal state, private methods, or specific function call counts
- Tests that break when refactoring internals even though behavior is unchanged
- Spying on internal methods rather than asserting on outputs/side effects

```typescript
// BAD: Tests implementation details
expect(service.internalCache.size).toBe(3);
expect(mockFn).toHaveBeenCalledTimes(2);

// GOOD: Tests observable behavior
expect(result).toEqual(expectedOutput);
expect(await getUser(id)).toMatchObject({ name: "Alice" });
```

**Over-mocking that bypasses real logic:**
- Mocking the function under test (testing the mock, not the code)
- Mocking so aggressively that no real code path executes
- Replacing the entire module being tested with stubs

```typescript
// BAD: Mocking the thing you're testing
vi.mock("./calculatePrice");
const result = calculatePrice(100); // tests the mock, not your code

// GOOD: Mock only external dependencies
vi.mock("@trigify/prisma"); // mock the DB, test the service logic
const result = await pricingService.calculatePrice(100);
```

**Config/environment manipulation to force passing:**
- Setting `NODE_ENV=test` to skip validation or auth checks
- Using `vi.useFakeTimers()` to sidestep race conditions instead of fixing them
- Overriding env vars to bypass feature flags or error paths
- Using `skipIf`, `todo`, or conditional logic to silently skip failing tests

```typescript
// BAD: Disabling the thing you should be testing
process.env.SKIP_AUTH = "true";
const result = await protectedEndpoint(); // auth was never tested

// BAD: Silently skipping failures
it.skipIf(process.env.CI)("should handle edge case", ...);

// GOOD: Test the real auth path
const result = await protectedEndpoint({ headers: { authorization: validToken } });
```

**Assertions that always pass:**
- `expect(result).toBeDefined()` on non-nullable returns
- `expect(result).toBeTruthy()` when a specific value should be checked
- `toMatchObject({})` with an empty object (matches anything)
- Missing assertions entirely (test passes because it didn't throw)
- `expect(true).toBe(true)` or other tautological assertions

```typescript
// BAD: Assertions that prove nothing
expect(result).toBeDefined();
expect(response).toBeTruthy();
expect(data).toMatchObject({});

// GOOD: Assert on specific expected values
expect(result).toEqual({ status: "active", credits: 100 });
expect(response.status).toBe(200);
expect(data).toMatchObject({ id: expect.any(String), name: "Test" });
```

**Snapshot abuse:**
- Snapshots of large objects where specific assertions would be clearer
- Snapshots that get blindly updated when they fail (`-u` without review)
- Using snapshots as a substitute for understanding what the output should be

**AI-agent-generated test smells (Codex, Claude, Copilot, etc.):**

AI coding agents frequently produce tests that look comprehensive but verify nothing meaningful. Apply extra scrutiny to tests in PRs authored by or pair-programmed with AI agents:

- **Circular mock-assert pattern**: setting up a mock return value then asserting the exact same value came back. The test just proves the mock works, not the code.

```typescript
// BAD: Circular - asserts what the mock returns, not what the code does
vi.mocked(prisma.user.findUnique).mockResolvedValue({ id: "1", name: "Alice" });
const result = await userService.getUser("1");
expect(result).toEqual({ id: "1", name: "Alice" }); // just tests the mock
// The service could return mockReturnValue directly and this still passes

// GOOD: Mock the dependency, assert on transformation/business logic
vi.mocked(prisma.user.findUnique).mockResolvedValue({ id: "1", name: "Alice", plan: "free", creditsUsed: 95 });
const result = await userService.getUser("1");
expect(result.isNearLimit).toBe(true); // tests actual business logic
expect(result.displayName).toBe("Alice (Free)"); // tests transformation
```

- **Mirror tests**: test logic that duplicates the implementation rather than specifying expected behavior. If the test breaks, the implementation is probably also broken in the same way.

```typescript
// BAD: Mirrors the implementation - if the formula is wrong, both are wrong
const expected = items.reduce((sum, i) => sum + i.price * i.qty, 0) * 1.1;
expect(calculateTotal(items)).toBe(expected);

// GOOD: Hardcode the expected result from a known specification
expect(calculateTotal([{ price: 10, qty: 2 }, { price: 5, qty: 1 }])).toBe(27.5);
```

- **Happy-path-only coverage**: AI agents generate passing tests for the golden path but skip error handling, edge cases, and boundary conditions. Look for test files with only positive-case `it` blocks.

- **Describe-block theater**: deeply nested describe blocks with elaborate setup but shallow or missing assertions inside. Volume of test code masking lack of actual verification.

```typescript
// BAD: Looks thorough, tests nothing meaningful
describe("PaymentService", () => {
  describe("processPayment", () => {
    describe("when amount is valid", () => {
      describe("and user has sufficient credits", () => {
        it("should process", async () => {
          const result = await service.processPayment(100);
          expect(result).toBeDefined(); // <-- this is the only real assertion
        });
      });
    });
  });
});
```

- **Auto-generated test file with no domain understanding**: test file structure that mirrors the source file 1:1 (one test per exported function) with generic names like "should work", "should return result", "should not throw". These indicate the agent generated tests from function signatures without understanding what the code should actually do.

**Test setup that hides bugs:**
- `beforeEach` that resets state in ways that mask test pollution
- Shared mutable state between tests (order-dependent tests)
- `try/catch` in tests that swallow errors to prevent failures

```typescript
// BAD: Swallowing errors
it("should process payment", async () => {
  try {
    await processPayment(invalidData);
  } catch {
    // test passes whether it throws or not
  }
});

// GOOD: Assert the error explicitly
it("should reject invalid payment", async () => {
  await expect(processPayment(invalidData)).rejects.toThrow(PaymentError);
});
```

### 3.7 Style Violations

**Minor** - Note for consistency:
- Ternary expressions in JSX (be declarative)
- Inconsistent naming conventions
- Missing type annotations on public APIs
- Console.log statements (remove or use Effect.log)

### 3.8 Other Best Practices

**Minor to Major:**
- Missing error boundaries in React
- Unbounded queries (no pagination/limits)
- Missing loading/error states in UI
- Race conditions in async code
- Memory leaks (uncleared intervals/subscriptions)
- Hardcoded values that should be config

## Phase 4: Post Comments

### Comment Format

Use concise, actionable comments with code suggestions.

**For code suggestions:**
```bash
gh api repos/:owner/:repo/pulls/[PR_NUMBER]/comments \
  --method POST \
  -f body="$(cat <<'EOF'
**[Severity]**: [Category]

[1-2 sentence explanation]

\`\`\`suggestion
[suggested code fix]
\`\`\`
EOF
)"  \
  -f commit_id="[HEAD_SHA]" \
  -f path="[FILE_PATH]" \
  -f line=[LINE_NUMBER]
```

**Severity levels:**
- `Critical` - Security issues, data loss risks
- `Major` - DRY violations, over-complications, missing tests, CLAUDE.md violations
- `Minor` - Style issues, suggestions

**Example comments:**

```markdown
**Major**: DRY Violation

This fetch pattern is repeated 4 times. Extract to a shared utility.

\`\`\`suggestion
import { fetchApi } from '@trigify/utils';

const users = await fetchApi<User[]>('/api/users');
\`\`\`
```

```markdown
**Major**: Missing Effect-TS

Backend services must use Effect-TS per CLAUDE.md.

\`\`\`suggestion
export class PaymentService extends Effect.Service<PaymentService>()("PaymentService", {
  effect: Effect.gen(function* () {
    const stripe = yield* StripeClient;
    return {
      charge: (amount: number) => Effect.tryPromise({
        try: () => stripe.charges.create({ amount }),
        catch: (e) => new PaymentError({ cause: e }),
      }),
    };
  }),
}) {}
\`\`\`
```

```markdown
**Major**: Missing Tests

New business logic needs test coverage. Add tests for:
- Happy path
- Error cases
- Edge cases (empty input, max values)

Expected location: `packages/services/src/__tests__/billing/calculate-usage.spec.ts`
```

```markdown
**Major**: Test Integrity - Testing Implementation Details

This test asserts on mock call counts and internal state rather than observable behavior. It will break on any refactor even if behavior is unchanged.

\`\`\`suggestion
// Assert on the output/side effect, not how we got there
const result = await billingService.calculateUsage(orgId);
expect(result).toEqual({ credits: 50, overage: false });
\`\`\`
```

```markdown
**Major**: Test Integrity - Tautological Assertion

`expect(result).toBeDefined()` proves nothing here since the function always returns an object. Assert on the actual expected values.

\`\`\`suggestion
expect(result).toEqual({
  status: "active",
  plan: "pro",
  creditsRemaining: 100,
});
\`\`\`
```

```markdown
**Major**: Test Integrity - Circular Mock-Assert

This test sets up a mock return value then asserts that exact value came back. It proves the mock works, not the business logic. Assert on transformations, computed values, or side effects the code actually performs.

\`\`\`suggestion
// Mock the raw data, assert on what the service does with it
vi.mocked(prisma.user.findUnique).mockResolvedValue({
  id: "1", name: "Alice", plan: "free", creditsUsed: 95
});
const result = await userService.getUser("1");
expect(result.isNearLimit).toBe(true);
expect(result.displayName).toBe("Alice (Free)");
\`\`\`
```

```markdown
**Critical**: SQL Injection

User input is interpolated directly into query. Use parameterized queries.

\`\`\`suggestion
const user = await prisma.user.findUnique({
  where: { id: userId }
});
\`\`\`
```

### Get Commit SHA

```bash
gh pr view [PR_NUMBER] --json headRefOid --jq '.headRefOid'
```

### Batch Comments

Post all comments in a review to reduce noise:

```bash
gh api repos/:owner/:repo/pulls/[PR_NUMBER]/reviews \
  --method POST \
  -f body="Code review complete. See inline comments." \
  -f event="COMMENT" \
  -f comments='[
    {"path": "file1.ts", "line": 10, "body": "..."},
    {"path": "file2.ts", "line": 25, "body": "..."}
  ]'
```

## Phase 5: Summary

Output review summary:

```
Code Review Complete: PR #[NUMBER] "[TITLE]"

Issues Found:
- Critical: [X]
- Major: [Y]
- Minor: [Z]

Categories:
- Security: [count]
- DRY Violations: [count]
- Over-complications: [count]
- CLAUDE.md Violations: [count]
- Missing Tests: [count]
- Test Integrity: [count]
- Style: [count]

[X] comments posted to PR.
```

## Review Checklist

Use this checklist for each PR:

```
[ ] Security: No injection vulnerabilities, secrets, or auth issues
[ ] DRY: No code repeated 3+ times
[ ] Simplicity: No premature abstractions or over-engineering
[ ] Effect-TS: Backend services use Effect patterns
[ ] React: No unnecessary useEffect, uses tRPC for data
[ ] Tests: Business logic has unit tests
[ ] E2E: Frontend changes have Playwright tests
[ ] Integration: Inngest functions have integration tests
[ ] Test Integrity: Tests verify behavior, not implementation details
[ ] Test Integrity: No over-mocking, config manipulation, or tautological assertions
[ ] Test Integrity: No AI-agent circular mock-assert, mirror tests, or happy-path-only coverage
[ ] Style: Follows Biome rules, consistent naming
```

## Error Handling

### No PR Found
```
Error: No PR found for current branch.
Options:
1. Create PR: gh pr create
2. Specify number: /code-review 123
```

### No Changes to Review
```
PR #[NUMBER] has no changed files to review.
```

### gh CLI Not Authenticated
```
Error: GitHub CLI not authenticated.
Run: gh auth login
```
