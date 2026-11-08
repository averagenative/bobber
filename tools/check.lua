--[[
Static checks for Bobber. Run from the repository root:

    nvim -l tools/check.lua

Neovim's built-in LuaJIT runs this; it speaks Lua 5.1, the same Lua the game
uses. The checks:

* Every Lua file in the TOC exists and compiles.
* Every Lua file in the repository root is listed in the TOC.
* No file uses `goto` or other syntax WoW's Lua 5.1 doesn't have.
* Every source file is plain ASCII.
* CHANGELOG.md has an entry for the TOC's version.

Exits with status 1 if anything fails.
]]

local failureCount = 0

local function Fail(message)
    failureCount = failureCount + 1
    print("FAIL " .. message)
end

local function ReadFile(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local contents = file:read("*a")
    file:close()
    return contents
end

local tocText = ReadFile("Bobber.toc")
if not tocText then
    print("FAIL run this from the repository root (Bobber.toc not found)")
    os.exit(1)
end

local tocVersion = tocText:match("## Version:%s*([%w%.%-]+)")
local listedLuaFiles = {}
local isListed = {}
for line in tocText:gmatch("[^\r\n]+") do
    if line:match("^[%w_]+%.lua$") then
        listedLuaFiles[#listedLuaFiles + 1] = line
        isListed[line] = true
    end
end

-- 1. Each listed file exists and compiles.
for _, luaFile in ipairs(listedLuaFiles) do
    local source = ReadFile(luaFile)
    if not source then
        Fail(luaFile .. " is in the TOC but doesn't exist")
    else
        local compiled, compileError = loadstring(source, "@" .. luaFile)
        if not compiled then
            Fail(compileError)
        end
        -- LuaJIT accepts goto; WoW's Lua 5.1 doesn't.
        if source:match("%f[%w_]goto%f[^%w_]") then
            Fail(luaFile .. " uses goto, which WoW's Lua doesn't support")
        end
    end
end

-- 2. Every root Lua file is listed.
local listing = io.popen("ls -1")
for fileName in listing:lines() do
    if fileName:match("%.lua$") and not isListed[fileName] then
        Fail(fileName .. " isn't listed in Bobber.toc, so the game won't load it")
    end
end
listing:close()

-- 3. Plain ASCII in everything that ships or documents.
local filesToCheckForAscii = { "Bobber.toc", "Bindings.xml", "README.md", "CHANGELOG.md", "LICENSE" }
for _, luaFile in ipairs(listedLuaFiles) do
    filesToCheckForAscii[#filesToCheckForAscii + 1] = luaFile
end
for _, path in ipairs(filesToCheckForAscii) do
    local contents = ReadFile(path)
    if contents then
        local lineNumber = 1
        for line in (contents .. "\n"):gmatch("([^\n]*)\n") do
            if line:find("[\128-\255]") then
                Fail(path .. ":" .. lineNumber .. " has a non-ASCII character")
            end
            lineNumber = lineNumber + 1
        end
    end
end

-- 4. The changelog covers this version.
local changelog = ReadFile("CHANGELOG.md") or ""
if not tocVersion then
    Fail("Bobber.toc has no ## Version line")
elseif not changelog:find("## " .. tocVersion:gsub("%p", "%%%0"), 1) then
    Fail("CHANGELOG.md has no '## " .. tocVersion .. "' entry")
end

if failureCount > 0 then
    print(failureCount .. " check(s) failed")
    os.exit(1)
end
print("ok   static checks passed (" .. #listedLuaFiles .. " Lua files, version " .. tostring(tocVersion) .. ")")
