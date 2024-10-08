local module = {}

export type Cache = {
	Name: string,

	Attributes: {Attribute: string|number},
	
	Expiring: RBXScriptSignal,
	KeyExpiring: RBXScriptSignal,
	
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
