--!native
--!optimize 2

local BufferUtil = {}

BufferUtil.VERSION = "1.1.0"
BufferUtil.API_VERSION = 1
BufferUtil.COMPAT_API_VERSION = 1
BufferUtil.PATCH_VERSION = 1
BufferUtil.HOTFIX_VERSION = 1
BufferUtil.PERFORMANCE_VERSION = 1
BufferUtil.MAX_BUFFER_SIZE = 1_073_741_824
BufferUtil.MAX_BIT_WIDTH = 32
BufferUtil.MAX_EXACT_INT_BITS = 53
BufferUtil.SIZE_BASE = 1024
BufferUtil.BYTES_PER_KB = 1_024
BufferUtil.BYTES_PER_MB = 1_048_576
BufferUtil.BYTES_PER_GB = 1_073_741_824
BufferUtil.MAX_VAR_UINT_BYTES = 8

export type IntType =
	"i8" | "u8"
| "i16" | "u16"
| "i24" | "u24"
| "i32" | "u32"
| "i40" | "u40"
| "i48" | "u48"
| "i53" | "u53"

export type FloatType =
	"f8e4m3"
| "f8e5m2"
| "f16"
| "bf16"
| "f24"
| "f32"
| "f40"
| "f48"
| "f64"
export type ValueType = IntType | FloatType

export type ByteUnit = "B" | "KB" | "MB" | "GB" | "kB"
export type BitUnit = "b" | "Kb" | "Mb" | "Gb" | "kb" | "mb" | "gb"
export type SizeUnit = ByteUnit | BitUnit

export type Cursor = {
	buff: buffer,
	pos: number,
	_bufferUtilCursorKind: "byte"?,
}

export type BitCursor = {
	buff: buffer,
	bitPos: number,
	_bufferUtilCursorKind: "bit"?,
}

export type LayoutField = {
	name: string?,
	type: ValueType,
}

export type CompiledField = {
	name: string?,
	type: ValueType,
	offset: number,
	size: number,
}

export type CompiledLayout = {
	size: number,
	count: number,
	off: {[any]: number},
	type: {[any]: ValueType},
	fields: {CompiledField},
}

export type HexDumpOptions = {
	columns: number?,
	showAscii: boolean?,
	showOffset: boolean?,
	start: number?,
	count: number?,
}

export type BinaryDumpOptions = {
	columns: number?,
	showOffset: boolean?,
	start: number?,
	count: number?,
}

export type BufferDifference = {
	offset: number,
	a: number?,
	b: number?,
}

export type CompactInfo = {
	originalBytes: number,
	originalBits: number,
	usedBits: number,
	unusedBits: number,
	compactBytes: number,
	compactStorageBits: number,
	paddingBits: number,
	removedBits: number,
	savedBytes: number,
	percentSaved: number,
	efficiency: number,
}

local MAX_BUFFER_SIZE = BufferUtil.MAX_BUFFER_SIZE
local MAX_BIT_WIDTH = BufferUtil.MAX_BIT_WIDTH
local BYTES_PER_KB = BufferUtil.BYTES_PER_KB
local BYTES_PER_MB = BufferUtil.BYTES_PER_MB
local BYTES_PER_GB = BufferUtil.BYTES_PER_GB
local BITS_PER_KB = BYTES_PER_KB
local BITS_PER_MB = BYTES_PER_MB
local BITS_PER_GB = BYTES_PER_GB
local MAX_VAR_UINT_BYTES = BufferUtil.MAX_VAR_UINT_BYTES
local POW2_32 = 4_294_967_296
local SAFE_UINT_MAX = 9_007_199_254_740_991
local SAFE_SIGNED_53_MIN = -4_503_599_627_370_496
local SAFE_SIGNED_53_MAX = 4_503_599_627_370_495

BufferUtil.MAX_SAFE_UINT = SAFE_UINT_MAX
BufferUtil.MIN_SAFE_I53 = SAFE_SIGNED_53_MIN
BufferUtil.MAX_SAFE_I53 = SAFE_SIGNED_53_MAX

local SIZE: {[ValueType]: number} = {
	i8 = 1,
	u8 = 1,
	i16 = 2,
	u16 = 2,
	i24 = 3,
	u24 = 3,
	i32 = 4,
	u32 = 4,
	i40 = 5,
	u40 = 5,
	i48 = 6,
	u48 = 6,
	i53 = 7,
	u53 = 7,
	f8e4m3 = 1,
	f8e5m2 = 1,
	f16 = 2,
	bf16 = 2,
	f24 = 3,
	f32 = 4,
	f40 = 5,
	f48 = 6,
	f64 = 8,
}

BufferUtil.Size = table.freeze(SIZE)

BufferUtil.Units = table.freeze({
	bit = "b",
	byte = "B",
	kilobit = "Kb",
	kilobyte = "KB",
	megabit = "Mb",
	megabyte = "MB",
	gigabit = "Gb",
	gigabyte = "GB",
})

local HEX_LOOKUP = table.create(256)
local BINARY_LOOKUP = table.create(256)
local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local BASE64_ENCODE = table.create(64)
local BASE64_DECODE: {[string]: number} = {}

for index = 0, 63 do
	local ch = string.sub(BASE64_ALPHABET, index + 1, index + 1)
	BASE64_ENCODE[index + 1] = ch
	BASE64_DECODE[ch] = index
end

table.freeze(BASE64_ENCODE)
table.freeze(BASE64_DECODE)

for value = 0, 255 do
	HEX_LOOKUP[value + 1] = string.format("%02X", value)

	local chars = table.create(8)
	for bit = 7, 0, -1 do
		chars[8 - bit] = bit32.extract(value, bit) == 1 and "1" or "0"
	end
	BINARY_LOOKUP[value + 1] = table.concat(chars)
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function isInteger(value: any): boolean
	return isFiniteNumber(value) and value % 1 == 0
end

local CURSOR_KIND_FIELD = "_bufferUtilCursorKind"
local BYTE_CURSOR_KIND = "byte"
local BIT_CURSOR_KIND = "bit"

local function classifyCursorObject(value: any): string?
	if typeof(value) ~= "table" then
		return nil
	end

	local object = value :: any
	local tag = rawget(object, CURSOR_KIND_FIELD)
	if tag == BYTE_CURSOR_KIND or tag == BIT_CURSOR_KIND then
		return tag
	elseif tag ~= nil then
		return "invalid"
	end

	local hasPos = rawget(object, "pos") ~= nil
	local hasBitPos = rawget(object, "bitPos") ~= nil
	if hasPos and hasBitPos then
		return "ambiguous"
	elseif hasPos then
		return BYTE_CURSOR_KIND
	elseif hasBitPos then
		return BIT_CURSOR_KIND
	end

	return nil
end

local function cursorKindName(kind: string?): string
	if kind == BYTE_CURSOR_KIND then
		return "Cursor"
	elseif kind == BIT_CURSOR_KIND then
		return "BitCursor"
	elseif kind == "ambiguous" then
		return "ambiguous Cursor/BitCursor table"
	elseif kind == "invalid" then
		return "invalid tagged cursor"
	end
	return "non-cursor value"
end

local function assertNumber(value: any, label: string, level: number?)
	if type(value) ~= "number" then
		error(
			string.format("BufferUtil: %s must be a number, got %s", label, typeof(value)),
			level or 3
		)
	end
end

local function assertString(value: any, label: string, level: number?)
	if type(value) ~= "string" then
		error(
			string.format("BufferUtil: %s must be a string, got %s", label, typeof(value)),
			level or 3
		)
	end
end

local function assertBoolean(value: any, label: string, level: number?)
	if type(value) ~= "boolean" then
		error(
			string.format("BufferUtil: %s must be a boolean, got %s", label, typeof(value)),
			level or 3
		)
	end
end

local function assertNonNegativeNumber(value: any, label: string, level: number?)
	if not isFiniteNumber(value) or value < 0 then
		error(
			string.format("BufferUtil: %s must be a finite non-negative number, got %s", label, tostring(value)),
			level or 3
		)
	end
end

local function assertFormatDecimals(decimals: number?, level: number?): number
	local actual = if decimals == nil then 2 else decimals
	if not isInteger(actual) or actual < 0 or actual > 9 then
		error(
			string.format("BufferUtil: decimals must be an integer from 0 to 9, got %s", tostring(actual)),
			level or 3
		)
	end
	return actual
end

local function trimFormattedNumber(value: number, decimals: number): string
	if decimals == 0 then
		return string.format("%.0f", value)
	end

	local text = string.format("%." .. tostring(decimals) .. "f", value)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	if text == "-0" then
		return "0"
	end
	return text
end

local function normalizeSizeUnit(unit: string, level: number?): (string, boolean, number)
	if unit == "B" then
		return "B", true, 1
	elseif unit == "KB" or unit == "kB" then
		return "KB", true, BYTES_PER_KB
	elseif unit == "MB" then
		return "MB", true, BYTES_PER_MB
	elseif unit == "GB" then
		return "GB", true, BYTES_PER_GB
	elseif unit == "b" then
		return "b", false, 1
	elseif unit == "Kb" or unit == "kb" then
		return "Kb", false, BITS_PER_KB
	elseif unit == "Mb" or unit == "mb" then
		return "Mb", false, BITS_PER_MB
	elseif unit == "Gb" or unit == "gb" then
		return "Gb", false, BITS_PER_GB
	end

	error(
		string.format(
			'BufferUtil: invalid size unit %q; expected b/B, Kb/KB, Mb/MB, or Gb/GB',
			tostring(unit)
		),
		level or 3
	)
end

local function sizeToBits(value: number, unit: string, level: number?): number
	assertNonNegativeNumber(value, "size value", (level or 3) + 1)
	local _, isByteUnit, multiplier = normalizeSizeUnit(unit, (level or 3) + 1)

	local bits = if isByteUnit then value * multiplier * 8 else value * multiplier
	if not isFiniteNumber(bits) then
		error(
			string.format("BufferUtil: size conversion overflow for %s %s", tostring(value), tostring(unit)),
			level or 3
		)
	end

	return bits
end

local function sizeToWholeBytes(value: number, unit: string, level: number?): number
	local bits = sizeToBits(value, unit, (level or 3) + 1)
	local bytes = bits / 8

	if not isInteger(bytes) then
		error(
			string.format(
				"BufferUtil: %s %s does not resolve to a whole number of bytes",
				tostring(value),
				tostring(unit)
			),
			level or 3
		)
	end

	return bytes
end

local function selectByteDisplay(byteCount: number): (number, string)
	if byteCount >= BYTES_PER_GB then
		return byteCount / BYTES_PER_GB, "GB"
	elseif byteCount >= BYTES_PER_MB then
		return byteCount / BYTES_PER_MB, "MB"
	elseif byteCount >= BYTES_PER_KB then
		return byteCount / BYTES_PER_KB, "KB"
	end

	return byteCount, "B"
end

local function selectBitDisplay(bitCount: number): (number, string)
	if bitCount >= BITS_PER_GB then
		return bitCount / BITS_PER_GB, "Gb"
	elseif bitCount >= BITS_PER_MB then
		return bitCount / BITS_PER_MB, "Mb"
	elseif bitCount >= BITS_PER_KB then
		return bitCount / BITS_PER_KB, "Kb"
	end

	return bitCount, "b"
end

local function assertNonNegativeInteger(value: number, label: string, level: number?)
	if not isInteger(value) or value < 0 then
		error(
			string.format("BufferUtil: %s must be a non-negative integer, got %s", label, tostring(value)),
			level or 3
		)
	end
end

local function assertPositiveInteger(value: number, label: string, level: number?)
	if not isInteger(value) or value <= 0 then
		error(
			string.format("BufferUtil: %s must be a positive integer, got %s", label, tostring(value)),
			level or 3
		)
	end
end


local function assertSafeUnsignedInteger(value: any, label: string, level: number?)
	if not isInteger(value) or value < 0 or value > SAFE_UINT_MAX then
		error(
			string.format(
				"BufferUtil: %s must be an exact integer in range [0, %.0f], got %s",
				label,
				SAFE_UINT_MAX,
				tostring(value)
			),
			level or 3
		)
	end
end

local function assertSafeSignedInteger(value: any, label: string, level: number?)
	if not isInteger(value) or value < SAFE_SIGNED_53_MIN or value > SAFE_SIGNED_53_MAX then
		error(
			string.format(
				"BufferUtil: %s must be an exact integer in range [%.0f, %.0f], got %s",
				label,
				SAFE_SIGNED_53_MIN,
				SAFE_SIGNED_53_MAX,
				tostring(value)
			),
			level or 3
		)
	end
end

local function varUIntSizeUnsafe(value: number): number
	local size = 1
	local remaining = value

	while remaining >= 128 do
		remaining = math.floor(remaining / 128)
		size += 1
	end

	return size
end

local function zigZagEncode(value: number): number
	if value >= 0 then
		return value * 2
	end
	return (-value) * 2 - 1
end

local function zigZagDecode(value: number): number
	if value % 2 == 0 then
		return value / 2
	end
	return -((value + 1) / 2)
end

local function createExact(size: number): buffer
	assertNonNegativeInteger(size, "size", 3)

	if size > MAX_BUFFER_SIZE then
		error(
			string.format(
				"BufferUtil: size %d exceeds Roblox buffer limit of %d bytes",
				size,
				MAX_BUFFER_SIZE
			),
			3
		)
	end

	if size == 0 then
		return buffer.fromstring("")
	end

	return buffer.create(size)
end

local function sizeOfUnsafe(typ: ValueType): number
	local size = SIZE[typ]
	if size == nil then
		error(string.format("BufferUtil: invalid value type %q", tostring(typ)), 3)
	end
	return size
end

local function assertByteRange(buff: buffer, offset: number, count: number, level: number?)
	if typeof(buff) ~= "buffer" then
		error(
			string.format("BufferUtil: expected buffer, got %s", typeof(buff)),
			level or 3
		)
	end

	local length = buffer.len(buff)
	local validOffset = isInteger(offset)
	local validCount = isInteger(count)
	local rangeEnd = if validOffset and validCount then offset + count else nil
	local invalid = not validOffset or not validCount

	if not invalid then
		invalid = offset < 0 or count < 0 or (rangeEnd :: number) > length
	end

	if invalid then
		error(
			string.format(
				"BufferUtil: byte range [%s, %s) is outside buffer length %d",
				tostring(offset),
				if rangeEnd == nil then "?" else tostring(rangeEnd),
				length
			),
			level or 3
		)
	end
end

local function assertBytePosition(buff: buffer, position: number, level: number?)
	assertByteRange(buff, position, 0, (level or 3) + 1)
end

local function assertBitWidth(bitCount: number, level: number?)
	if not isInteger(bitCount) or bitCount < 0 or bitCount > MAX_BIT_WIDTH then
		error(
			string.format(
				"BufferUtil: bitCount must be an integer from 0 to %d, got %s",
				MAX_BIT_WIDTH,
				tostring(bitCount)
			),
			level or 3
		)
	end
end

local function assertBitRange(buff: buffer, bitOffset: number, bitCount: number, level: number?)
	if typeof(buff) ~= "buffer" then
		error(
			string.format("BufferUtil: expected buffer, got %s", typeof(buff)),
			level or 3
		)
	end

	local maxBits = buffer.len(buff) * 8
	local validOffset = isInteger(bitOffset)
	local validCount = isInteger(bitCount)
	local rangeEnd = if validOffset and validCount then bitOffset + bitCount else nil
	local invalid = not validOffset or not validCount

	if not invalid then
		invalid = bitOffset < 0 or bitCount < 0 or (rangeEnd :: number) > maxBits
	end

	if invalid then
		error(
			string.format(
				"BufferUtil: bit range [%s, %s) is outside buffer bit length %d",
				tostring(bitOffset),
				if rangeEnd == nil then "?" else tostring(rangeEnd),
				maxBits
			),
			level or 3
		)
	end
end

local function assertBitPosition(buff: buffer, position: number, level: number?)
	assertBitRange(buff, position, 0, (level or 3) + 1)
end

local function assertCursorIdentity(value: any, expectedKind: string, level: number?): buffer
	local kind = classifyCursorObject(value)
	if kind ~= expectedKind then
		error(
			string.format(
				"BufferUtil: expected %s, got %s",
				cursorKindName(expectedKind),
				cursorKindName(kind)
			),
			level or 3
		)
	end

	local object = value :: any
	local buff = rawget(object, "buff")
	if typeof(buff) ~= "buffer" then
		error(
			string.format(
				"BufferUtil: %s.buff must be a buffer, got %s",
				cursorKindName(expectedKind),
				typeof(buff)
			),
			level or 3
		)
	end

	return buff
end

local function assertByteCursorPosition(value: any, level: number?): (buffer, number)
	local buff = assertCursorIdentity(value, BYTE_CURSOR_KIND, (level or 3) + 1)
	local position = rawget(value :: any, "pos")
	assertBytePosition(buff, position, (level or 3) + 1)
	return buff, position
end

local function assertBitCursorPosition(value: any, level: number?): (buffer, number)
	local buff = assertCursorIdentity(value, BIT_CURSOR_KIND, (level or 3) + 1)
	local position = rawget(value :: any, "bitPos")
	assertBitPosition(buff, position, (level or 3) + 1)
	return buff, position
end

local function assertExactBitWidth(bitCount: number, level: number?)
	if not isInteger(bitCount) or bitCount < 1 or bitCount > 53 then
		error(
			string.format("BufferUtil: exact integer bit width must be in range [1, 53], got %s", tostring(bitCount)),
			level or 3
		)
	end
end

local function unsignedMax(bitCount: number): number
	return 2 ^ bitCount - 1
end

local function signedMin(bitCount: number): number
	return -(2 ^ (bitCount - 1))
end

local function signedMax(bitCount: number): number
	return 2 ^ (bitCount - 1) - 1
end

