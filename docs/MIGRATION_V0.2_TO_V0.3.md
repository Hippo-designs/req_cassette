# Migration Guide: v0.2 → v0.3

This guide helps you upgrade from ReqCassette v0.2 to v0.3.

## Overview

v0.3.0 is a **breaking change release** that simplifies the recording mode API
by consolidating `:record` and `:record_missing` into a single, safer `:record`
mode.

## Breaking Changes

### Recording Modes: 4 → 3

**v0.2.0 (Old) - 4 modes:**

- `:record_missing` (default) - Record if missing, otherwise replay
- `:record` - ⚠️ Always hit network and **overwrite entire cassette on each
  request**
- `:replay` - Only replay
- `:bypass` - Always hit network, never save

**v0.3.0 (New) - 3 modes:**

- `:record` (default) - Record if cassette/interaction missing, otherwise replay
- `:replay` - Only replay
- `:bypass` - Always hit network, never save

### What Changed?

#### 1. `:record_missing` Removed

The `:record_missing` mode has been removed. Use `:record` instead.

**Before (v0.2):**

```elixir
with_cassette "api_call", [mode: :record_missing], fn plug ->
  Req.get!("https://api.example.com/data", plug: plug)
end
```

**After (v0.3):**

```elixir
with_cassette "api_call", [mode: :record], fn plug ->
  Req.get!("https://api.example.com/data", plug: plug)
end

# Or omit mode entirely (defaults to :record)
with_cassette "api_call", fn plug ->
  Req.get!("https://api.example.com/data", plug: plug)
end
```

#### 2. `:record` Behavior Changed

The `:record` mode **no longer overwrites the entire cassette on each request**.
Instead, it now appends new interactions (the old `:record_missing` behavior).

**Before (v0.2):**

```elixir
# ⚠️ Old :record mode - DANGEROUS for multi-request tests
with_cassette "test", [mode: :record], fn plug ->
  Req.get!("/api/1", plug: plug)  # Cassette: [interaction 1]
  Req.get!("/api/2", plug: plug)  # Cassette: [interaction 2] (lost #1!)
end
# Result: Only the last request saved ❌
```

**After (v0.3):**

```elixir
# ✅ New :record mode - Safe for multi-request tests
with_cassette "test", [mode: :record], fn plug ->
  Req.get!("/api/1", plug: plug)  # Cassette: [interaction 1]
  Req.get!("/api/2", plug: plug)  # Cassette: [interaction 1, 2]
end
# Result: All requests saved ✅
```

#### 3. Default Mode Changed

The default mode is still `:record`, but its behavior now matches the old
`:record_missing` mode.

## Migration Steps

### Step 1: Update Dependency

Update `mix.exs`:

```elixir
def deps do
  [
    {:req, "~> 0.5.15"},
    {:req_cassette, "~> 0.3.0"}  # was: "~> 0.2.0"
  ]
end
```

Run:

```bash
mix deps.update req_cassette
```

### Step 2: Replace `:record_missing` with `:record`

**Automated approach:**

```bash
# Replace in all test files
find test -name "*.exs" -type f -exec sed -i.bak 's/mode: :record_missing/mode: :record/g' {} +
find test -name "*.exs.bak" -type f -delete
```

**Manual approach:**

Search your codebase for `record_missing` and replace with `record`:

```elixir
# Before
with_cassette "test", [mode: :record_missing], fn plug ->

# After
with_cassette "test", [mode: :record], fn plug ->
```

### Step 3: Verify Tests

Run your test suite:

```bash
mix test
```

All tests should pass without changes. The new `:record` mode behaves
identically to the old `:record_missing` mode.

## Re-recording Cassettes

If you need to re-record a cassette (the old `:record` mode use case), manually
delete the cassette file first:

**Before (v0.2):**

```elixir
# Force re-record by using :record mode
with_cassette "api_call", [mode: :record], fn plug ->
  Req.get!("https://api.example.com/data", plug: plug)
end
```

**After (v0.3):**

```elixir
# Delete cassette first, then record with :record mode
File.rm!("test/cassettes/api_call.json")

with_cassette "api_call", [mode: :record], fn plug ->
  Req.get!("https://api.example.com/data", plug: plug)
end
```

Or from the command line:

```bash
# Delete all cassettes
rm -rf test/cassettes/*.json

# Re-run tests to re-record
mix test
```

## Why This Change?

### Problem: Old `:record` Mode Was Dangerous

The old `:record` mode had a critical flaw:

1. It **overwrote the entire cassette on each HTTP request**
2. For multi-request tests, only the **last request was saved**
3. This was a **silent failure** that confused users
4. It was documented with warnings, but still error-prone

### Solution: Consolidate Into One Safe Mode

v0.3.0 fixes this by:

1. **Removing** the dangerous `:record` mode behavior
2. **Renaming** the safe `:record_missing` behavior to `:record`
3. **Simplifying** the API: 3 modes instead of 4
4. **Eliminating** an entire class of bugs

### Benefits

✅ **Safer** - No more accidentally overwriting multi-request cassettes ✅
**Simpler** - Fewer modes to understand ✅ **Clearer** - No warnings needed
about multi-request tests ✅ **More explicit** - To re-record, delete cassette
first (no silent overwrites)

## Summary

**Mode mapping:**

| v0.2 Mode         | v0.3 Mode | Notes                                     |
| ----------------- | --------- | ----------------------------------------- |
| `:record_missing` | `:record` | Exact same behavior                       |
| `:record`         | (removed) | Delete cassette first, then use `:record` |
| `:replay`         | `:replay` | No change                                 |
| `:bypass`         | `:bypass` | No change                                 |

**Quick migration checklist:**

- [ ] Update `mix.exs` to `req_cassette ~> 0.3.0`
- [ ] Replace all `:record_missing` with `:record`
- [ ] Run tests to verify everything works
- [ ] Update any scripts/docs that reference modes

That's it! Your tests should continue to work exactly as before.

## Getting Help

If you run into issues:

1. Check the
   [CHANGELOG](https://github.com/lostbean/req_cassette/blob/main/CHANGELOG.md)
2. Review
   [examples](https://github.com/lostbean/req_cassette/tree/main/examples)
3. Open an issue on [GitHub](https://github.com/lostbean/req_cassette/issues)
