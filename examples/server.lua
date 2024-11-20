local mooncake = require("mooncake")
local OIDC = require("../openidc.lua") -- replace with "steam-openidc"

local server = mooncake:new()
server:get("/", function(req, res)
    if req.query["openid.claimed_id"] then
        OIDC(req.query, "http://localhost:8563", function(steamid, err)
            if not steamid then return res:status(401):send("Error: " .. err) end
            res:status(200):send(steamid)
        end)
    else res:status(200):sendFile("./index.html") end
end)

server:start(8563, "0.0.0.0")
print("Server started at port 8563")
