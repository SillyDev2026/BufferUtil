# BufferUtil

**Fast, compact binary serialization for Roblox Luau.**

BufferUtil is a **single ModuleScript** built for networking, serialization, custom number systems, bit packing, compact storage, and high-performance Roblox systems.

It combines a simple `Writer` / `Reader` workflow with advanced integer widths, compact floats, VarInts, bit cursors, layouts, Roblox datatype codecs, compaction, Base64, and debugging utilities.

> **Version:** `4.7.1`  
> **API:** `4`  
> **Runtime:** Roblox Luau

---

## Features

| | |
|---|---|
| ⚡ Fast Reader / Writer hot paths | Automatic Writer growth |
| 📦 Single ModuleScript | No dependency tree |
| 🔢 1–53 bit exact integers | `u24/u40/u48/u53` |
| 🧮 Compact floats | `f8/f16/bf16/f24/f40/f48` |
| 🧱 Compiled layouts | Struct-like binary records |
| 🧩 VarUInt / VarInt / VarString | Compact dynamic values |
| 🎯 ByteCursor / BitCursor | Bit-level packing |
| 🗜️ Buffer compaction | Trim unused capacity |
| 🎮 Roblox datatypes | Vector3, CFrame, Color3, etc. |
| 🔍 Debug utilities | Hex, binary, Base64, diff, inspect |

---

## Installation

Create one ModuleScript:

```text
ReplicatedStorage
└── BufferUtil
```

Require it:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BufferUtil = require(ReplicatedStorage.BufferUtil)
```

That's it.

---

## Quick Start

```lua
local BufferUtil = require(game.ReplicatedStorage.BufferUtil)

local writer = BufferUtil.writer()

writer:WriteUInt8(5)
writer:WriteUInt32(1_000_000)
writer:WriteFloat64(math.pi)
writer:WriteVector3(Vector3.new(10, 20, 30))

local packet = writer:Finish()

local reader = BufferUtil.reader(packet)

print(reader:ReadUInt8())
print(reader:ReadUInt32())
print(reader:ReadFloat64())
print(reader:ReadVector3())
```

The Writer grows automatically. `Finish()` returns only the bytes actually written.

---

## Writer / Reader

### Writer

```lua
local writer = BufferUtil.writer()
```

Optional initial capacity:

```lua
local writer = BufferUtil.writer(128)
```

Native methods:

```lua
writer:WriteInt8(-10)
writer:WriteUInt8(255)

writer:WriteInt16(-1000)
writer:WriteUInt16(50000)

writer:WriteInt32(-1_000_000)
writer:WriteUInt32(4_000_000_000)

writer:WriteFloat32(123.5)
writer:WriteFloat64(math.pi)
```

Short aliases:

```lua
writer:WriteI8(-10)
writer:WriteU8(255)
writer:WriteI16(-1000)
writer:WriteU16(50000)
writer:WriteI32(-1_000_000)
writer:WriteU32(4_000_000_000)
writer:WriteF32(123.5)
writer:WriteF64(math.pi)
```

### Reader

```lua
local reader = BufferUtil.reader(packet)

local id = reader:ReadUInt32()
local value = reader:ReadFloat64()
local position = reader:ReadVector3()
```

Short aliases:

```lua
reader:ReadU32()
reader:ReadF64()
reader:ReadVector3()
```

---

## Numeric Formats

### Integers

| Type | Bytes | Bits |
|---|---:|---:|
| `i8 / u8` | 1 | 8 |
| `i16 / u16` | 2 | 16 |
| `i24 / u24` | 3 | 24 |
| `i32 / u32` | 4 | 32 |
| `i40 / u40` | 5 | 40 |
| `i48 / u48` | 6 | 48 |
| `i53 / u53` | 7 | 53 |

```lua
writer:WriteU24(15_000_000)
writer:WriteU53(9_000_000_000_000)
```

BufferUtil also supports exact integer bit widths from **1 to 53 bits**.

### Floating Point

| Type | Bytes | Format |
|---|---:|---|
| `f8e4m3` | 1 | 1 / 4 / 3 |
| `f8e5m2` | 1 | 1 / 5 / 2 |
| `f16` | 2 | 1 / 5 / 10 |
| `bf16` | 2 | 1 / 8 / 7 |
| `f24` | 3 | 1 / 8 / 15 |
| `f32` | 4 | Native |
| `f40` | 5 | 1 / 8 / 31 |
| `f48` | 6 | 1 / 11 / 36 |
| `f64` | 8 | Native |

```lua
writer:WriteF16(87.5)
writer:WriteF48(123456.789)
```

Compact float formats trade precision for smaller payloads.

---

## Variable-Length Codecs

### VarUInt

```lua
writer:WriteVarUInt(5)
writer:WriteVarUInt(500)
writer:WriteVarUInt(1_000_000)

