--[[
	by atrocy(aka cheez1i or Romazka57)

	! IF YOU NEED AUTOCOMPLETION, READ LINE 156!!!
	
	no doc yet..
	
]]

local cache_module = {}
cache_module.__index = cache_module

local instances = {}

--VARIABLES--
local HttpService = game:GetService('HttpService')
local RunService = game:GetService('RunService')
local DataStoreService = game:GetService("DataStoreService")
local Packages = script.Packages

local RateLimitTime = 6

--MODULES--
local Types = require(script.Types)
local Signal = require(Packages.Signal)
local Compressor = require(Packages.Compress)

--TYPES--
type Cache = Types.Cache
type ExpiryCache = Types.ExpiryCache

--DEFAULTS--
cache_module.Settings = {}

cache_module.Settings.DEFAULT_EXPIRATION = 310
cache_module.Settings.DEFAULT_EXPIRABLE_BOOLEAN = true
cache_module.Settings.DEFAULT_GLOBAL_BOOLEAN = false
cache_module.Settings.DEFAULT_ATTRIBUTES = {}

cache_module.Enum = {
	Events = {
		Set = 'Set',
		Unset = 'Unset',
	}
}

local LOG_FORMAT = '[CACHER]: %s'
local GLOBAL_NAME = 'Cach3%r%Cachd_plsbro314devdevdev'
local GLOBAL_KEY = 'cupocheerCacheer3%'

local cacheStore
if RunService:IsServer() then cacheStore = DataStoreService:GetDataStore(GLOBAL_NAME) end

--Private Functions
local function generateUniqueId()
	return HttpService:GenerateGUID(false)
end

local function errorLog(text: string)
	error(LOG_FORMAT:format(text), 2)
end

local function Compress(table: {})
	if typeof(table) == 'table' then return Compressor.Compress(HttpService:JSONEncode(table)) else return Compressor.Compress(table) end
end

local function Decompress(Compressed: string)
	local decompressed = HttpService:JSONDecode(Compressor.Decompress(Compressed))
	if typeof(decompressed) == 'string' then
		print('Could not decompress data. Retrying...')
		for i = 1, 5 do
			decompressed = HttpService:JSONDecode(Compressor.Decompress(Compressed))
			if typeof(decompressed) ~= 'string' then print('Success!') return decompressed end
		end
	end
	return decompressed
end

local function Timestamp()
	return os.time()
end

local function fpcall(f: 'function', handler: 'function')
	local success, response: any = pcall(f)
	if not success then return success, handler(response) end
	return success, response
end

local function cacheTableCancelThread(uniqueId: string)
	local instance_cache: Cache = instances[uniqueId]

	if instance_cache and instance_cache._thread then if coroutine.status(instance_cache._thread) == 'suspended' then task.cancel(instance_cache._thread) end instance_cache._thread = nil end
end

local function cacheExpiryUpdateAt(cache: Cache, Key: any, Expiration: number)
	local expiry: ExpiryCache = {}
	expiry.expireAt = Timestamp()+Expiration
	
	cache._expiry[Key] = expiry
	if not cache._global then return end --skips the update async if not global
	fpcall(function()
		return cacheStore:UpdateAsync(GLOBAL_KEY, function(data)
			if not data then return end
			local decdata = Decompress(data)

			if not decdata[cache._uniqueId] then return data end
			if not decdata._expiry then return data end

			decdata._expiry[Key] = expiry
			data = Compress(decdata)
			return data
		end)
	end, function(err)
		errorLog(err)
		return
	end)
end

local function cacheExpiryUnset(cache: Cache, Key: any)
	cache._expiry[Key] = nil
	if not cache._global then return end --skips the update async if not global
	fpcall(function()
		return cacheStore:UpdateAsync(GLOBAL_KEY, function(data)
			if not data then return end
			local decdata = Decompress(data)

			if not decdata[cache._uniqueId] then return data end
			if not decdata._expiry then return data end
			if not decdata._expiry[Key] then return data end

			decdata._expiry[Key] = nil
			data = Compress(decdata)
			return data
		end)
	end, function(err)
		errorLog(err)
		return
	end)
end

local function cacheExpiryCompareExpired(cache: Cache, Key: any)
	if not cache._expiry[Key] then return false end
	return (cache._expiry[Key].expireAt - Timestamp()) <= 0
end

local function cacheExpiryThreadCancel(cache: Cache, Key: any)
	if not cache._expiry[Key] or not cache._expiry[Key].thread then return end
	if coroutine.status(cache._expiry[Key].thread) ~= 'suspended' then return end
	
	task.cancel(cache._expiry[Key].thread)
end

local function cacheExpire(cache: Cache)
	if cache.Expiring then cache.Expiring:Fire() end
	cache.Status = 'Expired'

	fpcall(function()
		return cacheStore:UpdateAsync(GLOBAL_KEY, function(data)
			if not data then return end
			local decdata = Compress.Decompress(data)
			if not data[cache._uniqueId] then return data end

			decdata[cache._uniqueId] = nil
			data = Compress(decdata)
			return data
		end)
	end, function(err)
		errorLog(err)
	end)
	cacheTableCancelThread(cache._uniqueId)
	
	for i, v in cache do
		if typeof(v) == 'thread' then task.cancel(v) end
		cache[i] = nil
	end
	
	setmetatable(cache, nil)
