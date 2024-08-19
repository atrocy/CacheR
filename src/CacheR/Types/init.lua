local module = {}

export type Cache = {
	Name: string,
	--Value: any,
	Attributes: {Attribute: string|number},
	
	Expiring: RBXScriptSignal,
	KeyExpiring: RBXScriptSignal,

	_updated: RBXScriptSignal,
	
	_items: {},
	_expiry: {},
	_expiration: number?,
	_status: 'Active' | 'Expired' ,
	_uniqueId: string,
	_thread: thread,
}

export type ExpiryCache = {
	expireAt: {},
	thread: thread
}

return module
