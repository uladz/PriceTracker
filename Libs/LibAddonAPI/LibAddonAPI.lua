-- LibAddonAPI provides base functionality for publishing of addon APIs 
-- allowing addons to intercommunicate without polluting LUA global namespace 
-- via well defined versioned API objects. It is based on LibLoadedAddon idea
-- and includes its base functionality.

-- Register LibAddonAPI with LibStub
local LIBRARY_NAME = "LibAddonAPI"
local MAJOR, MINOR = LIBRARY_NAME, 1
local laa, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not laa then return end  --the same or newer version of this lib is already loaded into memory 

local AddonAPI = {}
local doneLoading = false

--------------------------------------------------------------------------------
--  Addon functions.
--------------------------------------------------------------------------------

-- Register a new addon and it's main (unnamed) API.
-- Returns true if successfully registered.
function laa:RegisterAddon(addonName, versionNumber, apiObject)
  if type(versionNumber) ~= "number" then 
    return false, "Version number must be a number"
  end
  
  local addon = AddonAPI[addonName]
  if addon then
    local version = addon.version
    if version == 0 then
      AddonAPI[addonName] = {
        version = versionNumber,
        APIs = {["_"]=apiObject},
      }
      return true
    else
      return false, "Version number already set for this addon"
    end
  end
  return false, "Addon "..addonName.." is not loaded."
end

-- Completely unregister addon and all its APIs.
-- Returns true if successfully unregistered.
function laa:UnregisterAddon(addonName)
  if AddonAPI[addonName] then
    AddonAPI[addonName] = nil
    return true
  end
  return false, "Addon "..addonName.." was not registered"
end

-- Check if addon was loaded and its version.
-- Returns nil if loading is not finished yet and status unknown.
function laa:IsAddonLoaded(addonName)
  if not doneLoading then
    return nil, "Addon "..addonName.." is still loading."
  end
  local addon = AddonAPI[addonName]
  if addon then
    return true, addon.version
  end
  return false, "Addon "..addonName.." is not loaded."
end

-- Register a new addon API.
-- Returns true if successfully registered.
function laa:RegisterAPI(addonName, apiName, apiObject)
  assert(apiName ~= "_")
  local addon = AddonAPI[addonName]
  if addon then
    if not apiName then
      apiName = "_"
    end
    if not addon.APIs[apiName] then
      addon.APIs[apiName] = apiObject
      return true
    end
    return false, "API "..addonName.."."..apiName.." is already registered"
  end
  return false, "Addon "..addonName.." is not loaded"
end

-- Unregister one of the addon's APIs.
-- Returns true if successfully unregistered.
function laa:UnregisterAPI(addonName, apiName)
  local addon = AddonAPI[addonName]
  if addon then
    if not apiName then
      apiName = "_"
    end
    local api = addon.APIs[apiName]
    if addon.APIs[apiName] then
      addon.APIs[apiName] = nil
      return true
    end
    return false, "API "..addonName.."."..apiName.." was not registered"
  end
  return false, "Addon "..addonName.." was not registered"
end

-- Get addon's API by name, don't specify name to get main API.
-- Returns nil if API does not exist.
function laa:GetAddonAPI(addonName, apiName)
  local addon = AddonAPI[addonName]
  if addon then
    if not apiName then
      apiName = "_"
    end
    if addon.APIs[apiName] then
      return addon.APIs[apiName]
    end
    return nil, "API "..addonName.."."..apiName.." was not registered."
  end
  return nil, "Addon "..addonName.." was not registered."
end

local function OnPlayerActivated()
  EVENT_MANAGER:UnregisterForEvent(LIBRARY_NAME, EVENT_ADD_ON_LOADED)
  EVENT_MANAGER:UnregisterForEvent(LIBRARY_NAME, EVENT_PLAYER_ACTIVATED)
  doneLoading = true
end

local function OnAddOnLoaded(_, addonName)
  AddonAPI[addonName] = {version=0, APIs={}}
end

--------------------------------------------------------------------------------
--  Register for events
--------------------------------------------------------------------------------

EVENT_MANAGER:UnregisterForEvent(LIBRARY_NAME, EVENT_ADD_ON_LOADED)
EVENT_MANAGER:UnregisterForEvent(LIBRARY_NAME, EVENT_PLAYER_ACTIVATED)

EVENT_MANAGER:RegisterForEvent(LIBRARY_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
EVENT_MANAGER:RegisterForEvent(LIBRARY_NAME, EVENT_PLAYER_ACTIVATED, OnPlayerActivated)

