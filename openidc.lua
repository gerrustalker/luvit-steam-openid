-- https://github.com/xPaw/SteamOpenID.php
-- but in Lua
-- (lua-resty-openidc was too hard to rewrite)

local http = require("coro-http")
local query = require("querystring")

local explode = function(str, sep)
    local sep, t = sep or "%s", {}
    for s in string.gmatch(str, "([^" .. sep .. "]+)") do
        t[#t + 1] = s
    end return t
end

local ParseKeyValues = function(res)
    local lines, keys = explode(res, "\n"), {}
    for k, v in ipairs(lines) do
        local p = explode(v, ":")
        if p then keys[p[1]] = string.sub(v, ({string.find(v, p[1])})[2] + 2) end
    end
    return keys
end

local OPENID_NS = "http://specs.openid.net/auth/2.0"

return function(data, url, cb)
    if data["openid.mode"] ~= "id_res" then return cb(false, "invalid openid mode") end

    local args = {
        openid_ns             = data["openid.ns"],
        openid_op_endpoint    = data["openid.op_endpoint"],
        openid_claimed_id     = data["openid.claimed_id"],
        openid_identity       = data["openid.identity"],
        openid_return_to      = data["openid.return_to"],
        openid_response_nonce = data["openid.response_nonce"],
        openid_assoc_handle   = data["openid.assoc_handle"],
        openid_signed         = data["openid.signed"],
        openid_sig            = data["openid.sig"],
    }

    if next(args) == nil then return cb(false, "invalid arguments") end
    for k, v in pairs(args) do
        if type(v) ~= "string" then return cb(false, k .. "is not a string") end
    end

    if args.openid_claimed_id ~= args.openid_identity then return cb(false, "openid_claimed_id not equals to openid_identity") end -- idk
    if args.openid_op_endpoint ~= "https://steamcommunity.com/openid/login" then return cb(false, "endpoint is not Steam") end
    if args.openid_ns ~= OPENID_NS then return cb(false, "bad specs") end
    if args.openid_signed ~= "signed,op_endpoint,claimed_id,identity,return_to,response_nonce,assoc_handle" then return cb(false, "invalid signed") end
    if string.find(args.openid_return_to, url) ~= 1 then return cb(false, "openid_return_to does not point to server") end

    local steamid = string.match(args.openid_identity, "^https?://steamcommunity.com/openid/id/(7656119%d%d%d%d%d%d%d%d%d%d)/?$")
    if not steamid then return cb(false, "bad identity SteamID") end

    args.openid_mode = "check_authentication"
    for k, v in pairs(args) do args[string.gsub(k, "openid_", "openid.")], args[k] = v, nil end
    coroutine.wrap(function()
        local s, res, body = pcall(http.request,
            "POST", "https://steamcommunity.com/openid/login", {
                {"Content-Type", "application/x-www-form-urlencoded"},
                {"User-Agent", "OpenID Verification (+https://github.com/gerrustalker/luvit-steam-openid)"}
            }, query.stringify(args))

        if not s then return cb(false, "http request error") end
        if res.code ~= 200 then return cb(false, res.reason) end
        if string.find(body, "<!DOCTYPE html>") then return cb(false, "steam error") end

        local s, kv = pcall(ParseKeyValues, body) if not s then return cb(false, "parse failure") end
        if kv.ns ~= OPENID_NS then return cb(false, "bad steam specs") end
        if kv.is_valid ~= "true" then return cb(false, "not valid") end

        cb(steamid)
    end)()
end