local function writeUnsignedBitsExact(
	buff: buffer,
	bitOffset: number,
	bitCount: number,
	value: number,
	level: number?
)
	assertExactBitWidth(bitCount, (level or 3) + 1)
	assertBitRange(buff, bitOffset, bitCount, (level or 3) + 1)

	local maxValue = unsignedMax(bitCount)
	if not isInteger(value) or value < 0 or value > maxValue then
		error(
			string.format(
				"BufferUtil: u%d value must be an exact integer in range [0, %.0f], got %s",
				bitCount,
				maxValue,
				tostring(value)
			),
			level or 3
		)
	end

	if bitCount <= 32 then
		buffer.writebits(buff, bitOffset, bitCount, value)
		return
	end

	local low = value % POW2_32
	local high = math.floor(value / POW2_32)

	buffer.writebits(buff, bitOffset, 32, low)
	buffer.writebits(buff, bitOffset + 32, bitCount - 32, high)
end

local function readUnsignedBitsExact(
	buff: buffer,
	bitOffset: number,
	bitCount: number,
	level: number?
): number
	assertExactBitWidth(bitCount, (level or 3) + 1)
	assertBitRange(buff, bitOffset, bitCount, (level or 3) + 1)

	if bitCount <= 32 then
		return buffer.readbits(buff, bitOffset, bitCount)
	end

	local low = buffer.readbits(buff, bitOffset, 32)
	local high = buffer.readbits(buff, bitOffset + 32, bitCount - 32)
	return low + high * POW2_32
end

local function writeSignedBitsExact(
	buff: buffer,
	bitOffset: number,
	bitCount: number,
	value: number,
	level: number?
)
	assertExactBitWidth(bitCount, (level or 3) + 1)

	local minValue = signedMin(bitCount)
	local maxValue = signedMax(bitCount)

	if not isInteger(value) or value < minValue or value > maxValue then
		error(
			string.format(
				"BufferUtil: i%d value must be an exact integer in range [%.0f, %.0f], got %s",
				bitCount,
				minValue,
				maxValue,
				tostring(value)
			),
			level or 3
		)
	end

	local encoded = value
	if encoded < 0 then
		encoded += 2 ^ bitCount
	end

	writeUnsignedBitsExact(buff, bitOffset, bitCount, encoded, (level or 3) + 1)
end

local function readSignedBitsExact(
	buff: buffer,
	bitOffset: number,
	bitCount: number,
	level: number?
): number
	assertExactBitWidth(bitCount, (level or 3) + 1)

	local encoded = readUnsignedBitsExact(buff, bitOffset, bitCount, (level or 3) + 1)
	local signThreshold = 2 ^ (bitCount - 1)

	if encoded >= signThreshold then
		return encoded - 2 ^ bitCount
	end

	return encoded
end

local function roundToEven(value: number): number
	local floorValue = math.floor(value)
	local fraction = value - floorValue

	if fraction > 0.5 then
		return floorValue + 1
	elseif fraction < 0.5 then
		return floorValue
	end

	if floorValue % 2 == 0 then
		return floorValue
	end

	return floorValue + 1
end

local function isNegativeZero(value: number): boolean
	return value == 0 and 1 / value == -math.huge
end

local function encodeBinaryFloat(value: number, exponentBits: number, mantissaBits: number): number
	local exponentFieldMax = 2 ^ exponentBits - 1
	local mantissaScale = 2 ^ mantissaBits
	local signWeight = 2 ^ (exponentBits + mantissaBits)
	local bias = 2 ^ (exponentBits - 1) - 1

	local negative = value < 0 or isNegativeZero(value)
	local signBits = if negative then signWeight else 0

	if value ~= value then
		local quietMantissa = if mantissaBits > 0 then 2 ^ (mantissaBits - 1) else 1
		return signBits + exponentFieldMax * mantissaScale + quietMantissa
	end

	local magnitude = math.abs(value)

	if magnitude == math.huge then
		return signBits + exponentFieldMax * mantissaScale
	end

	if magnitude == 0 then
		return signBits
	end

	local minNormalExponent = 1 - bias
	local maxNormalExponent = exponentFieldMax - 1 - bias

	-- Avoid logarithm rounding around exact powers of two.
	local fraction, binaryExponent = math.frexp(magnitude)
	local exponent = binaryExponent - 1
	local normalized = fraction * 2

	if exponent > maxNormalExponent then
		return signBits + exponentFieldMax * mantissaScale
	end

	if exponent < minNormalExponent then
		local subnormalStep = math.ldexp(1, minNormalExponent - mantissaBits)
		local mantissa = roundToEven(magnitude / subnormalStep)

		if mantissa <= 0 then
			return signBits
		end

		if mantissa >= mantissaScale then
			return signBits + mantissaScale
		end

		return signBits + mantissa
	end

	local mantissa = roundToEven((normalized - 1) * mantissaScale)

	if mantissa >= mantissaScale then
		mantissa = 0
		exponent += 1

		if exponent > maxNormalExponent then
			return signBits + exponentFieldMax * mantissaScale
		end
	end

	local exponentField = exponent + bias
	return signBits + exponentField * mantissaScale + mantissa
end

local function decodeBinaryFloat(bits: number, exponentBits: number, mantissaBits: number): number
	local exponentFieldMax = 2 ^ exponentBits - 1
	local mantissaScale = 2 ^ mantissaBits
	local signWeight = 2 ^ (exponentBits + mantissaBits)
	local bias = 2 ^ (exponentBits - 1) - 1

	local negative = bits >= signWeight
	local body = bits % signWeight
	local exponentField = math.floor(body / mantissaScale)
	local mantissa = body - exponentField * mantissaScale

	if exponentField == exponentFieldMax then
		if mantissa == 0 then
			return if negative then -math.huge else math.huge
		end

		return math.huge - math.huge
	end

	if exponentField == 0 then
		if mantissa == 0 then
			return if negative then -1 / math.huge else 0
		end

		local value = math.ldexp(mantissa / mantissaScale, 1 - bias)
		return if negative then -value else value
	end

	local value = math.ldexp(1 + mantissa / mantissaScale, exponentField - bias)
	return if negative then -value else value
end

local FLOAT_FORMATS: {[string]: {bits: number, exponentBits: number, mantissaBits: number}} = {
	f8e4m3 = {bits = 8, exponentBits = 4, mantissaBits = 3},
	f8e5m2 = {bits = 8, exponentBits = 5, mantissaBits = 2},
	f16 = {bits = 16, exponentBits = 5, mantissaBits = 10},
	bf16 = {bits = 16, exponentBits = 8, mantissaBits = 7},
	f24 = {bits = 24, exponentBits = 8, mantissaBits = 15},
	f40 = {bits = 40, exponentBits = 8, mantissaBits = 31},
	f48 = {bits = 48, exponentBits = 11, mantissaBits = 36},
}

for _, formatInfo in FLOAT_FORMATS do
	table.freeze(formatInfo)
end
table.freeze(FLOAT_FORMATS)

local TYPE_INFO: {[string]: any} = {}

local function registerIntInfo(name: string, signed: boolean, bits: number, native: boolean)
	local bytes = (bits + 7) // 8

	TYPE_INFO[name] = table.freeze({
		kind = if signed then "int" else "uint",
		bits = bits,
		bytes = bytes,
		storageBits = bytes * 8,
		paddingBits = bytes * 8 - bits,
		signed = signed,
		native = native,
		min = if signed then signedMin(bits) else 0,
		max = if signed then signedMax(bits) else unsignedMax(bits),
	})
end

registerIntInfo("i8", true, 8, true)
registerIntInfo("u8", false, 8, true)
registerIntInfo("i16", true, 16, true)
registerIntInfo("u16", false, 16, true)
registerIntInfo("i24", true, 24, false)
registerIntInfo("u24", false, 24, false)
registerIntInfo("i32", true, 32, true)
registerIntInfo("u32", false, 32, true)
registerIntInfo("i40", true, 40, false)
registerIntInfo("u40", false, 40, false)
registerIntInfo("i48", true, 48, false)
registerIntInfo("u48", false, 48, false)
registerIntInfo("i53", true, 53, false)
registerIntInfo("u53", false, 53, false)

for name, formatInfo in FLOAT_FORMATS do
	local bias = 2 ^ (formatInfo.exponentBits - 1) - 1
	local maxNormalExponent = (2 ^ formatInfo.exponentBits - 2) - bias
	local minNormalExponent = 1 - bias
	local precisionBits = formatInfo.mantissaBits + 1

	TYPE_INFO[name] = table.freeze({
		kind = "float",
		bits = formatInfo.bits,
		bytes = formatInfo.bits // 8,
		storageBits = formatInfo.bits,
		paddingBits = 0,
		exponentBits = formatInfo.exponentBits,
		mantissaBits = formatInfo.mantissaBits,
		precisionBits = precisionBits,
		precisionDigits = precisionBits * math.log10(2),
		minNormal = math.ldexp(1, minNormalExponent),
		minSubnormal = math.ldexp(1, minNormalExponent - formatInfo.mantissaBits),
		maxFinite = math.ldexp(2 - 2 ^ (-formatInfo.mantissaBits), maxNormalExponent),
		supportsInf = true,
		supportsNaN = true,
		native = false,
	})
end

TYPE_INFO.f32 = table.freeze({
	kind = "float",
	bits = 32,
	bytes = 4,
	storageBits = 32,
	paddingBits = 0,
	exponentBits = 8,
	mantissaBits = 23,
	precisionBits = 24,
	precisionDigits = 24 * math.log10(2),
	minNormal = math.ldexp(1, -126),
	minSubnormal = math.ldexp(1, -149),
	maxFinite = math.ldexp(2 - 2 ^ -23, 127),
	supportsInf = true,
	supportsNaN = true,
	native = true,
})

TYPE_INFO.f64 = table.freeze({
	kind = "float",
	bits = 64,
	bytes = 8,
	storageBits = 64,
	paddingBits = 0,
	exponentBits = 11,
	mantissaBits = 52,
	precisionBits = 53,
	precisionDigits = 53 * math.log10(2),
	minNormal = math.ldexp(1, -1022),
	minSubnormal = math.ldexp(1, -1074),
	maxFinite = 1.7976931348623157e308,
	supportsInf = true,
	supportsNaN = true,
	native = true,
})

BufferUtil.TypeInfo = table.freeze(TYPE_INFO)

local function assertByteValue(value: number, level: number?)
	if not isInteger(value) or value < 0 or value > 255 then
		error(
			string.format("BufferUtil: byte value must be an integer from 0 to 255, got %s", tostring(value)),
			level or 3
		)
	end
end

local function assertTypedValue(typ: ValueType, value: number, level: number?)
	local info = TYPE_INFO[typ]
	if info == nil then
		error(string.format("BufferUtil: invalid value type %q", tostring(typ)), level or 3)
	end

	if type(value) ~= "number" then
		error(string.format("BufferUtil: %s value must be a number", tostring(typ)), level or 3)
	end

	if info.kind == "int" or info.kind == "uint" then
		if not isInteger(value) or value < info.min or value > info.max then
			error(
				string.format(
					"BufferUtil: %s value must be an integer in range [%.0f, %.0f], got %s",
					tostring(typ),
					info.min,
					info.max,
					tostring(value)
				),
				level or 3
			)
		end
	end
end

local function resolveLayoutField(
	lay: CompiledLayout,
	field: any,
	explicitType: ValueType?
): (number, ValueType)
	local offset = lay.off[field]
	if offset == nil then
		error(string.format("BufferUtil: unknown layout field %q", tostring(field)), 3)
	end

	local layoutType = lay.type[field]

	if explicitType ~= nil and layoutType ~= nil and explicitType ~= layoutType then
		error(
			string.format(
				"BufferUtil: type mismatch for field %q; layout is %s, requested %s",
				tostring(field),
				tostring(layoutType),
				tostring(explicitType)
			),
			3
		)
	end

	local typ = explicitType or layoutType
	if typ == nil then
		error(string.format("BufferUtil: layout field %q has no type", tostring(field)), 3)
	end

	return offset, typ
end

local function maskTrailingBits(buff: buffer, bitLength: number)
	local byteLength = (bitLength + 7) // 8
	local usedBitsInLastByte = bitLength % 8

	if byteLength == 0 or usedBitsInLastByte == 0 then
		return
	end

	local lastOffset = byteLength - 1
	local lastByte = buffer.readu8(buff, lastOffset)
	local keepMask = bit32.lshift(1, usedBitsInLastByte) - 1
	buffer.writeu8(buff, lastOffset, bit32.band(lastByte, keepMask))
end

local function compactInfoFor(buff: buffer, usedBits: number, level: number?): CompactInfo
	assertNonNegativeInteger(usedBits, "usedBits", (level or 3) + 1)

	local originalBytes = buffer.len(buff)
	local originalBits = originalBytes * 8
	if usedBits > originalBits then
		error(
			string.format(
				"BufferUtil: usedBits %d exceeds source capacity %d bits",
				usedBits,
				originalBits
			),
			level or 3
		)
	end

	local compactBytes = (usedBits + 7) // 8
	local compactStorageBits = compactBytes * 8
	local padding = compactStorageBits - usedBits
	local removedBits = originalBits - compactStorageBits
	local savedBytes = originalBytes - compactBytes
	local percentSaved = if originalBytes == 0 then 0 else savedBytes / originalBytes * 100
	local efficiency = if compactStorageBits == 0 then 100 else usedBits / compactStorageBits * 100

	return {
		originalBytes = originalBytes,
		originalBits = originalBits,
		usedBits = usedBits,
		unusedBits = originalBits - usedBits,
		compactBytes = compactBytes,
		compactStorageBits = compactStorageBits,
		paddingBits = padding,
		removedBits = removedBits,
		savedBytes = savedBytes,
		percentSaved = percentSaved,
		efficiency = efficiency,
	}
end

local function resolveCompactSource(source: any, usedBits: number?, level: number?): (buffer, number)
	local sourceKind = typeof(source)

	if sourceKind == "buffer" then
		if usedBits == nil then
			error(
				"BufferUtil: compact(buffer) requires usedBits; raw buffers do not record which trailing zero bits are meaningful data",
				level or 3
			)
		end
		compactInfoFor(source, usedBits, (level or 3) + 1)
		return source, usedBits
	end

	if sourceKind == "table" then
		local kind = classifyCursorObject(source)
		if kind == BIT_CURSOR_KIND or kind == BYTE_CURSOR_KIND then
			if usedBits ~= nil then
				error("BufferUtil: usedBits must be omitted when compacting a Cursor or BitCursor", level or 3)
			end
		end

		if kind == BIT_CURSOR_KIND then
			local buff, bitPos = assertBitCursorPosition(source, (level or 3) + 1)
			return buff, bitPos
		elseif kind == BYTE_CURSOR_KIND then
			local buff, pos = assertByteCursorPosition(source, (level or 3) + 1)
			return buff, pos * 8
		elseif kind == "ambiguous" then
			error(
				"BufferUtil: compact received an ambiguous cursor table containing both pos and bitPos",
				level or 3
			)
		elseif kind == "invalid" then
			error("BufferUtil: compact received a cursor with an invalid cursor tag", level or 3)
		end
	end

	error(
		string.format(
			"BufferUtil: compact expects a buffer + usedBits, Cursor, or BitCursor; got %s",
			sourceKind
		),
		level or 3
	)
end

function BufferUtil.new(size: number, unit: SizeUnit?): buffer
	if unit == nil then
		return createExact(size)
	end

	local byteCount = sizeToWholeBytes(size, unit, 2)
	return createExact(byteCount)
end

function BufferUtil.fromString(value: string): buffer
	assertString(value, "value", 2)
	local length = #value
	if length > MAX_BUFFER_SIZE then
		error(
			string.format(
				"BufferUtil: string length %d exceeds Roblox buffer limit of %d bytes",
				length,
				MAX_BUFFER_SIZE
			),
			2
		)
	end
	return buffer.fromstring(value)
end

function BufferUtil.toString(buff: buffer): string
	return buffer.tostring(buff)
end

function BufferUtil.fromHex(value: string): buffer
	assertString(value, "value", 2)
	local clean = string.gsub(value, "[%s:_%-]", "")

	if string.sub(clean, 1, 2) == "0x" or string.sub(clean, 1, 2) == "0X" then
		clean = string.sub(clean, 3)
	end

	if #clean % 2 ~= 0 then
		error("BufferUtil: hex string must contain an even number of hexadecimal digits", 2)
	end

	local byteLength = #clean // 2
	local out = createExact(byteLength)

	for index = 1, byteLength do
		local startIndex = (index - 1) * 2 + 1
		local pair = string.sub(clean, startIndex, startIndex + 1)
		local byteValue = tonumber(pair, 16)

		if byteValue == nil then
			error(string.format("BufferUtil: invalid hexadecimal byte %q", pair), 2)
		end

		buffer.writeu8(out, index - 1, byteValue)
	end

	return out
end

function BufferUtil.len(buff: buffer): number
	return buffer.len(buff)
end

function BufferUtil.bitLen(buff: buffer): number
	return buffer.len(buff) * 8
end

function BufferUtil.isEmpty(buff: buffer): boolean
	return buffer.len(buff) == 0
end

function BufferUtil.clear(buff: buffer): ()
	local length = buffer.len(buff)
	if length > 0 then
		buffer.fill(buff, 0, 0, length)
	end
end

function BufferUtil.copy(
	dst: buffer,
	dstOffset: number,
	src: buffer,
	srcOffset: number?,
	count: number?
): ()
	local sourceOffset = srcOffset or 0
	local actualCount = count

	if actualCount == nil then
		actualCount = buffer.len(src) - sourceOffset
	end

	assertByteRange(src, sourceOffset, actualCount, 2)
	assertByteRange(dst, dstOffset, actualCount, 2)

	if actualCount > 0 then
		buffer.copy(dst, dstOffset, src, sourceOffset, actualCount)
	end
