--[[
	by atrocy!!!(aka cheez1i or Romazka57)

	# CacheR - Create expirable or non expirable Caches, Values!

	You can read this post about caching :)
	https://devforum.roblox.com/t/a-basic-guide-to-caching-for-roblox-lua/1138577

	[ Example Usage ]
	 	local CacheR = require(path.to.module)
		local newCache = CacheR.new('CacheCache', false)

		local newCache_value = 'stringy stringy string ima stringy stringy string'

		newCache:SetValue('StringData', newCache_value, true, 2)
		print(newCache:GetValue('StringData')) -> "stringy stringy string ima stringy stringy string"
		task.wait(2)
		print('Expired value:', newCache:GetValue('StringData', ':(')) -> "Expired value: :("

	[ CACHER API ]
	 	# Functions
			CacheR.new(Name: string, Expirable: boolean?, Expiration: number? Attributes: {}?) -> Cache
				Description:
					Creates a new Cache
				Returns:
					Cache

					
			CacheR.GetByUniqueId(uniqueId: string) -> Cache|nil
				Returns:
					Cache or nil

			CacheR.GetByName(Name: any) -> Cache|nil
				Returns:
					Cache or nil

		# Methods
			Cache:SetValue(Key: any, Value: any, Expirable: boolean?, Expiration: number?) -> void
				Description:
					Sets a new value for the cache, or updates it
				Note:
					Expirable's and Expiration's default value is in the settings

			Cache:UnsetValue(Key: any) -> void
				Description:
					Unsets the Cache's key

			Cache:GetValue(Key: any, Default: any?, setDefault: boolean?) -> any
				Description:
					Gets the Cache's key
				Returns:
					any
				Note:
					If Default is provided, it'll return the Default value if Key equals nil.
					If setDefault set to true, it will set the Key's value to the Default value thats provided-
					IF key's value equals to nil


			Cache:UpdateExpiration(Expiration: number) -> void
				Description:
					Updates cache's expiration "date"


			Cache:SetAttribute(Name: any, Value: any)
				Description:
					Sets a new Attribute for the cache, or updates it

			Cache:GetAttribute(Name: any) -> any
				Description:
					Returns the attribute in cache
				Returns:
					Attribute: {}
	
]]

local cache_module = {}
cache_module.__index = cache_module

local instances = {}

--VARIABLES--
local HttpService = game:GetService('HttpService')

--MODULES--
local Types = require(script.Types)
local Signal = require(script.Packages.Signal)

--TYPES--
type Cache = Types.Cache
type ExpiryCache = Types.ExpiryCache

--DEFAULTS--
cache_module.Settings = {}

cache_module.Settings.DEFAULT_EXPIRATION = 15
cache_module.Settings.DEFAULT_EXPIRABLE_BOOLEAN = true
cache_module.Settings.DEFAULT_ATTRIBUTES = {}

--Private Functions
local function generateUniqueId()
	return HttpService:GenerateGUID(false)
end

local function Timestamp()
	return os.time()
end

local function cacheTableCancelThread(uniqueId: string)
	local instance_cache: Cache = instances[uniqueId]

	if instance_cache and instance_cache._thread then if coroutine.status(instance_cache._thread) == 'suspended' then task.cancel(instance_cache._thread) end instance_cache._thread = nil end
end

local function cacheExpiryUpdateAt(cache: Cache, Key: any, Expiration: number)
	local expiry: ExpiryCache = {}
	expiry.expireAt = Timestamp()+Expiration
	
	cache._expiry[Key] = expiry
end

local function cacheExpiryUnset(cache: Cache, Key: any)
	cache._expiry[Key] = nil
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

	cacheTableCancelThread(cache._uniqueId)
	
	for i, v in cache do
		if typeof(v) == 'thread' and coroutine.status(v) == 'suspended' then task.cancel(v) end
	end

	if instances[cache._uniqueId] then instances[cache._uniqueId] = nil end
	
	setmetatable(cache, nil)
	table.clear(cache)
	table.freeze(cache)
end

local function cacheValueExpire(cache: Cache, Key: any)
	if not cache or not cache._items then return end
	if not cacheExpiryCompareExpired(cache, Key) then repeat task.wait() until cacheExpiryCompareExpired(cache, Key) end
	if cache.KeyExpiring then cache.KeyExpiring:Fire(Key, cache._items[Key]) end
	
	cache._items[Key] = nil
	cacheExpiryUnset(cache, Key)
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

