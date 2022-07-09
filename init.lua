--[[
<Object type="0x01ff" id="Sheep">asdf<foo/></Object>
<!--
<
 Object 
        type="
		      0x01ff" 
			          id="
						  Sheep"
								>
								 asdf
								     <
									  foo
									     />
										   <
										    /Object>
Text
Tag
 STag
		Attr name
			  Attr value
					  Attr name
						  Attr value
								Attr name
								Tag end, opening
								 Text
								     Tag
									  STag
									     Attr name
										 Tag end, self-closing
										   Text
										   Tag
										    ETag
											        Text
													Tag
													EOF
-->

</Object>
<!--
</
  Object>
ETag
  Name
-->

<Object foo="bar"/>
<!--
<
 Object 
        foo="
		     bar"
			     />
Tag
 STag
		Attr name
			 Attr value
				 End of attributes, self-closing
-->
]]

--[[

todo:
make parsing more bulletproof/more error-happy
look over all errors and ensure the positions are right
add a variant of Text that goes up to entities, leaving it up to you to expand them?

https://www.w3.org/TR/xml/

]]

local xmls = {}

-- Markup
-- The character < or end of file
-- Transition to STag, ETag, CDATA, Comment, PI or MalformedTag
-- Return nil
function xmls.markup(str, pos)
	if pos > #str then
		return xmls.eof, pos
	end
	
	local sigil = str:sub(pos + 1, pos + 1)
	
	if sigil:match("%w") then -- <tag
		return xmls.stag, pos + 1
		
	elseif sigil == "/" then -- </
		if str:sub(pos + 2, pos + 2):match("%w") then -- </tag
			return xmls.etag, pos + 2
		else -- </>
			return xmls.malformed, pos
		end
		
	elseif sigil == "!" then -- <!
		if str:sub(pos + 2, pos + 3) == "--" then -- <!--
			return xmls.comment, pos + 4
		elseif str:sub(pos + 2, pos + 8) == "[CDATA[" then -- <![CDATA[
			return xmls.cdata, pos + 9
		else -- <!asdf
			return xmls.malformed, pos
		end
		
	elseif sigil == "?" then -- <?
		return xmls.pi, pos + 1
		
	else -- <\
		return xmls.malformed, pos
	end
end

-- Name of starting tag.
-- Any name character
-- Transition to Attr
-- Return end of name
function xmls.stag(str, pos)
	pos = str:match("^%w+()", pos)
	if pos == nil then
		error("Invalid tag name at " .. pos)
	end
	return xmls.attr, str:match("^[ \t\r\n]*()", pos), pos - 1
end

-- Name of ending tag.
-- Any name character
-- Transition to Text
-- Return end of name
function xmls.etag(str, pos)
	pos = str:match("^%w+()", pos)
	if pos == nil then
		error("Invalid etag name at " .. pos)
		
	elseif str:sub(pos, pos) ~= ">" then
		-- todo: is a trailing space in an etag valid?
		error("Malformed etag at " .. pos) -- incorrect position
	end
	return xmls.text, pos + 1, pos - 1
end

-- CDATA section
-- Anything
-- Transition to Text
-- Return end of content
function xmls.cdata(str, pos)
	-- todo: not a great idea to make this a case of Markup,
	-- because it is actually text data
	local pos2 = str:match("%]%]>()", pos)
	if pos2 then
		return xmls.text, pos2, pos2 - 4
	else
		-- unterminated
		error("Unterminated CDATA section at " .. pos)
		-- pos = #str
		-- return xmls.text, pos, pos
	end
end

-- Comment.
-- Anything
-- Transition to Text
-- Return end of content
function xmls.comment(str, pos)
	local pos2 = str:match("%-%->()", pos)
	if pos2 then
		return xmls.text, pos2, pos2 - 4
	else
		-- unterminated
		error("Unterminated comment at " .. pos)
		-- pos = #str
		-- return xmls.text, pos, pos
	end
end

-- Processing instruction.
-- Anything
-- Transition to Text
-- Return end of content
function xmls.pi(str, pos)
	local pos2 = str:match("?>()", pos)
	if pos2 then
		return xmls.text, pos2, pos2 - 3
	else
		-- unterminated
		error("Unterminated processing instruction at " .. pos)
		-- pos = #str
		-- return xmls.text, pos, pos
	end
end

-- Obviously malformed tag.
-- The character <
-- Transition to Text
-- Return nil
function xmls.malformed(str, pos)
	-- zip to after >
	error("Malformed tag at " .. pos)
end

-- Attribute name or end of tag (end of attribute list).
-- The characters /, > or any name character
-- Transition to Value or TagEnd
-- Return end of name if Value or nil if TagEnd
function xmls.attr(str, pos)
	if str:match("^[^/>]", pos) then
		local nameend = str:match("^%w+()", pos)
		if nameend == nil then
			error("Invalid attribute name at " .. pos)
		end
		pos = str:match("^[ \t\r\n]*()", nameend)
		if str:sub(pos, pos) ~= "=" then
			error("Malformed attribute at " .. pos)
		end
		pos = str:match("^[ \t\r\n]*()", pos + 1)
		return xmls.value, pos, nameend - 1
	else
		return xmls.tagend, pos, nil
	end
end

-- Attribute value.
-- Anything
-- Transition to Attr
-- Return end of value
function xmls.value(str, pos)
	if str:sub(pos, pos) == '"' then
		pos = str:match("^[^\"]*()", pos + 1)
		if str:sub(pos, pos) ~= '"' then
			error("Unclosed attribute value at " .. pos)
		end
	else
		pos = str:match("^[^']*()", pos + 1)
		if str:sub(pos, pos) ~= "'" then
			error("Unclosed attribute value at " .. pos)
		end
	end
	return xmls.attr, str:match("^[ \t\r\n]*()", pos + 1), pos - 1
end

-- End of tag
-- The characters / or >
-- Transition to Text
-- Return true if opening tag, false if self-closing
function xmls.tagend(str, pos)
	-- todo: figure out when this could possibly be called if it isn't / or >
	-- xmls.attr will defer to this if it runs into the end of file
	local sigil = str:sub(pos, pos)
	if sigil == ">" then
		return xmls.text, pos + 1, true
	elseif sigil == "/" then
		pos = pos + 1
		if str:sub(pos, pos) == ">" then
			return xmls.text, pos + 1, false
		else
			error("Malformed tag end at " .. pos)
		end
	else
		error("Malformed tag end at " .. pos)
	end
end

-- Plain text
-- Anything
-- Transition to Tag
-- Return end of content
function xmls.text(str, pos)
	pos = str:match("[^<]*()", pos)
	return xmls.markup, pos, pos - 1
end

-- End of file
-- Error, shouldn't have read any further
function xmls.eof(str, pos)
	return error("Exceeding end of file")
end

---------------------------------------------

-- Iterate over attribute name-value pairs.
-- Use after STag
-- Must follow up with TagEnd
function xmls.attrs(str, pos)
	local state, posB
	local posA = pos
	state, pos, posB = xmls.attr(str, pos)
	if state == xmls.value then
		local key = str:sub(posA, posB)
		posA = pos + 1 -- skip the quote
		state, pos, posB = xmls.value(str, pos)
		return pos, key, str:sub(posA, posB)
	else
		return nil
	end
end
--[[ Example:
local str = '<test key="value" key="value">'
local pos = 7
for i, k, v in xmls.attrs, str, pos do
	pos = i
	print(k, v)
end
print(xmls.tagend(str, pos))
]]

-- Skip attributes.
-- Use after STag
-- Must follow up with TagEnd
function xmls.wasteAttrs(str, pos)
	return str:match("^[^/>]*()", pos)
end
--[[ Example:
local str = '<test key="value" key="value">'
local pos = 7
pos = xmls.wasteAttrs(str, pos)
print(xmls.tagend(str, pos))
]]

-- testing

if false then

local back = {}
for k,v in pairs(xmls) do back[v] = k end

-- local str = "<foo bar='123'></foo>"
local file = assert(io.open("equip.xml"))
local str = file:read("*a")
file:close()

local op = xmls.text
local pos = 1
local ret

print()
while true do
	local a, b = back[op], pos
	local ret
	op, pos, ret = op(str, pos)
	print(a, b, ret)
	if op == xmls.eof then return end
end

end

return xmls