end

function BufferUtil.copyWithin(
	buff: buffer,
	dstOffset: number,
	srcOffset: number,
	count: number
): ()
	BufferUtil.copy(buff, dstOffset, buff, srcOffset, count)
end

function BufferUtil.fillRange(
	buff: buffer,
	start: number,
	count: number,
	value: number
): ()
	assertByteRange(buff, start, count, 2)
	assertByteValue(value, 2)

	if count > 0 then
		buffer.fill(buff, start, value, count)
	end
end

function BufferUtil.slice(buff: buffer, start: number, count: number?): buffer
	local sourceLength = buffer.len(buff)
	local actualCount = count

	if actualCount == nil then
		actualCount = sourceLength - start
	end

	assertByteRange(buff, start, actualCount, 2)

	local out = createExact(actualCount)
	if actualCount > 0 then
		buffer.copy(out, 0, buff, start, actualCount)
	end

	return out
end

function BufferUtil.clone(buff: buffer, count: number?): buffer
	local sourceLength = buffer.len(buff)
	local actualCount = count or sourceLength

	assertByteRange(buff, 0, actualCount, 2)

	local out = createExact(actualCount)
	if actualCount > 0 then
		buffer.copy(out, 0, buff, 0, actualCount)
	end

	return out
end

function BufferUtil.cloneRange(buff: buffer, start: number, count: number): buffer
	return BufferUtil.slice(buff, start, count)
end

function BufferUtil.cloneBits(buff: buffer, bitLength: number): buffer
	assertNonNegativeInteger(bitLength, "bitLength", 2)

	local maxBits = buffer.len(buff) * 8
	if bitLength > maxBits then
		error(
			string.format("BufferUtil: bitLength %d exceeds source capacity %d bits", bitLength, maxBits),
			2
		)
	end

	local byteLength = (bitLength + 7) // 8
	local out = BufferUtil.clone(buff, byteLength)
	maskTrailingBits(out, bitLength)
	return out
end

function BufferUtil.compactStats(source: any, usedBits: number?): CompactInfo
	local buff, resolvedBits = resolveCompactSource(source, usedBits, 2)
	return compactInfoFor(buff, resolvedBits, 2)
end

function BufferUtil.compact(source: any, usedBits: number?): buffer
	local buff, resolvedBits = resolveCompactSource(source, usedBits, 2)
	return BufferUtil.cloneBits(buff, resolvedBits)
end

function BufferUtil.compactWithInfo(source: any, usedBits: number?): (buffer, CompactInfo)
	local buff, resolvedBits = resolveCompactSource(source, usedBits, 2)
	local info = compactInfoFor(buff, resolvedBits, 2)
	return BufferUtil.cloneBits(buff, resolvedBits), info
end

function BufferUtil.compactBits(buff: buffer, usedBits: number): buffer
	return BufferUtil.compact(buff, usedBits)
end

function BufferUtil.compactBytes(buff: buffer, usedBytes: number): buffer
	assertNonNegativeInteger(usedBytes, "usedBytes", 2)
	if usedBytes > buffer.len(buff) then
		error(
			string.format(
				"BufferUtil: usedBytes %d exceeds source length %d bytes",
				usedBytes,
				buffer.len(buff)
			),
			2
		)
	end
	return BufferUtil.clone(buff, usedBytes)
end

function BufferUtil.resize(buff: buffer, newSize: number): buffer
	local out = createExact(newSize)
	local copyCount = math.min(buffer.len(buff), newSize)

	if copyCount > 0 then
		buffer.copy(out, 0, buff, 0, copyCount)
	end

	return out
end

function BufferUtil.concat(buffers: {buffer}): buffer
	local totalLength = 0

	for index = 1, #buffers do
		totalLength += buffer.len(buffers[index])

		if totalLength > MAX_BUFFER_SIZE then
			error(
				string.format(
					"BufferUtil: concatenated length exceeds Roblox buffer limit of %d bytes",
					MAX_BUFFER_SIZE
				),
				2
			)
		end
	end

	local out = createExact(totalLength)
	local offset = 0

	for index = 1, #buffers do
		local item = buffers[index]
		local length = buffer.len(item)

		if length > 0 then
			buffer.copy(out, offset, item, 0, length)
			offset += length
		end
	end

	return out
end

function BufferUtil.readUintBits(buff: buffer, bitOffset: number, bitCount: number): number
	return readUnsignedBitsExact(buff, bitOffset, bitCount, 2)
end

function BufferUtil.writeUintBits(buff: buffer, bitOffset: number, bitCount: number, value: number): ()
	writeUnsignedBitsExact(buff, bitOffset, bitCount, value, 2)
end

function BufferUtil.readIntBits(buff: buffer, bitOffset: number, bitCount: number): number
	return readSignedBitsExact(buff, bitOffset, bitCount, 2)
end

function BufferUtil.writeIntBits(buff: buffer, bitOffset: number, bitCount: number, value: number): ()
	writeSignedBitsExact(buff, bitOffset, bitCount, value, 2)
end

local function readByteAlignedUnsigned(buff: buffer, offset: number, bitCount: number): number
	local byteCount = (bitCount + 7) // 8
	assertByteRange(buff, offset, byteCount, 3)
	return readUnsignedBitsExact(buff, offset * 8, bitCount, 3)
end

local function writeByteAlignedUnsigned(buff: buffer, offset: number, bitCount: number, value: number)
	local byteCount = (bitCount + 7) // 8
	assertByteRange(buff, offset, byteCount, 3)

	local bitOffset = offset * 8
	writeUnsignedBitsExact(buff, bitOffset, bitCount, value, 3)

	local padding = byteCount * 8 - bitCount
	if padding > 0 then
		buffer.writebits(buff, bitOffset + bitCount, padding, 0)
	end
end

local function readByteAlignedSigned(buff: buffer, offset: number, bitCount: number): number
	local byteCount = (bitCount + 7) // 8
	assertByteRange(buff, offset, byteCount, 3)
	return readSignedBitsExact(buff, offset * 8, bitCount, 3)
end

local function writeByteAlignedSigned(buff: buffer, offset: number, bitCount: number, value: number)
	local byteCount = (bitCount + 7) // 8
	assertByteRange(buff, offset, byteCount, 3)

	local bitOffset = offset * 8
	writeSignedBitsExact(buff, bitOffset, bitCount, value, 3)

	local padding = byteCount * 8 - bitCount
	if padding > 0 then
		buffer.writebits(buff, bitOffset + bitCount, padding, 0)
	end
end

-- Direct typed helpers for Roblox-native numeric formats.
-- These keep BufferUtil's strict validation instead of raw buffer truncation.
function BufferUtil.readi8(buff: buffer, offset: number): number
	assertByteRange(buff, offset, 1, 2)
	return buffer.readi8(buff, offset)
end

function BufferUtil.writei8(buff: buffer, offset: number, value: number): ()
	assertByteRange(buff, offset, 1, 2)
	assertTypedValue("i8", value, 2)
	buffer.writei8(buff, offset, value)
end

function BufferUtil.readu8(buff: buffer, offset: number): number
	assertByteRange(buff, offset, 1, 2)
	return buffer.readu8(buff, offset)
end

function BufferUtil.writeu8(buff: buffer, offset: number, value: number): ()
	assertByteRange(buff, offset, 1, 2)
	assertTypedValue("u8", value, 2)
	buffer.writeu8(buff, offset, value)
end

function BufferUtil.readi16(buff: buffer, offset: number): number
	assertByteRange(buff, offset, 2, 2)
	return buffer.readi16(buff, offset)
end

function BufferUtil.writei16(buff: buffer, offset: number, value: number): ()
	assertByteRange(buff, offset, 2, 2)
	assertTypedValue("i16", value, 2)
	buffer.writei16(buff, offset, value)
end

function BufferUtil.readu16(buff: buffer, offset: number): number
	assertByteRange(buff, offset, 2, 2)
	return buffer.readu16(buff, offset)
end

function BufferUtil.writeu16(buff: buffer, offset: number, value: number): ()
	assertByteRange(buff, offset, 2, 2)
	assertTypedValue("u16", value, 2)
	buffer.writeu16(buff, offset, value)
end

function BufferUtil.readi32(buff: buffer, offset: number): number
	assertByteRange(buff, offset, 4, 2)
	return buffer.readi32(buff, offset)
end

function BufferUtil.writei32(buff: buffer, offset: number, value: number): ()
	assertByteRange(buff, offset, 4, 2)
	assertTypedValue("i32", value, 2)
	buffer.writei32(buff, offset, value)
end

function BufferUtil.readu32(buff: buffer, offset: number): number
	assertByteRange(buff, offset, 4, 2)
	return buffer.readu32(buff, offset)
end

function BufferUtil.writeu32(buff: buffer, offset: number, value: number): ()
	assertByteRange(buff, offset, 4, 2)
	assertTypedValue("u32", value, 2)
	buffer.writeu32(buff, offset, value)
end

function BufferUtil.readf32(buff: buffer, offset: number): number
	assertByteRange(buff, offset, 4, 2)
	return buffer.readf32(buff, offset)
end

function BufferUtil.writef32(buff: buffer, offset: number, value: number): ()
	assertByteRange(buff, offset, 4, 2)
	assertTypedValue("f32", value, 2)
	buffer.writef32(buff, offset, value)
end

function BufferUtil.readf64(buff: buffer, offset: number): number
	assertByteRange(buff, offset, 8, 2)
	return buffer.readf64(buff, offset)
end

function BufferUtil.writef64(buff: buffer, offset: number, value: number): ()
	assertByteRange(buff, offset, 8, 2)
	assertTypedValue("f64", value, 2)
	buffer.writef64(buff, offset, value)
end

function BufferUtil.readu24(buff: buffer, offset: number): number
	return readByteAlignedUnsigned(buff, offset, 24)
end

function BufferUtil.writeu24(buff: buffer, offset: number, value: number): ()
	writeByteAlignedUnsigned(buff, offset, 24, value)
end

function BufferUtil.readi24(buff: buffer, offset: number): number
	return readByteAlignedSigned(buff, offset, 24)
end

function BufferUtil.writei24(buff: buffer, offset: number, value: number): ()
	writeByteAlignedSigned(buff, offset, 24, value)
end

function BufferUtil.readu40(buff: buffer, offset: number): number
	return readByteAlignedUnsigned(buff, offset, 40)
end

function BufferUtil.writeu40(buff: buffer, offset: number, value: number): ()
	writeByteAlignedUnsigned(buff, offset, 40, value)
end

function BufferUtil.readi40(buff: buffer, offset: number): number
	return readByteAlignedSigned(buff, offset, 40)
end

function BufferUtil.writei40(buff: buffer, offset: number, value: number): ()
	writeByteAlignedSigned(buff, offset, 40, value)
end

function BufferUtil.readu48(buff: buffer, offset: number): number
	return readByteAlignedUnsigned(buff, offset, 48)
end

function BufferUtil.writeu48(buff: buffer, offset: number, value: number): ()
	writeByteAlignedUnsigned(buff, offset, 48, value)
end

function BufferUtil.readi48(buff: buffer, offset: number): number
	return readByteAlignedSigned(buff, offset, 48)
end

function BufferUtil.writei48(buff: buffer, offset: number, value: number): ()
	writeByteAlignedSigned(buff, offset, 48, value)
end

function BufferUtil.readu53(buff: buffer, offset: number): number
	return readByteAlignedUnsigned(buff, offset, 53)
end

function BufferUtil.writeu53(buff: buffer, offset: number, value: number): ()
	writeByteAlignedUnsigned(buff, offset, 53, value)
end

function BufferUtil.readi53(buff: buffer, offset: number): number
	return readByteAlignedSigned(buff, offset, 53)
end

function BufferUtil.writei53(buff: buffer, offset: number, value: number): ()
	writeByteAlignedSigned(buff, offset, 53, value)
end

local function readCustomFloat(buff: buffer, offset: number, typ: string): number
	local formatInfo = FLOAT_FORMATS[typ]
	if formatInfo == nil then
		error(string.format("BufferUtil: unknown custom float format %q", typ), 3)
	end

	local byteCount = formatInfo.bits // 8
	assertByteRange(buff, offset, byteCount, 3)

	local bits = readUnsignedBitsExact(buff, offset * 8, formatInfo.bits, 3)
	return decodeBinaryFloat(bits, formatInfo.exponentBits, formatInfo.mantissaBits)
end

local function writeCustomFloat(buff: buffer, offset: number, typ: string, value: number)
	local formatInfo = FLOAT_FORMATS[typ]
	if formatInfo == nil then
		error(string.format("BufferUtil: unknown custom float format %q", typ), 3)
	end

	assertNumber(value, typ .. " value", 3)

	local byteCount = formatInfo.bits // 8
	assertByteRange(buff, offset, byteCount, 3)

	local bits = encodeBinaryFloat(value, formatInfo.exponentBits, formatInfo.mantissaBits)
	writeUnsignedBitsExact(buff, offset * 8, formatInfo.bits, bits, 3)
end

function BufferUtil.readf8e4m3(buff: buffer, offset: number): number
	return readCustomFloat(buff, offset, "f8e4m3")
end

function BufferUtil.writef8e4m3(buff: buffer, offset: number, value: number): ()
	writeCustomFloat(buff, offset, "f8e4m3", value)
end

function BufferUtil.readf8e5m2(buff: buffer, offset: number): number
	return readCustomFloat(buff, offset, "f8e5m2")
end

function BufferUtil.writef8e5m2(buff: buffer, offset: number, value: number): ()
	writeCustomFloat(buff, offset, "f8e5m2", value)
end

function BufferUtil.readf16(buff: buffer, offset: number): number
	return readCustomFloat(buff, offset, "f16")
end

function BufferUtil.writef16(buff: buffer, offset: number, value: number): ()
	writeCustomFloat(buff, offset, "f16", value)
end

function BufferUtil.readbf16(buff: buffer, offset: number): number
	return readCustomFloat(buff, offset, "bf16")
end

function BufferUtil.writebf16(buff: buffer, offset: number, value: number): ()
	writeCustomFloat(buff, offset, "bf16", value)
end

function BufferUtil.readf24(buff: buffer, offset: number): number
	return readCustomFloat(buff, offset, "f24")
end

function BufferUtil.writef24(buff: buffer, offset: number, value: number): ()
	writeCustomFloat(buff, offset, "f24", value)
end

function BufferUtil.readf40(buff: buffer, offset: number): number
	return readCustomFloat(buff, offset, "f40")
end

function BufferUtil.writef40(buff: buffer, offset: number, value: number): ()
	writeCustomFloat(buff, offset, "f40", value)
end

function BufferUtil.readf48(buff: buffer, offset: number): number
	return readCustomFloat(buff, offset, "f48")
end

function BufferUtil.writef48(buff: buffer, offset: number, value: number): ()
	writeCustomFloat(buff, offset, "f48", value)
end

BufferUtil.readI8 = BufferUtil.readi8
BufferUtil.writeI8 = BufferUtil.writei8
BufferUtil.readU8 = BufferUtil.readu8
BufferUtil.writeU8 = BufferUtil.writeu8
BufferUtil.readI16 = BufferUtil.readi16
BufferUtil.writeI16 = BufferUtil.writei16
BufferUtil.readU16 = BufferUtil.readu16
BufferUtil.writeU16 = BufferUtil.writeu16
BufferUtil.readI24 = BufferUtil.readi24
BufferUtil.writeI24 = BufferUtil.writei24
BufferUtil.readU24 = BufferUtil.readu24
BufferUtil.writeU24 = BufferUtil.writeu24
BufferUtil.readI32 = BufferUtil.readi32
BufferUtil.writeI32 = BufferUtil.writei32
BufferUtil.readU32 = BufferUtil.readu32
BufferUtil.writeU32 = BufferUtil.writeu32
BufferUtil.readI40 = BufferUtil.readi40
BufferUtil.writeI40 = BufferUtil.writei40
BufferUtil.readU40 = BufferUtil.readu40
BufferUtil.writeU40 = BufferUtil.writeu40
BufferUtil.readI48 = BufferUtil.readi48
BufferUtil.writeI48 = BufferUtil.writei48
BufferUtil.readU48 = BufferUtil.readu48
BufferUtil.writeU48 = BufferUtil.writeu48
BufferUtil.readI53 = BufferUtil.readi53
BufferUtil.writeI53 = BufferUtil.writei53
BufferUtil.readU53 = BufferUtil.readu53
BufferUtil.writeU53 = BufferUtil.writeu53
BufferUtil.readF8E4M3 = BufferUtil.readf8e4m3
BufferUtil.writeF8E4M3 = BufferUtil.writef8e4m3
BufferUtil.readF8E5M2 = BufferUtil.readf8e5m2
BufferUtil.writeF8E5M2 = BufferUtil.writef8e5m2
BufferUtil.readF16 = BufferUtil.readf16
BufferUtil.writeF16 = BufferUtil.writef16
BufferUtil.readBF16 = BufferUtil.readbf16
BufferUtil.writeBF16 = BufferUtil.writebf16
BufferUtil.readF24 = BufferUtil.readf24
BufferUtil.writeF24 = BufferUtil.writef24
BufferUtil.readF32 = BufferUtil.readf32
BufferUtil.writeF32 = BufferUtil.writef32
BufferUtil.readF40 = BufferUtil.readf40
BufferUtil.writeF40 = BufferUtil.writef40
BufferUtil.readF48 = BufferUtil.readf48
BufferUtil.writeF48 = BufferUtil.writef48
BufferUtil.readF64 = BufferUtil.readf64
BufferUtil.writeF64 = BufferUtil.writef64

function BufferUtil.isValidType(typ: any): boolean
	return type(typ) == "string" and SIZE[typ :: ValueType] ~= nil
end

