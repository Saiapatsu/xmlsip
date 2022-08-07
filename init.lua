--[[
xmls2
minimal XML parsing utilities in Lua

code todo:
	make parsing more bulletproof/more error-happy
	look over all errors and ensure the positions are right

spec todo:
	https://www.w3.org/TR/xml/
	add a variant of Text that goes up to entities, leaving it up to the user to expand them?
	implement entities in attribute values
	add XML preamble support, if only to skip it entirely
	parse names correctly per https://www.w3.org/TR/xml/#charsets
	make it easy to verify user-side whether etag matches stag
		(in the c port, take a char* to stag and check whether it matches etag)

features todo:
	innerText
	entities
	substitution (using a separate object), specify the ranges whose text to replace and it will splice together original text and replacement text into one rope

stag and value are always followed by attr even if there are no attributes following
that's because a stag always has an attribute list, said list may simply be empty
therefore, stag and value leading to attr is not really redundant... or is it?
attr() could check whether it's actually at attr and you are required to always
consume all attributes with attrs() or skipAttrs()
this only makes functions that check state == xmls.attr more complicated
of which there are quite a few, actually...

there is a separate "markup" state because it sets up the next state
such that it begins at the beginning of the important string in it
if text were to go straight to stag for example, then consumers would only see
the positions of start of text, end of text and start of stag name
now that I've written it out, it doesn't seem that bad because text necessarily
returns its end (i.e. before start of markup), making markup truly redundant...
I was thinking that it'd be impossible to know where stag name started
I actually thought that while looking at etag name, actually, but that's solved too

there are no productions with leading spaces here, only trailing spaces
(not sure, verify this)

]]

--[[
<Object type="0x01ff" id="Sheep">asdf<foo/></Object>
<       type=         id=       >    <   />  Object>
 Object      "0x01ff"    "Sheep" asdf foo  </
text
markup
 stag
        attr
             value
                      attr
                         value
                                attr
                                tagend (opening)
                                 text
                                     markup
                                      stag
                                         attr
                                         tagend (self-closing)
                                           text
                                           markup
                                             etag
                                                    text
                                                    markup
                                                    eof
]]

local xmls = {}

-- States
-- ======

-- Mapping from state function to state name
xmls.names = {} -- [function] = string
--[[
text
markup
stag
etag
cdata
comment
pi
malformed
attr
value
tagend
eof
]]

-- Plain text
-- Use outside of markup
-- Transition to Markup
-- Return end of text
function xmls.text(str, pos)
	pos = str:match("[^<]*()", pos)
	return pos, xmls.markup, pos - 1
end

