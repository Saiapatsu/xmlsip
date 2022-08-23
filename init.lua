--[[
MIT License

Copyright (c) 2022 twiswist

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local xmls = {}
local utf8char = utf8.char

-- States
-- ======

-- Plain text
-- Use after ">", after ";" or at beginning of document
-- Transition to Entity, STag, ETag, CDATA, Comment, PI or EOF
-- Return end of text
function xmls:TEXT(str, pos)
	local pos0 = str:match("[^<&]*()", pos)
	
	if str:byte(pos0) == 38 then -- &
		return pos0 + 1, self.ENTITY, pos0
	end
	
	pos = pos0 + 1
	
	if str:find("^[:A-Z_a-z\x80-\xff]", pos) ~= nil then -- <tag
		return pos, self.STAG, pos0
	end
	
	local byte = str:byte(pos)
	
	if byte == 47 then -- </
		pos = pos + 1
		if str:find("^[:A-Z_a-z\x80-\xff]", pos) ~= nil then -- </tag
			return pos, self.ETAG, pos0
		else -- </>
			return self.error("Invalid tag name", str, pos)
		end
		
	elseif byte == 33 then -- <!
		pos = pos + 1
		if str:sub(pos, pos + 1) == "--" then -- <!--
			return pos + 2, self.COMMENT, pos0
		elseif str:sub(pos, pos + 6) == "[CDATA[" then -- <![CDATA[
			return pos + 7, self.CDATA, pos0
		else -- <!asdf
			return self.error("Unrecognized exclamation point tag", str, pos)
		end
		
	elseif byte == 63 then -- <?
		return pos + 1, self.PI, pos0
		
	elseif pos >= #str then -- end of file
		return pos - 1, self.EOF, pos0
		
	else -- <\
		return self.error("Invalid tag name", str, pos)
	end
end

-- Name of entity reference
-- Use after "&"
-- Return end of name
local function makeEntity(state)
	return function(self, str, pos)
		local pos2 = str:match("^[#%w]+();", pos)
		if pos2 == nil then
			return self.error("Bad entity", str, pos)
		end
		return pos2 + 1, self[state], pos2
	end
end
-- Transition to Text
xmls.ENTITY = makeEntity("TEXT")
-- Transition to Value1
xmls.VALUE1ENT = makeEntity("VALUE1")
-- Transition to Value2
xmls.VALUE2ENT = makeEntity("VALUE2")

-- Name of starting tag
-- Use after "<"
-- Transition to Attr
-- Return end of name
function xmls:STAG(str, pos)
	local posName, posSpace = str:match("^[:A-Z_a-z\x80-\xff][-.0-9:A-Z_a-z\x80-\xff]*()[ \t\r\n]*()", pos)
	if posName == nil then
		return self.error("Invalid tag name", str, pos)
	end
	return posSpace, self.ATTR, posName
end

-- Name of ending tag
-- Use after "</"
-- Transition to Text
-- Return end of name
function xmls:ETAG(str, pos)
	local posName, posSpace = str:match("^[:A-Z_a-z\x80-\xff][-.0-9:A-Z_a-z\x80-\xff]*()[ \t\r\n]*()", pos)
	if posName == nil then
		return self.error("Invalid etag name", str, pos)
	end
	if str:byte(posSpace) ~= 62 then
		return self.error("Malformed etag", str, pos)
	end
	return posSpace + 1, self.TEXT, posName
end

-- Content of CDATA section
-- Use after "<![CDATA["
-- Transition to Text
-- Return end of content
function xmls:CDATA(str, pos)
	local pos2 = str:match("%]%]>()", pos)
	if pos2 ~= nil then
		return pos2, self.TEXT, pos2 - 3
	else
		return self.error("Unterminated CDATA section", str, pos)
	end
end

-- Content of comment
-- Use after "<!--"
-- Transition to Text
-- Return end of content
function xmls:COMMENT(str, pos)
	local pos2 = str:match("%-%->()", pos)
	if pos2 ~= nil then
		return pos2, self.TEXT, pos2 - 3
	else
		-- unterminated
		return self.error("Unterminated comment", str, pos)
		-- pos = #str
		-- return pos, self.TEXT, pos
	end
end

-- Content of processing instruction
-- Use after "<?"
-- Transition to Text
-- Return end of content
function xmls:PI(str, pos)
	local pos2 = str:match("?>()", pos)
	if pos2 ~= nil then
		return pos2, self.TEXT, pos2 - 2
	else
		-- unterminated
		return self.error("Unterminated processing instruction", str, pos)
		-- pos = #str
		-- return pos, self.TEXT, pos
	end
end

-- Attribute name or end of tag (end of attribute list).
-- Use at attribute name or ">" or "/>"
-- Transition to Value and return end of name
-- Transition to TagEnd and return nil
function xmls:ATTR(str, pos)
	local posName, posQuote = str:match("^[:A-Z_a-z\x80-\xff][-.0-9:A-Z_a-z\x80-\xff]*()[ \t\r\n]*=[ \t\r\n]*()", pos)
	if posName then
		if not str:find("^[ \t\r\n]", pos - 1) then
			return self.error("Attribute not separated by a space", str, pos)
		end
		local byte = str:byte(posQuote)
		if byte == 34 then -- "
			return posQuote + 1, self.VALUE2, posName
		elseif byte == 39 then -- '
			return posQuote + 1, self.VALUE1, posName
		else
			return self.error("Unquoted attribute value", str, posQuote)
		end
	else
		-- check for / or >
		return pos, self.TAGEND, nil
	end
end

-- Single-quoted attribute value
-- Use after "'"
-- Transition to Attr or Value1Entity
-- Return end of value
function xmls:VALUE1(str, pos)
	posSpecial = str:match("^[^'&]*()", pos)
	local byte = str:byte(posSpecial)
	if byte == 38 then -- &
		return posSpecial + 1, self.VALUE1ENT, posSpecial
	elseif byte == 39 then -- '
		return str:match("^[ \t\r\n]*()", posSpecial + 1), self.ATTR, posSpecial
	else
		return self.error("Unterminated attribute value", str, pos)
	end
end

-- Double-quoted attribute value
-- Use after '"'
-- Transition to Attr or Value2Entity
-- Return end of value
function xmls:VALUE2(str, pos)
	posSpecial = str:match("^[^\"&]*()", pos)
	local byte = str:byte(posSpecial)
	if byte == 38 then -- &
		return posSpecial + 1, self.VALUE2ENT, posSpecial
	elseif byte == 34 then -- "
		return str:match("^[ \t\r\n]*()", posSpecial + 1), self.ATTR, posSpecial
	else
		return self.error("Unterminated attribute value", str, pos)
	end
end

-- End of tag
-- Use at ">" or "/>"
-- Transition to Text
-- Return true if opening tag, false if self-closing
function xmls:TAGEND(str, pos)
	-- c port?: return enum instead of bool
	local byte = str:byte(pos)
	if byte == 62 then -- >
		return pos + 1, self.TEXT, true
	elseif byte == 47 then -- /
		if str:byte(pos + 1) == 62 then -- >
			return pos + 2, self.TEXT, false
		end
	end
	return self.error("Malformed attribute", str, pos)
end

-- End of file
-- Do not use
-- Throws an error, shouldn't have read any further
function xmls:EOF(str, pos)
	return self.error("Exceeding end of file", str, pos)
end

-- Map state to state name
local names = {} -- [function] = string
for k,v in pairs(xmls) do
	names[v] = k
end
xmls.names = names

-- State-like functions
-- ====================

-- Skip attributes and content of a tag
-- Use at Attr
-- Transition to Text
-- Return nothing
function xmls:SKIPTAG(str, pos)
	pos = self:SKIPATTR(str, pos)
	return self:SKIPCONTENT(str, pos)
end

-- Skip attributes of a tag
-- Use between a "<" and a ">"
-- Transition to TagEnd
-- Return nothing
function xmls:SKIPATTR(str, pos)
	-- fails when there's a slash in an attribute value!
	-- local pos2 = str:match("^[^/>]*()", pos)
	-- local pos2 = str:match("^.-()/?>", pos)
	-- if pos2 == nil then
		-- self.error("Unterminated start tag", str, pos2)
	-- end
	pos = str:match("^[^>]*()", pos)
	if str:byte(pos - 1) == 47 then
		return pos - 1, self.TAGEND
	else
		return pos, self.TAGEND
	end
end

-- Skip attribute value
-- Use after "'"
-- Transition to Attr
-- Return end of value
function xmls:SKIPVALUE1(str, pos)
	posQuote, posSpace = str:match("()'[ \t\r\n]*()", pos)
	if posQuote == nil then
		return self.error("Unterminated attribute value", str, pos)
	end
	return posSpace, self.ATTR, posQuote
end

-- Skip attribute value
-- Use after '"'
-- Transition to Attr
-- Return end of value
function xmls:SKIPVALUE2(str, pos)
	posQuote, posSpace = str:match('()"[ \t\r\n]*()', pos)
	if posQuote == nil then
		return self.error("Unterminated attribute value", str, pos)
	end
	return posSpace, self.ATTR, posQuote
end

-- Skip the content and end tag of a tag
-- Use at TagEnd
-- Transition to Text
-- Return end of content just before the end tag
function xmls:SKIPCONTENT(str, pos)
	local pos, state, opening = self:TAGEND(str, pos) --> text
	if opening then
		return self:SKIPINNER(str, pos) --> text
	else
		return pos, state, nil
	end
end

-- Skip the content and end tag of a tag
-- Use at Text after TagEnd
-- Transition to Text
-- Return end of content just before the end tag
function xmls:SKIPINNER(str, pos)
	local level, state, value = 1, self.TEXT
	local posB
	while true do --> text
		pos, state, posB = state(self, str, pos) --> ?
		if state == self.STAG then --> stag
			-- pos, state = state(self, str, pos) --> attr
			pos, state = self:SKIPATTR(str, pos) --> tagend
			pos, state, opening = state(self, str, pos) --> text
			if opening then
				level = level + 1
			end
			
		elseif state == self.ETAG then --> etag
			pos, state = state(self, str, pos) --> text
			if level == 1 then
				return pos, state, posB
			end
			level = level - 1
			
		else --> ?
			pos, state = state(self, str, pos) --> text
		end
	end
end

-- Parsing state object
-- ====================

xmls.__index = xmls

-- Constructor
-- You're free to use an instance to store arbitrary data.
-- In particular, xmls:traceback() acts differently if name is set.
function xmls.new(str, pos, state)
	return setmetatable({
		str = str,
		pos = pos or 1,
		state = state or xmls.TEXT,
	}, xmls)
end

-- Advance to the next state
-- Return next state and current state's return value
function xmls:__call()
	local value
	self.pos, self.state, value = self.state(self, self.str, self.pos)
	return self.state, value
end

-- Use a specific state
-- Return next state and used state's return value
function xmls:dostate(state)
	local value
	self.pos, self.state, value = state(self, self.str, self.pos)
	return self.state, value
end

-- Use a specific state or current state
-- Return start and end positions of the state's "value"
function xmls:statePos(state)
	local posA, posB = self.pos
	self.pos, self.state, posB = (state or self.state)(self, self.str, self.pos)
	return posA, posB
end

-- Use a specific state or current state
-- Return the state's "value" as a string
function xmls:stateValue(state)
	local posA, posB = self.pos
	self.pos, self.state, posB = (state or self.state)(self, self.str, self.pos)
	return self:cut(posA, posB)
end

-- Skipping
-- ========

-- Use at Attr
-- Transition to Text
function xmls:skipTag()
	self:assertState(self.ATTR, "skipTag")
	return self:dostate(self.SKIPTAG)
end

-- Use at Attr
-- Transition to TagEnd
function xmls:skipAttr()
	self:assertState(self.ATTR, "skipAttr")
	return self:dostate(self.SKIPATTR)
end

-- Use at TagEnd
-- Transition to Text
function xmls:skipContent()
	self:assertState(self.TAGEND, "skipContent")
	return self:dostate(self.SKIPCONTENT)
end

-- Manual extraction
-- =================

-- Use at Attr
-- Transition to Value and return key
-- Transition to TagEnd and return nil
function xmls:getKey()
	local posA = self.pos
	local state, posB = self()
	if state ~= self.TAGEND then -- is a value
		return self:cut(posA, posB)
	else
		return nil
	end
end

-- Use at Attr
-- Transition to Value and return keyPos, keyLast
-- Transition to TagEnd and return nil
function xmls:getKeyPos()
	local posA = self.pos
	local state, posB = self()
	if state ~= self.TAGEND then -- is a value
		return posA, posB
	else
		return nil
	end
end

-- Use at Value
-- Transition to Attr and return value
function xmls:getValue()
	local value = self:stateValue()
	if self.state == self.ATTR then return value end
	local rope = {value}
	while true do
		local entity = self.decodeEntity(self:stateValue())
		if entity == nil then return self.error("Unrecognized entity", str, pos) end
		table.insert(rope, entity)
		table.insert(rope, self:stateValue())
		if self.state == self.ATTR then return table.concat(rope) end
	end
end

-- Use at Value
-- Transition to Attr and return value
function xmls:getValueRaw()
	return self:stateValue(self.state == self.VALUE2 and self.SKIPVALUE2 or self.SKIPVALUE1)
end

-- Use at Value
-- Transition to Attr and return valuePos, valueLast
function xmls:getValuePos()
	return self:statePos(self.state == self.VALUE2 and self.SKIPVALUE2 or self.SKIPVALUE1)
end

-- Use at TagEnd
-- Transition to Text
-- Return inner XML text and TagEnd's return value
function xmls:getInnerXML()
	self:assertState(self.TAGEND, "getInnerXML")
	local state, opening = self() --> text
	if opening then
		return self:stateValue(self.SKIPINNER), opening --> text
	else
		return "", opening
	end
end

-- Use at TagEnd
-- Transition to Text
-- Return inner XML start and end positions and TagEnd's return value
function xmls:getInnerPos()
	self:assertState(self.TAGEND, "getInnerPos")
	local state, opening = self() --> text
	if opening then
		local a, b = self:statePos(self.SKIPINNER)
		return a, b, opening --> text
	else
		return self.pos, self.pos, opening
	end
end

-- Use at TagEnd
-- Transition to Text
-- Return inner text, start and end positions of content and TagEnd's return value
function xmls:getInnerText()
	self:assertState(self.TAGEND, "getInnerText")
	local state, opening = self() --> text
	if opening then
		local posA, posB = self:statePos()
		if self.state == self.ETAG then
			self() --> text
			return self:cut(posA, posB), posA, posB, opening
		end
		local rope = {self:cut(posA, posB)}
		for level, text, pos, pos in self.getText, self, 1 do
			posB = pos
			table.insert(rope, text)
		end
		return table.concat(rope), posA, posB, opening
	else
		return "", opening
	end
end

-- Use at Attr
-- Return map of attributes
-- Transition to TagEnd
function xmls:getAttrMap(tbl)
	self:assertState(self.ATTR, "getAttrMap")
	tbl = tbl or {}
	for k, v in self.getAttr, self do
		tbl[k] = v
	end
	return tbl
end

-- Iterables
-- =========

-- Use at Text
-- Return tag name and tag position at Attr
-- Bring to Text
-- Transition to EOF
function xmls:forRoot()
	self:assertState(self.TEXT, "forRoot")
	return self.getRoot, self
end

-- Use at Attr
-- Return key, value at Attr
-- Transition to TagEnd
function xmls:forAttr()
	self:assertState(self.ATTR, "forAttr")
	return self.getAttr, self
end

-- Use at Attr
-- Return key, value at Attr
-- Transition to TagEnd
function xmls:forAttrXML()
	self:assertState(self.ATTR, "forAttrXML")
	return self.getAttrXML, self
end

-- Use at Attr
-- Return keypos, keylastpos, valuepos, valuelastpos at Attr
-- Transition to TagEnd
function xmls:forAttrPos()
	self:assertState(self.ATTR, "forAttrPos")
	return self.getAttrPos, self
end

-- Use at Attr
-- Return key at Attr
-- Transition to Value
function xmls:forKey()
	self:assertState(self.ATTR, "forKey")
	return self.getKey, self
end

-- Use at Attr
-- Return keyPos, keyLast at Attr
-- Transition to Value
function xmls:forKeyPos()
	self:assertState(self.ATTR, "forKeyPos")
	return self.getKeyPos, self
end

-- Use at TagEnd
-- Return tag name, tag text content, whether it was an opening tag and tag position at Text
-- Transition to Text
function xmls:forSimple()
	self:assertState(self.TAGEND, "forSimple")
	local state, opening = self()
	return opening and self.getSimple or self.getNothing, self
end

-- Use at TagEnd
-- Return tag name, tag XML content, whether it was an opening tag and tag position at Text
-- Transition to Text
function xmls:forSimpleXML()
	self:assertState(self.TAGEND, "forSimpleXML")
	local state, opening = self()
	return opening and self.getSimpleXML or self.getNothing, self
end

-- Use at TagEnd
-- Return tag name, tag content start and end positions, whether it was an opening tag and tag position at Text
-- Transition to Text
function xmls:forSimplePos()
	self:assertState(self.TAGEND, "forSimplePos")
	local state, opening = self()
	return opening and self.getSimplePos or self.getNothing, self
end

-- Use at TagEnd
-- Return state at ?
-- Bring to Text
-- Transition to Text
function xmls:forMarkup()
	self:assertState(self.TAGEND, "forMarkup")
	local state, opening = self()
	return opening and self.getMarkup or self.getNothing, self
end

-- Use at TagEnd
-- Return tag name and tag position at Attr
-- Bring to Text
-- Transition to Text
function xmls:forTag()
	self:assertState(self.TAGEND, "forTag")
	local state, opening = self()
	return opening and self.getTag or self.getNothing, self
end

-- Use at TagEnd
-- Return level, text and text start and end positions at ?
-- Transition to Text
function xmls:forText()
	self:assertState(self.TAGEND, "forText")
	local state, opening = self()
	return opening and self.getText or self.getNothing, self, 1
end

-- Iterators
-- =========

-- Use at Text
-- Do nothing
function xmls.getNothing() end

-- Use at Text
-- Transition to Attr and return tag name and tag position
-- Transition to Text and return nil
function xmls:getRoot()
	while true do
		local state, pos = self() --> ?
		if state == self.STAG then
			return self:stateValue(), pos --> attr
		elseif state == self.EOF then
			return nil
		end
	end
end

-- Use at Attr
-- Transition to Attr and return key, value
-- Transition to TagEnd and return nil
function xmls:getAttr()
	local posA, posB, state, key
	posA = self.pos
	state, posB = self() --> value
	if state ~= self.TAGEND then -- is a value
		return self:cut(posA, posB), self:getValue()
	else
		return nil
	end
end

-- Use at Attr
-- Transition to Attr and return key, value
-- Transition to TagEnd and return nil
function xmls:getAttrXML()
	local posA, posB, state, key
	posA = self.pos
	state, posB = self()
	if state ~= self.TAGEND then -- is a value
		return self:cut(posA, posB), self:getValueRaw()
	else
		return nil
	end
end

-- Use at Attr
-- Transition to Attr and return keypos, keylastpos, valuepos, valuelastpos
-- Transition to TagEnd and return nil
function xmls:getAttrPos()
	local posA, posB, posC, posD, state
	posA = self.pos
	state, posB = self()
	if state ~= self.TAGEND then -- is a value
		return posA, posB, self:getValuePos()
	else
		return nil
	end
end

-- Use at Text
-- Transition to ? and return state, pos
-- Transition to Text and return nil
function xmls:getMarkup()
	local state, pos = self() --> ?
	if state ~= self.ETAG then
		return state, pos
	else
		self() --> text
		return nil
	end
end

-- Use at Text
-- Transition to Attr and return tag name and tag position
-- Transition to Text and return nil
function xmls:getTag()
	while true do
		local state, pos = self() --> ?
		if state == self.STAG then
			return self:stateValue(), pos --> attr
		elseif state == self.ETAG then
			self() --> text
			return nil
		end
	end
end

-- Use at Text
-- Transition to Text and return tag name, tag text content, whether it was an opening tag and tag position
-- Transition to Text and return nil
function xmls:getSimple()
	while true do
		local state, pos = self() --> ?
		if state == self.STAG then
			local name = self:stateValue() --> attr
			self:dostate(self.SKIPATTR) --> tagend
			local value, opening = self:getInnerText()
			return name, value, opening, pos --> text
		elseif state == self.ETAG then
			self() --> text
			return nil
		end
	end
end

-- Use at Text
-- Transition to Text and return tag name, tag XML content, whether it was an opening tag and tag position
-- Transition to Text and return nil
function xmls:getSimpleXML()
	while true do
		local state, pos = self() --> ?
		if state == self.STAG then
			local name = self:stateValue() --> attr
			self:dostate(self.SKIPATTR) --> tagend
			local value, opening = self:getInnerXML()
			return name, value, opening, pos --> text
		elseif state == self.ETAG then
			self() --> text
			return nil
		end
	end
end

-- Use at Text
-- Transition to Text and return tag name, tag content starting and ending position, whether it was an opening tag and tag position
-- Transition to Text and return nil
function xmls:getSimplePos()
	while true do
		local state, pos = self() --> ?
		if state == self.STAG then
			local name = self:stateValue() --> attr
			self:dostate(self.SKIPATTR) --> tagend
			local a, b, opening = self:getInnerPos()
			return name, a, b, opening, pos --> text
		elseif state == self.ETAG then
			self() --> text
			return nil
		end
	end
end

-- Use at any state
-- Transition to any state except Text and return level, text data and text start and end positions
-- Transition to Text and return nil
function xmls:getText(level)
	local state = self.state
	if state == self.STAG then
		self:dostate(self.SKIPATTR) --> tagend
		if select(2, self()) then --> text
			level = level + 1
		end
	elseif state == self.ETAG then
		self()
		if level == 1 then return end
		level = level - 1
	elseif state == self.ENTITY then
		local posA, posB = self:statePos()
		local entity = self.decodeEntity(self:cut(posA, posB))
		if entity == nil then return self.error("Unrecognized entity", str, pos) end
		return level, entity, posA, posB
	elseif state == self.TEXT or state == self.CDATA then
		-- good!
	elseif state == self.EOF then
		return
	else
		-- skip
		self() --> text
	end
	local posA, posB = self:statePos()
	return level, self:cut(posA, posB), posA, posB
end

-- Declarative parsing
-- ===================

-- Unique token/atom for default tag handler
xmls.DEFAULT = function() end

-- Use at TagEnd
-- Transition to Text
function xmls:doTags(tree)
	self:assertState(self.TAGEND, "doTags")
	if select(2, self()) == false then return end --> text
	self:doTagsRoot(tree) --> text
end

-- Use at Text
-- Transition to Text or EOF
function xmls:doTagsRoot(tree)
	while true do
		local state, pos = self() --> ?
		if state == self.STAG then
			local name = self:stateValue() --> attr
			self:doSwitch(tree[name] or tree[self.DEFAULT], name, pos)
		elseif state == self.ETAG then
			return
		elseif state == self.EOF then
			return
		else -- Comment, PI
			local action = tree[state]
			if type(action) == "function" then
				action(self, state, pos)
			else
				self() --> text
			end
		end
	end
end

-- Use at TagEnd
-- Transition to Text
-- A function can return true and leave content unconsumed to allow the search to continue
function xmls:doDescendants(tree)
	self:assertState(self.TAGEND, "doDescendants")
	if select(2, self()) then --> text
		self:doDescendantsRoot(tree) --> etag
	end
	self() --> text
end

-- Use at Text
-- Transition to ETag or EOF
-- A function can return true and leave content unconsumed to allow the search to continue
function xmls:doDescendantsRoot(tree)
	local stack = {}
	while true do
		local state, pos = self() --> ?
		if state == self.STAG then
			local name = self:stateValue() --> attr
			local action = tree[name] or tree[self.DEFAULT]
			local case = type(action)
			
			if case == "table" then
				self:dostate(self.SKIPATTR) --> tagend
				for name, pos in self:forTag() do
					self:doSwitch(action[name], name, pos)
				end --> text
				-- consumed
				
			elseif case == "function" then
				if action(self, name, pos) == true then --> tagend
					-- not consumed
					if select(2, self()) then --> text
						table.insert(stack, name)
					end
				end
				-- else --> text
				
			else
				-- not consumed
				self:dostate(self.SKIPATTR) --> tagend
				if select(2, self()) then --> text
					table.insert(stack, name)
				end
			end
			
		elseif state == self.ETAG then
			if stack[1] == nil then return end
			table.remove(stack)
			self() --> text
			
		elseif state == self.EOF then
			return
			
		else -- Comment, PI
			local action = tree[state]
			if type(action) == "function" then
				action(self, state, pos)
			else
				self() --> text
			end
		end
	end
end

-- Use at Attr
-- Transition to Text
function xmls:doSwitch(action, name, pos)
	local case = type(action)
	
	if case == "nil" then
		return self:dostate(self.SKIPTAG) --> text
		
	elseif case == "table" then
		self:dostate(self.SKIPATTR)
		for name, pos in self:forTag() do
			self:doSwitch(action[name], name, pos)
		end
		
	elseif case == "function" then
		return action(self, name, pos)
	end
end

-- Generate function that calls doDescendants
function xmls:toDescendants(root)
	return function(xml, stag)
		self:dostate(self.SKIPATTR)
		return xml:doDescendants(root, stag)
	end
end

-- Other
-- =====

-- Get input string substring [a, b)
function xmls:cut(a, b)
	return self.str:sub(a, b - 1)
end

-- Get input string substring [a, end]
function xmls:cutEnd(a)
	return self.str:sub(a)
end

-- Entities
-- ========

-- XML mandatory entities
xmls.entityToLiteral = {
	quot = '"',
	apos = "'",
	amp = "&",
	lt = "<",
	gt = ">",
}

-- Resolve an entity to a string or nil
function xmls.decodeEntity(str)
	local literal = xmls.entityToLiteral[str]
	if literal then return literal end
	if str:byte(1) ~= 35 then return end -- #
	if str:byte(2) == 120 then -- x
		str = str:match("^%x+$", 3)
	else
		str = str:match("^%d+$", 2)
	end
	if str == nil then return end
	return utf8char(tonumber(str, 16))
end

-- Error reporting supplements
-- ===========================

-- Get line number and position in line from string and position in string
function xmls.linepos(str, pos)
	local line = 0
	local lastpos = 1
	-- find first line break that's after pos
	for linestart in string.gmatch(str, "()[^\n]*") do
		if pos < linestart then break end
		lastpos = linestart
		line = line + 1
	end
	return line, pos - lastpos + 1
end

function xmls.locate(str, pos, name)
	local line, linepos = xmls.linepos(str, pos)
	if name then
		return string.format("%s:%d:%d:%d", name, pos, line, linepos)
	else
		return string.format("%d:%d:%d", pos, line, linepos)
	end
end

function xmls.error(reason, str, filepos)
	local line, linepos = xmls.linepos(str, filepos)
	return error(debug.traceback(string.format("%s at %d:%d:%d", reason, filepos, line, linepos), 2), 2)
end

function xmls:traceback(pos)
	return self.locate(self.str, pos or self.pos, self.name)
end

function xmls:assertState(state, name)
	if self.state ~= state then
		return self.error(string.format("%s called at %s instead of %s", name, self.names[self.state], self.names[state]), self.str, self.pos)
	end
end

-- Replacement/editing functions
-- =============================

function xmls:replaceInit()
	self.replaceA = {}
	self.replaceB = {}
	self.replacePayload = {}
end

function xmls:replace(a, b, payload)
	table.insert(self.replaceA, a)
	table.insert(self.replaceB, b)
	table.insert(self.replacePayload, payload)
end

-- Replace tag content (between a and b) with payload, opening or closing the tag as necessary
function xmls:replaceContent(a, b, opening, name, payload)
	if opening then
		if payload ~= "" then
			-- replace content as normal
			self:replace(a, b, payload)
		else
			-- self-close the opening tag and remove the content and closing tag
			self:replace(a - 1, a - 1, "/")
			self:replace(a, self.pos, "")
		end
	else -- self-closing
		if payload ~= "" then
			-- remove the / and add a closing tag
			self:replace(a - 2, a - 1, "")
			self:replace(a, b, payload .. string.format("</%s>", name))
		else
			-- do nothing
		end
	end
end

-- Perform pending replacements
function xmls:replaceFinish()
	-- sort replacements
	local proxy = {}
	for i = 1, #self.replacePayload do
		table.insert(proxy, i)
	end
	table.sort(proxy, function(a, b)
		return self.replaceB[a] < self.replaceA[b]
	end)
	-- perform replacements
	local rope = {}
	local pos = 1
	for i = 1, #self.replacePayload do
		i = proxy[i]
		if self.replaceA[i] < pos then
			return xmls.error("Overlapping replacements", self.str, pos)
		end
		local payload = self.replacePayload[i]
		if type(payload) == "function" then payload = payload(self) end
		table.insert(rope, self:cut(pos, self.replaceA[i]))
		table.insert(rope, payload)
		pos = self.replaceB[i]
	end
	table.insert(rope, self:cutEnd(pos))
	return table.concat(rope)
end

-- End
-- ===

return xmls