end

local function cacheValueExpire(cache: Cache, Key: any)
	if not cache or not cache._items then return end
	if not cacheExpiryCompareExpired(cache, Key) then repeat task.wait() until cacheExpiryCompareExpired(cache, Key) end
	if cache.KeyExpiring then cache.KeyExpiring:Fire(Key, cache._items[Key]) end
	
	cache._items[Key] = nil
	cacheExpiryUnset(cache, Key)

	if cache._global then cache._updated:Fire(cache_module.Enum.Events.Set, Key, nil) end
end

local function delayExpire(cache: Cache): thread
	return task.delay(cache._expiration, cacheExpire, cache)
end

local function delayValueExpire(cache: Cache, Key: any, Expiration: number): thread
	local thread = task.delay(Expiration, cacheValueExpire, cache, Key)
	cache._expiry[Key].thread = thread
	
	return thread
end

local function cacheTableUpdate(uniqueId: string, key: string, value: any)
	local cache: Cache = instances[uniqueId]
	
	if not cache then return end
	cache[key] = value
end

local function cacheTableUpdateAttributes(uniqueId: string, key: string, value: any)
	local cache: Cache = instances[uniqueId]

	if not cache then return end
	cache.Attributes[key] = value
end

--Main
function cache_module:Expire()
	cacheExpire(self)
end

function cache_module.new(Name: string, Expirable: boolean?, Expiration: number?, Attributes: {}?, Global: boolean?)
	-- Checking if nil, cuz if we do if not Expirable, it will ignore `false` boolean
	if Expirable == nil then Expirable = cache_module.Settings.DEFAULT_EXPIRABLE_BOOLEAN end
	if Global == nil then Global = cache_module.Settings.DEFAULT_GLOBAL_BOOLEAN end
	Expiration = Expiration or cache_module.Settings.DEFAULT_EXPIRATION
	Attributes = Attributes or cache_module.Settings.DEFAULT_ATTRIBUTES
	
	local self: Cache = {
		Name = Name,
		--Value = Value, deprecated :o
		Attributes = Attributes,
		
		--Expiring = Signal.new(), will be added if `Expirable`.
		KeyExpiring = Signal.new(),
		_updated = Signal.new(),
		
		--_expiration = Expiration, will be added if `Expirable`.
		_items = {},
		_expiry = {}, --store item's expiration, compare and stuff..
		
		_uniqueId = generateUniqueId(),
		_status = "Active",
		_global = Global
	}
	if Expirable then self.Expiring = Signal.new() self._expiration = Expiration self._thread = delayExpire(self) end
	if instances[self._uniqueId] then warn('Cache with that uniqueId is already running.') repeat task.wait() self._uniqueId = generateUniqueId() until not instances[self._uniqueId] end	
	if Global then --if global then search for the already existing cache, if it does exist ofc.
		local success, cache_list = fpcall(function()
			return cacheStore:GetAsync(GLOBAL_KEY)
		end, function(err)
			errorLog(err)
		end)
		
		if success and cache_list and cache_list ~= '[]' then
			print(cache_list)
			cache_list = Decompress(cache_list)

			for id, cache: Cache in cache_list do
				if cache.Name ~= self.Name then return end
				self._uniqueId = cache._uniqueId
				print('found a global cache with the same name and overwritten your uniqueId!')
			end
		end
	end

	if Global then self._updated:Connect(function(event, key, value, expiration) 
		if event == cache_module.Enum.Events.Set then
			fpcall(function()
				return cacheStore:UpdateAsync(GLOBAL_KEY, function(data)
					local default = {}
					default[self._uniqueId] = {}
					default[self._uniqueId].Name = self.Name
					default[self._uniqueId].Attributes = self.Attributes
					default[self._uniqueId]._items = self._items
					default[self._uniqueId]._expiry = self._expiry
					default[self._uniqueId]._uniqueId = self._uniqueId

					if not data then return Compress(default) end

					-- data = data or default
					local decdata = Decompress(data)
					-- if data == '[]' then decdata = {} else decdata = Decompress(data) end
					if not decdata[self._uniqueId] then decdata[self._uniqueId] = {Name = self.Name,Attributes = self.Attributes,_items = self._items,_expiry = self._expiry,_uniqueId = self._uniqueId} end
					if not decdata[self._uniqueId].SessionLock then decdata[self._uniqueId].SessionLock = Timestamp() end
					if Timestamp() - decdata[self._uniqueId].SessionLock > RateLimitTime then
						decdata[self._uniqueId]._items[key] = value
					else
						warn('Global Cache is Ratelimited!')
						return
					end

					local json = HttpService:JSONEncode(decdata)
					data = Compress(json)

					return data
				end)
			end, function(err)
				errorLog(err)
			end)
		elseif event == cache_module.Enum.Events.Unset then
			fpcall(function()
				return cacheStore:UpdateAsync(GLOBAL_KEY, function(data)
					if not data then return end
					
					local decdata = Decompress(data)
					if not decdata[self._uniqueId] then return data end
					if not decdata[self._uniqueId].SessionLock then decdata[self._uniqueId].SessionLock = Timestamp() end
					if Timestamp() - data[self._uniqueId].SessionLock > RateLimitTime then
						decdata[self._uniqueId]._items[key] = nil
					else
						warn('Global Cache is Ratelimited!')
						return
					end

					local json = HttpService:JSONEncode(decdata)
					data = Compress(json)

					return data
				end)
			end, function(err)
				errorLog(err)
			end)
		end
	end) end
	
	setmetatable(self, cache_module)
	instances[self._uniqueId] = self
	
	return self
