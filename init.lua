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

]]

local xmls = {}

-- Tag
-- The character < or end of file
-- Transition to STag, ETag, Comment, PI or MalformedTag
-- Return nil
function xmls.tag(str, pos)
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
	return xmls.attr, str:match("^[ \t\r\n]*()", pos), pos
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
	return xmls.text, pos + 1, pos
end

-- Comment.
-- Anything
-- Transition to Text
-- Return end of content
function xmls.comment(str, pos)
	local pos2 = str:match("%-%->()", pos)
	if pos2 then
		return xmls.text, pos2, pos2 - 3
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
		return xmls.text, pos2, pos2 - 2
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
-- Return end of name
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
		return xmls.value, pos, nameend
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
		pos = str:match("[^\"]*()", pos + 1)
		if str:sub(pos, pos) ~= '"' then
			error("Unclosed attribute value at " .. pos)
		end
	else
		pos = str:match("[^']*()", pos + 1)
		if str:sub(pos, pos) ~= "'" then
			error("Unclosed attribute value at " .. pos)
		end
	end
	return xmls.attr, str:match("^[ \t\r\n]*()", pos + 1), pos
end

-- End of tag
-- The characters / or >
-- Transition to Text
-- Return true if opening tag, false if self-closing
function xmls.tagend(str, pos)
	if str:sub(pos, pos) ~= "/" then
		return xmls.text, pos + 1, true
	else
		return xmls.text, pos + 2, false
	end
end

-- Plain text
-- Transition to Tag
-- Return nil. pos is end of content
function xmls.text(str, pos)
	pos = str:match("[^<]*()", pos)
	return xmls.tag, pos
end

-- End of file
-- Error, shouldn't have read any further
function xmls.eof(str, pos)
	return error("Exceeding end of file")
end

---------------------------------------------

-- function xmls.tags()
-- end

-- xmls.attrs

-- xmls.waste -- only in Attr
-- xmls.wasteAttrs -- only in Attr
-- xmls.wasteContent -- only... where? Text?
-- better name?


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
