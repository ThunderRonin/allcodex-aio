---
name: schema-drift
description: Detect Zod schema mismatches between Portal allknower-schemas.ts and AllKnower response-schemas.ts. Run after changing AllKnower pipeline response shapes.
model: sonnet
---

# Cross-Service Schema Drift Detector

Portal validates AllKnower responses with Zod schemas in `allcodex-portal/lib/allknower-schemas.ts`. These must match the actual response shapes defined in `allknower/src/pipeline/schemas/response-schemas.ts` and the route handlers. Mismatches cause false 502s at runtime.

## Steps

1. Read Portal schemas:
   ```
   allcodex-portal/lib/allknower-schemas.ts
   ```

2. Read AllKnower source-of-truth schemas:
   ```
   allknower/src/pipeline/schemas/response-schemas.ts
   ```

3. For each matching schema pair, compare:
   - Field names (exact match required)
   - Field types (string vs number vs enum values)
   - Optional vs required (`.optional()` / `.nullable()`)
   - Array element types
   - Nested object shapes
   - Enum/union values

4. Also check route handlers for inline response shapes not captured in response-schemas.ts:
   ```
   allknower/src/routes/brain-dump.ts
   allknower/src/routes/copilot.ts
   allknower/src/routes/suggest.ts
   allknower/src/routes/consistency.ts
   allknower/src/routes/config.ts
   ```

## Output format

```
SchemaName.fieldName — portal: type, allknower: type
SchemaName — portal missing field: fieldName (required in allknower)
SchemaName — allknower removed field: fieldName (still expected by portal)
```

If no drift: `All schemas aligned.`