end

--[[ Setting index functions (ruins autocomplete nooo...!!!!)
	If you need autocomplete you can remove/comment those, if you do, you will only be able to get/set cache values by using
	functions, if youre ok without autocompletion and left these on, you can set/get cache values through index!
	Example:
	
		Cache.someKey = 'jello!!' 
		print(Cache.someKey) -> jello!!
	
	Note that, if you set the cache values like that, their Expiration will be set to the default value in Settings!
--]]

--Returning the cache value if youre doing it through Cache.key!!
-- function cache_module:__index(index)
-- 	if cache_module[index] then return cache_module[index] else return self:GetValue(index) end
-- end

----Setting the cache value if youre doing it through Cache.key = value!!
-- function cache_module:__newindex(index, value)
-- 	if value == nil then self:UnsetValue(index) else self:SetValue(index, value) end
-- end
--End

function cache_module.GetByUniqueId(uniqueId: string): Cache|nil
	return instances[uniqueId]
end

function cache_module.GetByName(Name: string): Cache|nil
	for _, cache: Cache in instances do
		if not cache.Name then continue end
		if cache.Name ~= Name then continue end
		
		return cache
	end
	
	return nil
end

function cache_module:SetValue(Key: any, Value: any, Expiration: number?)
	if self._thread then if coroutine.status(self._thread) == 'dead' or coroutine.status(self._thread) == 'running' then return end end
	Expiration = Expiration or cache_module.Settings.DEFAULT_EXPIRATION
	
	self._items[Key] = Value
	
	cacheExpiryThreadCancel(self, Key)
	
	cacheExpiryUpdateAt(self, Key, Expiration)
	delayValueExpire(self, Key, Expiration)
	if self._global then self._updated:Fire(cache_module.Enum.Events.Set, Key, Value, Expiration) end
end

function cache_module:UnsetValue(Key: any)
	if self._thread then if coroutine.status(self._thread) == 'dead' or coroutine.status(self._thread) == 'running' then return end end
	
	self._items[Key] = nil
	cacheExpiryUnset(self, Key)
	if self._global then self._updated:Fire(cache_module.Enum.Events.Unset, Key) end
end

function cache_module:GetValue(Key: any, Default: any?, setDefault: boolean?, SearchGlobal: boolean?)
	if setDefault == nil then setDefault =  false end
	if SearchGlobal == nil then SearchGlobal = false end
	
	if self._items then
		if self._items[Key] then return self._items[Key] end
	end

	if SearchGlobal and self._global then
		local success, cache_list = fpcall(function()
			return cacheStore:GetAsync(GLOBAL_KEY)
		end, function(err)
			errorLog(err)
		end)
		
		if not success then return nil end
		cache_list = Decompress(cache_list)

		for id, cache: Cache in cache_list do
			if id ~= self._uniqueId then continue end
			if not cache._items or not cache._items[Key] then return end
			return cache._items[Key]
		end
	end
	
	--Doing ~= nil cuz if i do if NOT Default, it can ignore `false` boolean.
	if Default ~= nil and not setDefault then return Default end
	if setDefault and Default ~= nil then self:SetValue(Key, Default) return Default end
	
	return nil
end

function cache_module:UpdateExpiration(Expiration: number) --If Expirable, for cache, not values
	if self._thread then task.cancel(self._thread) self._thread = nil cacheTableCancelThread(self._uniqueId) end
	
	self._expiration = Expiration
	local newThread = delayExpire(self)
	
	self._thread = newThread
	cacheTableCancelThread()
	cacheTableUpdate(self._uniqueId, '_thread', newThread)
	--we dont update the thread for global thing cuz we cant have threads in datastores lol
end

function cache_module:SetAttribute(Name: any, Value: any)
	if self._thread then if coroutine.status(self._thread) == 'dead' or coroutine.status(self._thread) == 'running' then return end end
	
	self.Attributes[Name] = Value
	cacheTableUpdateAttributes(self._uniqueId, Name, Value)
	if not self._global then return end --skips the update async if not global
	fpcall(function()
		return cacheStore:UpdateAsync(GLOBAL_KEY, function(data)
			local decdata = Decompress(data)

			if not decdata[self._uniqueId] then return data end
			if not decdata.Attributes then return data end

			decdata.Attributes[Name] = Value
			data = Compress(decdata)
			return data
		end)
	end, function(err)
		errorLog(err)
		return
	end)
end

function cache_module:GetAttribute(Name: any)
	return self.Attributes[Name]
end

return cache_module