local xmls = require "xmls2"

local xmo = {}
xmo.__index = xmo

function xmo.new(str, pos, state)
	return setmetatable({
		str = str,
		pos = pos or 1,
		state = state or xmls.text,
	}, xmo)
end

function xmo:__call()
	local value
	self.pos, self.state, value = self.state(self.str, self.pos)
	return self.state, value
end

function xmo:doState(state)
	local value
	self.pos, self.state, value = state(self.str, self.pos)
	return self.state, value
end

-- Use at Attr
-- Transition to Attr and return key, value
-- Transition to TagEnd and return nil
function xmo:nextAttr()
	local posA = self.pos
	local state, posB = self()
	if state == xmls.value then
		local key = self.str:sub(posA, posB)
		posA = self.pos + 1 -- skip the quote
		state, posB = self()
		return key, self.str:sub(posA, posB)
	else
		return nil
	end
end

-- Use at Attr
-- Transition to TagEnd
function xmo:attrs()
	assert(self.state == xmls.attr)
	return xmo.nextAttr, self
end

------------

-- Use at Text after TagEnd->false
local function nop() end

-- Use at Text
-- Transition to ? and return state
-- Transition to Text and return nil
function xmo:nextMarkup()
	self() --> markup
	local state = self() --> ?
	if state ~= xmls.etag then
		return state
	else
		self() --> text
		return nil
	end
end

-- Use at TagEnd
-- Transition to Text
function xmo:markup()
	assert(self.state == xmls.tagend)
	local state, value = self()
	return value and xmo.nextMarkup or nop, self
end

-- Use at Text
-- Transition to Attr and return tag name
-- Transition to Text and return nil
function xmo:nextTag()
	self() --> markup
	while true do
		local state = self() --> ?
		if state == xmls.stag then
			return self.str:sub(self.pos, select(2, self())) --> attr
		elseif state == xmls.etag then
			self() --> text
			return nil
		end
	end
end

-- Use at TagEnd
-- Transition to Text
function xmo:tags()
	assert(self.state == xmls.tagend)
	local state, value = self()
	return value and xmo.nextTag or nop, self
end

-- Use at Attr
-- Transition to Text
function xmo:skip()
	assert(self.state == xmls.attr)
	self:doState(xmls.skip)
end

-- Use at Attr
-- Transition to TagEnd
function xmo:skipAttrs()
	assert(self.state == xmls.attr)
	self:doState(xmls.skipAttrs)
end

-- Use at TagEnd
-- Transition to Text
function xmo:skipContent()
	assert(self.state == xmls.tagend)
	self:doState(xmls.skipContent)
end

-- to get innertext, you definitely need a rope to join cdatas and anything around comments, PIs etc.
-- but most of the time you are only interested in innerXML, hellyea

-- the nextTag, nextMarkup etc. could take an argument: the tag they are in
-- if the argument is supplied and the end tag doesn't match, complain
-- it works because the nop() doesn't complain ever

-- the declarative kinda thing with the tables..
-- the one that takes a table and calls functions for stuff that's in the table
-- the one that calls a callback for every child
-- the one that calls a callback for every descendant (stops descending when the cb says so)
	-- useful for a sax/xpath kinda thing?
-- 6 am specs

-- Use at Text
-- Transition to Attr and return tag name
-- Transition to Text and return nil
function xmo:nextPair()
	self() --> markup
	while true do
		local state = self() --> ?
		if state == xmls.stag then
			
			
			
			
		elseif state == xmls.etag then
			self() --> text
			return nil
		end
	end
end

-- pairs of tagname, innerXML of course
-- with nil as the name
-- Use at TagEnd
-- Transition to Text
function xmo:pairs()
	assert(self.state == xmls.tagend)
	local state, value = self()
	return value and xmo.nextPair or nop, self
end

function xmo:getAttrs(tbl)
	tbl = tbl or {}
	for k, v in self:attrs() do
		tbl[k] = v
	end
	return tbl
end

-- Use at Text
-- Transition to Attr and return tag name
-- Transition to Text and return nil
function xmo:nextRoot()
	self() --> markup
	while true do
		local state = self() --> ?
		if state == xmls.stag then
			return self.str:sub(self.pos, select(2, self())) --> attr
		elseif state == xmls.eof then
			return nil
		end
	end
end

-- Use at Text
-- or Preamble, rather?
-- Transition to EOF
function xmo:roots()
	assert(self.state == xmls.text)
	-- todo handle the <?xml?> whatever
	return xmo.nextRoot, self
end

-- Use at Attr
-- Transition to Text
function xmo:doSwitch(action, name)
	local case = type(action)
	
	if case == "nil" then
		return self:skip()
		
	elseif case == "table" then
		self:skipAttrs()
		return self:doTags(action)
		
	elseif case == "function" then
		return action(self, name)
	end
end

-- Use at TagEnd
-- Transition to Text
function xmo:doTags(tree)
	for name in self:tags() do
		self:doSwitch(tree[name], name)
	end
end

-- Use at Start
-- Transition to EOF
function xmo:doRoots(tree)
	for name in self:roots() do
		self:doSwitch(tree[name], name)
	end
end

return xmo