function BufferUtil.typeInfo(typ: ValueType): any
	local info = TYPE_INFO[typ]
	if info == nil then
		error(string.format("BufferUtil: invalid value type %q", tostring(typ)), 2)
	end
	return info
end

function BufferUtil.quantize(typ: ValueType, value: number): number
	local temp = createExact(sizeOfUnsafe(typ))
	BufferUtil.write(temp, typ, 0, value)
	return BufferUtil.read(temp, typ, 0)
end

function BufferUtil.write(buff: buffer, typ: ValueType, offset: number, value: number): ()
	-- Dispatch through the direct helpers so every API path shares validation.
	if typ == "u8" then
		BufferUtil.writeu8(buff, offset, value)
	elseif typ == "i8" then
		BufferUtil.writei8(buff, offset, value)
	elseif typ == "u16" then
		BufferUtil.writeu16(buff, offset, value)
	elseif typ == "i16" then
		BufferUtil.writei16(buff, offset, value)
	elseif typ == "u24" then
		BufferUtil.writeu24(buff, offset, value)
	elseif typ == "i24" then
		BufferUtil.writei24(buff, offset, value)
	elseif typ == "u32" then
		BufferUtil.writeu32(buff, offset, value)
	elseif typ == "i32" then
		BufferUtil.writei32(buff, offset, value)
	elseif typ == "u40" then
		BufferUtil.writeu40(buff, offset, value)
	elseif typ == "i40" then
		BufferUtil.writei40(buff, offset, value)
	elseif typ == "u48" then
		BufferUtil.writeu48(buff, offset, value)
	elseif typ == "i48" then
		BufferUtil.writei48(buff, offset, value)
	elseif typ == "u53" then
		BufferUtil.writeu53(buff, offset, value)
	elseif typ == "i53" then
		BufferUtil.writei53(buff, offset, value)
	elseif typ == "f8e4m3" then
		BufferUtil.writef8e4m3(buff, offset, value)
	elseif typ == "f8e5m2" then
		BufferUtil.writef8e5m2(buff, offset, value)
	elseif typ == "f16" then
		BufferUtil.writef16(buff, offset, value)
	elseif typ == "bf16" then
		BufferUtil.writebf16(buff, offset, value)
	elseif typ == "f24" then
		BufferUtil.writef24(buff, offset, value)
	elseif typ == "f32" then
		BufferUtil.writef32(buff, offset, value)
	elseif typ == "f40" then
		BufferUtil.writef40(buff, offset, value)
	elseif typ == "f48" then
		BufferUtil.writef48(buff, offset, value)
	elseif typ == "f64" then
		BufferUtil.writef64(buff, offset, value)
	else
		error(string.format("BufferUtil: invalid value type %q", tostring(typ)), 2)
	end
end

function BufferUtil.read(buff: buffer, typ: ValueType, offset: number): number
	-- Dispatch through the direct helpers so every API path shares validation.
	if typ == "u8" then
		return BufferUtil.readu8(buff, offset)
	elseif typ == "i8" then
		return BufferUtil.readi8(buff, offset)
	elseif typ == "u16" then
		return BufferUtil.readu16(buff, offset)
	elseif typ == "i16" then
		return BufferUtil.readi16(buff, offset)
	elseif typ == "u24" then
		return BufferUtil.readu24(buff, offset)
	elseif typ == "i24" then
		return BufferUtil.readi24(buff, offset)
	elseif typ == "u32" then
		return BufferUtil.readu32(buff, offset)
	elseif typ == "i32" then
		return BufferUtil.readi32(buff, offset)
	elseif typ == "u40" then
		return BufferUtil.readu40(buff, offset)
	elseif typ == "i40" then
		return BufferUtil.readi40(buff, offset)
	elseif typ == "u48" then
		return BufferUtil.readu48(buff, offset)
	elseif typ == "i48" then
		return BufferUtil.readi48(buff, offset)
	elseif typ == "u53" then
		return BufferUtil.readu53(buff, offset)
	elseif typ == "i53" then
		return BufferUtil.readi53(buff, offset)
	elseif typ == "f8e4m3" then
		return BufferUtil.readf8e4m3(buff, offset)
	elseif typ == "f8e5m2" then
		return BufferUtil.readf8e5m2(buff, offset)
	elseif typ == "f16" then
		return BufferUtil.readf16(buff, offset)
	elseif typ == "bf16" then
		return BufferUtil.readbf16(buff, offset)
	elseif typ == "f24" then
		return BufferUtil.readf24(buff, offset)
	elseif typ == "f32" then
		return BufferUtil.readf32(buff, offset)
	elseif typ == "f40" then
		return BufferUtil.readf40(buff, offset)
	elseif typ == "f48" then
		return BufferUtil.readf48(buff, offset)
	elseif typ == "f64" then
		return BufferUtil.readf64(buff, offset)
	else
		error(string.format("BufferUtil: invalid value type %q", tostring(typ)), 2)
	end
end

function BufferUtil.writeBits(
	buff: buffer,
	bitOffset: number,
	bitCount: number,
	value: number
): ()
	assertBitWidth(bitCount, 2)
	assertBitRange(buff, bitOffset, bitCount, 2)
	buffer.writebits(buff, bitOffset, bitCount, value)
end

function BufferUtil.writeBitsChecked(
	buff: buffer,
	bitOffset: number,
	bitCount: number,
	value: number
): ()
	assertBitWidth(bitCount, 2)
	assertBitRange(buff, bitOffset, bitCount, 2)

	local maxValue = if bitCount == 32 then 0xFFFFFFFF else 2 ^ bitCount - 1
	if not isInteger(value) or value < 0 or value > maxValue then
		error(
			string.format(
				"BufferUtil: %d-bit value must be an integer in range [0, %.0f], got %s",
				bitCount,
				maxValue,
				tostring(value)
			),
			2
		)
	end

	buffer.writebits(buff, bitOffset, bitCount, value)
end

function BufferUtil.readBits(
	buff: buffer,
	bitOffset: number,
	bitCount: number
): number
	assertBitWidth(bitCount, 2)
	assertBitRange(buff, bitOffset, bitCount, 2)
	return buffer.readbits(buff, bitOffset, bitCount)
end

function BufferUtil.writeString(
	buff: buffer,
	offset: number,
	value: string,
	count: number?
): ()
	assertString(value, "value", 2)
	local actualCount = count or #value

	if not isInteger(actualCount) or actualCount < 0 or actualCount > #value then
		error(
			string.format(
				"BufferUtil: string count must be an integer from 0 to %d, got %s",
				#value,
				tostring(actualCount)
			),
			2
		)
	end

	assertByteRange(buff, offset, actualCount, 2)

	if actualCount > 0 then
		buffer.writestring(buff, offset, value, actualCount)
	end
end

function BufferUtil.readString(
	buff: buffer,
	offset: number,
	count: number
): string
	assertByteRange(buff, offset, count, 2)

	if count == 0 then
		return ""
	end

	return buffer.readstring(buff, offset, count)
end


function BufferUtil.bitsRequired(value: number): number
	assertSafeUnsignedInteger(value, "value", 2)

	if value == 0 then
		return 1
	end

	local bits = 0
	local remaining = value
	while remaining > 0 do
		bits += 1
		remaining = math.floor(remaining / 2)
	end
	return bits
end

function BufferUtil.bitsRequiredValues(valueCount: number): number
	assertPositiveInteger(valueCount, "valueCount", 2)
	if valueCount > SAFE_UINT_MAX then
		error(
			string.format("BufferUtil: valueCount exceeds exact integer limit %.0f", SAFE_UINT_MAX),
			2
		)
	end
	return BufferUtil.bitsRequired(valueCount - 1)
end

function BufferUtil.writeBool(buff: buffer, bitOffset: number, value: boolean): ()
	assertBoolean(value, "value", 2)
	assertBitRange(buff, bitOffset, 1, 2)
	buffer.writebits(buff, bitOffset, 1, if value then 1 else 0)
end

function BufferUtil.readBool(buff: buffer, bitOffset: number): boolean
	assertBitRange(buff, bitOffset, 1, 2)
	return buffer.readbits(buff, bitOffset, 1) ~= 0
end

function BufferUtil.varUIntSize(value: number): number
	assertSafeUnsignedInteger(value, "value", 2)
	return varUIntSizeUnsafe(value)
end

function BufferUtil.varIntSize(value: number): number
	assertSafeSignedInteger(value, "value", 2)
	return varUIntSizeUnsafe(zigZagEncode(value))
end

function BufferUtil.writeVarUInt(buff: buffer, offset: number, value: number): number
	assertSafeUnsignedInteger(value, "value", 2)

	local byteCount = varUIntSizeUnsafe(value)
	assertByteRange(buff, offset, byteCount, 2)

	local remaining = value
	for index = 0, byteCount - 1 do
		local payload = remaining % 128
		remaining = math.floor(remaining / 128)

		local encoded = payload
		if index < byteCount - 1 then
			encoded += 128
		end

		buffer.writeu8(buff, offset + index, encoded)
	end

	return byteCount
end

function BufferUtil.readVarUInt(buff: buffer, offset: number): (number, number)
	assertBytePosition(buff, offset, 2)

	local length = buffer.len(buff)
	local result = 0
	local multiplier = 1

	for index = 0, MAX_VAR_UINT_BYTES - 1 do
		local position = offset + index
		if position >= length then
			error("BufferUtil: unterminated VarUInt reaches end of buffer", 2)
		end

		local encoded = buffer.readu8(buff, position)
		local payload = encoded % 128

		if index == MAX_VAR_UINT_BYTES - 1 and payload > 15 then
			error("BufferUtil: VarUInt exceeds Luau's exact 53-bit integer range", 2)
		end

		result += payload * multiplier

		if encoded < 128 then
			if result > SAFE_UINT_MAX then
				error("BufferUtil: VarUInt exceeds Luau's exact 53-bit integer range", 2)
			end

			local byteCount = index + 1
			if byteCount ~= varUIntSizeUnsafe(result) then
				error("BufferUtil: non-canonical VarUInt encoding", 2)
			end

			return result, byteCount
		end

		multiplier *= 128
	end

	error("BufferUtil: VarUInt exceeds maximum encoded length of 8 bytes", 2)
end

function BufferUtil.writeVarInt(buff: buffer, offset: number, value: number): number
	assertSafeSignedInteger(value, "value", 2)
	return BufferUtil.writeVarUInt(buff, offset, zigZagEncode(value))
end

function BufferUtil.readVarInt(buff: buffer, offset: number): (number, number)
	local encoded, byteCount = BufferUtil.readVarUInt(buff, offset)
	local value = zigZagDecode(encoded)

	if value < SAFE_SIGNED_53_MIN or value > SAFE_SIGNED_53_MAX then
		error("BufferUtil: decoded VarInt is outside supported signed range", 2)
	end

	return value, byteCount
end

function BufferUtil.writeVarString(buff: buffer, offset: number, value: string): number
	assertString(value, "value", 2)

	local stringLength = #value
	if stringLength > MAX_BUFFER_SIZE then
		error(
			string.format(
				"BufferUtil: string length %d exceeds Roblox buffer limit of %d bytes",
				stringLength,
				MAX_BUFFER_SIZE
			),
			2
		)
	end

	local prefixBytes = varUIntSizeUnsafe(stringLength)
	local totalBytes = prefixBytes + stringLength
	assertByteRange(buff, offset, totalBytes, 2)

	BufferUtil.writeVarUInt(buff, offset, stringLength)
	if stringLength > 0 then
		buffer.writestring(buff, offset + prefixBytes, value, stringLength)
	end

	return totalBytes
end

function BufferUtil.readVarString(buff: buffer, offset: number): (string, number)
	local stringLength, prefixBytes = BufferUtil.readVarUInt(buff, offset)
	if stringLength > MAX_BUFFER_SIZE then
		error("BufferUtil: decoded VarString length exceeds Roblox buffer limit", 2)
	end

	local stringOffset = offset + prefixBytes
	assertByteRange(buff, stringOffset, stringLength, 2)

	local value = if stringLength == 0 then "" else buffer.readstring(buff, stringOffset, stringLength)
	return value, prefixBytes + stringLength
end

function BufferUtil.toBase64(buff: buffer): string
	local length = buffer.len(buff)
	if length == 0 then
		return ""
	end

	local groupCount = (length + 2) // 3
	local out = table.create(groupCount * 4)
	local outIndex = 1

	for offset = 0, length - 1, 3 do
		local remaining = length - offset
		local a = buffer.readu8(buff, offset)
		local b = if remaining >= 2 then buffer.readu8(buff, offset + 1) else 0
		local c = if remaining >= 3 then buffer.readu8(buff, offset + 2) else 0

		local packed = a * 65_536 + b * 256 + c
		local i1 = math.floor(packed / 262_144) % 64
		local i2 = math.floor(packed / 4_096) % 64
		local i3 = math.floor(packed / 64) % 64
		local i4 = packed % 64

		out[outIndex] = BASE64_ENCODE[i1 + 1]
		out[outIndex + 1] = BASE64_ENCODE[i2 + 1]
		out[outIndex + 2] = if remaining >= 2 then BASE64_ENCODE[i3 + 1] else "="
		out[outIndex + 3] = if remaining >= 3 then BASE64_ENCODE[i4 + 1] else "="
		outIndex += 4
	end

	return table.concat(out)
end

