-- Secure loader for CAC Ultimate
local HttpService = game:GetService("HttpService")

local http_request = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
if not http_request then
    error("Executor does not support HTTP requests")
end

local API_BASE = "https://cac-licensing-api.cacultimatev1.workers.dev"

local function getShared()
    local shared = (_G or {})
    pcall(function()
        if getgenv then
            shared = getgenv()
        end
    end)
    return shared
end

local function parseJson(raw)
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if ok then return decoded end
    return nil
end

local function gethwid()
    local file = "cac_ultimate_hwid_v4.txt"
    if isfile and readfile and writefile then
        if isfile(file) then
            return tostring(readfile(file)):gsub("%s+", "")
        end
        local generated = HttpService:GenerateGUID(false)
        pcall(function() writefile(file, generated) end)
        return generated
    end
    return HttpService:GenerateGUID(false)
end

local function readLoaderKeyFromFile()
    local candidates = {
        "cac_loader_key.txt",
        "workspace/cac_loader_key.txt",
        "Workspace/cac_loader_key.txt",
        "CAC_Output/cac_loader_key.txt"
    }

    if isfile and readfile then
        for _, path in ipairs(candidates) do
            local okExists, exists = pcall(function() return isfile(path) end)
            if okExists and exists then
                local okRead, content = pcall(function() return readfile(path) end)
                if okRead and content and tostring(content):gsub("%s+", "") ~= "" then
                    return tostring(content):gsub("%s+", "")
                end
            end
        end
    end

    return nil
end

local function postJson(path, payload)
    local ok, response = pcall(function()
        return http_request({
            Url = API_BASE .. path,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload)
        })
    end)

    if not ok or not response then
        return false, nil, "Network error"
    end

    local data = parseJson(response.Body or "")
    if response.StatusCode < 200 or response.StatusCode > 299 then
        local msg = "Request failed"
        if data and data.error and data.error.message then
            msg = tostring(data.error.message)
        end
        return false, data, msg
    end

    return true, data, nil
end

local function getText(url)
    local ok, response = pcall(function()
        return http_request({ Url = url, Method = "GET" })
    end)
    if not ok or not response then
        return false, nil, "Download failed"
    end
    if response.StatusCode < 200 or response.StatusCode > 299 then
        local parsed = parseJson(response.Body or "")
        if parsed and parsed.error and parsed.error.message then
            return false, nil, "Download HTTP " .. tostring(response.StatusCode) .. ": " .. tostring(parsed.error.message)
        end
        return false, nil, "Download HTTP " .. tostring(response.StatusCode)
    end
    return true, response.Body, nil
end

local hwid = gethwid()
local clientVersion = "cac-loader-v1"

local sessionToken = nil
local resolvedKey = nil

local okAuto, dataAuto = postJson("/v1/auth/session/auto-start", {
    hwid = hwid,
    device_label = "roblox-client",
    client_version = clientVersion
})

if okAuto and dataAuto and dataAuto.ok and dataAuto.data and dataAuto.data.session_token then
    sessionToken = tostring(dataAuto.data.session_token)
end

if not sessionToken then
    local shared = getShared()

    local key = nil
    if shared and shared.CAC_KEY then
        key = tostring(shared.CAC_KEY)
    end
    if (not key or key:gsub("%s+", "") == "") and shared and shared.KEY then
        key = tostring(shared.KEY)
    end
    if (not key or key:gsub("%s+", "") == "") and shared and shared.cac_key then
        key = tostring(shared.cac_key)
    end
    if not key or key:gsub("%s+", "") == "" then
        key = readLoaderKeyFromFile()
    end

    if not key or key:gsub("%s+", "") == "" then
        error("Auto-login unavailable. Run in ONE line: getgenv().CAC_KEY='YOUR_KEY'; loadstring(game:HttpGet('https://raw.githubusercontent.com/cacultimate/scriptv1/refs/heads/main/executor-loader.lua'))()")
    end

    local okStart, dataStart, errStart = postJson("/v1/auth/session/start", {
        key = key,
        hwid = hwid,
        device_label = "roblox-client",
        client_version = clientVersion
    })

    if not okStart or not dataStart or not dataStart.ok or not dataStart.data or not dataStart.data.session_token then
        error("Login failed: " .. tostring(errStart or "unknown"))
    end

    sessionToken = tostring(dataStart.data.session_token)
    resolvedKey = tostring(key)
end

local okTicket, dataTicket, errTicket = postJson("/v1/client/script/ticket", {
    session_token = sessionToken,
    hwid = hwid
})

if not okTicket or not dataTicket or not dataTicket.ok or not dataTicket.data or not dataTicket.data.download_url then
    error("Failed to get script ticket: " .. tostring(errTicket or "unknown"))
end

local okScript, scriptBody, errScript = getText(tostring(dataTicket.data.download_url))
if not okScript or not scriptBody or scriptBody == "" then
    error("Failed to download protected script: " .. tostring(errScript or "unknown"))
end

local sharedEnv = getShared()

sharedEnv.CAC_PREAUTH_TOKEN = sessionToken
if resolvedKey and resolvedKey ~= "" then
    sharedEnv.CAC_LAST_KEY = resolvedKey
    pcall(function()
        if writefile then
            writefile("cac_loader_key.txt", resolvedKey)
        end
    end)
end
sharedEnv.CAC_KEY = nil

local fn, compileErr = loadstring(scriptBody)
if not fn then
    error("Compile failed: " .. tostring(compileErr))
end

fn()
