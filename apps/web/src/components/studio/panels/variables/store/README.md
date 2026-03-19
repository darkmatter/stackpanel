# Variables Panel State Management with Zustand + Immer

This directory contains the state management stores for the variables panel using Zustand with Immer middleware for immutable updates.

## Overview

The variables panel state is split into two focused stores:

1. **VariablesUIStore** - UI state (search, filters, expanded, revealed secrets, editing)
2. **SecretOperationsStore** - Async operation state (reveal/delete loading and errors)

Both stores use Immer middleware to allow writing state updates in an intuitive, mutative style while maintaining immutability under the hood.

## Stores

### variables-ui-store.ts

Manages all UI-related state for the variables panel.

**State:**
```typescript
{
  // Search and filtering
  searchQuery: string
  selectedType: VariableTypeName | "all"
  
  // Expand/collapse state
  expandedId: string | null
  
  // Secret reveal state
  revealedSecrets: Record<string, { value: string; loading: boolean }>
  
  // Secret edit dialog state
  editingSecret: EditingSecret | null
}
```

**Actions:**
- `setSearchQuery(query: string)` - Update search query
- `setSelectedType(type)` - Update selected variable type filter
- `toggleExpanded(id: string)` - Toggle variable details expansion
- `clearExpanded()` - Close all expanded variables
- `setRevealedSecret(id, value, loading)` - Set revealed secret state
- `clearRevealedSecret(id)` - Clear one revealed secret
- `clearAllRevealedSecrets()` - Clear all revealed secrets
- `setEditingSecret(secret)` - Set secret being edited
- `reset()` - Reset to initial state

**Usage:**
```typescript
import { useVariablesUIStore } from './store/variables-ui-store'

// In a component
const searchQuery = useVariablesUIStore((state) => state.searchQuery)
const setSearchQuery = useVariablesUIStore((state) => state.setSearchQuery)

// Call action
setSearchQuery('my-search')
```

### use-secret-operations.ts

Manages async operation state for reveal and delete operations.

**State:**
```typescript
{
  // Reveal operation state
  revealingSecretId: string | null
  revealError: string | null
  
  // Delete operation state
  deletingSecretId: string | null
  deleteError: string | null
}
```

**Actions:**
- `setRevealingSecretId(id)` - Set currently revealing secret ID
- `setRevealError(error)` - Set reveal operation error
- `clearRevealState()` - Clear reveal operation state
- `setDeletingSecretId(id)` - Set currently deleting secret ID
- `setDeleteError(error)` - Set delete operation error
- `clearDeleteState()` - Clear delete operation state
- `reset()` - Reset to initial state

**Usage:**
```typescript
import { useSecretOperationsStore } from './store/use-secret-operations'

// Check if a specific secret is being revealed
const revealingSecretId = useSecretOperationsStore((state) => state.revealingSecretId)
const isRevealing = revealingSecretId === 'some-id'
```

## Immer Integration

Both stores use the Immer middleware from Zustand, which allows writing state updates in a simple, mutative style:

### Before Immer (Manual Immutability)
```typescript
setRevealedSecret: (variableId, value, loading) =>
  set(
    (state) => ({
      revealedSecrets: {
        ...state.revealedSecrets,
        [variableId]: { value, loading },
      },
    }),
    false,
    "setRevealedSecret"
  )
```

### After Immer (Simple Mutation)
```typescript
setRevealedSecret: (variableId, value, loading) => {
  set(
    (state) => {
      state.revealedSecrets[variableId] = { value, loading }
    },
    false,
    "setRevealedSecret"
  )
}
```

### Benefits of Immer

1. **Simpler Code** - Write mutations naturally, Immer handles immutability
2. **Less Boilerplate** - No spread operators or manual object/array copying
3. **Fewer Bugs** - Easier to understand and less chance of accidentally mutating original state
4. **Performance** - Immer creates minimal diffs, only changed parts are new objects
5. **Structural Sharing** - Unchanged parts share the same reference as before

## Using the Stores in Components

### In Functional Components

```typescript
import { useVariablesUIStore } from '../store/variables-ui-store'

export function VariablesFilter() {
  // Select specific slices of state
  const searchQuery = useVariablesUIStore((state) => state.searchQuery)
  const setSearchQuery = useVariablesUIStore((state) => state.setSearchQuery)
  const selectedType = useVariablesUIStore((state) => state.selectedType)
  const setSelectedType = useVariablesUIStore((state) => state.setSelectedType)
  
  return (
    <input
      value={searchQuery}
      onChange={(e) => setSearchQuery(e.target.value)}
    />
  )
}
```

### Selecting Multiple State Slices

```typescript
// Good: Select only what you need (fine-grained subscriptions)
const searchQuery = useVariablesUIStore((state) => state.searchQuery)
const selectedType = useVariablesUIStore((state) => state.selectedType)

// Avoid: Selecting entire state (causes unnecessary re-renders)
const { searchQuery, selectedType } = useVariablesUIStore()
```

### Performance Optimization

Zustand's selector system ensures components only re-render when their selected slices change:

```typescript
// This component only re-renders when searchQuery changes
const SearchComponent = () => {
  const searchQuery = useVariablesUIStore((state) => state.searchQuery)
  return <div>{searchQuery}</div>
}

// This component only re-renders when selectedType changes
const FilterComponent = () => {
  const selectedType = useVariablesUIStore((state) => state.selectedType)
  return <div>{selectedType}</div>
}
```

## DevTools Integration

Both stores include Zustand DevTools middleware for debugging. When in development mode, you can:

1. Inspect state changes in real-time
2. See action names and payloads
3. Time-travel through state changes
4. Export/import state snapshots

The DevTools are available in the browser's Redux DevTools extension.

## Testing Stores

Stores can be easily tested in isolation:

```typescript
import { useVariablesUIStore } from './store/variables-ui-store'

describe('VariablesUIStore', () => {
  beforeEach(() => {
    // Reset store before each test
    useVariablesUIStore.getState().reset()
  })

  it('updates search query', () => {
    const { setSearchQuery, getState } = useVariablesUIStore
    setSearchQuery('test-query')
    expect(getState().searchQuery).toBe('test-query')
  })

  it('toggles expanded state', () => {
    const { toggleExpanded, getState } = useVariablesUIStore
    toggleExpanded('var-1')
    expect(getState().expandedId).toBe('var-1')
    toggleExpanded('var-1')
    expect(getState().expandedId).toBeNull()
  })
})
```

## Future Enhancements

### 1. Persist State to localStorage

```typescript
import { persist } from 'zustand/middleware'

export const useVariablesUIStore = create<VariablesUIState>()(
  persist(
    immer((set) => ({
      // ... store definition
    })),
    {
      name: 'variables-ui-store',
      partialize: (state) => ({
        // Only persist these fields
        searchQuery: state.searchQuery,
        selectedType: state.selectedType,
      }),
    }
  )
)
```

### 2. Subscribe to Specific State Slices

```typescript
// Subscribe to searchQuery changes only
useVariablesUIStore.subscribe(
  (state) => state.searchQuery,
  (searchQuery) => {
    console.log('Search query changed:', searchQuery)
  }
)
```

### 3. Create Derived State

```typescript
const useFilteredVariables = () => {
  const searchQuery = useVariablesUIStore((state) => state.searchQuery)
  const selectedType = useVariablesUIStore((state) => state.selectedType)
  const variables = useVariables() // From react-query
  
  return useMemo(() => {
    // Filter logic here
  }, [variables, searchQuery, selectedType])
}
```

## Architecture Diagram

```
VariablesPanel (orchestrator)
├── useVariablesUIStore (Zustand + Immer)
│   ├── Component: VariablesFilter (selects: searchQuery, selectedType)
│   ├── Component: VariableItem (selects: expandedId, revealedSecrets)
│   └── Component: EditDialog (selects: editingSecret)
│
├── useSecretOperationsStore (Zustand + Immer)
│   └── Hook: useSecretActions (performs reveal/delete operations)
│
└── Custom Hooks
    └── useVariableFilters (reads from store, filters data)
```

## Migration from useState

If refactoring existing code that uses `useState`:

**Before:**
```typescript
const [searchQuery, setSearchQuery] = useState('')
const [selectedType, setSelectedType] = useState<VariableTypeName | 'all'>('all')
```

**After:**
```typescript
const searchQuery = useVariablesUIStore((state) => state.searchQuery)
const setSearchQuery = useVariablesUIStore((state) => state.setSearchQuery)
const selectedType = useVariablesUIStore((state) => state.selectedType)
const setSelectedType = useVariablesUIStore((state) => state.setSelectedType)
```

Benefits:
- Shared state across components without prop drilling
- Persistent state (can add localStorage)
- Better devtools support
- Easier to test
- Cleaner component code

## Troubleshooting

### Store not updating?

Ensure you're calling the action function, not just accessing it:
```typescript
// ❌ Wrong - just accesses the function
const setSearchQuery = useVariablesUIStore((state) => state.setSearchQuery)

// ✅ Correct - accesses both state and action, then calls it
const setSearchQuery = useVariablesUIStore((state) => state.setSearchQuery)
setSearchQuery('new-value')
```

### Component re-rendering too often?

Use fine-grained selectors to select only the state you need:
```typescript
// ❌ Bad - subscribes to entire store
const state = useVariablesUIStore()

// ✅ Good - subscribes only to searchQuery
const searchQuery = useVariablesUIStore((state) => state.searchQuery)
```

### Immer not working as expected?

Remember that Immer works with plain objects/arrays. Don't mix mutative and immutative patterns:
```typescript
// ❌ Don't mix patterns
set((state) => {
  state.revealedSecrets[id] = { value, loading }
  return state // Don't return - Immer handles this
})

// ✅ Just mutate
set((state) => {
  state.revealedSecrets[id] = { value, loading }
})
```

## References

- [Zustand Documentation](https://github.com/pmndrs/zustand)
- [Immer Documentation](https://immerjs.github.io/immer/)
- [Zustand Immer Middleware](https://github.com/pmndrs/zustand#immer-middleware)