local value = reader:ReadVarUInt()
```

### VarInt

```lua
writer:WriteVarInt(-50)
writer:WriteVarInt(50)

local value = reader:ReadVarInt()
```

Signed values use ZigZag encoding.

### VarString

```lua
writer:WriteVarString("Hello")

local text = reader:ReadVarString()
```

`"Hello"` uses:

```text
1 B length
5 B payload
---------
6 B total
```

---

## Roblox Datatypes

Direct codecs include:

- `Vector2`
- `Vector3`
- `Color3`
- compact `Color3u8`
- `UDim`
- `UDim2`
- `Rect`
- `NumberRange`
- `CFrame`
- `BrickColor`

```lua
writer:WriteVector3(Vector3.new(1, 2, 3))
writer:WriteColor3(Color3.fromRGB(255, 100, 25))
writer:WriteCFrame(CFrame.new(10, 20, 30))
```

```lua
local position = reader:ReadVector3()
local color = reader:ReadColor3()
local cf = reader:ReadCFrame()
```

Generic datatype writing is also available:

```lua
writer:WriteDataType(Vector3.new(1, 2, 3))
```

For hot paths, prefer the dedicated method.

---

## Bit Packing

```lua
local buff = BufferUtil.new(16)
local cur = BufferUtil.bitCursor(buff)

BufferUtil.writeUintBitsNext(cur, 13, 5000)
BufferUtil.writeUintBitsNext(cur, 20, 900000)
BufferUtil.writeUintBitsNext(cur, 20, 800000)
```

That stores exactly:

```text
13 + 20 + 20 = 53 bits
```

Compact it:

```lua
local compact = BufferUtil.compact(cur)

print(buffer.len(compact))
-- 7
```

Because:

```text
ceil(53 / 8) = 7 bytes
```

---

## Direct Buffer Access

```lua
local buff = BufferUtil.new(16)

BufferUtil.writei8(buff, 0, 1)
BufferUtil.writef64(buff, 1, 123.456)

local sign = BufferUtil.readi8(buff, 0)
local value = BufferUtil.readf64(buff, 1)
```

Generic form:

```lua
BufferUtil.write(buff, "u32", 0, 500)

local value = BufferUtil.read(buff, "u32", 0)
```

For hot paths, prefer dedicated typed methods.

---

<details>
<summary><strong>Cursor API</strong></summary>

```lua
local buff = BufferUtil.new(32)
local cur = BufferUtil.cursor(buff)

BufferUtil.writeNext(cur, "u32", 500)
BufferUtil.writeNext(cur, "f64", 99.9)

BufferUtil.reset(cur)

local id = BufferUtil.readNext(cur, "u32")
local value = BufferUtil.readNext(cur, "f64")
```

ByteCursor and BitCursor are kept separate to prevent accidental cross-use.

</details>

---

<details>
<summary><strong>Compiled Layouts</strong></summary>

```lua
local Layout = BufferUtil.compileLayout({
	{ name = "Sign", type = "i8" },
	{ name = "Value", type = "f64" },
	{ name = "Exponent", type = "i32" },
})

local buff = BufferUtil.structNew(Layout)
```

Useful for:

- fixed packet layouts
- ECS components
- custom number systems
- binary save formats
- compact runtime records

</details>

---

<details>
<summary><strong>Writer / Reader Management</strong></summary>

Writer:

```lua
print(writer:Tell())
print(writer:Length())
print(writer:Capacity())
print(writer:Remaining())

writer:EnsureCapacity(128)
writer:Seek(4)
writer:Skip(8)
writer:Reset()
writer:Clear()

local backing = writer:GetBuffer()
local packet = writer:Finish()
```

Reader:

```lua
print(reader:Tell())
print(reader:Remaining())

reader:Seek(8)
reader:Skip(4)
reader:Reset()

if reader:CanRead(8) then
	-- safe to read
end

local value = reader:PeekU32()
```

</details>

---

<details>
<summary><strong>Compaction</strong></summary>

Raw buffer:

```lua
local compact = BufferUtil.compact(buff, 53)
```

BitCursor:

```lua
local compact = BufferUtil.compact(bitCursor)
```

Byte Cursor:

```lua
local compact = BufferUtil.compact(cursor)
```

BufferUtil does **not** scan for arbitrary zero bits.

Zero bits can be valid data.

Compaction only removes unused trailing capacity.

Stats:

```lua
local stats = BufferUtil.compactStats(bitCursor)

