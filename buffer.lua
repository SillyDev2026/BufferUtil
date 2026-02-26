--!native
--!optimize 2

--[[
    created by SillyDev2026
    Buffer Utility Module (Luau / Roblox)

    Purpose:
    - Provide fast, low-level helpers for working with Roblox buffers
    - Support typed reads/writes (i8, u8, i16, u16, i32, u32, f32, f64)
    - Support sequential cursor-based access with automatic advancement
    - Support compiled layouts (struct-like buffers) with named fields
    - Slice, clone, reverse, fill, and compare buffers
    - Convert buffers to hex or binary strings for debugging
    - Efficient for hot paths and memory-sensitive systems
    - Fully optimized for --!native and --!optimize 2

    Design Philosophy:
    - Unsafe by design (no bounds checks)
    - Predictable constant-time operations
    - Composable for building higher-level serializers, ECS storage, or numeric systems

    This module is intended for:
    - Serialization and binary packet building
    - Custom numeric systems (BN, layered numbers, scientific)
    - ECS / archetype storage
    - Networking or performance-critical data formats

    Caller is responsible for buffer size, offsets, and type correctness.
]]

local module = {}
export type IntType = "i8"|"u8"|"i16"|"u16"|"i32"|"u32"
export type FloatType = "f32"|"f64"
export type ValueType = IntType | FloatType

module.Size = {
	i8  = 1,  u8  = 1,
	i16 = 2,  u16 = 2,
	i32 = 4,  u32 = 4,
	f32 = 4,
	f64 = 8,
}

--[[ Creates a new buffer with a fixed byte size
Example: module.new(12)
-- 1 byte i8 + 8 bytes f64 + 3 bytes padding
]]
function module.new(size: number): buffer
	return buffer.create(size)
end

-- Returns the length of a buffer in bytes
function module.len(buff: buffer): number
	return buffer.len(buff)
end

-- Zero-fills the entire buffer
function module.clear(buff: buffer): ()
	buffer.fill(buff, 0, 0, buffer.len(buff))
end

-- Copies raw bytes between buffers
function module.copy(dst: buffer, doff: number, src: buffer, soff: number, len: number): ()
	buffer.copy(dst, doff, src, soff, len)
end

--[[ Writes a value of the given type at a byte offset.
	⚠ No bounds checking.
	⚠ Caller must ensure offset + sizeof(type) is valid.
]]
function module.write(buff: buffer, typ: ValueType, off: number, val: any)
	if typ == "i8" then buffer.writei8(buff, off, val)
	elseif typ == "u8" then buffer.writeu8(buff, off, val)
	elseif typ == "i16" then buffer.writei16(buff, off, val)
	elseif typ == "u16" then buffer.writeu16(buff, off, val)
	elseif typ == "i32" then buffer.writei32(buff, off, val)
	elseif typ == "u32" then buffer.writeu32(buff, off, val)
	elseif typ == "f32" then buffer.writef32(buff, off, val)
	elseif typ == "f64" then buffer.writef64(buff, off, val)
	end
end

--[[ Reads a value of the given type at a byte offset.
	⚠ No bounds checking.
]]
function module.read(buff: buffer, typ: ValueType, off: number)
	if typ == "i8" then return buffer.readi8(buff, off)
	elseif typ == "u8" then return buffer.readu8(buff, off)
	elseif typ == "i16" then return buffer.readi16(buff, off)
	elseif typ == "u16" then return buffer.readu16(buff, off)
	elseif typ == "i32" then return buffer.readi32(buff, off)
	elseif typ == "u32" then return buffer.readu32(buff, off)
	elseif typ == "f32" then return buffer.readf32(buff, off)
	elseif typ == "f64" then return buffer.readf64(buff, off)
	end
end

--[[ Creates a cursor object for sequential reading/writing.
	The cursor tracks a mutable byte position.
]]
function module.cursor(buff: buffer, pos: number): {buff: buffer, pos: number}
	return {buff = buff, pos = pos}
end

--[[ Writes a value at the cursor position
	and automatically advances the cursor.
	Used for sequential packing.
]]
function module.writeNext(cur, typ: ValueType, val: any)
	local p = cur.pos
	if typ == "i8" then
		buffer.writei8(cur.buff, p, val)
		cur.pos = p + 1
	elseif typ == "u8" then
		buffer.writeu8(cur.buff, p, val)
		cur.pos = p + 1
	elseif typ == "i16" then
		buffer.writei16(cur.buff, p, val)
		cur.pos = p + 2
	elseif typ == "u16" then
		buffer.writeu16(cur.buff, p, val)
		cur.pos = p + 2
	elseif typ == "i32" then
		buffer.writei32(cur.buff, p, val)
		cur.pos = p + 4
	elseif typ == "u32" then
		buffer.writeu32(cur.buff, p, val)
		cur.pos = p + 4
	elseif typ == "f32" then
		buffer.writef32(cur.buff, p, val)
		cur.pos = p + 4
	elseif typ == "f64" then
		buffer.writef64(cur.buff, p, val)
		cur.pos = p + 8
	end
