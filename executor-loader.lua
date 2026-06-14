-- Secure loader for CAC Ultimate
local HttpService = game:GetService("HttpService")

local requestCandidates = {}
local requestCandidateNames = {}
local seenRequestCandidates = {}

local function addRequestCandidate(name, fn)
    if type(fn) == "function" and not seenRequestCandidates[fn] then
        seenRequestCandidates[fn] = true
        requestCandidates[#requestCandidates + 1] = fn
        requestCandidateNames[#requestCandidateNames + 1] = name
    end
end

addRequestCandidate("syn.request", syn and syn.request)
addRequestCandidate("http.request", http and http.request)
addRequestCandidate("http_request", http_request)
addRequestCandidate("fluxus.request", fluxus and fluxus.request)
addRequestCandidate("request", request)

if #requestCandidates == 0 then
    error("Executor does not support HTTP requests")
end

local API_BASE = "https://cac-licensing-api.cacultimatev1.workers.dev"
local HTTP_HEADER_PROFILES = {
    {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
        ["User-Agent"] = "Roblox/WinInet",
        ["X-CAC-Client"] = "executor-loader"
    },
    {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json, text/plain, */*",
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36",
        ["X-CAC-Client"] = "executor-loader"
    },
    {
        ["Content-Type"] = "application/json"
    }
}

local HTTP_GET_HEADER_PROFILES = {
    {
        ["Accept"] = "text/plain, application/json, */*",
        ["User-Agent"] = "Roblox/WinInet",
        ["X-CAC-Client"] = "executor-loader"
    },
    {
        ["Accept"] = "text/plain, application/json, */*",
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36",
        ["X-CAC-Client"] = "executor-loader"
    },
    {}
}

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

local function getStatusCode(response)
    return tonumber(response and (response.StatusCode or response.Status or response.status_code or response.status)) or 0
end

local function responsePreview(body)
    local text = tostring(body or "")
    text = text:gsub("[%c\r\n\t]", " ")
    text = text:gsub("%s+", " ")
    if #text > 180 then
        text = text:sub(1, 180) .. "..."
    end
    return text
end

local function apiErrorMessage(prefix, response, data)
    local statusCode = getStatusCode(response)
    local msg = prefix or "Request failed"
    if data and data.error then
        if data.error.message then
            msg = tostring(data.error.message)
        elseif data.error.code then
            msg = tostring(data.error.code)
        end
    end

    local bodyHint = responsePreview(response and response.Body or "")
    if bodyHint ~= "" and (not data or not data.error) then
        msg = msg .. " | body: " .. bodyHint
    end

    if statusCode > 0 then
        return "HTTP " .. tostring(statusCode) .. ": " .. msg
    end
    return msg
end

local function requestWithCandidate(fn, options)
    local ok, response = pcall(function()
        return fn(options)
    end)

    if not ok or not response then
        return false, nil
    end

    return true, response
end

local function requestLabel(candidateName, profileIndex)
    if profileIndex and profileIndex > 0 then
        return tostring(candidateName) .. "/h" .. tostring(profileIndex)
    end
    return tostring(candidateName)
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

local function deviceTokenPaths()
    return {
        "cac_device_token.txt",
        "workspace/cac_device_token.txt",
        "Workspace/cac_device_token.txt",
        "CAC_Output/cac_device_token.txt"
    }
end

local function legacyLoaderKeyPaths()
    return {
        "cac_loader_key.txt",
        "workspace/cac_loader_key.txt",
        "Workspace/cac_loader_key.txt",
        "CAC_Output/cac_loader_key.txt"
    }
end

local function readFirstExistingFile(paths)
    if isfile and readfile then
        for _, path in ipairs(paths) do
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

local function writeFirstPossibleFile(paths, content)
    if not writefile then return false end
    for _, path in ipairs(paths) do
        local ok = pcall(function()
            writefile(path, tostring(content or ""))
        end)
        if ok then return true end
    end
    return false
end

local function deleteFiles(paths)
    if not (delfile and isfile) then return end
    for _, path in ipairs(paths) do
        pcall(function()
            if isfile(path) then
                delfile(path)
            end
        end)
    end
end

local function readDeviceTokenFromFile()
    return readFirstExistingFile(deviceTokenPaths())
end

local function saveDeviceToken(token)
    token = tostring(token or ""):gsub("%s+", "")
    if token == "" then return false end
    return writeFirstPossibleFile(deviceTokenPaths(), token)
end

local function readLegacyLoaderKeyFromFile()
    return readFirstExistingFile(legacyLoaderKeyPaths())
end

local function deleteLegacyLoaderKeyFiles()
    deleteFiles(legacyLoaderKeyPaths())
end

local function autoLoginDisableFlagPaths()
    return {
        "cac_disable_auto_login.flag",
        "workspace/cac_disable_auto_login.flag",
        "Workspace/cac_disable_auto_login.flag",
        "CAC_Output/cac_disable_auto_login.flag"
    }
end

local function isAutoLoginDisabled()
    if not isfile then return false end
    for _, path in ipairs(autoLoginDisableFlagPaths()) do
        local okExists, exists = pcall(function() return isfile(path) end)
        if okExists and exists then
            return true
        end
    end
    return false
end

local function clearAutoLoginDisabledFlag()
    if not (delfile and isfile) then return end
    for _, path in ipairs(autoLoginDisableFlagPaths()) do
        pcall(function()
            if isfile(path) then
                delfile(path)
            end
        end)
    end
end

local function readExplicitKeyFromShared(shared)
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
    if not key then return nil end
    key = key:gsub("%s+", "")
    if key == "" then return nil end
    return key
end

local function postJson(path, payload)
    local lastData = nil
    local lastErr = "Network error: executor request failed before receiving a response"

    for index, fn in ipairs(requestCandidates) do
        for profileIndex, headers in ipairs(HTTP_HEADER_PROFILES) do
            local label = requestLabel(requestCandidateNames[index], profileIndex)
            local ok, response = requestWithCandidate(fn, {
                Url = API_BASE .. path,
                Method = "POST",
                Headers = headers,
                Body = HttpService:JSONEncode(payload)
            })

            if not ok then
                lastErr = "Network error via " .. label
            else
                local data = parseJson(response.Body or "")
                local statusCode = getStatusCode(response)
                if statusCode >= 200 and statusCode <= 299 then
                    return true, data, nil
                end

                lastData = data
                lastErr = apiErrorMessage("Request failed", response, data) .. " via " .. label
                if statusCode ~= 403 or (data and data.error) then
                    return false, data, lastErr
                end
            end
        end
    end

    return false, lastData, lastErr
end

local function getText(url)
    local lastErr = "Download failed"

    for index, fn in ipairs(requestCandidates) do
        for profileIndex, headers in ipairs(HTTP_GET_HEADER_PROFILES) do
            local label = requestLabel(requestCandidateNames[index], profileIndex)
            local ok, response = requestWithCandidate(fn, { Url = url, Method = "GET", Headers = headers })
            if not ok then
                lastErr = "Download failed via " .. label
            else
                local statusCode = getStatusCode(response)
                if statusCode >= 200 and statusCode <= 299 then
                    return true, response.Body, nil
                end

                local parsed = parseJson(response.Body or "")
                if parsed and parsed.error and parsed.error.message then
                    lastErr = "Download HTTP " .. tostring(statusCode) .. ": " .. tostring(parsed.error.message) .. " via " .. label
                else
                    local bodyHint = responsePreview(response.Body or "")
                    if bodyHint ~= "" then
                        lastErr = "Download HTTP " .. tostring(statusCode) .. ": " .. bodyHint .. " via " .. label
                    else
                        lastErr = "Download HTTP " .. tostring(statusCode) .. " via " .. label
                    end
                end

                if statusCode ~= 403 or (parsed and parsed.error) then
                    return false, nil, lastErr
                end
            end
        end
    end

    return false, nil, lastErr
end

local hwid = gethwid()
local clientVersion = "cac-loader-v1"

local sessionToken = nil
local deviceToken = nil

local shared = getShared()
local explicitKey = readExplicitKeyFromShared(shared)

if explicitKey then
    local okStart, dataStart, errStart = postJson("/v1/auth/session/start", {
        key = explicitKey,
        hwid = hwid,
        product = "script",
        device_label = "roblox-client",
        client_version = clientVersion
    })

    if not okStart or not dataStart or not dataStart.ok or not dataStart.data or not dataStart.data.session_token then
        error("Login failed: " .. tostring(errStart or "unknown"))
    end

    sessionToken = tostring(dataStart.data.session_token)
    deviceToken = dataStart.data.device_token and tostring(dataStart.data.device_token) or nil
    if deviceToken and deviceToken ~= "" then
        saveDeviceToken(deviceToken)
    end
    deleteLegacyLoaderKeyFiles()
    clearAutoLoginDisabledFlag()
else
    local disabled = isAutoLoginDisabled()
    local savedDeviceToken = readDeviceTokenFromFile()
    local legacyKeyFromFile = readLegacyLoaderKeyFromFile()

    if savedDeviceToken and savedDeviceToken:gsub("%s+", "") ~= "" and not disabled then
        local okAuto, dataAuto, errAuto = postJson("/v1/auth/session/auto-start", {
            device_token = savedDeviceToken,
            hwid = hwid,
            product = "script",
            device_label = "roblox-client",
            client_version = clientVersion
        })

        if not okAuto or not dataAuto or not dataAuto.ok or not dataAuto.data or not dataAuto.data.session_token then
            error("Auto-login unavailable. Set getgenv().CAC_KEY='YOUR_KEY' and run loader again. Error: " .. tostring(errAuto or "unknown"))
        end

        sessionToken = tostring(dataAuto.data.session_token)
        deviceToken = dataAuto.data.device_token and tostring(dataAuto.data.device_token) or savedDeviceToken
        if deviceToken and deviceToken ~= "" and deviceToken ~= savedDeviceToken then
            saveDeviceToken(deviceToken)
        end
    elseif legacyKeyFromFile and legacyKeyFromFile:gsub("%s+", "") ~= "" then
        local okStart, dataStart, errStart = postJson("/v1/auth/session/start", {
            key = legacyKeyFromFile,
            hwid = hwid,
            product = "script",
            device_label = "roblox-client",
            client_version = clientVersion
        })

        if not okStart or not dataStart or not dataStart.ok or not dataStart.data or not dataStart.data.session_token then
            error("Saved key login failed. Update key or wipe local login data. Error: " .. tostring(errStart or "unknown"))
        end

        sessionToken = tostring(dataStart.data.session_token)
        deviceToken = dataStart.data.device_token and tostring(dataStart.data.device_token) or nil
        if deviceToken and deviceToken ~= "" then
            saveDeviceToken(deviceToken)
            deleteLegacyLoaderKeyFiles()
        end
        clearAutoLoginDisabledFlag()
    elseif disabled then
        error("Auto-login is disabled on this device. Set getgenv().CAC_KEY='YOUR_KEY' and run loader again.")
    else
        error("Auto-login unavailable. Set getgenv().CAC_KEY='YOUR_KEY' and run loader again.")
    end
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
sharedEnv.CAC_PREAUTH = {
    session_token = sessionToken,
    device_token = deviceToken
}
sharedEnv.CAC_LAST_KEY = nil
sharedEnv.CAC_KEY = nil
sharedEnv.KEY = nil
sharedEnv.cac_key = nil

local fn, compileErr = loadstring(scriptBody)
if not fn then
    error("Compile failed: " .. tostring(compileErr))
end

fn()