-- Markup
-- Use at "<" or EOF
-- Transition to STag, ETag, CDATA, Comment, PI, MalformedTag or EOF
-- Return nil
function xmls.markup(str, pos)
	-- jump over the <
	pos = pos + 1
	
	if str:match("^%w()", pos) ~= nil then -- <tag
		return pos, xmls.stag, nil
	end
	
	local byte = str:byte(pos)
	
	if byte == 47 then -- </
		pos = pos + 1
		if str:match("^%w()", pos) ~= nil then -- </tag
			return pos, xmls.etag, nil
		else -- </>
			return pos - 1, xmls.malformed, nil
		end
		
	elseif byte == 33 then -- <!
		pos = pos + 1
		if str:sub(pos, pos + 1) == "--" then -- <!--
			return pos + 2, xmls.comment, nil
		elseif str:sub(pos, pos + 6) == "[CDATA[" then -- <![CDATA[
			return pos + 7, xmls.cdata, nil
		else -- <!asdf
			return pos - 1, xmls.malformed, nil
		end
		
	elseif byte == 63 then -- <?
		return pos + 1, xmls.pi, nil
		
	elseif pos >= #str then -- end of file
		return pos - 1, xmls.eof, nil
		
	else -- <\
		return pos, xmls.malformed, nil
	end
end

-- Name of starting tag
-- Use at name character after "<"
-- Transition to Attr
-- Return end of name
function xmls.stag(str, pos)
	local posName, posSpace = str:match("^%w+()[ \t\r\n]*()", pos)
	if posName == nil then
		return xmls.error("Invalid tag name", str, pos)
	end
	return posSpace, xmls.attr, posName - 1
end

-- Name of ending tag
-- Use at name character after "</"
-- Transition to Text
-- Return end of name
function xmls.etag(str, pos)
	local posName, posSpace = str:match("^%w+()[ \t\r\n]*()", pos)
	if posName == nil then
		return xmls.error("Invalid etag name", str, pos)
	end
	if str:byte(posSpace) ~= 62 then
		return xmls.error("Malformed etag", str, pos)
	end
	return posSpace + 1, xmls.text, posName - 1
end

-- Content of CDATA section
-- Use after "<![CDATA["
-- Transition to Text
-- Return end of content
function xmls.cdata(str, pos)
	local pos2 = str:match("%]%]>()", pos)
	if pos2 ~= nil then
		return pos2, xmls.text, pos2 - 4
	else
		return xmls.error("Unterminated CDATA section", str, pos)
	end
end

-- Content of comment
-- Use after "<!--"
-- Transition to Text
-- Return end of content
function xmls.comment(str, pos)
	local pos2 = str:match("%-%->()", pos)
	if pos2 ~= nil then
		return pos2, xmls.text, pos2 - 4
	else
		-- unterminated
		return xmls.error("Unterminated comment", str, pos)
		-- pos = #str
		-- return pos, xmls.text, pos
	end
end

-- Content of processing instruction
-- Use after "<?"
-- Transition to Text
-- Return end of content
function xmls.pi(str, pos)
	local pos2 = str:match("?>()", pos)
	if pos2 ~= nil then
		return pos2, xmls.text, pos2 - 3
	else
		-- unterminated
		return xmls.error("Unterminated processing instruction", str, pos)
		-- pos = #str
		-- return pos, xmls.text, pos
	end
end

-- Content of an obviously malformed tag
-- Use after "<"
-- Transition to Text
-- Return nil
function xmls.malformed(str, pos)
	-- zip to after >
	return xmls.error("Malformed tag", str, pos)
end

-- Attribute name or end of tag (end of attribute list).
-- Use at attribute name or ">" or "/>"
-- Transition to Value and return end of name
-- Transition to TagEnd and return nil
function xmls.attr(str, pos)
	if str:match("^[^/>]()", pos) ~= nil then
		local posName, posSpace = str:match("^%w+()[ \t\r\n]*=[ \t\r\n]*()", pos)
		if posName == nil then
			return xmls.error("Malformed attribute", str, pos)
		end
		return posSpace, xmls.value, posName - 1
	else
		return pos, xmls.tagend, nil
	end
end

-- Attribute value
-- Use at "'" or '"'
-- Transition to Attr
-- Return end of value
function xmls.value(str, pos)
	local posQuote, posSpace = str:byte(pos)
	if posQuote == 34 then -- "
		posQuote, posSpace = str:match('()"[ \t\r\n]*()', pos + 1)
	elseif posQuote == 39 then -- '
		posQuote, posSpace = str:match("()'[ \t\r\n]*()", pos + 1)
	else
		return xmls.error("Unquoted attribute value", str, pos)
	end
	if posQuote == nil then
		return xmls.error("Unterminated attribute value", str, pos)
	end
	return posSpace, xmls.attr, posQuote - 1
end

-- End of tag
-- Use at ">" or "/>"
-- Transition to Text
-- Return true if opening tag, false if self-closing
function xmls.tagend(str, pos)
	-- warning: xmls.attr will transition to this if it runs into the end of file
	local byte = str:byte(pos)
	if byte == 62 then -- >
		return pos + 1, xmls.text, true
	elseif byte == 47 then -- /
		if str:byte(pos + 1) == 62 then -- >
			return pos + 2, xmls.text, false
		end
	end
	return xmls.error("Malformed tag end", str, pos)
end

-- End of file
-- Do not use
-- Throws an error, shouldn't have read any further
function xmls.eof(str, pos)
	return xmls.error("Exceeding end of file", str, pos)
end

-- Populate xmls.names
for k,v in pairs(xmls) do
	xmls.names[v] = k
end

-- Error reporting
-- ===============

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

function xmls.error(reason, str, filepos)
	local line, linepos = xmls.linepos(str, filepos)
	return error(debug.traceback(string.format("%s at %d:%d (%d)", reason, line, linepos, filepos), 2), 2)
end

-- Supplementary methods
-- =====================

-- Skip attributes and content of a tag
-- Use at Attr
-- Transition to Text
function xmls.skip(str, pos)
	pos = xmls.skipAttrs(str, pos)
	return xmls.skipContent(str, pos)
end

-- Skip attributes of a tag
-- Use between a < and a >
-- Transition to TagEnd
function xmls.skipAttrs(str, pos)
	-- fails when there's a slash in an attribute value!
	-- local pos2 = str:match("^[^/>]*()", pos)
	-- local pos2 = str:match("^.-()/?>", pos)
	-- if pos2 == nil then
		-- xmls.error("Unterminated start tag", str, pos2)
	-- end
	pos = str:match("^[^>]*()", pos)
	if str:byte(pos - 1) == 47 then
		return pos - 1, xmls.tagend
	else
		return pos, xmls.tagend
	end
end

-- Skip the content and end tag of a tag
-- Use at TagEnd
-- Transition to Text
-- Return value is not useful
function xmls.skipContent(str, pos)
	local pos, state, value = xmls.tagend(str, pos) --> text
	if value == true then
		return xmls.skipInner(str, pos) --> text
	else
		return pos, state, nil
	end
end

-- Skip the content and end tag of a tag
-- Use at Text after TagEnd
-- Transition to Text
-- Return end of content just before the end tag
function xmls.skipInner(str, pos)
	local level, state, value = 1, xmls.text
	local posB
	repeat --> text
		pos, state = state(str, pos) --> markup
		posB = pos
		pos, state = state(str, pos) --> ?
		if state == xmls.stag then --> stag
			-- pos, state = state(str, pos) --> attr
			pos, state = xmls.skipAttrs(str, pos) --> tagend
			pos, state, value = state(str, pos) --> text
			if value == true then
				level = level + 1
			end
			
		elseif state == xmls.etag then --> etag
			level = level - 1
			pos, state = state(str, pos) --> text
			
		else --> ?
			pos, state = state(str, pos) --> text
		end
	until level == 0
	return pos, state, posB - 1
end

-- Parsing using a state-holding object
-- ====================================

local xmo = {}
xmo.__index = xmo
xmls.xmo = xmo

-- Constructor
function xmls.new(str, pos, state)
	return setmetatable({
		str = str,
		pos = pos or 1,
		state = state or xmls.text,
	}, xmo)
end

-- Advance to the next state
function xmo:__call()
	local value
	self.pos, self.state, value = self.state(self.str, self.pos)
	return self.state, value
end

-- Use a supplemental method
function xmo:doState(state)
	local value
	self.pos, self.state, value = state(self.str, self.pos)
	return self.state, value
end

-- Skipping irrelevant content
-- ===========================

-- Use at Attr
-- Transition to Text
function xmo:skip()
	assert(self.state == xmls.attr)
	return self:doState(xmls.skip)
end

-- Use at Attr
-- Transition to TagEnd
function xmo:skipAttrs()
	assert(self.state == xmls.attr)
	return self:doState(xmls.skipAttrs)
end

-- Use at TagEnd
-- Transition to Text
function xmo:skipContent()
	assert(self.state == xmls.tagend)
	return self:doState(xmls.skipContent)
end

-- Use at TagEnd
-- Transition to Text
-- Return inner XML
function xmo:getInner()
	assert(self.state == xmls.tagend)
	local state, value = self() --> text
	if value == true then
		return self.str:sub(self.pos, select(2, self:doState(xmls.skipInner))) --> text
	else
		return ""
	end
end

-- Iterables
-- =========

-- Iterator that stops immediately
local function nop() end

-- Use at Text
-- Return tag name at Attr
-- Bring to Text
-- Transition to EOF
function xmo:roots()
	assert(self.state == xmls.text)
	return xmo.nextRoot, self
end

-- Use at Attr
-- Return key, value at Attr
-- Transition to TagEnd
function xmo:attrs()
	assert(self.state == xmls.attr)
	return xmo.nextAttr, self
end

-- Use at TagEnd
-- Return tag name, inner XML at Text
-- Transition to Text
function xmo:pairs()
	assert(self.state == xmls.tagend)
	local state, value = self()
	return value and xmo.nextPair or nop, self
end

-- Use at TagEnd
-- Return state at ?
-- Bring to Text
-- Transition to Text
function xmo:markup()
	assert(self.state == xmls.tagend)
	local state, value = self()
	return value and xmo.nextMarkup or nop, self
end

-- Use at TagEnd
-- Return tag name at Attr
-- Bring to Text
-- Transition to Text
function xmo:tags()
	assert(self.state == xmls.tagend)
	local state, value = self()
	return value and xmo.nextTag or nop, self
end

-- Iterators
-- =========

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

-- Use at Text
-- Transition to Text and return tag name, tag content
-- Transition to Text and return nil
function xmo:nextPair()
	self() --> markup
	while true do
		local state = self() --> ?
		if state == xmls.stag then
			local name = self.str:sub(self.pos, select(2, self())) --> attr
			self:doState(xmls.skipAttrs) --> tagend
			local state, value = self() --> text
			if value == true then
				return name, self.str:sub(self.pos, select(2, self:doState(xmls.skipInner))) --> text
			else
				return name, ""
			end
		elseif state == xmls.etag then
			self() --> text
			return nil
		end
	end
end

-- Parsing with callbacks
-- ======================

-- Use at TagEnd
-- Transition to Text
function xmo:doTags(tree)
	assert(self.state == xmls.tagend)
	for name in self:tags() do
		self:doSwitch(tree[name], name)
	end
end

-- Use at Start
-- Transition to EOF
function xmo:doRoots(tree)
	assert(self.state == xmls.text)
	for name in self:roots() do
		self:doSwitch(tree[name], name)
	end
end

-- Use at Attr
-- Transition to Text
function xmo:doSwitch(action, name)
	local case = type(action)
	
	if case == "nil" then
		return self:doState(xmls.skip)
		
	elseif case == "table" then
		self:doState(xmls.skipAttrs)
		for name in self:tags() do
			self:doSwitch(action[name], name)
		end
		
	elseif case == "function" then
		return action(self, name)
	end
end

-- Other
-- =====

-- Use at Attr
-- Return map of attributes
-- Transition to TagEnd
function xmo:getAttrs(tbl)
	assert(self.state == xmls.attr)
	tbl = tbl or {}
	for k, v in xmo.nextAttr, self do
		tbl[k] = v
	end
	return tbl
end

-- End
-- ===

return xmls
