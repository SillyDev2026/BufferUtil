--!strict
-- Roblox Studio Script beside a ModuleScript named buffer.
local U = require(script.Parent:WaitForChild("buffer"))
assert(U.VERSION == "1.1.1")
for _, text in {"", "a", "ab", "abc", "foobar", string.rep("a\000b", 1000)} do
    local encoded = U.toBase64(buffer.fromstring(text))
    local decoded = U.fromBase64(encoded)
    assert(buffer.tostring(decoded) == text, "Base64 round trip failed")
end
local spaces = U.fromBase64(" Zm9v\nYmFy ")
assert(buffer.tostring(spaces) == "foobar", "Whitespace tolerance changed")
for _, bad in {"A", "==AA", "Zm=v", "Zm9=", "Zg=A", "Zg==AAAA", "####", "Zh=="} do
    assert(not pcall(U.fromBase64, bad), "Invalid Base64 unexpectedly accepted: " .. bad)
end
print("BufferUtil v1.1.1 Base64 regression PASS")