function BufferUtil.fromBase64(value: string): buffer
	assertString(value, "value", 2)
	local clean = string.gsub(value, "%s+", "")

	if #clean == 0 then
		return createExact(0)
	end

	if #clean % 4 ~= 0 then
		error("BufferUtil: Base64 length must be a multiple of 4", 2)
	end

	local padding = 0
	if string.sub(clean, -1) == "=" then
		padding += 1
	end
	if string.sub(clean, -2, -2) == "=" then
		padding += 1
	end

	local outputLength = (#clean // 4) * 3 - padding
	local out = createExact(outputLength)
	local outputOffset = 0

	for index = 1, #clean, 4 do
		local c1 = string.sub(clean, index, index)
		local c2 = string.sub(clean, index + 1, index + 1)
		local c3 = string.sub(clean, index + 2, index + 2)
		local c4 = string.sub(clean, index + 3, index + 3)
		local finalGroup = index + 3 == #clean

		if c1 == "=" or c2 == "=" then
			error("BufferUtil: invalid Base64 padding position", 2)
		end

		local pad3 = c3 == "="
		local pad4 = c4 == "="

		if pad3 and not pad4 then
			error("BufferUtil: invalid Base64 padding; third '=' requires fourth '='", 2)
		end
		if (pad3 or pad4) and not finalGroup then
			error("BufferUtil: Base64 padding is only valid in the final group", 2)
		end

		local a = BASE64_DECODE[c1]
		local b = BASE64_DECODE[c2]
		local c = if pad3 then 0 else BASE64_DECODE[c3]
		local d = if pad4 then 0 else BASE64_DECODE[c4]

		if a == nil or b == nil or c == nil or d == nil then
			error("BufferUtil: invalid Base64 character", 2)
		end

		if pad3 and b % 16 ~= 0 then
			error("BufferUtil: non-canonical Base64 padding bits", 2)
		end
		if pad4 and not pad3 and c % 4 ~= 0 then
			error("BufferUtil: non-canonical Base64 padding bits", 2)
		end

		local packed = a * 262_144 + b * 4_096 + c * 64 + d
		local byte1 = math.floor(packed / 65_536) % 256
		local byte2 = math.floor(packed / 256) % 256
		local byte3 = packed % 256

		if outputOffset < outputLength then
			buffer.writeu8(out, outputOffset, byte1)
			outputOffset += 1
		end
		if not pad3 and outputOffset < outputLength then
			buffer.writeu8(out, outputOffset, byte2)
			outputOffset += 1
		end
		if not pad4 and outputOffset < outputLength then
			buffer.writeu8(out, outputOffset, byte3)
			outputOffset += 1
		end
	end

	return out
end

function BufferUtil.sizeOf(typ: ValueType): number
	return sizeOfUnsafe(typ)
end

function BufferUtil.bitsToBytes(bitCount: number): number
	assertNonNegativeInteger(bitCount, "bitCount", 2)
	return (bitCount + 7) // 8
end

function BufferUtil.bytesToBits(byteCount: number): number
	assertNonNegativeInteger(byteCount, "byteCount", 2)
	return byteCount * 8
end

function BufferUtil.toBits(value: number, unit: SizeUnit): number
	return sizeToBits(value, unit, 2)
end

function BufferUtil.toBytes(value: number, unit: SizeUnit): number
	return sizeToBits(value, unit, 2) / 8
end

function BufferUtil.formatBytes(byteCount: number, decimals: number?): string
	assertNonNegativeNumber(byteCount, "byteCount", 2)
	local precision = assertFormatDecimals(decimals, 2)
	local displayValue, unit = selectByteDisplay(byteCount)
	return trimFormattedNumber(displayValue, precision) .. " " .. unit
end

function BufferUtil.formatBits(bitCount: number, decimals: number?): string
	assertNonNegativeNumber(bitCount, "bitCount", 2)
	local precision = assertFormatDecimals(decimals, 2)
	local displayValue, unit = selectBitDisplay(bitCount)
	return trimFormattedNumber(displayValue, precision) .. " " .. unit
end

function BufferUtil.formatDataBits(bitCount: number, decimals: number?): string
	assertNonNegativeInteger(bitCount, "bitCount", 2)

	if bitCount >= 8 and bitCount % 8 == 0 then
		return BufferUtil.formatBytes(bitCount / 8, decimals)
	end

	return BufferUtil.formatBits(bitCount, decimals)
end

function BufferUtil.formatBuffer(buff: buffer, decimals: number?): string
	return BufferUtil.formatBytes(buffer.len(buff), decimals)
end

function BufferUtil.formatTypeSize(typ: ValueType, decimals: number?): string
	local info = BufferUtil.typeInfo(typ)
	local byteText = BufferUtil.formatBytes(info.bytes, decimals)

	if info.paddingBits ~= nil and info.paddingBits > 0 then
		return string.format("%s (%d b data + %d b padding)", byteText, info.bits, info.paddingBits)
	end

	return string.format("%s (%d b)", byteText, info.bits)
end

function BufferUtil.formatLayoutSize(lay: CompiledLayout, decimals: number?): string
	if lay.size == nil then
		error("BufferUtil: layout must be compiled with BufferUtil.compileLayout first", 2)
	end
	return BufferUtil.formatBytes(lay.size, decimals)
end

function BufferUtil.formatBufferBits(buff: buffer, decimals: number?): string
	return BufferUtil.formatBits(buffer.len(buff) * 8, decimals)
end

function BufferUtil.formatBufferUsage(buff: buffer, usedBits: number, decimals: number?): string
	assertNonNegativeInteger(usedBits, "usedBits", 2)

	local capacityBits = buffer.len(buff) * 8
	if usedBits > capacityBits then
		error(
			string.format(
				"BufferUtil: usedBits %d exceeds buffer capacity %d bits",
				usedBits,
				capacityBits
			),
			2
		)
	end

	local precision = assertFormatDecimals(decimals, 2)
	local used = BufferUtil.formatDataBits(usedBits, precision)
	local capacity = BufferUtil.formatBytes(buffer.len(buff), precision)
	local percent = if capacityBits == 0 then 0 else usedBits / capacityBits * 100
	return string.format("%s / %s (%s%%)", used, capacity, trimFormattedNumber(percent, precision))
end

function BufferUtil.formatCompactStats(info: CompactInfo, decimals: number?): string
	if type(info) ~= "table" then
		error("BufferUtil: formatCompactStats expects CompactInfo", 2)
	end

	local fields = {
		"originalBytes",
		"originalBits",
		"usedBits",
		"unusedBits",
		"compactBytes",
		"compactStorageBits",
		"paddingBits",
		"removedBits",
		"savedBytes",
		"percentSaved",
		"efficiency",
	}

	for _, field in fields do
		if not isFiniteNumber((info :: any)[field]) or (info :: any)[field] < 0 then
			error(string.format("BufferUtil: invalid CompactInfo field %s", field), 2)
		end
	end

	local precision = assertFormatDecimals(decimals, 2)
	return string.format(
		"%s -> %s (saved %s / %s%%, %d b data + %d b padding, %s%% efficient)",
		BufferUtil.formatBytes(info.originalBytes, precision),
		BufferUtil.formatBytes(info.compactBytes, precision),
		BufferUtil.formatBytes(info.savedBytes, precision),
		trimFormattedNumber(info.percentSaved, precision),
		info.usedBits,
		info.paddingBits,
		trimFormattedNumber(info.efficiency, precision)
	)
end

function BufferUtil.formatAuto(value: any, unit: SizeUnit?, decimals: number?): string
	local valueKind = typeof(value)

	if valueKind == "buffer" then
		if unit ~= nil then
			error("BufferUtil: formatAuto unit is only used when formatting a numeric value", 2)
		end
		return BufferUtil.formatBuffer(value, decimals)
	end

	if valueKind == "number" then
		if unit == nil then
			return BufferUtil.formatBytes(value, decimals)
		end

		local _, isByteUnit = normalizeSizeUnit(unit, 2)
		local bitCount = sizeToBits(value, unit, 2)

		if isByteUnit then
			return BufferUtil.formatBytes(bitCount / 8, decimals)
		end

		if isInteger(bitCount) then
			return BufferUtil.formatDataBits(bitCount, decimals)
		end

		return BufferUtil.formatBits(bitCount, decimals)
	end

	if valueKind == "string" then
		if unit ~= nil then
			error("BufferUtil: formatAuto unit is only used when formatting a numeric value", 2)
		end

		if BufferUtil.isValidType(value) then
			return BufferUtil.formatTypeSize(value :: ValueType, decimals)
		end

		error(string.format("BufferUtil: formatAuto does not recognize string %q", value), 2)
	end

	if valueKind == "table" then
		if unit ~= nil then
			error("BufferUtil: formatAuto unit is only used when formatting a numeric value", 2)
		end

		local object = value :: any
		local cursorKind = classifyCursorObject(object)
		if cursorKind == BIT_CURSOR_KIND then
			local buff, bitPos = assertBitCursorPosition(object, 2)
			return BufferUtil.formatBufferUsage(buff, bitPos, decimals)
		elseif cursorKind == BYTE_CURSOR_KIND then
			local buff, pos = assertByteCursorPosition(object, 2)
			return BufferUtil.formatBufferUsage(buff, pos * 8, decimals)
		elseif cursorKind == "ambiguous" then
			error("BufferUtil: formatAuto received an ambiguous cursor table containing both pos and bitPos", 2)
		elseif cursorKind == "invalid" then
			error("BufferUtil: formatAuto received a cursor with an invalid cursor tag", 2)
		end

		if object.originalBytes ~= nil
			and object.compactBytes ~= nil
			and object.usedBits ~= nil
			and object.savedBytes ~= nil
		then
			return BufferUtil.formatCompactStats(object :: CompactInfo, decimals)
		end

		if object.size ~= nil and object.fields ~= nil and object.off ~= nil and object.type ~= nil then
			if not isInteger(object.size) or object.size < 0 then
				error("BufferUtil: formatAuto received an invalid compiled layout", 2)
			end
			return BufferUtil.formatLayoutSize(object :: CompiledLayout, decimals)
		end
	end

	error(string.format("BufferUtil: formatAuto does not support %s", valueKind), 2)
end

function BufferUtil.paddingBits(bitCount: number): number
	assertNonNegativeInteger(bitCount, "bitCount", 2)
	return (8 - (bitCount % 8)) % 8
end

function BufferUtil.isByteAligned(bitOffset: number): boolean
	return isInteger(bitOffset) and bitOffset >= 0 and bitOffset % 8 == 0
end

function BufferUtil.canAccess(buff: buffer, offset: number, count: number): boolean
	return typeof(buff) == "buffer"
		and isInteger(offset)
		and isInteger(count)
		and offset >= 0
		and count >= 0
		and offset + count <= buffer.len(buff)
end

function BufferUtil.canAccessBits(buff: buffer, bitOffset: number, bitCount: number): boolean
	return typeof(buff) == "buffer"
		and isInteger(bitOffset)
		and isInteger(bitCount)
		and bitOffset >= 0
		and bitCount >= 0
		and bitOffset + bitCount <= buffer.len(buff) * 8
end

function BufferUtil.assertRange(buff: buffer, offset: number, count: number): ()
	assertByteRange(buff, offset, count, 2)
end

function BufferUtil.assertBitRange(buff: buffer, bitOffset: number, bitCount: number): ()
	assertBitRange(buff, bitOffset, bitCount, 2)
end

function BufferUtil.cursorKind(value: any): string?
	local kind = classifyCursorObject(value)
	if kind == BYTE_CURSOR_KIND then
		local ok = pcall(function()
			assertByteCursorPosition(value, 3)
		end)
		return if ok then BYTE_CURSOR_KIND else nil
	elseif kind == BIT_CURSOR_KIND then
		local ok = pcall(function()
			assertBitCursorPosition(value, 3)
		end)
		return if ok then BIT_CURSOR_KIND else nil
	end
	return nil
end

function BufferUtil.isCursor(value: any): boolean
	return BufferUtil.cursorKind(value) == BYTE_CURSOR_KIND
end

function BufferUtil.isBitCursor(value: any): boolean
	return BufferUtil.cursorKind(value) == BIT_CURSOR_KIND
end

function BufferUtil.cursor(buff: buffer, pos: number?): Cursor
	local position = pos or 0
	assertBytePosition(buff, position, 2)

	return {
		buff = buff,
		pos = position,
		_bufferUtilCursorKind = BYTE_CURSOR_KIND,
	}
end

function BufferUtil.tell(cur: Cursor): number
	local _, pos = assertByteCursorPosition(cur, 2)
	return pos
end

function BufferUtil.seek(cur: Cursor, pos: number): Cursor
	local buff = assertCursorIdentity(cur, BYTE_CURSOR_KIND, 2)
	assertBytePosition(buff, pos, 2)
	cur.pos = pos
	return cur
end

function BufferUtil.reset(cur: Cursor): Cursor
	assertCursorIdentity(cur, BYTE_CURSOR_KIND, 2)
	cur.pos = 0
	return cur
end

function BufferUtil.remaining(cur: Cursor): number
	local buff, pos = assertByteCursorPosition(cur, 2)
	return buffer.len(buff) - pos
end

function BufferUtil.skip(cur: Cursor, byteCount: number): Cursor
	assertNonNegativeInteger(byteCount, "byteCount", 2)
	local buff, pos = assertByteCursorPosition(cur, 2)

	local nextPos = pos + byteCount
	assertBytePosition(buff, nextPos, 2)
	cur.pos = nextPos
	return cur
end

function BufferUtil.rewind(cur: Cursor, byteCount: number): Cursor
	assertNonNegativeInteger(byteCount, "byteCount", 2)
	local buff, pos = assertByteCursorPosition(cur, 2)

	local nextPos = pos - byteCount
	assertBytePosition(buff, nextPos, 2)
	cur.pos = nextPos
	return cur
end

function BufferUtil.advance(cur: Cursor, typ: ValueType): Cursor
	local buff, pos = assertByteCursorPosition(cur, 2)

	local nextPos = pos + sizeOfUnsafe(typ)
	assertBytePosition(buff, nextPos, 2)
	cur.pos = nextPos
	return cur
end

function BufferUtil.advanced(cur: Cursor, typ: ValueType): Cursor
	return BufferUtil.advance(cur, typ)
end

function BufferUtil.canReadNext(cur: Cursor, typ: ValueType): boolean
	local size = SIZE[typ]
	if size == nil or classifyCursorObject(cur) ~= BYTE_CURSOR_KIND then
		return false
	end

	local object = cur :: any
	local buff = rawget(object, "buff")
	local pos = rawget(object, "pos")
	return typeof(buff) == "buffer" and BufferUtil.canAccess(buff, pos, size)
end

BufferUtil.canWriteNext = BufferUtil.canReadNext

function BufferUtil.peekNext(cur: Cursor, typ: ValueType): number
	local buff, pos = assertByteCursorPosition(cur, 2)
	return BufferUtil.read(buff, typ, pos)
end

function BufferUtil.writeNext(cur: Cursor, typ: ValueType, value: number): ()
	local buff, pos = assertByteCursorPosition(cur, 2)
	local size = sizeOfUnsafe(typ)
	BufferUtil.write(buff, typ, pos, value)
	cur.pos = pos + size
end

function BufferUtil.readNext(cur: Cursor, typ: ValueType): number
	local buff, pos = assertByteCursorPosition(cur, 2)
	local size = sizeOfUnsafe(typ)
	local value = BufferUtil.read(buff, typ, pos)
	cur.pos = pos + size
	return value
end

function BufferUtil.writeStringNext(cur: Cursor, value: string, count: number?): ()
	local buff, pos = assertByteCursorPosition(cur, 2)
	BufferUtil.writeString(buff, pos, value, count)
	local actualCount = if count == nil then #value else count
	cur.pos = pos + actualCount
end

function BufferUtil.peekStringNext(cur: Cursor, count: number): string
	local buff, pos = assertByteCursorPosition(cur, 2)
	return BufferUtil.readString(buff, pos, count)
end

function BufferUtil.readStringNext(cur: Cursor, count: number): string
	local buff, pos = assertByteCursorPosition(cur, 2)
	local value = BufferUtil.readString(buff, pos, count)
	cur.pos = pos + count
	return value
end

function BufferUtil.bitCursor(buff: buffer, bitPos: number?): BitCursor
	local pos = bitPos or 0
	assertBitPosition(buff, pos, 2)

	return {
		buff = buff,
		bitPos = pos,
		_bufferUtilCursorKind = BIT_CURSOR_KIND,
	}
end

function BufferUtil.tellBits(cur: BitCursor): number
	local _, bitPos = assertBitCursorPosition(cur, 2)
	return bitPos
end

function BufferUtil.seekBits(cur: BitCursor, bitPos: number): BitCursor
	local buff = assertCursorIdentity(cur, BIT_CURSOR_KIND, 2)
	assertBitPosition(buff, bitPos, 2)
	cur.bitPos = bitPos
	return cur
end

function BufferUtil.resetBits(cur: BitCursor): BitCursor
	assertCursorIdentity(cur, BIT_CURSOR_KIND, 2)
	cur.bitPos = 0
	return cur
end

function BufferUtil.remainingBits(cur: BitCursor): number
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	return buffer.len(buff) * 8 - bitPos
end

function BufferUtil.skipBits(cur: BitCursor, bitCount: number): BitCursor
	assertNonNegativeInteger(bitCount, "bitCount", 2)
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	local nextPos = bitPos + bitCount
	assertBitPosition(buff, nextPos, 2)
	cur.bitPos = nextPos
	return cur
end

function BufferUtil.rewindBits(cur: BitCursor, bitCount: number): BitCursor
	assertNonNegativeInteger(bitCount, "bitCount", 2)
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	local nextPos = bitPos - bitCount
	assertBitPosition(buff, nextPos, 2)
	cur.bitPos = nextPos
	return cur
end

function BufferUtil.alignBits(cur: BitCursor, alignment: number?): BitCursor
	local actualAlignment = alignment or 8
	assertPositiveInteger(actualAlignment, "alignment", 2)
	local buff, bitPos = assertBitCursorPosition(cur, 2)

	local aligned = ((bitPos + actualAlignment - 1) // actualAlignment) * actualAlignment
	assertBitPosition(buff, aligned, 2)
	cur.bitPos = aligned
	return cur
end

function BufferUtil.canReadBitsNext(cur: BitCursor, bitCount: number): boolean
	if classifyCursorObject(cur) ~= BIT_CURSOR_KIND then
		return false
	end

	local object = cur :: any
	local buff = rawget(object, "buff")
	local bitPos = rawget(object, "bitPos")
	return typeof(buff) == "buffer"
		and isInteger(bitCount)
		and bitCount >= 0
		and bitCount <= MAX_BIT_WIDTH
		and BufferUtil.canAccessBits(buff, bitPos, bitCount)
end

BufferUtil.canWriteBitsNext = BufferUtil.canReadBitsNext

function BufferUtil.canReadUintBitsNext(cur: BitCursor, bitCount: number): boolean
	if classifyCursorObject(cur) ~= BIT_CURSOR_KIND then
		return false
	end

	local object = cur :: any
	local buff = rawget(object, "buff")
	local bitPos = rawget(object, "bitPos")
	return typeof(buff) == "buffer"
		and isInteger(bitCount)
		and bitCount >= 1
		and bitCount <= BufferUtil.MAX_EXACT_INT_BITS
		and BufferUtil.canAccessBits(buff, bitPos, bitCount)
end

BufferUtil.canWriteUintBitsNext = BufferUtil.canReadUintBitsNext
BufferUtil.canReadIntBitsNext = BufferUtil.canReadUintBitsNext
BufferUtil.canWriteIntBitsNext = BufferUtil.canReadUintBitsNext

function BufferUtil.peekBitsNext(cur: BitCursor, bitCount: number): number
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	return BufferUtil.readBits(buff, bitPos, bitCount)
end

function BufferUtil.writeBitsNext(cur: BitCursor, bitCount: number, value: number): ()
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	BufferUtil.writeBits(buff, bitPos, bitCount, value)
	cur.bitPos = bitPos + bitCount
end

function BufferUtil.readBitsNext(cur: BitCursor, bitCount: number): number
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	local value = BufferUtil.readBits(buff, bitPos, bitCount)
	cur.bitPos = bitPos + bitCount
	return value
end

function BufferUtil.peekUintBitsNext(cur: BitCursor, bitCount: number): number
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	return BufferUtil.readUintBits(buff, bitPos, bitCount)
end

function BufferUtil.writeUintBitsNext(cur: BitCursor, bitCount: number, value: number): ()
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	BufferUtil.writeUintBits(buff, bitPos, bitCount, value)
	cur.bitPos = bitPos + bitCount
end

function BufferUtil.readUintBitsNext(cur: BitCursor, bitCount: number): number
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	local value = BufferUtil.readUintBits(buff, bitPos, bitCount)
	cur.bitPos = bitPos + bitCount
	return value
end

function BufferUtil.peekIntBitsNext(cur: BitCursor, bitCount: number): number
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	return BufferUtil.readIntBits(buff, bitPos, bitCount)
end

function BufferUtil.writeIntBitsNext(cur: BitCursor, bitCount: number, value: number): ()
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	BufferUtil.writeIntBits(buff, bitPos, bitCount, value)
	cur.bitPos = bitPos + bitCount
end

function BufferUtil.readIntBitsNext(cur: BitCursor, bitCount: number): number
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	local value = BufferUtil.readIntBits(buff, bitPos, bitCount)
	cur.bitPos = bitPos + bitCount
	return value
end

function BufferUtil.writeVarUIntNext(cur: Cursor, value: number): number
	local buff, pos = assertByteCursorPosition(cur, 2)
	local byteCount = BufferUtil.writeVarUInt(buff, pos, value)
	cur.pos = pos + byteCount
	return byteCount
end

function BufferUtil.readVarUIntNext(cur: Cursor): (number, number)
	local buff, pos = assertByteCursorPosition(cur, 2)
	local value, byteCount = BufferUtil.readVarUInt(buff, pos)
	cur.pos = pos + byteCount
	return value, byteCount
end

function BufferUtil.writeVarIntNext(cur: Cursor, value: number): number
	local buff, pos = assertByteCursorPosition(cur, 2)
	local byteCount = BufferUtil.writeVarInt(buff, pos, value)
	cur.pos = pos + byteCount
	return byteCount
end

function BufferUtil.readVarIntNext(cur: Cursor): (number, number)
	local buff, pos = assertByteCursorPosition(cur, 2)
	local value, byteCount = BufferUtil.readVarInt(buff, pos)
	cur.pos = pos + byteCount
	return value, byteCount
end

function BufferUtil.writeVarStringNext(cur: Cursor, value: string): number
	local buff, pos = assertByteCursorPosition(cur, 2)
	local byteCount = BufferUtil.writeVarString(buff, pos, value)
	cur.pos = pos + byteCount
	return byteCount
end

function BufferUtil.readVarStringNext(cur: Cursor): (string, number)
	local buff, pos = assertByteCursorPosition(cur, 2)
	local value, byteCount = BufferUtil.readVarString(buff, pos)
	cur.pos = pos + byteCount
	return value, byteCount
end

function BufferUtil.writeBoolNext(cur: BitCursor, value: boolean): ()
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	BufferUtil.writeBool(buff, bitPos, value)
	cur.bitPos = bitPos + 1
end

function BufferUtil.readBoolNext(cur: BitCursor): boolean
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	local value = BufferUtil.readBool(buff, bitPos)
	cur.bitPos = bitPos + 1
	return value
end

function BufferUtil.peekBoolNext(cur: BitCursor): boolean
	local buff, bitPos = assertBitCursorPosition(cur, 2)
	return BufferUtil.readBool(buff, bitPos)
end

function BufferUtil.compileLayout(lay: {any}): CompiledLayout
	local offsets: {[any]: number} = {}
	local types: {[any]: ValueType} = {}
	local explicitNames: {[string]: boolean} = {}
	local fields: {CompiledField} = table.create(#lay)
	local cursor = 0

	for index = 1, #lay do
		local spec = lay[index]
		local typ: ValueType
		local name: string? = nil
		local legacyTypeAlias = false

		if type(spec) == "string" then
			typ = spec :: ValueType
			legacyTypeAlias = true
		elseif type(spec) == "table" then
			local rawType = spec.type or spec[2]
			local rawName = spec.name or spec[1]

			if type(rawType) ~= "string" then
				error(string.format("BufferUtil: layout field #%d is missing a valid type", index), 2)
			end

			typ = rawType :: ValueType

			if rawName ~= nil then
				if type(rawName) ~= "string" then
					error(string.format("BufferUtil: layout field #%d name must be a string", index), 2)
				end
				name = rawName
			end
		else
			error(string.format("BufferUtil: invalid layout field #%d", index), 2)
		end

		local fieldSize = sizeOfUnsafe(typ)

		offsets[index] = cursor
		types[index] = typ

		if name ~= nil then
			if explicitNames[name] then
				error(string.format("BufferUtil: duplicate layout field name %q", name), 2)
			end

			-- Explicit names take precedence over legacy primitive aliases.
			offsets[name] = cursor
			types[name] = typ
			explicitNames[name] = true
		elseif legacyTypeAlias and not explicitNames[typ] then
			-- Preserve v1.x last-wins aliases for duplicate primitive entries,
			-- but never let a legacy alias overwrite an explicit named field.
			offsets[typ] = cursor
			types[typ] = typ
		end

		fields[index] = {
			name = name,
			type = typ,
			offset = cursor,
			size = fieldSize,
		}

		cursor += fieldSize

		if cursor > MAX_BUFFER_SIZE then
			error(
				string.format(
					"BufferUtil: compiled layout exceeds Roblox buffer limit of %d bytes",
					MAX_BUFFER_SIZE
				),
				2
			)
		end
	end

	return {
		size = cursor,
		count = #lay,
		off = offsets,
		type = types,
		fields = fields,
	}
end

function BufferUtil.structNew(lay: CompiledLayout): buffer
	if lay.size == nil then
		error("BufferUtil: layout must be compiled with BufferUtil.compileLayout first", 2)
	end

	return createExact(lay.size)
end

function BufferUtil.structGet(
	buff: buffer,
	lay: CompiledLayout,
	field: any,
	typ: ValueType?
): number
	local offset, resolvedType = resolveLayoutField(lay, field, typ)
	return BufferUtil.read(buff, resolvedType, offset)
end

function BufferUtil.structSet(
	buff: buffer,
	lay: CompiledLayout,
	field: any,
	typOrValue: ValueType | number,
	value: number?
): ()
	local resolvedType: ValueType?
	local resolvedValue: number

	if value ~= nil then
		if type(typOrValue) ~= "string" then
			error("BufferUtil: legacy structSet type argument must be a value type string", 2)
		end

		resolvedType = typOrValue :: ValueType
		resolvedValue = value
	else
		if type(typOrValue) ~= "number" then
			error("BufferUtil: structSet value must be a number", 2)
		end

		resolvedType = nil
		resolvedValue = typOrValue
	end

	local offset, typ = resolveLayoutField(lay, field, resolvedType)
	BufferUtil.write(buff, typ, offset, resolvedValue)
end

function BufferUtil.reverse(buff: buffer): ()
	local length = buffer.len(buff)
	local left = 0
	local right = length - 1

	while left < right do
		local a = buffer.readu8(buff, left)
		local b = buffer.readu8(buff, right)

		buffer.writeu8(buff, left, b)
		buffer.writeu8(buff, right, a)

		left += 1
		right -= 1
	end
end

function BufferUtil.equalsRange(
	a: buffer,
	aOffset: number,
	b: buffer,
	bOffset: number,
	count: number
): boolean
	assertByteRange(a, aOffset, count, 2)
	assertByteRange(b, bOffset, count, 2)

	local offset = 0
	local chunkEnd = count - (count % 4)

	while offset < chunkEnd do
		if buffer.readu32(a, aOffset + offset) ~= buffer.readu32(b, bOffset + offset) then
			return false
		end
		offset += 4
	end

	while offset < count do
		if buffer.readu8(a, aOffset + offset) ~= buffer.readu8(b, bOffset + offset) then
			return false
		end
		offset += 1
	end

	return true
end

function BufferUtil.equals(a: buffer, b: buffer): boolean
	local length = buffer.len(a)

	if length ~= buffer.len(b) then
		return false
	end

	return BufferUtil.equalsRange(a, 0, b, 0, length)
end

function BufferUtil.compare(a: buffer, b: buffer): number
	local aLength = buffer.len(a)
	local bLength = buffer.len(b)
	local sharedLength = math.min(aLength, bLength)
	local offset = 0
	local chunkEnd = sharedLength - (sharedLength % 4)

	while offset < chunkEnd do
		if buffer.readu32(a, offset) ~= buffer.readu32(b, offset) then
			for byteOffset = offset, offset + 3 do
				local av = buffer.readu8(a, byteOffset)
				local bv = buffer.readu8(b, byteOffset)

				if av < bv then
					return -1
				elseif av > bv then
					return 1
				end
			end
		end

		offset += 4
	end

	while offset < sharedLength do
		local av = buffer.readu8(a, offset)
		local bv = buffer.readu8(b, offset)

		if av < bv then
			return -1
		elseif av > bv then
			return 1
		end

		offset += 1
	end

	if aLength < bLength then
		return -1
	elseif aLength > bLength then
		return 1
	end

	return 0
end


function BufferUtil.hexDump(buff: buffer, options: HexDumpOptions?): string
	local config = options or {}
	local columns = config.columns or 16
	local showAscii = if config.showAscii == nil then true else config.showAscii
	local showOffset = if config.showOffset == nil then true else config.showOffset
	local start = config.start or 0
	local count = config.count

	if not isInteger(columns) or columns < 1 or columns > 64 then
		error("BufferUtil: hexDump columns must be an integer from 1 to 64", 2)
	end
	if type(showAscii) ~= "boolean" or type(showOffset) ~= "boolean" then
		error("BufferUtil: hexDump showAscii/showOffset must be booleans", 2)
	end

	local length = buffer.len(buff)
	local actualCount = if count == nil then length - start else count
	assertByteRange(buff, start, actualCount, 2)

	if actualCount == 0 then
		return ""
	end

	local rows = table.create((actualCount + columns - 1) // columns)
	local rowIndex = 1
	local finish = start + actualCount

	for rowStart = start, finish - 1, columns do
		local rowCount = math.min(columns, finish - rowStart)
		local hexParts = table.create(columns)
		local asciiParts = if showAscii then table.create(rowCount) else nil

		for index = 0, rowCount - 1 do
			local byteValue = buffer.readu8(buff, rowStart + index)
			hexParts[index + 1] = HEX_LOOKUP[byteValue + 1]

			if asciiParts ~= nil then
				asciiParts[index + 1] = if byteValue >= 32 and byteValue <= 126
					then string.char(byteValue)
					else "."
			end
		end

		local hexText = table.concat(hexParts, " ")
		if showAscii and rowCount < columns then
			hexText ..= string.rep("   ", columns - rowCount)
		end

		local parts = table.create(3)
		local partCount = 0

		if showOffset then
			partCount += 1
			parts[partCount] = string.format("%08X", rowStart)
		end

		partCount += 1
		parts[partCount] = hexText

		if asciiParts ~= nil then
			partCount += 1
			parts[partCount] = "|" .. table.concat(asciiParts) .. "|"
		end

		rows[rowIndex] = table.concat(parts, "  ", 1, partCount)
		rowIndex += 1
	end

	return table.concat(rows, "\n")
end

function BufferUtil.binaryDump(buff: buffer, options: BinaryDumpOptions?): string
	local config = options or {}
	local columns = config.columns or 8
	local showOffset = if config.showOffset == nil then true else config.showOffset
	local start = config.start or 0
	local count = config.count

	if not isInteger(columns) or columns < 1 or columns > 32 then
		error("BufferUtil: binaryDump columns must be an integer from 1 to 32", 2)
	end
	if type(showOffset) ~= "boolean" then
		error("BufferUtil: binaryDump showOffset must be a boolean", 2)
	end

	local length = buffer.len(buff)
	local actualCount = if count == nil then length - start else count
	assertByteRange(buff, start, actualCount, 2)

	if actualCount == 0 then
		return ""
	end

	local rows = table.create((actualCount + columns - 1) // columns)
	local rowIndex = 1
	local finish = start + actualCount

	for rowStart = start, finish - 1, columns do
		local rowCount = math.min(columns, finish - rowStart)
		local binaryParts = table.create(rowCount)

		for index = 0, rowCount - 1 do
			binaryParts[index + 1] = BINARY_LOOKUP[buffer.readu8(buff, rowStart + index) + 1]
		end

		local dataText = table.concat(binaryParts, " ")
		rows[rowIndex] = if showOffset
			then string.format("%08X  %s", rowStart, dataText)
			else dataText
		rowIndex += 1
	end

	return table.concat(rows, "\n")
end

function BufferUtil.diffBytes(
	a: buffer,
	b: buffer,
	limit: number?
): ({BufferDifference}, boolean)
	local maxDifferences = if limit == nil then 256 else limit
	if not isInteger(maxDifferences) or maxDifferences < 1 or maxDifferences > 65_536 then
		error("BufferUtil: diff limit must be an integer from 1 to 65536", 2)
	end

	local aLength = buffer.len(a)
	local bLength = buffer.len(b)
	local maxLength = math.max(aLength, bLength)
	local differences: {BufferDifference} = table.create(math.min(maxDifferences, maxLength))

	for offset = 0, maxLength - 1 do
		local av = if offset < aLength then buffer.readu8(a, offset) else nil
		local bv = if offset < bLength then buffer.readu8(b, offset) else nil

		if av ~= bv then
			if #differences >= maxDifferences then
				return differences, true
			end

			differences[#differences + 1] = {
				offset = offset,
				a = av,
				b = bv,
			}
		end
	end

	return differences, false
end

function BufferUtil.diff(a: buffer, b: buffer, limit: number?): string
	local differences, truncated = BufferUtil.diffBytes(a, b, limit)

	if #differences == 0 then
		return "Buffers are identical"
	end

	local rows = table.create(#differences + 2)
	rows[1] = string.format(
		"Buffer diff: %s vs %s",
		BufferUtil.formatBuffer(a),
		BufferUtil.formatBuffer(b)
	)

	for index, item in differences do
		local left = if item.a == nil then "--" else HEX_LOOKUP[item.a + 1]
		local right = if item.b == nil then "--" else HEX_LOOKUP[item.b + 1]
		rows[index + 1] = string.format("%08X  %s -> %s", item.offset, left, right)
	end

	if truncated then
		rows[#differences + 2] = "... difference list truncated ..."
	end

	return table.concat(rows, "\n")
end

function BufferUtil.inspect(
	buff: buffer,
	lay: CompiledLayout?,
	previewBytes: number?
): string
	local preview = if previewBytes == nil then 64 else previewBytes
	if not isInteger(preview) or preview < 0 or preview > 256 then
		error("BufferUtil: inspect previewBytes must be an integer from 0 to 256", 2)
	end

	local length = buffer.len(buff)
	local previewCount = math.min(length, preview)
	local rows = {
		"BufferUtil Buffer",
		"----------------------------------------",
		"Size       : " .. BufferUtil.formatBuffer(buff),
		"Bits       : " .. BufferUtil.formatBufferBits(buff),
	}

	if previewCount > 0 then
		rows[#rows + 1] = "Hex preview:"
		rows[#rows + 1] = BufferUtil.hexDump(buff, {
			start = 0,
			count = previewCount,
			columns = 16,
			showAscii = true,
			showOffset = true,
		})
		if previewCount < length then
			rows[#rows + 1] = string.format("... %s not shown ...", BufferUtil.formatBytes(length - previewCount))
		end
	end

	if lay ~= nil then
		if not isInteger(lay.size) or lay.size < 0 or lay.fields == nil then
			error("BufferUtil: inspect layout must be compiled with BufferUtil.compileLayout", 2)
		end
		if lay.size > length then
			error(
				string.format(
					"BufferUtil: layout size %d exceeds buffer length %d",
					lay.size,
					length
				),
				2
			)
		end

		rows[#rows + 1] = "Fields:"
		for index, field in lay.fields do
			local label = field.name or ("#" .. tostring(index))
			local value = BufferUtil.read(buff, field.type, field.offset)
			rows[#rows + 1] = string.format(
				"  %-16s %-8s @%-8d %s",
				label,
				field.type,
				field.offset,
				tostring(value)
			)
		end
	end

	return table.concat(rows, "\n")
end

function BufferUtil.toHex(buff: buffer, separator: string?): string
	local length = buffer.len(buff)

	if length == 0 then
		return ""
	end

	local out = table.create(length)

	for offset = 0, length - 1 do
		out[offset + 1] = HEX_LOOKUP[buffer.readu8(buff, offset) + 1]
	end

	return table.concat(out, separator or "")
end

function BufferUtil.toBinaryString(buff: buffer, separator: string?): string
	local length = buffer.len(buff)

	if length == 0 then
		return ""
	end

	local out = table.create(length)

	for offset = 0, length - 1 do
		out[offset + 1] = BINARY_LOOKUP[buffer.readu8(buff, offset) + 1]
	end

	return table.concat(out, separator or "")
end

-- V4.7 object-oriented reader/writer facade and Roblox datatype codecs.
BufferUtil.DEFAULT_WRITER_CAPACITY = 64

export type RobloxDataTypeName =
	"Vector2"
| "Vector3"
| "Color3"
| "UDim"
| "UDim2"
| "Rect"
| "NumberRange"
| "CFrame"
| "BrickColor"

export type BufferWriter = any
export type BufferReader = any

local DATA_TYPE_SIZE: {[string]: number} = {
	Vector2 = 8,
	Vector3 = 12,
	Color3 = 12,
	UDim = 8,
	UDim2 = 16,
	Rect = 16,
	NumberRange = 8,
	CFrame = 48,
	BrickColor = 2,
}

BufferUtil.DataTypeSize = table.freeze(DATA_TYPE_SIZE)

local function assertRobloxDataType(value: any, expected: string, level: number)
	local actual = typeof(value)
	if actual ~= expected then
		error(
			string.format("BufferUtil: expected %s, got %s", expected, actual),
			level
		)
	end
end

function BufferUtil.dataTypeSize(kind: RobloxDataTypeName): number
	if type(kind) ~= "string" then
		error(string.format("BufferUtil: datatype name must be a string, got %s", typeof(kind)), 2)
	end
	local size = DATA_TYPE_SIZE[kind]
	if size == nil then
		error(string.format("BufferUtil: unsupported Roblox datatype %q", tostring(kind)), 2)
	end
	return size
end

function BufferUtil.writeVector2(buff: buffer, offset: number, value: Vector2): ()
	assertRobloxDataType(value, "Vector2", 2)
	assertByteRange(buff, offset, 8, 2)
	buffer.writef32(buff, offset, value.X)
	buffer.writef32(buff, offset + 4, value.Y)
end

function BufferUtil.readVector2(buff: buffer, offset: number): Vector2
	assertByteRange(buff, offset, 8, 2)
	return Vector2.new(
		buffer.readf32(buff, offset),
		buffer.readf32(buff, offset + 4)
	)
end

function BufferUtil.writeVector3(buff: buffer, offset: number, value: Vector3): ()
	assertRobloxDataType(value, "Vector3", 2)
	assertByteRange(buff, offset, 12, 2)
	buffer.writef32(buff, offset, value.X)
	buffer.writef32(buff, offset + 4, value.Y)
	buffer.writef32(buff, offset + 8, value.Z)
end

function BufferUtil.readVector3(buff: buffer, offset: number): Vector3
	assertByteRange(buff, offset, 12, 2)
	return Vector3.new(
		buffer.readf32(buff, offset),
		buffer.readf32(buff, offset + 4),
		buffer.readf32(buff, offset + 8)
	)
end

function BufferUtil.writeColor3(buff: buffer, offset: number, value: Color3): ()
	assertRobloxDataType(value, "Color3", 2)
	assertByteRange(buff, offset, 12, 2)
	buffer.writef32(buff, offset, value.R)
	buffer.writef32(buff, offset + 4, value.G)
	buffer.writef32(buff, offset + 8, value.B)
end

function BufferUtil.readColor3(buff: buffer, offset: number): Color3
	assertByteRange(buff, offset, 12, 2)
	return Color3.new(
		buffer.readf32(buff, offset),
		buffer.readf32(buff, offset + 4),
		buffer.readf32(buff, offset + 8)
	)
end

function BufferUtil.writeColor3u8(buff: buffer, offset: number, value: Color3): ()
	assertRobloxDataType(value, "Color3", 2)
	assertByteRange(buff, offset, 3, 2)
	buffer.writeu8(buff, offset, math.floor(math.clamp(value.R, 0, 1) * 255 + 0.5))
	buffer.writeu8(buff, offset + 1, math.floor(math.clamp(value.G, 0, 1) * 255 + 0.5))
	buffer.writeu8(buff, offset + 2, math.floor(math.clamp(value.B, 0, 1) * 255 + 0.5))
end

function BufferUtil.readColor3u8(buff: buffer, offset: number): Color3
	assertByteRange(buff, offset, 3, 2)
	return Color3.fromRGB(
		buffer.readu8(buff, offset),
		buffer.readu8(buff, offset + 1),
		buffer.readu8(buff, offset + 2)
	)
end

function BufferUtil.writeUDim(buff: buffer, offset: number, value: UDim): ()
	assertRobloxDataType(value, "UDim", 2)
	assertByteRange(buff, offset, 8, 2)
	buffer.writef32(buff, offset, value.Scale)
	BufferUtil.writei32(buff, offset + 4, value.Offset)
end

function BufferUtil.readUDim(buff: buffer, offset: number): UDim
	assertByteRange(buff, offset, 8, 2)
	return UDim.new(
		buffer.readf32(buff, offset),
		buffer.readi32(buff, offset + 4)
	)
end

function BufferUtil.writeUDim2(buff: buffer, offset: number, value: UDim2): ()
	assertRobloxDataType(value, "UDim2", 2)
	assertByteRange(buff, offset, 16, 2)
	buffer.writef32(buff, offset, value.X.Scale)
	BufferUtil.writei32(buff, offset + 4, value.X.Offset)
	buffer.writef32(buff, offset + 8, value.Y.Scale)
	BufferUtil.writei32(buff, offset + 12, value.Y.Offset)
end

function BufferUtil.readUDim2(buff: buffer, offset: number): UDim2
	assertByteRange(buff, offset, 16, 2)
	return UDim2.new(
		buffer.readf32(buff, offset),
		buffer.readi32(buff, offset + 4),
		buffer.readf32(buff, offset + 8),
		buffer.readi32(buff, offset + 12)
	)
end

function BufferUtil.writeRect(buff: buffer, offset: number, value: Rect): ()
	assertRobloxDataType(value, "Rect", 2)
	assertByteRange(buff, offset, 16, 2)
	buffer.writef32(buff, offset, value.Min.X)
	buffer.writef32(buff, offset + 4, value.Min.Y)
	buffer.writef32(buff, offset + 8, value.Max.X)
	buffer.writef32(buff, offset + 12, value.Max.Y)
end

function BufferUtil.readRect(buff: buffer, offset: number): Rect
	assertByteRange(buff, offset, 16, 2)
	return Rect.new(
		Vector2.new(buffer.readf32(buff, offset), buffer.readf32(buff, offset + 4)),
		Vector2.new(buffer.readf32(buff, offset + 8), buffer.readf32(buff, offset + 12))
	)
end

function BufferUtil.writeNumberRange(buff: buffer, offset: number, value: NumberRange): ()
	assertRobloxDataType(value, "NumberRange", 2)
	assertByteRange(buff, offset, 8, 2)
	buffer.writef32(buff, offset, value.Min)
	buffer.writef32(buff, offset + 4, value.Max)
end

function BufferUtil.readNumberRange(buff: buffer, offset: number): NumberRange
	assertByteRange(buff, offset, 8, 2)
	return NumberRange.new(
		buffer.readf32(buff, offset),
		buffer.readf32(buff, offset + 4)
	)
end

function BufferUtil.writeCFrame(buff: buffer, offset: number, value: CFrame): ()
	assertRobloxDataType(value, "CFrame", 2)
	assertByteRange(buff, offset, 48, 2)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()
	buffer.writef32(buff, offset, x)
	buffer.writef32(buff, offset + 4, y)
	buffer.writef32(buff, offset + 8, z)
	buffer.writef32(buff, offset + 12, r00)
	buffer.writef32(buff, offset + 16, r01)
	buffer.writef32(buff, offset + 20, r02)
	buffer.writef32(buff, offset + 24, r10)
	buffer.writef32(buff, offset + 28, r11)
	buffer.writef32(buff, offset + 32, r12)
	buffer.writef32(buff, offset + 36, r20)
	buffer.writef32(buff, offset + 40, r21)
	buffer.writef32(buff, offset + 44, r22)
end

function BufferUtil.readCFrame(buff: buffer, offset: number): CFrame
	assertByteRange(buff, offset, 48, 2)
	return CFrame.new(
		buffer.readf32(buff, offset),
		buffer.readf32(buff, offset + 4),
		buffer.readf32(buff, offset + 8),
		buffer.readf32(buff, offset + 12),
		buffer.readf32(buff, offset + 16),
		buffer.readf32(buff, offset + 20),
		buffer.readf32(buff, offset + 24),
		buffer.readf32(buff, offset + 28),
		buffer.readf32(buff, offset + 32),
		buffer.readf32(buff, offset + 36),
		buffer.readf32(buff, offset + 40),
		buffer.readf32(buff, offset + 44)
	)
end

function BufferUtil.writeBrickColor(buff: buffer, offset: number, value: BrickColor): ()
	assertRobloxDataType(value, "BrickColor", 2)
	BufferUtil.writeu16(buff, offset, value.Number)
end

function BufferUtil.readBrickColor(buff: buffer, offset: number): BrickColor
	return BrickColor.new(BufferUtil.readu16(buff, offset))
end

function BufferUtil.writeDataType(buff: buffer, offset: number, value: any): number
	local kind = typeof(value)
	if kind == "Vector2" then
		BufferUtil.writeVector2(buff, offset, value)
	elseif kind == "Vector3" then
		BufferUtil.writeVector3(buff, offset, value)
	elseif kind == "Color3" then
		BufferUtil.writeColor3(buff, offset, value)
	elseif kind == "UDim" then
		BufferUtil.writeUDim(buff, offset, value)
	elseif kind == "UDim2" then
		BufferUtil.writeUDim2(buff, offset, value)
	elseif kind == "Rect" then
		BufferUtil.writeRect(buff, offset, value)
	elseif kind == "NumberRange" then
		BufferUtil.writeNumberRange(buff, offset, value)
	elseif kind == "CFrame" then
		BufferUtil.writeCFrame(buff, offset, value)
	elseif kind == "BrickColor" then
		BufferUtil.writeBrickColor(buff, offset, value)
	else
		error(string.format("BufferUtil: unsupported Roblox datatype %s", kind), 2)
	end
	return DATA_TYPE_SIZE[kind]
end

function BufferUtil.readDataType(buff: buffer, offset: number, kind: RobloxDataTypeName): (any, number)
	local size = BufferUtil.dataTypeSize(kind)
	local value: any
	if kind == "Vector2" then
		value = BufferUtil.readVector2(buff, offset)
	elseif kind == "Vector3" then
		value = BufferUtil.readVector3(buff, offset)
	elseif kind == "Color3" then
		value = BufferUtil.readColor3(buff, offset)
	elseif kind == "UDim" then
		value = BufferUtil.readUDim(buff, offset)
	elseif kind == "UDim2" then
		value = BufferUtil.readUDim2(buff, offset)
	elseif kind == "Rect" then
		value = BufferUtil.readRect(buff, offset)
	elseif kind == "NumberRange" then
		value = BufferUtil.readNumberRange(buff, offset)
	elseif kind == "CFrame" then
		value = BufferUtil.readCFrame(buff, offset)
	elseif kind == "BrickColor" then
		value = BufferUtil.readBrickColor(buff, offset)
	else
		error(string.format("BufferUtil: unsupported Roblox datatype %q", tostring(kind)), 2)
	end
	return value, size
end

local WRITER_TAG_FIELD = "_bufferUtilWriter"
local READER_TAG_FIELD = "_bufferUtilReader"
local Writer: any = {}
Writer.__index = Writer
local Reader: any = {}
Reader.__index = Reader

local function assertWriterObject(self: any, level: number)
	if typeof(self) ~= "table" or rawget(self, WRITER_TAG_FIELD) ~= true or typeof(rawget(self, "buff")) ~= "buffer" then
		error("BufferUtil: expected BufferWriter", level)
	end
end

local function assertReaderObject(self: any, level: number)
	if typeof(self) ~= "table" or rawget(self, READER_TAG_FIELD) ~= true or typeof(rawget(self, "buff")) ~= "buffer" then
		error("BufferUtil: expected BufferReader", level)
	end
end

local function writerEnsure(self: any, additionalBytes: number, level: number)
	assertWriterObject(self, level)
	assertNonNegativeInteger(additionalBytes, "additionalBytes", level)
	local required = self.pos + additionalBytes
	if required > MAX_BUFFER_SIZE then
		error(
			string.format("BufferUtil: writer requires %d bytes, above Roblox buffer limit %d", required, MAX_BUFFER_SIZE),
			level
		)
	end

	local capacity = buffer.len(self.buff)
	if required <= capacity then
		return
	end

	local nextCapacity = math.max(capacity, 1)
	while nextCapacity < required do
		local doubled = nextCapacity * 2
		if doubled >= MAX_BUFFER_SIZE then
			nextCapacity = MAX_BUFFER_SIZE
		else
			nextCapacity = doubled
		end
		if nextCapacity == MAX_BUFFER_SIZE then
			break
		end
	end

	if nextCapacity < required then
		error("BufferUtil: writer cannot grow enough for requested data", level)
	end
	self.buff = BufferUtil.resize(self.buff, nextCapacity)
end

local function writerCommit(self: any, byteCount: number)
	self.pos += byteCount
	if self.pos > self.length then
		self.length = self.pos
	end
end

-- v4.7.1 hot-path primitives.
-- Valid Writer objects are validated once by BufferUtil.writer(); these paths avoid
-- re-running generic type dispatch and full range validation for every primitive.
local hotBufferLen = buffer.len
local hotBufferCreate = buffer.create
local hotBufferCopy = buffer.copy
local hotReadI8 = buffer.readi8
local hotReadU8 = buffer.readu8
local hotReadI16 = buffer.readi16
local hotReadU16 = buffer.readu16
local hotReadI32 = buffer.readi32
local hotReadU32 = buffer.readu32
local hotReadF32 = buffer.readf32
local hotReadF64 = buffer.readf64
local hotWriteI8 = buffer.writei8
local hotWriteU8 = buffer.writeu8
local hotWriteI16 = buffer.writei16
local hotWriteU16 = buffer.writeu16
local hotWriteI32 = buffer.writei32
local hotWriteU32 = buffer.writeu32
local hotWriteF32 = buffer.writef32
local hotWriteF64 = buffer.writef64
local hotWriteString = buffer.writestring
local hotReadString = buffer.readstring

local function writerReserveHot(self: any, byteCount: number): (buffer, number, number)
	local pos = self.pos
	local required = pos + byteCount
	local buff = self.buff
	local capacity = hotBufferLen(buff)

	if required > capacity then
		if required > MAX_BUFFER_SIZE then
			error(
				string.format(
					"BufferUtil: writer requires %d bytes, above Roblox buffer limit %d",
					required,
					MAX_BUFFER_SIZE
				),
				3
			)
		end

		local nextCapacity = if capacity > 0 then capacity else 1
		while nextCapacity < required do
			local doubled = nextCapacity * 2
			if doubled >= MAX_BUFFER_SIZE then
				nextCapacity = MAX_BUFFER_SIZE
				break
			end
			nextCapacity = doubled
		end

		if nextCapacity < required then
			error("BufferUtil: writer cannot grow enough for requested data", 3)
		end

		local grown = hotBufferCreate(nextCapacity)
		local writtenLength = self.length
		if writtenLength > 0 then
			hotBufferCopy(grown, 0, buff, 0, writtenLength)
		end
		self.buff = grown
		buff = grown
	end

	return buff, pos, required
end

local function commitWriterHot(self: any, nextPos: number)
	self.pos = nextPos
	if nextPos > self.length then
		self.length = nextPos
	end
end

local function assertHotInt(value: number, minValue: number, maxValue: number, label: string)
	if not isInteger(value) or value < minValue or value > maxValue then
		error(
			string.format(
				"BufferUtil: %s value must be an integer in range [%.0f, %.0f], got %s",
				label,
				minValue,
				maxValue,
				tostring(value)
			),
			3
		)
	end
end

local function assertHotNumber(value: any, label: string)
	if type(value) ~= "number" then
		error(string.format("BufferUtil: %s value must be a number", label), 3)
	end
end

function BufferUtil.isWriter(value: any): boolean
	return typeof(value) == "table"
		and rawget(value, WRITER_TAG_FIELD) == true
		and typeof(rawget(value, "buff")) == "buffer"
end

function BufferUtil.isReader(value: any): boolean
	return typeof(value) == "table"
		and rawget(value, READER_TAG_FIELD) == true
		and typeof(rawget(value, "buff")) == "buffer"
end

function BufferUtil.writer(initialCapacity: number?): BufferWriter
	local capacity = initialCapacity
	if capacity == nil then
		capacity = BufferUtil.DEFAULT_WRITER_CAPACITY
	end
	assertNonNegativeInteger(capacity, "initialCapacity", 2)
	if capacity > MAX_BUFFER_SIZE then
		error(string.format("BufferUtil: initialCapacity exceeds %d bytes", MAX_BUFFER_SIZE), 2)
	end
	return setmetatable({
		buff = createExact(capacity),
		pos = 0,
		length = 0,
		[WRITER_TAG_FIELD] = true,
	}, Writer) :: any
end

function BufferUtil.reader(buff: buffer, pos: number?): BufferReader
	if typeof(buff) ~= "buffer" then
		error(string.format("BufferUtil: reader expected buffer, got %s", typeof(buff)), 2)
	end
	local start = pos or 0
	assertBytePosition(buff, start, 2)
	return setmetatable({
		buff = buff,
		pos = start,
		start = start,
		[READER_TAG_FIELD] = true,
	}, Reader) :: any
end

function Writer:Tell(): number
	assertWriterObject(self, 2)
	return self.pos
end

function Writer:Length(): number
	assertWriterObject(self, 2)
	return self.length
end

function Writer:Capacity(): number
	assertWriterObject(self, 2)
	return buffer.len(self.buff)
end

function Writer:Remaining(): number
	assertWriterObject(self, 2)
	return buffer.len(self.buff) - self.pos
end

function Writer:EnsureCapacity(additionalBytes: number): BufferWriter
	writerEnsure(self, additionalBytes, 2)
	return self
end

function Writer:Seek(pos: number): BufferWriter
	assertWriterObject(self, 2)
	assertNonNegativeInteger(pos, "pos", 2)
	if pos > self.length then
		error(string.format("BufferUtil: writer seek position %d exceeds written length %d", pos, self.length), 2)
	end
	self.pos = pos
	return self
end

function Writer:Reset(): BufferWriter
	assertWriterObject(self, 2)
	self.pos = 0
	return self
end

function Writer:Clear(): BufferWriter
	assertWriterObject(self, 2)
	local capacity = buffer.len(self.buff)
	if capacity > 0 then
		buffer.fill(self.buff, 0, 0, capacity)
	end
	self.pos = 0
	self.length = 0
	return self
end

function Writer:Skip(byteCount: number): BufferWriter
	assertNonNegativeInteger(byteCount, "byteCount", 2)
	writerEnsure(self, byteCount, 2)
	writerCommit(self, byteCount)
	return self
end

function Writer:Write(typ: ValueType, value: number): BufferWriter
	local byteCount = BufferUtil.sizeOf(typ)
	writerEnsure(self, byteCount, 2)
	BufferUtil.write(self.buff, typ, self.pos, value)
	writerCommit(self, byteCount)
	return self
end

-- Native primitive methods are explicit in v4.7.1 so they bypass generic
-- Writer.Write -> BufferUtil.write dispatch while preserving strict values.
function Writer:WriteI8(value: number): BufferWriter
	assertHotInt(value, -128, 127, "i8")
	local buff, pos, nextPos = writerReserveHot(self, 1)
	hotWriteI8(buff, pos, value)
	commitWriterHot(self, nextPos)
	return self
end

function Writer:WriteU8(value: number): BufferWriter
	assertHotInt(value, 0, 255, "u8")
	local buff, pos, nextPos = writerReserveHot(self, 1)
	hotWriteU8(buff, pos, value)
	commitWriterHot(self, nextPos)
	return self
end

function Writer:WriteI16(value: number): BufferWriter
	assertHotInt(value, -32768, 32767, "i16")
	local buff, pos, nextPos = writerReserveHot(self, 2)
	hotWriteI16(buff, pos, value)
	commitWriterHot(self, nextPos)
	return self
end

function Writer:WriteU16(value: number): BufferWriter
	assertHotInt(value, 0, 65535, "u16")
	local buff, pos, nextPos = writerReserveHot(self, 2)
	hotWriteU16(buff, pos, value)
	commitWriterHot(self, nextPos)
	return self
end

function Writer:WriteI32(value: number): BufferWriter
	assertHotInt(value, -2147483648, 2147483647, "i32")
	local buff, pos, nextPos = writerReserveHot(self, 4)
	hotWriteI32(buff, pos, value)
	commitWriterHot(self, nextPos)
	return self
end

function Writer:WriteU32(value: number): BufferWriter
	assertHotInt(value, 0, 4294967295, "u32")
	local buff, pos, nextPos = writerReserveHot(self, 4)
	hotWriteU32(buff, pos, value)
	commitWriterHot(self, nextPos)
	return self
end

function Writer:WriteF32(value: number): BufferWriter
	assertHotNumber(value, "f32")
	local buff, pos, nextPos = writerReserveHot(self, 4)
	hotWriteF32(buff, pos, value)
	commitWriterHot(self, nextPos)
	return self
end

function Writer:WriteF64(value: number): BufferWriter
	assertHotNumber(value, "f64")
	local buff, pos, nextPos = writerReserveHot(self, 8)
	hotWriteF64(buff, pos, value)
	commitWriterHot(self, nextPos)
	return self
end

function Writer:WriteString(value: string, count: number?): BufferWriter
	if type(value) ~= "string" then
		error(string.format("BufferUtil: writer string must be a string, got %s", typeof(value)), 2)
	end
	local valueLength = #value
	local actualCount = count or valueLength
	if not isInteger(actualCount) or actualCount < 0 or actualCount > valueLength then
		error(string.format("BufferUtil: writer string count must be 0..%d", valueLength), 2)
	end
	local buff, pos, nextPos = writerReserveHot(self, actualCount)
	if actualCount > 0 then
		hotWriteString(buff, pos, value, actualCount)
	end
	commitWriterHot(self, nextPos)
	return self
end

function Writer:WriteBuffer(source: buffer, count: number?): BufferWriter
	if typeof(source) ~= "buffer" then
		error(string.format("BufferUtil: WriteBuffer expected buffer, got %s", typeof(source)), 2)
	end
	local sourceLength = buffer.len(source)
	local actualCount = count or sourceLength
	assertNonNegativeInteger(actualCount, "count", 2)
	if actualCount > sourceLength then
		error(string.format("BufferUtil: WriteBuffer count %d exceeds source length %d", actualCount, sourceLength), 2)
	end
	writerEnsure(self, actualCount, 2)
	if actualCount > 0 then
		buffer.copy(self.buff, self.pos, source, 0, actualCount)
	end
	writerCommit(self, actualCount)
	return self
end

function Writer:WriteBool(value: boolean): BufferWriter
	if type(value) ~= "boolean" then
		error(string.format("BufferUtil: WriteBool expected boolean, got %s", typeof(value)), 2)
	end
	return self:Write("u8", if value then 1 else 0)
end

function Writer:WriteVarUInt(value: number): BufferWriter
	local byteCount = BufferUtil.varUIntSize(value)
	writerEnsure(self, byteCount, 2)
	BufferUtil.writeVarUInt(self.buff, self.pos, value)
	writerCommit(self, byteCount)
	return self
end

function Writer:WriteVarInt(value: number): BufferWriter
	local byteCount = BufferUtil.varIntSize(value)
	writerEnsure(self, byteCount, 2)
	BufferUtil.writeVarInt(self.buff, self.pos, value)
	writerCommit(self, byteCount)
	return self
end

function Writer:WriteVarString(value: string): BufferWriter
	if type(value) ~= "string" then
		error(string.format("BufferUtil: WriteVarString expected string, got %s", typeof(value)), 2)
	end
	local byteCount = BufferUtil.varUIntSize(#value) + #value
	writerEnsure(self, byteCount, 2)
	BufferUtil.writeVarString(self.buff, self.pos, value)
	writerCommit(self, byteCount)
	return self
end

function Writer:WriteDataType(value: any): BufferWriter
	local kind = typeof(value)
	local byteCount = DATA_TYPE_SIZE[kind]
	if byteCount == nil then
		error(string.format("BufferUtil: unsupported Roblox datatype %s", kind), 2)
	end
	writerEnsure(self, byteCount, 2)
	BufferUtil.writeDataType(self.buff, self.pos, value)
	writerCommit(self, byteCount)
	return self
end

function Writer:WriteColor3u8(value: Color3): BufferWriter
	writerEnsure(self, 3, 2)
	BufferUtil.writeColor3u8(self.buff, self.pos, value)
	writerCommit(self, 3)
	return self
end


function Writer:WriteVector2(value: Vector2): BufferWriter
	if typeof(value) ~= "Vector2" then
		error(string.format("BufferUtil: WriteVector2 expected Vector2, got %s", typeof(value)), 2)
	end
	local buff, pos, nextPos = writerReserveHot(self, 8)
	hotWriteF32(buff, pos, value.X)
	hotWriteF32(buff, pos + 4, value.Y)
	commitWriterHot(self, nextPos)
	return self
end

function Writer:WriteVector3(value: Vector3): BufferWriter
	if typeof(value) ~= "Vector3" then
		error(string.format("BufferUtil: WriteVector3 expected Vector3, got %s", typeof(value)), 2)
	end
	local buff, pos, nextPos = writerReserveHot(self, 12)
	hotWriteF32(buff, pos, value.X)
	hotWriteF32(buff, pos + 4, value.Y)
	hotWriteF32(buff, pos + 8, value.Z)
	commitWriterHot(self, nextPos)
	return self
end

function Writer:WriteColor3(value: Color3): BufferWriter
	return self:WriteDataType(value)
end

function Writer:WriteUDim(value: UDim): BufferWriter
	return self:WriteDataType(value)
end

function Writer:WriteUDim2(value: UDim2): BufferWriter
	return self:WriteDataType(value)
end

function Writer:WriteRect(value: Rect): BufferWriter
	return self:WriteDataType(value)
end

function Writer:WriteNumberRange(value: NumberRange): BufferWriter
	return self:WriteDataType(value)
end

function Writer:WriteCFrame(value: CFrame): BufferWriter
	return self:WriteDataType(value)
end

function Writer:WriteBrickColor(value: BrickColor): BufferWriter
	return self:WriteDataType(value)
end

function Writer:GetBuffer(): buffer
	assertWriterObject(self, 2)
	return self.buff
end

function Writer:ToBuffer(shrink: boolean?): buffer
	assertWriterObject(self, 2)
	if shrink == false then
		return BufferUtil.clone(self.buff)
	end
	return BufferUtil.clone(self.buff, self.length)
end

function Writer:Finish(): buffer
	local length = self.length
	if length == 0 then
		return buffer.fromstring("")
	end
	local out = hotBufferCreate(length)
	hotBufferCopy(out, 0, self.buff, 0, length)
	return out
end

function Writer:Shrink(): buffer
	assertWriterObject(self, 2)
	if buffer.len(self.buff) ~= self.length then
		self.buff = BufferUtil.resize(self.buff, self.length)
	end
	return self.buff
end

function Reader:Tell(): number
	assertReaderObject(self, 2)
	return self.pos
end

function Reader:Remaining(): number
	assertReaderObject(self, 2)
	return buffer.len(self.buff) - self.pos
end

function Reader:Seek(pos: number): BufferReader
	assertReaderObject(self, 2)
	assertBytePosition(self.buff, pos, 2)
	self.pos = pos
	return self
end

function Reader:Reset(): BufferReader
	assertReaderObject(self, 2)
	self.pos = self.start
	return self
end

function Reader:Skip(byteCount: number): BufferReader
	assertReaderObject(self, 2)
	assertNonNegativeInteger(byteCount, "byteCount", 2)
	assertByteRange(self.buff, self.pos, byteCount, 2)
	self.pos += byteCount
	return self
end

function Reader:CanRead(typ: ValueType): boolean
	if not BufferUtil.isReader(self) or not BufferUtil.isValidType(typ) then
		return false
	end
	return BufferUtil.canAccess(self.buff, self.pos, BufferUtil.sizeOf(typ))
end

function Reader:Peek(typ: ValueType): number
	assertReaderObject(self, 2)
	return BufferUtil.read(self.buff, typ, self.pos)
end

function Reader:Read(typ: ValueType): number
	assertReaderObject(self, 2)
	local byteCount = BufferUtil.sizeOf(typ)
	local value = BufferUtil.read(self.buff, typ, self.pos)
	self.pos += byteCount
	return value
end

-- Native primitive reads rely on Roblox's own bounds check. The cursor is
-- committed only after the native read succeeds, so failed reads stay atomic.
function Reader:ReadI8(): number
	local pos = self.pos
	local value = hotReadI8(self.buff, pos)
	self.pos = pos + 1
	return value
end

function Reader:ReadU8(): number
	local pos = self.pos
	local value = hotReadU8(self.buff, pos)
	self.pos = pos + 1
	return value
end

function Reader:ReadI16(): number
	local pos = self.pos
	local value = hotReadI16(self.buff, pos)
	self.pos = pos + 2
	return value
end

function Reader:ReadU16(): number
	local pos = self.pos
	local value = hotReadU16(self.buff, pos)
	self.pos = pos + 2
	return value
end

function Reader:ReadI32(): number
	local pos = self.pos
	local value = hotReadI32(self.buff, pos)
	self.pos = pos + 4
	return value
end

function Reader:ReadU32(): number
	local pos = self.pos
	local value = hotReadU32(self.buff, pos)
	self.pos = pos + 4
	return value
end

function Reader:ReadF32(): number
	local pos = self.pos
	local value = hotReadF32(self.buff, pos)
	self.pos = pos + 4
	return value
end

function Reader:ReadF64(): number
	local pos = self.pos
	local value = hotReadF64(self.buff, pos)
	self.pos = pos + 8
	return value
end

function Reader:ReadString(count: number): string
	if not isInteger(count) or count < 0 then
		error(string.format("BufferUtil: string count must be a non-negative integer, got %s", tostring(count)), 2)
	end
	local pos = self.pos
	local value = if count == 0 then "" else hotReadString(self.buff, pos, count)
	self.pos = pos + count
	return value
end

function Reader:ReadBuffer(count: number): buffer
	assertReaderObject(self, 2)
	assertByteRange(self.buff, self.pos, count, 2)
	local value = BufferUtil.slice(self.buff, self.pos, count)
	self.pos += count
	return value
end

function Reader:ReadBool(): boolean
	return self:Read("u8") ~= 0
end

function Reader:ReadVarUInt(): number
	assertReaderObject(self, 2)
	local value, byteCount = BufferUtil.readVarUInt(self.buff, self.pos)
	self.pos += byteCount
	return value
end

function Reader:ReadVarInt(): number
	assertReaderObject(self, 2)
	local value, byteCount = BufferUtil.readVarInt(self.buff, self.pos)
	self.pos += byteCount
	return value
end

function Reader:ReadVarString(): string
	assertReaderObject(self, 2)
	local value, byteCount = BufferUtil.readVarString(self.buff, self.pos)
	self.pos += byteCount
	return value
end

function Reader:ReadDataType(kind: RobloxDataTypeName): any
	assertReaderObject(self, 2)
	local value, byteCount = BufferUtil.readDataType(self.buff, self.pos, kind)
	self.pos += byteCount
	return value
end

function Reader:ReadColor3u8(): Color3
	assertReaderObject(self, 2)
	local value = BufferUtil.readColor3u8(self.buff, self.pos)
	self.pos += 3
	return value
end


function Reader:ReadVector2(): Vector2
	local pos = self.pos
	local x = hotReadF32(self.buff, pos)
	local y = hotReadF32(self.buff, pos + 4)
	self.pos = pos + 8
	return Vector2.new(x, y)
end

function Reader:ReadVector3(): Vector3
	local pos = self.pos
	local x = hotReadF32(self.buff, pos)
	local y = hotReadF32(self.buff, pos + 4)
	local z = hotReadF32(self.buff, pos + 8)
	self.pos = pos + 12
	return Vector3.new(x, y, z)
end

function Reader:ReadColor3(): Color3
	return self:ReadDataType("Color3")
end

function Reader:ReadUDim(): UDim
	return self:ReadDataType("UDim")
end

function Reader:ReadUDim2(): UDim2
	return self:ReadDataType("UDim2")
end

function Reader:ReadRect(): Rect
	return self:ReadDataType("Rect")
end

function Reader:ReadNumberRange(): NumberRange
	return self:ReadDataType("NumberRange")
end

function Reader:ReadCFrame(): CFrame
	return self:ReadDataType("CFrame")
end

function Reader:ReadBrickColor(): BrickColor
	return self:ReadDataType("BrickColor")
end

function Reader:GetBuffer(): buffer
	assertReaderObject(self, 2)
	return self.buff
end

local NUMERIC_METHOD_SUFFIX: {[ValueType]: string} = {
	i8 = "I8",
	u8 = "U8",
	i16 = "I16",
	u16 = "U16",
	i24 = "I24",
	u24 = "U24",
	i32 = "I32",
	u32 = "U32",
	i40 = "I40",
	u40 = "U40",
	i48 = "I48",
	u48 = "U48",
	i53 = "I53",
	u53 = "U53",
	f8e4m3 = "F8E4M3",
	f8e5m2 = "F8E5M2",
	f16 = "F16",
	bf16 = "BF16",
	f24 = "F24",
	f32 = "F32",
	f40 = "F40",
	f48 = "F48",
	f64 = "F64",
}

local function makeWriterNumericMethod(typ: ValueType): (any, number) -> any
	return function(self: any, value: number): any
		return Writer.Write(self, typ, value)
	end
end

local function makeReaderNumericMethod(typ: ValueType): (any) -> number
	return function(self: any): number
		return Reader.Read(self, typ)
	end
end

local function makeReaderPeekNumericMethod(typ: ValueType): (any) -> number
	return function(self: any): number
		assertReaderObject(self, 2)
		return BufferUtil.read(self.buff, typ, self.pos)
	end
end

for typ, suffix in NUMERIC_METHOD_SUFFIX do
	local methodName = "Write" .. suffix
	local readName = "Read" .. suffix
	local writeMethod = (Writer :: any)[methodName]
	local readMethod = (Reader :: any)[readName]

	if writeMethod == nil then
		writeMethod = makeWriterNumericMethod(typ)
		;(Writer :: any)[methodName] = writeMethod
	end
	if readMethod == nil then
		readMethod = makeReaderNumericMethod(typ)
		;(Reader :: any)[readName] = readMethod
	end

	;(Writer :: any)["write" .. typ] = writeMethod
	;(Reader :: any)["read" .. typ] = readMethod
	;(Reader :: any)["Peek" .. suffix] = makeReaderPeekNumericMethod(typ)
end

-- Friendly long-form aliases for migration/ergonomics.
;(Writer :: any).WriteInt8 = Writer.WriteI8
;(Writer :: any).WriteUInt8 = Writer.WriteU8
;(Writer :: any).WriteInt16 = Writer.WriteI16
;(Writer :: any).WriteUInt16 = Writer.WriteU16
;(Writer :: any).WriteInt32 = Writer.WriteI32
;(Writer :: any).WriteUInt32 = Writer.WriteU32
;(Writer :: any).WriteFloat32 = Writer.WriteF32
;(Writer :: any).WriteFloat64 = Writer.WriteF64
;(Reader :: any).ReadInt8 = Reader.ReadI8
;(Reader :: any).ReadUInt8 = Reader.ReadU8
;(Reader :: any).ReadInt16 = Reader.ReadI16
;(Reader :: any).ReadUInt16 = Reader.ReadU16
;(Reader :: any).ReadInt32 = Reader.ReadI32
;(Reader :: any).ReadUInt32 = Reader.ReadU32
;(Reader :: any).ReadFloat32 = Reader.ReadF32
;(Reader :: any).ReadFloat64 = Reader.ReadF64

-- Friendly lowercase aliases for the object facade.
;(Writer :: any).write = Writer.Write
;(Writer :: any).writeString = Writer.WriteString
;(Writer :: any).writeBuffer = Writer.WriteBuffer
;(Writer :: any).writeBool = Writer.WriteBool
;(Writer :: any).writeVarUInt = Writer.WriteVarUInt
;(Writer :: any).writeVarInt = Writer.WriteVarInt
;(Writer :: any).writeVarString = Writer.WriteVarString
;(Writer :: any).writeDataType = Writer.WriteDataType
;(Writer :: any).writeVector2 = Writer.WriteVector2
;(Writer :: any).writeVector3 = Writer.WriteVector3
;(Writer :: any).writeColor3 = Writer.WriteColor3
;(Writer :: any).writeUDim = Writer.WriteUDim
;(Writer :: any).writeUDim2 = Writer.WriteUDim2
;(Writer :: any).writeRect = Writer.WriteRect
;(Writer :: any).writeNumberRange = Writer.WriteNumberRange
;(Writer :: any).writeCFrame = Writer.WriteCFrame
;(Writer :: any).writeBrickColor = Writer.WriteBrickColor
;(Writer :: any).finish = Writer.Finish
;(Reader :: any).read = Reader.Read
;(Reader :: any).readString = Reader.ReadString
;(Reader :: any).readBuffer = Reader.ReadBuffer
;(Reader :: any).readBool = Reader.ReadBool
;(Reader :: any).readVarUInt = Reader.ReadVarUInt
;(Reader :: any).readVarInt = Reader.ReadVarInt
;(Reader :: any).readVarString = Reader.ReadVarString
;(Reader :: any).readDataType = Reader.ReadDataType
;(Reader :: any).readVector2 = Reader.ReadVector2
;(Reader :: any).readVector3 = Reader.ReadVector3
;(Reader :: any).readColor3 = Reader.ReadColor3
;(Reader :: any).readUDim = Reader.ReadUDim
;(Reader :: any).readUDim2 = Reader.ReadUDim2
;(Reader :: any).readRect = Reader.ReadRect
;(Reader :: any).readNumberRange = Reader.ReadNumberRange
;(Reader :: any).readCFrame = Reader.ReadCFrame
;(Reader :: any).readBrickColor = Reader.ReadBrickColor

BufferUtil.Writer = Writer
BufferUtil.Reader = Reader

return BufferUtil