print(stats.originalBytes)
print(stats.usedBits)
print(stats.compactBytes)
print(stats.paddingBits)
print(stats.savedBytes)
print(stats.percentSaved)
```

</details>

---

<details>
<summary><strong>Hex / Binary / Base64 / Debugging</strong></summary>

Hex:

```lua
local hex = BufferUtil.toHex(buff)
local restored = BufferUtil.fromHex("DE AD BE EF")
```

Binary:

```lua
local binary = BufferUtil.toBinaryString(buff)
```

Dumps:

```lua
print(BufferUtil.hexDump(buff))
print(BufferUtil.binaryDump(buff))
```

Base64:

```lua
local encoded = BufferUtil.base64Encode(buff)
local decoded = BufferUtil.base64Decode(encoded)
```

Inspect:

```lua
print(BufferUtil.inspect(buff))
```

Diff:

```lua
local differences = BufferUtil.diff(a, b)
local byteDifferences = BufferUtil.diffBytes(a, b)
```

</details>

---

<details>
<summary><strong>Buffer Utilities</strong></summary>

```lua
local section = BufferUtil.slice(buff, 4, 8)

local copy = BufferUtil.clone(buff)

local bits = BufferUtil.cloneBits(buff, 53)

local resized = BufferUtil.resize(buff, 128)

local joined = BufferUtil.concat({
	header,
	payload,
	footer,
})

BufferUtil.fillRange(buff, 0, 8, 0xFF)

BufferUtil.copy(destination, 0, source, 0, 8)
```

</details>

---

## Size Utilities

```lua
local a = BufferUtil.new(4, "KB")
local b = BufferUtil.new(2, "MB")
```

Supported units:

```text
b / B
Kb / KB
Mb / MB
Gb / GB
```

Formatting:

```lua
print(BufferUtil.formatBytes(1536))
-- 1.5 KB

print(BufferUtil.formatBits(1024))
-- 1 Kb

print(BufferUtil.formatBuffer(buffer.create(4096)))
-- 4 KB

print(BufferUtil.formatTypeSize("u53"))
-- 7 B (53 b data + 3 b padding)
```

---

## Performance

BufferUtil uses:

```lua
--!strict
--!native
--!optimize 2
```

v4.7.1 introduced dedicated native Writer / Reader hot paths.

### Actual-game benchmark

```text
100,000 iterations
10,000 warmup iterations
7 rounds
Roblox game/client environment
```

| Operation | v4.7.1 |
|---|---:|
| Write U8 | ~66 ns/op |
| Write I16 | ~65 ns/op |
| Write U32 | ~66 ns/op |
| Write F32 | ~60 ns/op |
| Write F64 | ~63 ns/op |
| Read U8 | ~27 ns/op |
| Read I16 | ~27 ns/op |
| Read U32 | ~27 ns/op |
| Read F32 | ~27 ns/op |
| Read F64 | ~27 ns/op |
| Write raw string | ~106 ns/op |
| Read raw string | ~64 ns/op |
| Write Vector3 | ~78 ns/op |
| WriteDataType Vector3 | ~187 ns/op |
| Auto-grow packet | ~947 ns/op |

Performance varies by hardware, Roblox runtime version, execution context, and JIT state.

> Development comparisons used a clean-room Sleitnick-style compatibility module, **not** Sleitnick's official implementation. Those results should not be presented as official Sleitnick benchmark results.

---

## Why Dedicated Methods Matter

Generic:

```lua
writer:Write("u32", 500)
```

Dedicated:

```lua
writer:WriteU32(500)
```

The dedicated form avoids generic type dispatch.

Same idea for datatypes:

```lua
writer:WriteDataType(position)
```

versus:

```lua
writer:WriteVector3(position)
```

Use the dedicated method in hot paths.

---

## Example Network Packet

```lua
local writer = BufferUtil.writer()

writer:WriteU8(1)
writer:WriteVarUInt(12345)
writer:WriteVector3(Vector3.new(10, 20, 30))
writer:WriteF16(95.5)
writer:WriteVarString("Player")

local packet = writer:Finish()
```

Read it:

```lua
local reader = BufferUtil.reader(packet)

local packetType = reader:ReadU8()
local entityId = reader:ReadVarUInt()
local position = reader:ReadVector3()
local health = reader:ReadF16()
local name = reader:ReadVarString()
```

---

## Safety

BufferUtil validates important public API boundaries, including:

- buffer ranges
- integer widths
- numeric ranges
- cursor identity
- variable-length encodings
- layouts
- compaction lengths

Optimized native Reader / Writer paths avoid repeated generic dispatch while preserving important checks.

```lua
writer:WriteU8(256)
```

fails instead of silently truncating.

---

## Design Goals

**Performance** — keep common operations close to native buffer speed.

**Compactness** — use only the bytes or bits your protocol needs.

**Safety** — avoid silent corruption where practical.

**Control** — expose exact widths and binary layouts.

**Composability** — work well inside networking, ECS, storage, and numeric systems.

**One-module deployment** — no dependency tree required.

---

## Good Use Cases

- custom networking
- binary serialization
- compact RemoteEvent payloads
- custom number systems
- NetStream-style protocols
- ECS storage
- entity replication
- save formats
- bit fields
- packed metadata

---

## License

MIT License.

Use, modify, and distribute under the terms of the MIT License.

Software is provided without warranty.

---

## Author

Created by **SillyDev2026**.