end

--[[ Reads a value at the cursor position
	and automatically advances the cursor.
]]
function module.readNext(cur, typ: ValueType)
	local p = cur.pos
	if typ == "i8" then
		cur.pos = p + 1
		return buffer.readi8(cur.buff, p)
	elseif typ == "u8" then
		cur.pos = p + 1
		return buffer.readu8(cur.buff, p)
	elseif typ == "i16" then
		cur.pos = p + 2
		return buffer.readi16(cur.buff, p)
	elseif typ == "u16" then
		cur.pos = p + 2
		return buffer.readu16(cur.buff, p)
	elseif typ == "i32" then
		cur.pos = p + 4
		return buffer.readi32(cur.buff, p)
	elseif typ == "u32" then
		cur.pos = p + 4
		return buffer.readu32(cur.buff, p)
	elseif typ == "f32" then
		cur.pos = p + 4
		return buffer.readf32(cur.buff, p)
	elseif typ == "f64" then
		cur.pos = p + 8
		return buffer.readf64(cur.buff, p)
	end
end

-- Returns the byte size of a given primitive type
function module.sizeOf(typ: ValueType): number
	return module.Size[typ]
end

-- useful for padding or skipping fields
function module.advanced(cur, typ: ValueType)
	cur.pos = cur.pos + module.Size[typ]
end

--[[ Compiles a layout into fixed offsets.
	Input:
		{ "i8", "f64", "i32" }
	Output:
		{
			size = total byte size,
			off = { [1]=0, [2]=1, [3]=9 }
		}
	Run once, reuse forever.
]]
function module.compileLayout(lay): {size: number, off: {[string]: number}}
	local off = {}
	local cursor = 0
	for i = 1, #lay do
		local f = lay[i]
		off[f] = cursor
		cursor = cursor + module.Size[f]
	end
	return {size = cursor, off = off}
end

-- Creates a buffer sized exactly for a compiled layout
function module.structNew(lay)
	assert(lay.size, "Layout must be compiled with module.compileLayout first")
	return buffer.create(lay.size)
end

-- Reads a field from a structured buffer
function module.structGet(buff: buffer, lay, field, typ: ValueType)
	return module.read(buff, typ, lay.off[field])
end

-- Writes a field into a structured buffer
function module.structSet(buff: buffer, lay, field, typ: ValueType, val: any)
	module.write(buff, typ, lay.off[field], val)
end

-- Slices a buffer into a new buffer (fast, zero copy if possible)
function module.slice(buff: buffer, start: number, len: number): buffer
	local out = buffer.create(len)
	buffer.copy(out, 0, buff, start, len)
	return out
end

-- fill a range of buffer with a single value
function module.fillRange(buff: buffer, start: number, len: number, val: number)
	for i = 0, len - 1 do
		buffer.writeu8(buff, start + i, val)
	end
end

-- Reverse the bytes in a buffer
function module.reverse(buff: buffer): ()
	local len = buffer.len(buff)
	for i = 0, (len // 2) - 1 do
		local a = buffer.readu8(buff, i)
		local b = buffer.readu8(buff, len - i - 1)
		buffer.writeu8(buff, i, b)
		buffer.writeu8(buff, len - i - 1, a)
	end
end

-- Compare two buffers (returns -1 if a < b, 0 if equal, 1 if a > b)
function module.compare(a: buffer, b: buffer): number
	local len = math.min(buffer.len(a), buffer.len(b))
	for i = 0, len - 1 do
		local va = buffer.readu8(a, i)
		local vb = buffer.readu8(b, i)
		if va < vb then return -1 end
		if va > vb then return 1 end
	end
	if buffer.len(a) < buffer.len(b) then return -1
	elseif buffer.len(a) > buffer.len(b) then return 1
	end
	return 0
end

-- Clone a buffer
function module.clone(buff: buffer): buffer
	local out = buffer.create(buffer.len(buff))
	buffer.copy(out, 0, buff, 0, buffer.len(buff))
	return out
end

-- Convert a numeric buffer to hex string (useful for debugging)
function module.toHex(buff: buffer): string
	local s = {}
	for i = 0, buffer.len(buff) - 1 do
		s[i + 1] = string.format('%02X', buffer.readu8(buff, i))
	end
	return table.concat(s)
end

-- Convert a buffer to binary string (debugging or serialization)
function module.toBinaryString(buff: buffer): string
	local s = {}
	for i = 0, buffer.len(buff)-1 do
		local byte = buffer.readu8(buff, i)
		local bin = ""
		for b = 7, 0, -1 do
			bin = bin .. (bit32.extract(byte, b) == 1 and "1" or "0")
		end
		s[i+1] = bin
	end
	return table.concat(s)
end

return module