function cache_module.new(Name: string, Expirable: boolean?, Expiration: number?, Attributes: {}?)
	-- Checking if nil, cuz if we do if not Expirable, it will ignore `false` boolean
	if Expirable == nil then Expirable = cache_module.Settings.DEFAULT_EXPIRABLE_BOOLEAN end
	Expiration = Expiration or cache_module.Settings.DEFAULT_EXPIRATION
	Attributes = Attributes or cache_module.Settings.DEFAULT_ATTRIBUTES
	
	local self: Cache = {
		Name = Name,
		--Value = Value, deprecated :o
		Attributes = Attributes,
		
		--Expiring = Signal.new(), will be added if `Expirable`.
		KeyExpiring = Signal.new(),
		
		--_expiration = Expiration, will be added if `Expirable`.
		_items = {},
		_expiry = {}, --store item's expiration, compare and stuff..
		
		_uniqueId = generateUniqueId(),
		_status = "Active",
	}
	if Expirable then self.Expiring = Signal.new() self._expiration = Expiration self._thread = delayExpire(self) end
	
	if instances[self._uniqueId] then warn('Cache with that uniqueId is already running.') repeat task.wait() self._uniqueId = generateUniqueId() until not instances[self._uniqueId] end	
	
	setmetatable(self, cache_module)
	instances[self._uniqueId] = self
	
	return self
end

--[[ Setting index functions (ruins autocomplete nooo...!!!!)
	If you uncomment those, you will be also allowed to set/get through index
	Example:
	
		Cache.someKey = 'jello!!' 
		print(Cache.someKey) -> jello!!
	
	Note that, if you set the cache values like that, their Expiration will be set to the default value in Settings!
--]]

--Returning the cache value if youre doing it through Cache.key!!
--function cache_module:__index(index)
--	if cache_module[index] then return cache_module[index] else return self:GetValue(index) end
--end

----Setting the cache value if youre doing it through Cache.key = value!!
--function cache_module:__newindex(index, value)
--	if value == nil then self:UnsetValue(index) else self:SetValue(index, value) end
--end
--End

function cache_module.GetByUniqueId(uniqueId: string): Cache|nil
	return instances[uniqueId]
end

function cache_module.GetByName(Name: any): Cache|nil
	for _, cache: Cache in instances do
		if not cache.Name then continue end
		if cache.Name ~= Name then continue end
		
		return cache
	end
	
	return nil
end

function cache_module:SetValue(Key: any, Value: any, Expirable: boolean?, Expiration: number?)
	if self._thread then if coroutine.status(self._thread) == 'dead' or coroutine.status(self._thread) == 'running' then return end end
	-- Checking if nil, cuz if we do if not Expirable, it will ignore `false` boolean
	if Expirable == nil then Expirable = cache_module.Settings.DEFAULT_EXPIRABLE_BOOLEAN end
	Expiration = Expiration or cache_module.Settings.DEFAULT_EXPIRATION
	
	self._items[Key] = Value
	cacheExpiryThreadCancel(self, Key)
	
	if Expirable then cacheExpiryUpdateAt(self, Key, Expiration) delayValueExpire(self, Key, Expiration) end
end

function cache_module:UnsetValue(Key: any)
	if self._thread then if coroutine.status(self._thread) == 'dead' or coroutine.status(self._thread) == 'running' then return end end
	
	self._items[Key] = nil
	cacheExpiryUnset(self, Key)
end

function cache_module:GetValue(Key: any, Default: any?, setDefault: boolean?): any
	setDefault = setDefault or false
	
	if self._items then
		
		if self._items[Key] then return self._items[Key] end
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
end

function cache_module:SetAttribute(Name: any, Value: any)
	if self._thread then if coroutine.status(self._thread) == 'dead' or coroutine.status(self._thread) == 'running' then return end end
	
	self.Attributes[Name] = Value
	cacheTableUpdateAttributes(self._uniqueId, Name, Value)
end

function cache_module:GetAttribute(Name: any)
	return self.Attributes[Name]
end

return cache_module