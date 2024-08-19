# CacheR - Create expirable or non expirable Caches, Values!

### You can read this post about caching :)
https://devforum.roblox.com/t/a-basic-guide-to-caching-for-roblox-lua/1138577

# Example Usage
```lua
local CacheR = require(path.to.module)
local newCache = CacheR.new('CacheCache', false)

local newCache_value = 'stringy stringy string ima stringy stringy string'

newCache:SetValue('StringData', newCache_value, true, 2)
print(newCache:GetValue('StringData')) -> "stringy stringy string ima stringy stringy string"
task.wait(2)
print('Expired value:', newCache:GetValue('StringData', ':(')) -> "Expired value: :("
```

Further documentation can be found inside the modules code!