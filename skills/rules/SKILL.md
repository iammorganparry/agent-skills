---
name: rules
description: (no description)
disable-model-invocation: true
---

---
alwaysApply: true
---
# Cursor Rules for React Project

## General Guidelines
- **React useEffect**: Avoid using `useEffect` unless explicitly necessary. If used, include a comment explaining why it’s required (e.g., for handling side effects that cannot be managed otherwise, such as browser-specific APIs or third-party library integrations).
- **State Management**: Replicate server state using tRPC and React Query for data fetching, mutations, and caching.
- **Date Handling**: Use `dayjs` for all date and time operations, including formatting, parsing, and manipulation.
- **UI Components**: Use ShadCN components for all UI elements to ensure consistency and reusability.
- **D.R.Y Principles**: Anytime you use the same snippet of code more then once, refactor to a shared file. 
- **Keep it simple, stupid**: Keep logic simple, if complexity starts to creep in.. ensure we are delcarative in our approach and test, test, test. Always try to be declarative.. ex: avoid ternary expressions in React components
- **Document**: Ensure all complex code is well documented with thorough examples in JSDoc format and if necessary a feature guide markdown file
- **Package Manager**: User yarn package manager for package management


## Example Implementation

### Data Fetching with tRPC and React Query
```typescript
import { useQuery } from '@tanstack/react-query';
import { trpc } from '@/utils/trpc';
import { Button, Card } from '~/components';
import dayjs from 'dayjs';

interface User {
  id: string;
  name: string;
  createdAt: string;
}

export const UserList = () => {
  const { data, isLoading, error } = trpc.user.list.useQuery();

  if (isLoading) return <div>Loading...</div>;
  if (error) return <div>Error: {error.message}</div>;

  return (
    <Card>
      {data?.map((user: User) => (
        <div key={user.id}>
          <p>Name: {user.name}</p>
          <p>Joined: {dayjs(user.createdAt).format('MMMM D, YYYY')}</p>
          <Button>View Profile</Button>
        </div>
      ))}
    </Card>
  );
};
```

### tRPC Setup
```typescript
// utils/trpc.ts
import { createTRPCReact } from '@trpc/react-query';
import type { AppRouter } from '@/server/routers/_app';

export const trpc = createTRPCReact<AppRouter>();
```

### Date Handling with DayJS
```typescript
import dayjs from 'dayjs';

// Example: Formatting a date
const formattedDate = dayjs('2025-05-31').format('dddd, MMMM D, YYYY');
// Output: "Saturday, May 31, 2025"

// Example: Calculating date difference
const daysUntilEvent = dayjs('2025-12-25').diff(dayjs(), 'day');
// Output: Number of days until Christmas 2025
```

## Notes
- **Avoiding useEffect**: Prefer React Query’s `useQuery` and `useMutation` for data-related side effects. If `useEffect` is needed (e.g., for window event listeners), document the necessity:
  ```typescript
  // useEffect is necessary to handle window resize events
  useEffect(() => {
    const handleResize = () => { /* logic */ };
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);
  ```
- **ShadCN Components**: Import components like `Button`, `Card`, `Input`, etc. to maintain a consistent design system.
- **React Query**: Use trpc react `useQuery` for fetching data and `useMutation` for updates to ensure server state synchronization and optimistic updates where applicable.
- **DayJS**: Always use `dayjs` for date operations to avoid native JavaScript `Date` object inconsistencies.
- **NextJS**: All page components should be server components, all child components of that page are then client side rendered. 
- **Testing with Vitest**: 
  - Use Vitest for all unit and integration tests.
  - Inject dependencies (e.g., `trpc`) via props or context to enable easy mocking.
  - Avoid direct imports of dependencies in components; instead, pass them as props or through a provider to ensure testability.
  - Mock dependencies using `vi.fn()` for functions and objects to simulate behavior in tests.
  - Test all component states (e.g., loading, success, error) to ensure robust coverage.
  - Test files should be as close to their source counterparts as possible in a __tests__/ dir
